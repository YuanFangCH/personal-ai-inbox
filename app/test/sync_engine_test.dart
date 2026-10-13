import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/markdown_codec.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/data/sync_engine.dart';
import 'package:personal_ai_inbox/data/sync_provider.dart';

void main() {
  const codec = MarkdownCodec();
  late MemoryVaultStore vault;
  late MemoryIndexDatabase index;
  late ResultRepository repository;
  late MemorySyncProvider provider;
  late SyncEngine engine;

  setUp(() async {
    vault = MemoryVaultStore();
    index = MemoryIndexDatabase();
    repository = ResultRepository(
      vault: vault,
      index: index,
      deviceId: 'test-device',
    );
    await repository.initialize();
    provider = MemorySyncProvider();
    engine = SyncEngine(
      repository: repository,
      provider: provider,
      deviceId: 'test-device',
    );
  });

  test('uploads once and then reports unchanged', () async {
    await repository.create(
      type: ResultType.knowledge,
      title: '同步知识',
      body: '正文',
    );

    final first = await engine.sync();
    final second = await engine.sync();

    expect(first.uploaded, 1);
    expect(first.conflicts, 0);
    expect(second.unchanged, 1);
    expect(second.uploaded, 0);
  });

  test(
    'records a shared baseline when first observed hashes are equal',
    () async {
      final local = await repository.create(
        type: ResultType.knowledge,
        title: '已相同',
        body: '正文',
      );
      final source = await repository.readManagedResult(local.id);
      final remote = await provider.putObject(
        id: local.id,
        path: local.markdownPath,
        contents: source!,
        condition: const SyncWriteCondition.createOnly(),
      );

      final report = await engine.sync();
      final indexed = await repository.findIndexed(local.id);

      expect(report.unchanged, 1);
      expect(indexed!.lastSyncedHash, remote.hash);
      expect(indexed.remoteEtag, remote.etag);
    },
  );

  test('re-uploads when a configured remote loses the object', () async {
    await repository.create(
      type: ResultType.knowledge,
      title: '重新上传',
      body: '正文',
    );
    await engine.sync();

    final restartedProvider = MemorySyncProvider();
    final restartedEngine = SyncEngine(
      repository: repository,
      provider: restartedProvider,
      deviceId: 'test-device',
    );
    final report = await restartedEngine.sync();

    expect(report.uploaded, 1);
    expect(await restartedProvider.listObjects(), hasLength(1));
  });

  test('keeps both versions when local and remote changed', () async {
    final local = await repository.create(
      type: ResultType.knowledge,
      title: '原始标题',
      body: '正文',
    );
    await engine.sync();
    final indexed = await repository.findIndexed(local.id);
    await repository.save(local.copyWith(title: '本地标题'));
    await provider.putObject(
      id: local.id,
      path: local.markdownPath,
      contents: codec.encode(local.copyWith(title: '远端标题')),
      condition: SyncWriteCondition.matchEtag(indexed!.remoteEtag!),
    );

    final report = await engine.sync();
    final conflictRevision = (await repository.findIndexed(local.id))!.revision;
    await engine.sync();
    final conflicts = await repository.listConflictFiles();

    expect(report.conflicts, 1);
    expect(conflicts, hasLength(1));
    expect(vault.files[local.markdownPath], contains('本地标题'));
    expect(vault.files[conflicts.single], contains('远端标题'));
    expect(await repository.listConflicts(), hasLength(1));
    expect(
      (await repository.findIndexed(local.id))!.revision,
      conflictRevision,
    );
  });

  test(
    'rejects a mismatched remote identity without blocking valid objects',
    () async {
      final valid = await repository.create(
        type: ResultType.knowledge,
        title: '有效远端',
        body: '内容',
      );
      final remoteValid = valid.copyWith(revision: 4);
      final validSource = codec.encode(remoteValid);
      final invalid = remoteValid.copyWith(id: 'kn_other_12345678');
      await repository.deleteRaw(valid.markdownPath);
      await repository.rebuildIndex();
      final provider = _InjectedProvider([
        SyncRemoteObject(
          id: valid.id,
          path: valid.markdownPath,
          content: validSource,
          hash: repository.hashMarkdown(validSource),
          etag: 'valid-etag',
        ),
        SyncRemoteObject(
          id: invalid.id,
          path: valid.markdownPath,
          content: codec.encode(invalid),
          hash: repository.hashMarkdown(codec.encode(invalid)),
          etag: 'invalid-etag',
        ),
        SyncRemoteObject(
          id: 'kn_bad_hash_12345678',
          path: 'vault/knowledge/kn_bad_hash_12345678.md',
          content: codec.encode(
            remoteValid.copyWith(id: 'kn_bad_hash_12345678'),
          ),
          hash: 'sha256:incorrect',
          etag: 'bad-hash-etag',
        ),
      ]);
      final isolatedEngine = SyncEngine(
        repository: repository,
        provider: provider,
        deviceId: 'test-device',
      );

      final report = await isolatedEngine.sync();

      expect(report.failed, 2);
      expect(report.downloaded, 1);
      expect(await repository.readDocument(valid.id), isNotNull);
      expect(await repository.readDocument(invalid.id), isNull);
    },
  );

  test(
    'rejudges a create race and preserves divergent remote content',
    () async {
      final local = await repository.create(
        type: ResultType.knowledge,
        title: '本地版本',
        body: '内容',
      );
      final provider = _CreateRaceProvider(
        codec.encode(local.copyWith(title: '并发远端版本')),
      );
      final racingEngine = SyncEngine(
        repository: repository,
        provider: provider,
        deviceId: 'test-device',
      );

      final report = await racingEngine.sync();

      expect(report.conflicts, 1);
      expect(report.failed, 0);
      expect(
        codec.decode((await provider.listObjects()).single.content).title,
        '并发远端版本',
      );
      expect(await repository.listConflicts(), hasLength(1));
    },
  );
}

class _InjectedProvider extends MemorySyncProvider {
  _InjectedProvider(this.objects);

  final List<SyncRemoteObject> objects;

  @override
  Future<List<SyncRemoteObject>> listObjects() async => objects;
}

class _CreateRaceProvider extends MemorySyncProvider {
  _CreateRaceProvider(this.concurrentContents);

  final String concurrentContents;
  bool raced = false;

  @override
  Future<SyncRemoteObject> putObject({
    required String id,
    required String path,
    required String contents,
    required SyncWriteCondition condition,
  }) async {
    if (!raced && condition.kind == SyncWriteConditionKind.createOnly) {
      raced = true;
      await super.putObject(
        id: id,
        path: path,
        contents: concurrentContents,
        condition: const SyncWriteCondition.createOnly(),
      );
      throw SyncPreconditionFailed(id);
    }
    return super.putObject(
      id: id,
      path: path,
      contents: contents,
      condition: condition,
    );
  }
}
