import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/index_database.dart';
import 'package:personal_ai_inbox/data/sqlite_index_database.dart';

void main() {
  test('persists indexed results and capture records', () async {
    final directory = await Directory.systemTemp.createTemp('ai-inbox-index');
    addTearDown(() => directory.delete(recursive: true));
    final database = SqliteIndexDatabase('${directory.path}/index.sqlite3');
    await database.open();
    final versionDatabase = sqlite3.open('${directory.path}/index.sqlite3');
    expect(
      versionDatabase.select('PRAGMA user_version').single['user_version'],
      5,
    );
    versionDatabase.close();

    final record = IndexedResult(
      id: 'kn_20261004_12345678',
      type: ResultType.knowledge,
      title: '持久化知识',
      status: ResultStatus.canonical,
      revision: 1,
      updatedAt: DateTime(2026, 10, 4, 12),
      deleted: false,
      mdPath: 'vault/knowledge/kn_20261004_12345678.md',
      localHash: 'sha256:test',
      lastSyncedHash: null,
      syncState: SyncState.pendingUpload,
      searchText: '标题 包含 100%_ 字符',
    );
    await database.upsertResult(record);
    expect(
      await database.searchResults(
        query: '100%_',
        limit: 50,
        offset: 0,
        type: ResultType.knowledge,
      ),
      hasLength(1),
    );
    final operation = IdempotentOperation(
      key: 'capture:test-idempotency',
      resultId: record.id,
      payloadHash: 'sha256:payload',
      state: OperationState.completed,
      createdAt: DateTime(2026, 10, 4, 12),
      updatedAt: DateTime(2026, 10, 4, 12),
    );
    await database.upsertOperation(operation);
    final conflict = SyncConflictRecord(
      resultId: record.id,
      remoteHash: 'sha256:remote',
      remoteEtag: 'etag-1',
      localHash: record.localHash,
      copyPath: 'vault/conflicts/${record.id}.md',
      createdAt: DateTime(2026, 10, 4, 12),
    );
    await database.upsertConflict(conflict);
    final reversibleAction = ReversibleResultAction(
      id: 'result-action-1',
      resultId: record.id,
      kind: ReversibleActionKind.update,
      status: ReversibleActionStatus.applied,
      expectedRevision: 2,
      expectedHash: 'sha256:next',
      previousMarkdown: 'old markdown snapshot',
      previousHash: 'sha256:previous',
      createdAt: DateTime(2026, 10, 4, 12),
      undoUntil: DateTime(2026, 10, 4, 12).add(const Duration(minutes: 10)),
    );
    await database.upsertReversibleAction(reversibleAction);
    final candidate = GlobalKnowledgeCandidate(
      id: 'gkc_candidate_1',
      operation: GlobalKnowledgeOperation.create,
      status: GlobalKnowledgeCandidateStatus.pending,
      proposal: const {
        'title': '本学期',
        'body': '周数为十六周',
        'facts': {'week_count': 16},
      },
      digest: 'sha256:proposal',
      createdAt: DateTime(2026, 10, 4, 12),
      updatedAt: DateTime(2026, 10, 4, 12),
    );
    await database.upsertGlobalKnowledgeCandidate(candidate);
    await database.insertCapture(
      CaptureRecord(
        id: 'cap-1',
        deviceId: 'test-device',
        capturedAt: DateTime(2026, 10, 4, 12),
        sourceType: CaptureSourceType.text,
        text: '测试捕获',
        status: CaptureStatus.needsReview,
      ),
    );
    await database.close();

    final reopened = SqliteIndexDatabase('${directory.path}/index.sqlite3');
    await reopened.open();
    expect((await reopened.findResult(record.id))!.title, '持久化知识');
    expect(await reopened.listCaptures(reviewOnly: true), hasLength(1));
    expect((await reopened.findOperation(operation.key))?.resultId, record.id);
    expect((await reopened.findConflict(record.id))?.remoteEtag, 'etag-1');
    expect(
      (await reopened.findReversibleAction(reversibleAction.id))?.status,
      ReversibleActionStatus.applied,
    );
    expect(
      (await reopened.findReversibleAction(reversibleAction.id))
          ?.previousMarkdown,
      'old markdown snapshot',
    );
    expect(
      (await reopened.findGlobalKnowledgeCandidate(candidate.id))
          ?.proposal['title'],
      '本学期',
    );
    await reopened.clear();
    expect(await reopened.findResult(record.id), isNull);
    expect(await reopened.findOperation(operation.key), isNotNull);
    expect(
      await reopened.findReversibleAction(reversibleAction.id),
      isNotNull,
      reason: 'index clearing/rebuild must retain local undo material',
    );
    expect(
      await reopened.findGlobalKnowledgeCandidate(candidate.id),
      isNotNull,
      reason: 'index clearing/rebuild must retain local approval state',
    );
    await reopened.close();
  });

  test('migrates an index v4 database while preserving records and creating candidate storage', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ai-inbox-index-v4',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/index.sqlite3';
    final index = SqliteIndexDatabase(path);
    await index.open();
    final createdAt = DateTime(2026, 10, 20, 9);
    final record = IndexedResult(
      id: 'kn_20261020_12345678',
      type: ResultType.knowledge,
      title: '迁移前知识',
      status: ResultStatus.canonical,
      revision: 1,
      updatedAt: createdAt,
      deleted: false,
      mdPath: 'vault/knowledge/kn_20261020_12345678.md',
      localHash: 'sha256:before-migration',
      lastSyncedHash: null,
      syncState: SyncState.pendingUpload,
    );
    await index.upsertResult(record);
    await index.close();

    final v4 = sqlite3.open(path)
      ..execute('DROP TABLE global_knowledge_candidates')
      ..execute('PRAGMA user_version = 4');
    v4.close();

    final migrated = SqliteIndexDatabase(path);
    await migrated.open();
    expect((await migrated.findResult(record.id))?.title, '迁移前知识');
    final migratedVersion = sqlite3.open(path);
    expect(
      migratedVersion.select('PRAGMA user_version').single['user_version'],
      5,
    );
    migratedVersion.close();
    await migrated.upsertReversibleAction(
      ReversibleResultAction(
        id: 'update-1',
        resultId: record.id,
        kind: ReversibleActionKind.update,
        status: ReversibleActionStatus.applied,
        expectedRevision: 2,
        expectedHash: 'sha256:after-migration',
        previousMarkdown: 'old body',
        previousHash: 'sha256:before-migration',
        createdAt: createdAt,
        undoUntil: createdAt.add(const Duration(minutes: 10)),
      ),
    );
    expect(
      (await migrated.findReversibleAction('update-1'))?.previousMarkdown,
      'old body',
    );
    final migratedCandidate = GlobalKnowledgeCandidate(
      id: 'gkc_after_v4',
      operation: GlobalKnowledgeOperation.create,
      status: GlobalKnowledgeCandidateStatus.pending,
      proposal: const {
        'title': '课程',
        'body': '开学日期待确认',
        'facts': {'semester_start': '2026-09-01'},
      },
      digest: 'sha256:proposal',
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    await migrated.upsertGlobalKnowledgeCandidate(migratedCandidate);
    expect(
      (await migrated.findGlobalKnowledgeCandidate(migratedCandidate.id))
          ?.status,
      GlobalKnowledgeCandidateStatus.pending,
    );
    await migrated.close();
  });
}
