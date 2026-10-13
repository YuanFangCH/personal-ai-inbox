import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/index_database.dart';
import 'package:personal_ai_inbox/data/io_vault_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/data/vault_store.dart';

void main() {
  late MemoryVaultStore vault;
  late MemoryIndexDatabase index;
  late ResultRepository repository;

  setUp(() async {
    vault = MemoryVaultStore();
    index = MemoryIndexDatabase();
    repository = ResultRepository(
      vault: vault,
      index: index,
      deviceId: 'test-device',
    );
    await repository.initialize();
  });

  test('writes one markdown file and rebuilds index from it', () async {
    final created = await repository.create(
      type: ResultType.knowledge,
      title: '离线知识',
      body: '正文',
      tags: const ['测试'],
    );

    expect(vault.files.keys, contains(created.markdownPath));
    await index.clear();
    expect(await index.listResults(), isEmpty);

    await repository.rebuildIndex();
    final indexed = await index.listResults();
    expect(indexed, hasLength(1));
    expect(indexed.single.id, created.id);
    expect(indexed.single.localHash, startsWith('sha256:'));
  });

  test('deletes by writing a tombstone instead of removing the file', () async {
    final created = await repository.create(
      type: ResultType.todo,
      title: '买牛奶',
      body: '',
      due: DateTime(2026, 10, 5, 18),
    );

    await repository.delete(created.id);
    final raw = vault.files[created.markdownPath]!;
    final indexed = await index.findResult(created.id);

    expect(raw, contains('deleted: true'));
    expect(indexed!.deleted, isTrue);
    expect(await repository.listDocuments(), isEmpty);
  });

  test(
    'replays an idempotent create without producing a second result',
    () async {
      final timestamp = DateTime(2026, 10, 13, 10);
      final first = await repository.create(
        type: ResultType.knowledge,
        title: '稳定动作',
        body: '同一输入只创建一次',
        createdAt: timestamp,
        idempotencyKey: 'capture:stable-test-action',
      );
      final replay = await repository.create(
        type: ResultType.knowledge,
        title: '稳定动作',
        body: '同一输入只创建一次',
        createdAt: timestamp.add(const Duration(days: 1)),
        idempotencyKey: 'capture:stable-test-action',
      );

      expect(replay.id, first.id);
      expect(await repository.listDocuments(), hasLength(1));
    },
  );

  test(
    'does not overwrite content when an idempotency key is reused',
    () async {
      final timestamp = DateTime(2026, 10, 13, 10);
      final first = await repository.create(
        type: ResultType.knowledge,
        title: '原始内容',
        body: '已提交',
        createdAt: timestamp,
        idempotencyKey: 'capture:stable-conflict',
      );

      await expectLater(
        repository.create(
          type: ResultType.knowledge,
          title: '变更内容',
          body: '不得覆盖',
          createdAt: timestamp,
          idempotencyKey: 'capture:stable-conflict',
        ),
        throwsA(isA<StateError>()),
      );
      expect((await repository.readDocument(first.id))!.title, '原始内容');
    },
  );

  test(
    'replays the prepared write after interruption before target replacement',
    () async {
      final crashVault = _FailOnceVaultStore();
      final firstRepository = ResultRepository(
        vault: crashVault,
        index: index,
        deviceId: 'test-device',
      );
      final original = await firstRepository.create(
        type: ResultType.knowledge,
        title: '旧标题',
        body: '旧内容',
      );
      crashVault.failNextResultWrite = true;

      await expectLater(
        firstRepository.save(original.copyWith(title: '新标题')),
        throwsA(isA<StateError>()),
      );
      expect(crashVault.files[original.markdownPath], contains('旧标题'));

      final restartedRepository = ResultRepository(
        vault: crashVault,
        index: index,
        deviceId: 'test-device',
      );
      await restartedRepository.initialize();

      expect(
        (await restartedRepository.readDocument(original.id))!.title,
        '新标题',
      );
      expect(
        crashVault.files.keys.where(
          (path) => path.contains('.local-transactions'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'repairs the index when a committed file precedes an index failure',
    () async {
      final failingIndex = _FailOnceIndexDatabase();
      await failingIndex.open();
      final firstRepository = ResultRepository(
        vault: vault,
        index: failingIndex,
        deviceId: 'test-device',
      );
      final original = await firstRepository.create(
        type: ResultType.knowledge,
        title: '旧标题',
        body: '正文',
      );
      failingIndex.failNextUpsert = true;

      await expectLater(
        firstRepository.save(original.copyWith(title: '已提交标题')),
        throwsA(isA<StateError>()),
      );
      expect(await failingIndex.findResult(original.id), isNotNull);

      final restartedRepository = ResultRepository(
        vault: vault,
        index: failingIndex,
        deviceId: 'test-device',
      );
      await restartedRepository.initialize();

      expect(
        (await restartedRepository.readDocument(original.id))!.title,
        '已提交标题',
      );
      expect(await failingIndex.listResults(), hasLength(1));
    },
  );

  test('repeated capture confirmation reuses the first result ID', () async {
    final timestamp = DateTime(2026, 10, 13, 10);
    final first = await repository.create(
      type: ResultType.knowledge,
      title: '重复确认',
      body: '同一动作',
      createdAt: timestamp,
      idempotencyKey: 'capture:cap_stable',
    );
    final replay = await repository.create(
      type: ResultType.knowledge,
      title: '重复确认',
      body: '同一动作',
      createdAt: timestamp,
      idempotencyKey: 'capture:cap_stable',
    );

    expect(replay.id, first.id);
    expect(await repository.listDocuments(), hasLength(1));
  });

  test(
    'recovery completes the action ledger and replays the same result',
    () async {
      final failingIndex = _FailOnceIndexDatabase();
      await failingIndex.open();
      final firstRepository = ResultRepository(
        vault: vault,
        index: failingIndex,
        deviceId: 'test-device',
      );
      await firstRepository.initialize();
      final timestamp = DateTime(2026, 10, 13, 10);
      failingIndex.failNextUpsert = true;

      await expectLater(
        firstRepository.create(
          type: ResultType.knowledge,
          title: '可重放动作',
          body: '正文',
          createdAt: timestamp,
          idempotencyKey: 'chat:user-message:0',
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        (await failingIndex.findOperation('chat:user-message:0'))!.state,
        OperationState.prepared,
      );

      final restartedRepository = ResultRepository(
        vault: vault,
        index: failingIndex,
        deviceId: 'test-device',
      );
      await restartedRepository.initialize();
      final replay = await restartedRepository.create(
        type: ResultType.knowledge,
        title: '可重放动作',
        body: '正文',
        createdAt: timestamp.add(const Duration(days: 2)),
        idempotencyKey: 'chat:user-message:0',
      );

      expect(
        (await failingIndex.findOperation('chat:user-message:0'))!.state,
        OperationState.completed,
      );
      expect(await restartedRepository.listDocuments(), hasLength(1));
      expect(replay.id, (await failingIndex.listResults()).single.id);
    },
  );

  test(
    'filesystem journal recovers after a result-file write failure',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'inbox-vault-recovery',
      );
      addTearDown(() => directory.delete(recursive: true));
      final realVault = IoVaultStore.at(directory);
      final flakyVault = _FailOnceIoVaultStore(realVault);
      final fileIndex = MemoryIndexDatabase();
      final firstRepository = ResultRepository(
        vault: flakyVault,
        index: fileIndex,
        deviceId: 'test-device',
      );
      await firstRepository.initialize();
      final original = await firstRepository.create(
        type: ResultType.knowledge,
        title: '旧标题',
        body: '正文',
      );
      flakyVault.failNextResultWrite = true;

      await expectLater(
        firstRepository.save(original.copyWith(title: '新标题')),
        throwsA(isA<StateError>()),
      );

      final restartedRepository = ResultRepository(
        vault: realVault,
        index: fileIndex,
        deviceId: 'test-device',
      );
      await restartedRepository.initialize();
      expect(
        (await restartedRepository.readDocument(original.id))!.title,
        '新标题',
      );
      expect(
        (await realVault.listMarkdownFiles()).where(
          (path) => path.contains('.local-transactions'),
        ),
        isEmpty,
      );
    },
  );
}

class _FailOnceVaultStore extends MemoryVaultStore {
  bool failNextResultWrite = false;

  @override
  Future<void> write(String relativePath, String contents) async {
    if (failNextResultWrite && relativePath.startsWith('vault/knowledge/')) {
      failNextResultWrite = false;
      throw StateError('Injected failure before replacing result');
    }
    await super.write(relativePath, contents);
  }
}

class _FailOnceIndexDatabase extends MemoryIndexDatabase {
  bool failNextUpsert = false;

  @override
  Future<void> upsertResult(IndexedResult result) async {
    if (failNextUpsert) {
      failNextUpsert = false;
      throw StateError('Injected index update failure');
    }
    await super.upsertResult(result);
  }
}

class _FailOnceIoVaultStore implements VaultStore {
  _FailOnceIoVaultStore(this._delegate);

  final IoVaultStore _delegate;
  bool failNextResultWrite = false;

  @override
  Future<T> exclusive<T>(Future<T> Function() operation) {
    return _delegate.exclusive(operation);
  }

  @override
  Future<void> initialize() => _delegate.initialize();

  @override
  Future<String?> read(String relativePath) => _delegate.read(relativePath);

  @override
  Future<void> write(String relativePath, String contents) async {
    if (failNextResultWrite && relativePath.startsWith('vault/knowledge/')) {
      failNextResultWrite = false;
      throw StateError('Injected result-file write failure');
    }
    await _delegate.write(relativePath, contents);
  }

  @override
  Future<void> delete(String relativePath) => _delegate.delete(relativePath);

  @override
  Future<List<String>> listMarkdownFiles() => _delegate.listMarkdownFiles();

  @override
  Future<String> describeRoot() => _delegate.describeRoot();
}
