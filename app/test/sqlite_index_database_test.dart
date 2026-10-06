import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/sqlite_index_database.dart';

void main() {
  test('persists indexed results and capture records', () async {
    final directory = await Directory.systemTemp.createTemp('ai-inbox-index');
    addTearDown(() => directory.delete(recursive: true));
    final database = SqliteIndexDatabase('${directory.path}/index.sqlite3');
    await database.open();

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
    );
    await database.upsertResult(record);
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
    await reopened.close();
  });
}
