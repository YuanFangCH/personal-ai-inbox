import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/table_markdown_codec.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/table_repository.dart';
import 'package:personal_ai_inbox/modules/tables/table_library.dart';

void main() {
  test(
    'inbox assignment journal resumes a before image only on explicit retry',
    () async {
      final vault = _CrashAtInboxAssignmentWriteVault();
      final index = MemoryIndexDatabase();
      await index.open();
      final repository = TableRepository(vault: vault, index: index);
      await repository.initialize();
      final source = (await repository.inboxAssignments()).targetFor(
        InboxAssignmentKind.todo,
      )!;
      final target = await repository.createTable(title: '收纳目标');
      final before = await vault.read(TableRepository.inboxAssignmentsPath);
      final assignments = await repository.inboxAssignments();
      vault.failBeforeAssignmentWrite = true;

      await expectLater(
        repository.assignInboxTargetForOperation(
          operationId: 'act_inbox_resume',
          kind: InboxAssignmentKind.todo,
          expectedRevision: assignments.revision,
          expectedPreviousTableId: source,
          tableId: target.id,
        ),
        throwsStateError,
      );
      expect(await vault.read(TableRepository.inboxAssignmentsPath), before);
      expect(await vault.read(TableRepository.writeJournalPath), isNotNull);

      final reopened = TableRepository(vault: vault, index: index);
      await reopened.initialize();
      expect(await vault.read(TableRepository.inboxAssignmentsPath), before);
      expect(await vault.read(TableRepository.writeJournalPath), isNotNull);

      await expectLater(
        reopened.assignInboxTargetForOperation(
          operationId: 'act_inbox_resume',
          kind: InboxAssignmentKind.todo,
          expectedRevision: assignments.revision,
          expectedPreviousTableId: source,
          tableId: target.id,
          authorizationGuard: () async => false,
        ),
        throwsA(isA<InboxAssignmentAuthorizationDeferred>()),
      );
      expect(await vault.read(TableRepository.inboxAssignmentsPath), before);
      expect(await vault.read(TableRepository.writeJournalPath), isNotNull);

      final receipt = await reopened.assignInboxTargetForOperation(
        operationId: 'act_inbox_resume',
        kind: InboxAssignmentKind.todo,
        expectedRevision: assignments.revision,
        expectedPreviousTableId: source,
        tableId: target.id,
        authorizationGuard: () async => true,
      );
      expect(receipt.previousTableId, source);
      expect(receipt.tableId, target.id);
      expect(receipt.previousRevision, assignments.revision);
      expect(receipt.revision, assignments.revision + 1);
      expect(
        (await reopened.inboxAssignments()).targetFor(InboxAssignmentKind.todo),
        target.id,
      );
      expect(await vault.read(TableRepository.writeJournalPath), isNotNull);
      await expectLater(
        reopened.acknowledgeInboxAssignmentOperation(
          operationId: receipt.operationId,
          kind: receipt.kind,
          expectedRevision: receipt.previousRevision,
          expectedPreviousTableId: target.id,
          tableId: receipt.tableId,
        ),
        throwsStateError,
      );
      expect(
        await reopened.pendingInboxAssignmentOperationId(),
        receipt.operationId,
      );
      await reopened.acknowledgeInboxAssignmentOperation(
        operationId: receipt.operationId,
        kind: receipt.kind,
        expectedRevision: receipt.previousRevision,
        expectedPreviousTableId: receipt.previousTableId,
        tableId: receipt.tableId,
      );
      expect(await vault.read(TableRepository.writeJournalPath), isNull);
    },
  );

  test(
    'inbox assignment journal reuses the receipt after an after-image crash',
    () async {
      final vault = _CrashAtInboxAssignmentWriteVault();
      final index = MemoryIndexDatabase();
      await index.open();
      final repository = TableRepository(vault: vault, index: index);
      await repository.initialize();
      final source = (await repository.inboxAssignments()).targetFor(
        InboxAssignmentKind.todo,
      )!;
      final target = await repository.createTable(title: '收纳目标');
      final assignments = await repository.inboxAssignments();
      vault.failAfterAssignmentWrite = true;

      await expectLater(
        repository.assignInboxTargetForOperation(
          operationId: 'act_inbox_after',
          kind: InboxAssignmentKind.todo,
          expectedRevision: assignments.revision,
          expectedPreviousTableId: source,
          tableId: target.id,
        ),
        throwsStateError,
      );
      final after = await vault.read(TableRepository.inboxAssignmentsPath);
      expect((jsonDecode(after!) as Map)['revision'], assignments.revision + 1);
      expect(await vault.read(TableRepository.writeJournalPath), isNotNull);

      final reopened = TableRepository(vault: vault, index: index);
      await reopened.initialize();
      expect(await vault.read(TableRepository.inboxAssignmentsPath), after);
      final receipt = await reopened.assignInboxTargetForOperation(
        operationId: 'act_inbox_after',
        kind: InboxAssignmentKind.todo,
        expectedRevision: assignments.revision,
        expectedPreviousTableId: source,
        tableId: target.id,
      );
      expect(receipt.revision, assignments.revision + 1);
      expect(receipt.tableId, target.id);
      await reopened.acknowledgeInboxAssignmentOperation(
        operationId: receipt.operationId,
        kind: receipt.kind,
        expectedRevision: receipt.previousRevision,
        expectedPreviousTableId: receipt.previousTableId,
        tableId: receipt.tableId,
      );
      expect(await vault.read(TableRepository.writeJournalPath), isNull);
    },
  );

  test(
    'inbox assignment recovery preserves a third state without overwrite',
    () async {
      final vault = _CrashAtInboxAssignmentWriteVault();
      final index = MemoryIndexDatabase();
      await index.open();
      final repository = TableRepository(vault: vault, index: index);
      await repository.initialize();
      final source = (await repository.inboxAssignments()).targetFor(
        InboxAssignmentKind.todo,
      )!;
      final target = await repository.createTable(title: '收纳目标');
      final other = await repository.createTable(title: '外部目标');
      final assignments = await repository.inboxAssignments();
      vault.failBeforeAssignmentWrite = true;
      await expectLater(
        repository.assignInboxTargetForOperation(
          operationId: 'act_inbox_third_state',
          kind: InboxAssignmentKind.todo,
          expectedRevision: assignments.revision,
          expectedPreviousTableId: source,
          tableId: target.id,
        ),
        throwsStateError,
      );
      final external = jsonDecode(
        (await vault.read(TableRepository.inboxAssignmentsPath))!,
      ) as Map<String, dynamic>;
      (external['assignments'] as Map<String, dynamic>)['todo'] = other.id;
      external['revision'] = assignments.revision + 1;
      await vault.write(
        TableRepository.inboxAssignmentsPath,
        jsonEncode(external),
      );

      final reopened = TableRepository(vault: vault, index: index);
      await reopened.initialize();
      expect(reopened.inboxAssignmentNeedsReview, isTrue);
      expect(
        (await reopened.inboxAssignments()).targetFor(InboxAssignmentKind.todo),
        other.id,
      );
      await expectLater(
        reopened.createTable(title: '核对期间禁止写入'),
        throwsStateError,
      );
      expect(
        (jsonDecode((await vault.read(TableRepository.inboxAssignmentsPath))!)
            as Map)['assignments']['todo'],
        other.id,
      );
      expect(await vault.read(TableRepository.writeJournalPath), isNotNull);
    },
  );

  test(
    'third-state review blocks every table and recovery write path',
    () async {
      final vault = _CrashAtInboxAssignmentWriteVault();
      final index = MemoryIndexDatabase();
      await index.open();
      final repository = TableRepository(vault: vault, index: index);
      await repository.initialize();
      final source = (await repository.inboxAssignments()).targetFor(
        InboxAssignmentKind.todo,
      )!;
      final proposed = await repository.createTable(title: '提议目标');
      final external = await repository.createTable(title: '外部目标');
      final tableToDelete = await repository.createTable(title: '删除候选表');
      final tableWithEntrySeed = await repository.createTable(title: '内容候选表');
      final field = TableFieldDefinition(
        id: 'fld_third_state_write_gate',
        name: '分类',
        type: CustomFieldType.text,
      );
      final tableWithEntry = await repository.updateTable(
        tableWithEntrySeed.copyWith(fields: [field]),
        expectedRevision: tableWithEntrySeed.revision,
      );
      final now = DateTime.now();
      final entry = await repository.createEntry(
        TableEntryDocument(
          id: 'nt_third_state_write_gate',
          type: TableContentType.note,
          tableId: tableWithEntry.id,
          title: '保留内容',
          body: '核对期间不得修改',
          customValues: {field.id: '原字段值'},
          revision: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final expiringTable = await repository.createTable(title: '到期批次表');
      final expiredBatch = await repository.deleteTable(
        id: expiringTable.id,
        expectedRevision: expiringTable.revision,
        now: DateTime(2020),
      );
      final restoreTable = await repository.createTable(title: '恢复批次表');
      final restoreBatch = await repository.deleteTable(
        id: restoreTable.id,
        expectedRevision: restoreTable.revision,
        now: now,
      );
      final beforeRaw = await vault.read(TableRepository.inboxAssignmentsPath);
      final beforeAssignments = await repository.inboxAssignments();
      vault.failBeforeAssignmentWrite = true;
      await expectLater(
        repository.assignInboxTargetForOperation(
          operationId: 'act_third_state_all_writes',
          kind: InboxAssignmentKind.todo,
          expectedRevision: beforeAssignments.revision,
          expectedPreviousTableId: source,
          tableId: proposed.id,
        ),
        throwsStateError,
      );
      final externalState = jsonDecode(beforeRaw!) as Map<String, dynamic>;
      (externalState['assignments'] as Map<String, dynamic>)['todo'] =
          external.id;
      externalState['revision'] = beforeAssignments.revision + 1;
      await vault.write(
        TableRepository.inboxAssignmentsPath,
        jsonEncode(externalState),
      );
      final metadataAfterExternalEdit = await vault.read(
        TableRepository.inboxAssignmentsPath,
      );
      final journalBefore = await vault.read(TableRepository.writeJournalPath);

      final reopened = TableRepository(vault: vault, index: index);
      final library = TableLibrary(repository: reopened);
      await library.initialize();
      expect(library.inboxAssignmentNeedsReview, isTrue);
      final expiredBefore = await index.findTableRecoveryBatch(expiredBatch.id);
      expect(expiredBefore?.status, TableRecoveryStatus.active);

      final liveTableRaw = await vault.read(
        TableRepository.tablePath(tableToDelete.id),
      );
      final liveEntryRaw = await vault.read(
        TableRepository.entryPath(entry.id),
      );
      final fieldTableRaw = await vault.read(
        TableRepository.tablePath(tableWithEntry.id),
      );
      await expectLater(
        reopened.deleteEntry(id: entry.id, expectedRevision: entry.revision),
        throwsStateError,
      );
      await expectLater(
        reopened.deleteTable(
          id: tableToDelete.id,
          expectedRevision: tableToDelete.revision,
        ),
        throwsStateError,
      );
      await expectLater(
        reopened.restoreRecoveryBatch(restoreBatch.id),
        throwsStateError,
      );
      await expectLater(
        reopened.purgeExpiredRecoveryBatches(now: DateTime.now()),
        throwsStateError,
      );
      await expectLater(
        reopened.removeTableField(
          tableId: tableWithEntry.id,
          fieldId: field.id,
          expectedRevision: tableWithEntry.revision,
        ),
        throwsStateError,
      );

      expect(
        await vault.read(TableRepository.inboxAssignmentsPath),
        metadataAfterExternalEdit,
      );
      expect(await vault.read(TableRepository.writeJournalPath), journalBefore);
      expect(
        await vault.read(TableRepository.tablePath(tableToDelete.id)),
        liveTableRaw,
      );
      expect(
        await vault.read(TableRepository.entryPath(entry.id)),
        liveEntryRaw,
      );
      expect(
        await vault.read(TableRepository.tablePath(tableWithEntry.id)),
        fieldTableRaw,
      );
      expect(
        (await index.findTableRecoveryBatch(expiredBatch.id))?.status,
        TableRecoveryStatus.active,
      );
      expect(
        (await index.findTableRecoveryBatch(restoreBatch.id))?.status,
        TableRecoveryStatus.active,
      );
    },
  );

  test('v1 inbox assignment metadata reads with revision zero', () async {
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    await index.open();
    final seedRepository = TableRepository(vault: vault, index: index);
    await seedRepository.initialize();
    final seeded = await seedRepository.inboxAssignments();
    await vault.write(
      TableRepository.inboxAssignmentsPath,
      jsonEncode({
        'schema_version': 1,
        'seeded': true,
        'assignments': {
          for (final kind in InboxAssignmentKind.values)
            kind.wireName: seeded.targetFor(kind),
        },
      }),
    );
    final repository = TableRepository(vault: vault, index: index);
    await repository.initialize();
    expect((await repository.inboxAssignments()).revision, 0);
  });

  for (final failJournalCleanup in [false, true]) {
    test(
      'failed table commit restores file and index, cleanup failure: $failJournalCleanup',
      () async {
        final vault = _FailOnceJournalVault();
        final index = _FailOnceTableIndex();
        await index.open();
        final repository = TableRepository(vault: vault, index: index);
        await repository.initialize();
        final table = await repository.createTable(title: '回滚一致性');
        if (failJournalCleanup) {
          vault.failCleanup = true;
        } else {
          index.failUpsert = true;
        }
        await expectLater(
          repository.updateTable(
            table.copyWith(body: '不能留下的正文'),
            expectedRevision: table.revision,
          ),
          throwsStateError,
        );
        expect((await repository.readTable(table.id))!.body, table.body);
        expect((await index.findTable(table.id))!.revision, table.revision);
        expect(
          (await index.findTable(table.id))!.searchText,
          isNot(contains('不能留下的正文')),
        );
        expect(await vault.read(TableRepository.writeJournalPath), isNull);
        await repository.initialize();
        expect(
          (await repository.readTable(table.id))!.revision,
          table.revision,
        );
      },
    );
  }

  for (final newEntry in [true, false]) {
    for (final fileAlreadyWritten in [false, true]) {
      test(
        'recovers entry journal new: $newEntry file written: $fileAlreadyWritten',
        () async {
          final vault = MemoryVaultStore();
          final index = MemoryIndexDatabase();
          await index.open();
          final repository = TableRepository(vault: vault, index: index);
          await repository.initialize();
          final table = await repository.createTable(title: '内容恢复');
          final now = DateTime(2026, 11, 4);
          final original = TableEntryDocument(
            id: 'nt_journal_entry',
            type: TableContentType.note,
            tableId: table.id,
            title: '原记录',
            body: '原正文',
            revision: 1,
            createdAt: now,
            updatedAt: now,
          );
          if (!newEntry) await repository.createEntry(original);
          final path = TableRepository.entryPath(original.id);
          final before = await vault.read(path);
          final updated = original.copyWith(
            body: '恢复后的正文',
            revision: newEntry ? 1 : 2,
          );
          final after = const TableMarkdownCodec().encodeEntry(updated);
          await vault.write(
            TableRepository.writeJournalPath,
            jsonEncode({
              'schema_version': 1,
              'kind': 'entry',
              'id': original.id,
              'before': before,
              'after': after,
            }),
          );
          if (fileAlreadyWritten) await vault.write(path, after);
          final reopened = TableRepository(vault: vault, index: index);
          await reopened.initialize();
          expect((await reopened.readEntry(original.id))!.body, '恢复后的正文');
          expect(
            (await index.findTableEntry(original.id))!.revision,
            updated.revision,
          );
          expect(await vault.read(TableRepository.writeJournalPath), isNull);
          await reopened.initialize();
          expect(
            (await reopened.readEntry(original.id))!.revision,
            updated.revision,
          );
        },
      );
    }
  }

  for (final fileAlreadyWritten in [false, true]) {
    test(
      'recovers prepared table commit, file written: $fileAlreadyWritten',
      () async {
        final vault = MemoryVaultStore();
        final index = MemoryIndexDatabase();
        await index.open();
        final repository = TableRepository(vault: vault, index: index);
        await repository.initialize();
        final table = await repository.createTable(title: '恢复测试');
        final file = TableRepository.tablePath(table.id);
        final before = await vault.read(file);
        final updated = table.copyWith(
          body: '已提交的新正文',
          revision: table.revision + 1,
        );
        final after = const TableMarkdownCodec().encodeTable(updated);
        await vault.write(
          TableRepository.writeJournalPath,
          jsonEncode({
            'schema_version': 1,
            'kind': 'table',
            'id': table.id,
            'before': before,
            'after': after,
          }),
        );
        if (fileAlreadyWritten) await vault.write(file, after);
        final reopened = TableRepository(vault: vault, index: index);
        await reopened.initialize();
        expect((await reopened.readTable(table.id))!.body, '已提交的新正文');
        expect((await index.findTable(table.id))!.revision, updated.revision);
        expect(await vault.read(TableRepository.writeJournalPath), isNull);
        await reopened.initialize();
        expect(
          (await reopened.readTable(table.id))!.revision,
          updated.revision,
        );
      },
    );
  }

  test('recovery preserves an external edit and the pending journal', () async {
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    await index.open();
    final repository = TableRepository(vault: vault, index: index);
    await repository.initialize();
    final table = await repository.createTable(title: '外部修改');
    final file = TableRepository.tablePath(table.id);
    final before = await vault.read(file);
    const codec = TableMarkdownCodec();
    await vault.write(
      TableRepository.writeJournalPath,
      jsonEncode({
        'schema_version': 1,
        'kind': 'table',
        'id': table.id,
        'before': before,
        'after': codec.encodeTable(table.copyWith(body: '待提交版本', revision: 2)),
      }),
    );
    final external = codec.encodeTable(
      table.copyWith(body: '人工另行修改', revision: 3),
    );
    await vault.write(file, external);
    await expectLater(repository.initialize(), throwsStateError);
    expect(await vault.read(file), external);
    expect(await vault.read(TableRepository.writeJournalPath), isNotNull);
  });
}

class _FailOnceTableIndex extends MemoryIndexDatabase {
  bool failUpsert = false;
  @override
  Future<void> upsertTable(IndexedTable table) async {
    if (failUpsert) {
      failUpsert = false;
      throw StateError('injected index failure');
    }
    await super.upsertTable(table);
  }
}

class _FailOnceJournalVault extends MemoryVaultStore {
  bool failCleanup = false;
  @override
  Future<void> delete(String relativePath) async {
    if (failCleanup && relativePath == TableRepository.writeJournalPath) {
      failCleanup = false;
      throw StateError('injected journal cleanup failure');
    }
    await super.delete(relativePath);
  }
}

class _CrashAtInboxAssignmentWriteVault extends MemoryVaultStore {
  bool failBeforeAssignmentWrite = false;
  bool failAfterAssignmentWrite = false;

  @override
  Future<void> write(String relativePath, String contents) async {
    if (relativePath == TableRepository.inboxAssignmentsPath &&
        failBeforeAssignmentWrite) {
      failBeforeAssignmentWrite = false;
      throw StateError('injected before-image crash');
    }
    await super.write(relativePath, contents);
    if (relativePath == TableRepository.inboxAssignmentsPath &&
        failAfterAssignmentWrite) {
      failAfterAssignmentWrite = false;
      throw StateError('injected after-image crash');
    }
  }
}
