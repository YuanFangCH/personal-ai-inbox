import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/markdown_codec.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/index_database.dart';
import 'package:personal_ai_inbox/data/io_vault_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/data/vault_store.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';

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
    'global knowledge requires exact human approval at every write path',
    () async {
      final library = ResultLibrary(repository: repository);
      await library.initialize();
      final candidate = await library.proposeGlobalKnowledgeChange(
        operation: GlobalKnowledgeOperation.create,
        candidateId: 'gkc_create_approval',
        proposal: const {
          'title': '本学期安排',
          'body': '2026 秋季学期共有 16 周。',
          'facts': {'semester_start': '2026-09-01', 'week_count': 16},
        },
      );

      expect(candidate.status, GlobalKnowledgeCandidateStatus.pending);
      expect(await repository.listDocuments(), isEmpty);
      await expectLater(
        library.confirmGlobalKnowledgeChange(
          candidate.id,
          displayedDigest: 'sha256:changed',
        ),
        throwsStateError,
      );
      await expectLater(
        repository.create(
          type: ResultType.knowledge,
          title: '绕过确认',
          body: '不允许',
          extensionFields: const {
            globalKnowledgeScopeKey: globalKnowledgeScopeValue,
          },
        ),
        throwsStateError,
      );

      final created = await library.confirmGlobalKnowledgeChange(
        candidate.id,
        displayedDigest: candidate.digest,
      );
      expect(created.document.isGlobalKnowledge, isTrue);
      expect(created.document.extensionFields['global_facts'], {
        'semester_start': '2026-09-01',
        'week_count': 16,
      });
      expect(
        (await repository.findGlobalKnowledgeCandidate(candidate.id))?.status,
        GlobalKnowledgeCandidateStatus.applied,
      );

      final raw = vault.files[created.document.markdownPath]!;
      final currentHash = repository.hashMarkdown(raw);
      await expectLater(
        repository.save(created.document.copyWith(body: '直接篡改')),
        throwsStateError,
      );
      await expectLater(
        repository.delete(created.document.id),
        throwsStateError,
      );
      await expectLater(
        library.undoAction(created.action.id),
        throwsStateError,
      );

      final updateCandidate = await library.proposeGlobalKnowledgeChange(
        operation: GlobalKnowledgeOperation.update,
        candidateId: 'gkc_update_approval',
        targetId: created.document.id,
        expectedRevision: created.document.revision,
        expectedHash: currentHash,
        proposal: const {
          'title': '本学期安排（修订）',
          'body': '2026 秋季学期共有 17 周。',
          'facts': {'semester_start': '2026-09-01', 'week_count': 17},
        },
      );
      final updated = await library.confirmGlobalKnowledgeChange(
        updateCandidate.id,
        displayedDigest: updateCandidate.digest,
      );
      expect(updated.document.title, '本学期安排（修订）');
      expect(updated.document.isGlobalKnowledge, isTrue);

      final updatedHash = repository.hashMarkdown(
        vault.files[updated.document.markdownPath]!,
      );
      final deleteCandidate = await library.proposeGlobalKnowledgeChange(
        operation: GlobalKnowledgeOperation.delete,
        candidateId: 'gkc_delete_approval',
        targetId: updated.document.id,
        expectedRevision: updated.document.revision,
        expectedHash: updatedHash,
        proposal: const {},
      );
      final deleted = await library.confirmGlobalKnowledgeChange(
        deleteCandidate.id,
        displayedDigest: deleteCandidate.digest,
      );
      expect(deleted.document.deleted, isTrue);
      expect(deleted.document.isGlobalKnowledge, isTrue);
      await expectLater(
        library.undoAction(deleted.action.id),
        throwsStateError,
      );
      await library.shutdown();
      library.dispose();
    },
  );

  test(
    'reversible result operations use CAS and undo with new revisions',
    () async {
      final createdAt = DateTime(2026, 10, 4, 9);
      final created = await repository.create(
        type: ResultType.knowledge,
        title: '术语',
        body: '旧正文',
        createdAt: createdAt,
      );
      final actionCreatedAt = DateTime.now();
      final createdWithUndo = await repository.create(
        type: ResultType.todo,
        title: '提交材料',
        body: '初稿',
        createdAt: createdAt.add(const Duration(minutes: 1)),
        idempotencyKey: 'undoable-create',
        reversibleActionId: 'action-create-1',
      );
      final createAction = await repository.findReversibleAction(
        'action-create-1',
      );
      expect(createAction?.status, ReversibleActionStatus.applied);
      expect(createAction?.kind, ReversibleActionKind.create);
      expect(createAction?.undoUntil.isAfter(actionCreatedAt), isTrue);

      final originalMarkdown = vault.files[created.markdownPath]!;
      final originalHash = repository.hashMarkdown(originalMarkdown);
      final updated = await repository.saveWithUndo(
        document: created.copyWith(body: '修改正文'),
        expectedRevision: created.revision,
        expectedHash: originalHash,
        actionId: 'action-update-1',
      );
      expect(updated.body, '修改正文');
      expect(updated.revision, created.revision + 1);
      await expectLater(
        repository.saveWithUndo(
          document: created.copyWith(body: '过期修改'),
          expectedRevision: created.revision,
          expectedHash: originalHash,
          actionId: 'action-update-stale',
        ),
        throwsStateError,
      );

      final undoUpdate = await repository.undoAction('action-update-1');
      expect(undoUpdate.status, ReversibleActionStatus.undone);
      final restored = await repository.readDocument(created.id);
      expect(restored?.body, '旧正文');
      expect(restored?.revision, updated.revision + 1);

      final deleteHash = repository.hashMarkdown(
        vault.files[created.markdownPath]!,
      );
      final tombstone = await repository.deleteWithUndo(
        id: created.id,
        expectedRevision: restored!.revision,
        expectedHash: deleteHash,
        actionId: 'action-delete-1',
      );
      expect(tombstone.deleted, isTrue);
      final undoDelete = await repository.undoAction('action-delete-1');
      expect(undoDelete.status, ReversibleActionStatus.undone);
      final restoredDelete = await repository.readDocument(created.id);
      expect(restoredDelete?.deleted, isFalse);
      expect(restoredDelete?.body, '旧正文');
      expect(restoredDelete?.revision, tombstone.revision + 1);

      final createUndo = await repository.undoAction('action-create-1');
      expect(createUndo.status, ReversibleActionStatus.undone);
      final createdTombstone = await repository.readDocument(
        createdWithUndo.id,
      );
      expect(createdTombstone?.deleted, isTrue);
      expect(
        vault.files[createdWithUndo.markdownPath],
        contains('deleted: true'),
      );
    },
  );

  test(
    'reversible undo refuses stale versions and expires old snapshots',
    () async {
      final original = await repository.create(
        type: ResultType.knowledge,
        title: '课程',
        body: '周数为十六',
      );
      final previousHash = repository.hashMarkdown(
        vault.files[original.markdownPath]!,
      );
      final updated = await repository.saveWithUndo(
        document: original.copyWith(body: '周数为十五'),
        expectedRevision: original.revision,
        expectedHash: previousHash,
        actionId: 'action-undo-expired',
      );
      await repository.save(updated.copyWith(body: '稍后人工修改'));
      await expectLater(
        repository.undoAction('action-undo-expired'),
        throwsStateError,
      );
      expect(
        (await repository.findReversibleAction('action-undo-expired'))?.status,
        ReversibleActionStatus.failed,
      );

      final current = await repository.findDocument(original.id);
      final currentHash = repository.hashMarkdown(
        vault.files[original.markdownPath]!,
      );
      final expiring = await repository.saveWithUndo(
        document: current!.copyWith(body: '限时版本'),
        expectedRevision: current.revision,
        expectedHash: currentHash,
        actionId: 'action-undo-expiring',
      );
      final action = await repository.findReversibleAction(
        'action-undo-expiring',
      );
      await expectLater(
        repository.undoAction(
          'action-undo-expiring',
          now: action!.undoUntil.add(const Duration(seconds: 1)),
        ),
        throwsStateError,
      );
      expect(
        (await repository.findReversibleAction('action-undo-expiring'))?.status,
        ReversibleActionStatus.expired,
      );
      expect((await repository.findDocument(original.id))?.body, '限时版本');
      expect(expiring.revision, current.revision + 1);
    },
  );

  test(
    'recovers a committed reversible edit and keeps its undo snapshot',
    () async {
      final failureIndex = _FailOnceIndexDatabase();
      final failureVault = MemoryVaultStore();
      final initialRepository = ResultRepository(
        vault: failureVault,
        index: failureIndex,
        deviceId: 'test-device',
      );
      await initialRepository.initialize();
      final original = await initialRepository.create(
        type: ResultType.matter,
        title: '作业',
        body: '原始要求',
      );
      final oldHash = initialRepository.hashMarkdown(
        failureVault.files[original.markdownPath]!,
      );
      failureIndex.failNextUpsert = true;
      await expectLater(
        initialRepository.saveWithUndo(
          document: original.copyWith(body: '更新后的要求'),
          expectedRevision: original.revision,
          expectedHash: oldHash,
          actionId: 'action-recovery-edit',
        ),
        throwsStateError,
      );

      final recoveredRepository = ResultRepository(
        vault: failureVault,
        index: failureIndex,
        deviceId: 'test-device',
      );
      await recoveredRepository.initialize();
      expect(
        (await recoveredRepository.findReversibleAction('action-recovery-edit'))
            ?.status,
        ReversibleActionStatus.applied,
      );
      expect(
        (await recoveredRepository.readDocument(original.id))?.body,
        '更新后的要求',
      );
      await recoveredRepository.undoAction('action-recovery-edit');
      expect(
        (await recoveredRepository.readDocument(original.id))?.body,
        '原始要求',
      );
    },
  );

  test('searches normalized title body and tags with stable paging', () async {
    final first = await repository.create(
      type: ResultType.knowledge,
      title: 'Alpha',
      body: 'Literal 100%_ token',
      tags: const ['Needle'],
      createdAt: DateTime(2026, 1, 1),
    );
    await repository.create(
      type: ResultType.knowledge,
      title: 'Other',
      body: 'unrelated',
      tags: const ['needle'],
      createdAt: DateTime(2026, 1, 2),
    );

    expect(
      (await repository.searchDocuments(
        query: '100%_',
        type: ResultType.knowledge,
        offset: 0,
      )).single.id,
      first.id,
    );
    expect(
      await repository.searchDocuments(
        query: 'NEEDLE',
        type: ResultType.knowledge,
        offset: 0,
        limit: 1,
      ),
      hasLength(1),
    );
    expect(
      (await repository.searchDocuments(
        query: 'needle',
        type: ResultType.knowledge,
        offset: 1,
      )),
      hasLength(1),
    );
  });

  test(
    'index rebuild reports malformed files and excludes duplicate IDs',
    () async {
      final knowledge = await repository.create(
        type: ResultType.knowledge,
        title: '重复 ID',
        body: '知识文件',
      );
      final duplicate = knowledge.copyWith(type: ResultType.matter);
      await vault.write(
        duplicate.markdownPath,
        const MarkdownCodec().encode(duplicate),
      );
      await vault.write(
        'vault/knowledge/broken.md',
        'not valid markdown frontmatter',
      );

      final report = await repository.rebuildIndex();

      expect(report.scanned, 3);
      expect(report.indexed, 0);
      expect(report.failed, 3);
      expect(await repository.listIndex(), isEmpty);
      expect(
        report.diagnostics.map((item) => item.path),
        contains(knowledge.markdownPath),
      );
      expect(
        report.diagnostics.map((item) => item.path),
        contains(duplicate.markdownPath),
      );
      expect(
        report.diagnostics.map((item) => item.path),
        contains('vault/knowledge/broken.md'),
      );
    },
  );

  test(
    'saving a legacy Markdown file retains unknown extension fields',
    () async {
      final document = await repository.create(
        type: ResultType.knowledge,
        title: 'Legacy extension',
        body: 'Original body',
      );
      final source = vault.files[document.markdownPath]!;
      final withExtension = source.replaceFirst(
        'deleted: false\n',
        'deleted: false\nvendor_field: keep-me\n',
      );
      await vault.write(document.markdownPath, withExtension);
      await repository.rebuildIndex();

      final loaded = await repository.readDocument(document.id);
      expect(loaded!.extensionFields['vendor_field'], 'keep-me');
      await repository.save(loaded.copyWith(title: 'Edited legacy extension'));

      final saved = await repository.readRaw(document.markdownPath);
      expect(saved, contains('vendor_field: "keep-me"'));
      expect(
        (await repository.readDocument(document.id))!.title,
        'Edited legacy extension',
      );
    },
  );

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
