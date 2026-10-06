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
      etag: indexed!.remoteEtag,
    );

    final report = await engine.sync();
    final conflicts = await repository.listConflictFiles();

    expect(report.conflicts, 1);
    expect(conflicts, hasLength(1));
    expect(vault.files[local.markdownPath], contains('本地标题'));
    expect(vault.files[conflicts.single], contains('远端标题'));
  });
}
