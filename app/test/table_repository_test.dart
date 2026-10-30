import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/table_markdown_codec.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/io_vault_store.dart';
import 'package:personal_ai_inbox/data/sqlite_index_database.dart';
import 'package:personal_ai_inbox/data/table_repository.dart';
import 'package:personal_ai_inbox/data/vault_store.dart';

void main() {
  test(
    'initializes default tables idempotently and stores mixed entries',
    () async {
      final vault = MemoryVaultStore();
      final index = MemoryIndexDatabase();
      final repository = TableRepository(vault: vault, index: index);
      await index.open();
      await repository.initialize();
      await repository.ensureDefaultTables();

      expect(await repository.listTables(), hasLength(3));
      final table = await repository.createTable(title: '期中考试', body: '考试信息');
      final note = TableEntryDocument(
        id: 'nt_exam_notes',
        type: TableContentType.note,
        tableId: table.id,
        title: '考试范围',
        revision: 1,
        createdAt: DateTime.parse('2026-10-29T09:00:00+08:00'),
        updatedAt: DateTime.parse('2026-10-29T09:00:00+08:00'),
        body: '信号与系统第二章',
      );
      final todo = TableEntryDocument(
        id: 'td_exam_card',
        type: TableContentType.todo,
        title: '确认准考证',
        tableId: table.id,
        revision: 1,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
        body: '',
        due: DateTime.parse('2026-10-30T20:00:00+08:00'),
      );
      await repository.createEntry(note);
      await repository.createEntry(todo);

      expect(await repository.listEntries(tableId: table.id), hasLength(2));
      final results = await repository.searchEntries(
        query: '信号与系统',
        tableId: table.id,
        type: TableContentType.note,
      );
      expect(results.single.id, note.id);
      expect(
        (await repository.readEntry(todo.id))?.type,
        TableContentType.todo,
      );
      expect(await index.listTables(), hasLength(4));
    },
  );

  test(
    'index rebuild restores file changes and drops missing projections',
    () async {
      final vault = MemoryVaultStore();
      final index = MemoryIndexDatabase();
      final repository = TableRepository(vault: vault, index: index);
      await repository.initialize();
      final table = await repository.createTable(title: '重建测试');
      final now = DateTime.parse('2026-10-29T09:00:00+08:00');
      final note = TableEntryDocument(
        id: 'nt_rebuild',
        type: TableContentType.note,
        tableId: table.id,
        title: '索引重建',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '从 Markdown 还原',
      );
      await repository.createEntry(note);
      await index.removeTableEntry(note.id);
      final rebuilt = await repository.rebuildIndex();
      expect(rebuilt.failed, 0);
      expect(await repository.readEntry(note.id), isNotNull);

      await vault.delete(TableRepository.entryPath(note.id));
      await repository.rebuildIndex();
      expect(await index.findTableEntry(note.id), isNull);
    },
  );

  test(
    'index rebuild refuses a missing table owner for orphan content',
    () async {
      final vault = MemoryVaultStore();
      final index = MemoryIndexDatabase();
      final repository = TableRepository(vault: vault, index: index);
      await repository.initialize();
      final now = DateTime.parse('2026-10-29T09:00:00+08:00');
      final orphan = TableEntryDocument(
        id: 'nt_orphan',
        type: TableContentType.note,
        tableId: 'tb_missing',
        title: '无归属笔记',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '不能静默分配默认表',
      );
      await vault.write(
        TableRepository.entryPath(orphan.id),
        const TableMarkdownCodec().encodeEntry(orphan),
      );

      final report = await repository.rebuildIndex();

      expect(report.failed, 1);
      expect(await index.findTableEntry(orphan.id), isNull);
      expect(await repository.readEntry(orphan.id), isNotNull);
      expect(await repository.listEntries(), isEmpty);
    },
  );

  test('refuses a field change that would orphan saved values', () async {
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    final repository = TableRepository(vault: vault, index: index);
    await repository.initialize();
    final table = await repository.createTable(title: '字段测试');
    final field = TableFieldDefinition(
      id: 'fld_course',
      name: '课程',
      type: CustomFieldType.text,
    );
    final updatedTable = await repository.updateTable(
      table.copyWith(fields: [field]),
      expectedRevision: 1,
    );
    final now = DateTime.parse('2026-10-29T09:00:00+08:00');
    await repository.createEntry(
      TableEntryDocument(
        id: 'nt_field_value',
        type: TableContentType.note,
        tableId: table.id,
        title: '课程笔记',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '',
        customValues: const {'fld_course': '信号与系统'},
      ),
    );

    await expectLater(
      repository.updateTable(
        updatedTable.copyWith(fields: const []),
        expectedRevision: 2,
      ),
      throwsFormatException,
    );
    expect(
      (await repository.readTable(table.id))?.fields.single.id,
      'fld_course',
    );
  });

  test('deletes and restores one entry inside the short undo window', () async {
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    final repository = TableRepository(vault: vault, index: index);
    await repository.initialize();
    final table = await repository.createTable(title: '单条撤销');
    final now = DateTime.parse('2026-10-29T09:00:00+08:00');
    final note = TableEntryDocument(
      id: 'nt_single_undo',
      type: TableContentType.note,
      tableId: table.id,
      title: '可撤销内容',
      revision: 1,
      createdAt: now,
      updatedAt: now,
      body: '保留正文',
    );
    await repository.createEntry(note);

    final batch = await repository.deleteEntry(
      id: note.id,
      expectedRevision: 1,
      idempotencyKey: 'single-delete-once',
      now: now,
    );
    expect(batch.scope, TableRecoveryScope.entry);
    expect((await repository.readEntry(note.id))?.deleted, isTrue);
    expect(
      (await repository.deleteEntry(
        id: note.id,
        expectedRevision: 1,
        idempotencyKey: 'single-delete-once',
        now: now,
      )).id,
      batch.id,
    );

    final restored = await repository.restoreRecoveryBatch(
      batch.id,
      now: now.add(const Duration(minutes: 9)),
    );
    final entry = await repository.readEntry(note.id);
    expect(restored.status, TableRecoveryStatus.restored);
    expect(entry?.deleted, isFalse);
    expect(entry?.id, note.id);
    expect(entry?.revision, 3);
    expect(entry?.body, note.body);

    final expiringEntry = TableEntryDocument(
      id: 'nt_single_expiring',
      type: TableContentType.note,
      tableId: note.tableId,
      title: '短期撤销超时',
      revision: 1,
      createdAt: now,
      updatedAt: now,
      body: note.body,
    );
    await repository.createEntry(expiringEntry);
    final expiringBatch = await repository.deleteEntry(
      id: expiringEntry.id,
      expectedRevision: 1,
      idempotencyKey: 'single-delete-expiring',
      now: now,
    );
    await expectLater(
      repository.restoreRecoveryBatch(
        expiringBatch.id,
        now: now.add(const Duration(minutes: 10)),
      ),
      throwsStateError,
    );
    expect((await repository.readEntry(expiringEntry.id))?.body, isEmpty);
  });

  test(
    'deletes a custom table as one 30-day batch and protects defaults',
    () async {
      final vault = MemoryVaultStore();
      final index = MemoryIndexDatabase();
      final repository = TableRepository(vault: vault, index: index);
      await repository.initialize();
      final now = DateTime.parse('2026-10-29T09:00:00+08:00');
      final table = await repository.createTable(title: '考试', body: '考试说明');
      final entry = TableEntryDocument(
        id: 'nt_exam_notice',
        type: TableContentType.note,
        tableId: table.id,
        title: '地点通知',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '三教101',
      );
      await repository.createEntry(entry);

      final batch = await repository.deleteTable(
        id: table.id,
        expectedRevision: 1,
        idempotencyKey: 'delete-exam-once',
        now: now,
      );
      expect(batch.scope, TableRecoveryScope.table);
      expect((await repository.readTable(table.id))?.deleted, isTrue);
      expect((await repository.readEntry(entry.id))?.deleted, isTrue);
      final preview = await repository.previewDeletedTable(batch.id);
      expect(preview?.table.title, '考试');
      expect(preview?.table.body, '考试说明');
      expect(preview?.entries.map((item) => item.title), ['地点通知']);
      await expectLater(
        repository.deleteTable(
          id: TableRepository.defaultTables.first.$1,
          expectedRevision: 1,
          now: now,
        ),
        throwsStateError,
      );

      final restored = await repository.restoreRecoveryBatch(
        batch.id,
        now: now.add(const Duration(days: 29)),
      );
      expect(restored.status, TableRecoveryStatus.restored);
      expect((await repository.readTable(table.id))?.body, '考试说明');
      expect((await repository.readEntry(entry.id))?.body, '三教101');
      expect((await repository.readEntry(entry.id))?.tableId, table.id);
    },
  );

  test('resumes a table restore interrupted between object writes', () async {
    final vault = _FailingVaultStore(MemoryVaultStore());
    final index = MemoryIndexDatabase();
    final repository = TableRepository(vault: vault, index: index);
    await repository.initialize();
    final table = await repository.createTable(title: '恢复中断');
    final now = DateTime.parse('2026-10-29T09:00:00+08:00');
    final entry = TableEntryDocument(
      id: 'nt_restore_interrupted',
      type: TableContentType.note,
      tableId: table.id,
      title: '恢复正文',
      revision: 1,
      createdAt: now,
      updatedAt: now,
      body: '前像',
    );
    await repository.createEntry(entry);
    final batch = await repository.deleteTable(
      id: table.id,
      expectedRevision: 1,
      now: now,
    );
    vault.failOnNextManagedWrite = 2;
    await expectLater(
      repository.restoreRecoveryBatch(
        batch.id,
        now: now.add(const Duration(days: 1)),
      ),
      throwsStateError,
    );
    expect(
      (await index.findTableRecoveryBatch(batch.id))?.status,
      TableRecoveryStatus.restoring,
    );
    vault.failOnNextManagedWrite = null;

    final restarted = TableRepository(vault: vault, index: index);
    await restarted.initialize();
    expect(
      (await index.findTableRecoveryBatch(batch.id))?.status,
      TableRecoveryStatus.restored,
    );
    expect((await restarted.readTable(table.id))?.deleted, isFalse);
    expect((await restarted.readEntry(entry.id))?.body, '前像');
  });

  test(
    'table deletion removes and restores external schedule references',
    () async {
      final vault = MemoryVaultStore();
      final index = MemoryIndexDatabase();
      final repository = TableRepository(vault: vault, index: index);
      await repository.initialize();
      final scheduleTable = await repository.createTable(title: '考试');
      final eventTable = await repository.createTable(title: '教务通知');
      final now = DateTime.parse('2026-10-29T09:00:00+08:00');
      final schedule = TableEntryDocument(
        id: 'sc_cross_table',
        type: TableContentType.schedule,
        tableId: scheduleTable.id,
        title: '期中考试',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '',
        start: now.add(const Duration(days: 2)),
      );
      final event = TableEntryDocument(
        id: 'ev_cross_table',
        type: TableContentType.event,
        tableId: eventTable.id,
        title: '改期通知',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '考试改期',
        affects: [ScheduleChange(scheduleId: schedule.id)],
      );
      await repository.createEntry(schedule);
      await repository.createEntry(event);

      final batch = await repository.deleteTable(
        id: scheduleTable.id,
        expectedRevision: 1,
        now: now,
      );
      expect((await repository.readEntry(event.id))!.affects, isEmpty);

      await repository.restoreRecoveryBatch(
        batch.id,
        now: now.add(const Duration(days: 1)),
      );
      expect(
        (await repository.readEntry(event.id))!.affects.single.scheduleId,
        schedule.id,
      );
    },
  );

  test(
    'single schedule deletion removes and restores its event links',
    () async {
      final vault = MemoryVaultStore();
      final index = MemoryIndexDatabase();
      final repository = TableRepository(vault: vault, index: index);
      await repository.initialize();
      final scheduleTable = await repository.createTable(title: '考试安排');
      final eventTable = await repository.createTable(title: '考试通知');
      final now = DateTime.parse('2026-10-29T09:00:00+08:00');
      final schedule = TableEntryDocument(
        id: 'sc_single_delete',
        type: TableContentType.schedule,
        tableId: scheduleTable.id,
        title: '期末考试',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '',
        start: now.add(const Duration(days: 5)),
      );
      final event = TableEntryDocument(
        id: 'ev_single_delete',
        type: TableContentType.event,
        tableId: eventTable.id,
        title: '考试改期',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '',
        affects: [ScheduleChange(scheduleId: schedule.id)],
      );
      await repository.createEntry(schedule);
      await repository.createEntry(event);

      final batch = await repository.deleteEntry(
        id: schedule.id,
        expectedRevision: schedule.revision,
        now: now,
      );
      expect((await repository.readEntry(event.id))!.affects, isEmpty);
      expect(
        (await index.findTableRecoveryBatch(batch.id))!.manifestJson,
        contains(event.id),
      );

      await repository.restoreRecoveryBatch(
        batch.id,
        now: now.add(const Duration(minutes: 1)),
      );
      expect((await repository.readEntry(schedule.id))!.deleted, isFalse);
      expect(
        (await repository.readEntry(event.id))!.affects.single.scheduleId,
        schedule.id,
      );
    },
  );

  test(
    'schedule change commits a linked event and can be undone together',
    () async {
      final vault = MemoryVaultStore();
      final index = MemoryIndexDatabase();
      final repository = TableRepository(vault: vault, index: index);
      await repository.initialize();
      final table = await repository.createTable(title: '考试');
      final now = DateTime.parse('2026-10-29T09:00:00+08:00');
      final originalStart = now.add(const Duration(days: 2));
      final schedule = TableEntryDocument(
        id: 'sc_rescheduled',
        type: TableContentType.schedule,
        tableId: table.id,
        title: '期中考试',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '高数',
        start: originalStart,
      );
      await repository.createEntry(schedule);
      final newStart = now.add(const Duration(days: 5));

      final changed = await repository.changeScheduleFromEvent(
        scheduleId: schedule.id,
        expectedRevision: 1,
        start: newStart,
        eventTitle: '考试改期通知',
        eventBody: '老师把考试从周五改到周一',
        idempotencyKey: 'exam-rescheduled',
        now: now,
      );
      expect(changed.batch.scope, TableRecoveryScope.scheduleChange);
      expect(changed.schedule.start!.isAtSameMomentAs(newStart), isTrue);
      expect(changed.event.type, TableContentType.event);
      expect(changed.event.body, '老师把考试从周五改到周一');
      expect(changed.event.affects.single.scheduleId, schedule.id);

      final retry = await repository.changeScheduleFromEvent(
        scheduleId: schedule.id,
        expectedRevision: 1,
        start: originalStart,
        eventTitle: '重试不得重复',
        eventBody: '重试',
        idempotencyKey: 'exam-rescheduled',
        now: now,
      );
      expect(retry.event.id, changed.event.id);
      expect(
        (await repository.listEntries(
          tableId: table.id,
          type: TableContentType.event,
        )),
        hasLength(1),
      );

      final undone = await repository.restoreRecoveryBatch(
        changed.batch.id,
        now: now.add(const Duration(minutes: 5)),
      );
      expect(undone.status, TableRecoveryStatus.restored);
      expect(
        (await repository.readEntry(schedule.id))!.start!
            .isAtSameMomentAs(originalStart),
        isTrue,
      );
      expect((await repository.readEntry(changed.event.id))?.deleted, isTrue);
    },
  );

  test(
    'replays a partially written schedule change without duplicating its event',
    () async {
      final vault = _FailingVaultStore(MemoryVaultStore());
      final index = MemoryIndexDatabase();
      final repository = TableRepository(vault: vault, index: index);
      await repository.initialize();
      final table = await repository.createTable(title: '故障恢复');
      final now = DateTime.parse('2026-11-29T09:00:00+08:00');
      final schedule = TableEntryDocument(
        id: 'sc_replay',
        type: TableContentType.schedule,
        tableId: table.id,
        title: '考试',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '',
        start: now.add(const Duration(days: 2)),
      );
      await repository.createEntry(schedule);
      vault.failOnNextManagedWrite = 2;
      await expectLater(
        repository.changeScheduleFromEvent(
          scheduleId: schedule.id,
          expectedRevision: 1,
          start: now.add(const Duration(days: 5)),
          eventTitle: '考试改期',
          eventBody: '通知正文',
          idempotencyKey: 'schedule-change-replay',
          now: now,
        ),
        throwsStateError,
      );
      vault.failOnNextManagedWrite = null;

      final restarted = TableRepository(vault: vault, index: index);
      await restarted.initialize();
      final events = await restarted.listEntries(
        tableId: table.id,
        type: TableContentType.event,
      );
      expect(events, hasLength(1));
      expect(
        (await restarted.readEntry(schedule.id))!.start!
            .isAtSameMomentAs(now.add(const Duration(days: 5))),
        isTrue,
      );
      final batch = (await index.listTableRecoveryBatches(
        activeOnly: true,
      )).singleWhere((item) => item.scope == TableRecoveryScope.scheduleChange);
      expect(batch.status, TableRecoveryStatus.active);
    },
  );

  test(
    'expires full-table recovery material at 30 days and hardens tombstones',
    () async {
      final vault = MemoryVaultStore();
      final index = MemoryIndexDatabase();
      final repository = TableRepository(vault: vault, index: index);
      await repository.initialize();
      final now = DateTime.parse('2026-10-29T09:00:00+08:00');
      final table = await repository.createTable(title: '超期表', body: '有期限');
      final child = TableEntryDocument(
        id: 'nt_expired_child',
        type: TableContentType.note,
        tableId: table.id,
        title: '正文',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '到期应清空',
      );
      await repository.createEntry(child);
      final batch = await repository.deleteTable(
        id: table.id,
        expectedRevision: 1,
        idempotencyKey: 'expire-table',
        now: now,
      );

      await repository.purgeExpiredRecoveryBatches(
        now: now.add(const Duration(days: 30)),
      );

      expect(
        (await index.findTableRecoveryBatch(batch.id))?.status,
        TableRecoveryStatus.expired,
      );
      expect((await repository.readTable(table.id))?.body, isEmpty);
      expect((await repository.readEntry(child.id))?.body, isEmpty);
      final manifest = jsonDecode(batch.manifestJson) as Map<String, dynamic>;
      final first = (manifest['objects'] as List).first as Map<String, dynamic>;
      expect(await vault.read(first['before_path'] as String), isNull);
      await expectLater(
        repository.restoreRecoveryBatch(
          batch.id,
          now: now.add(const Duration(days: 30)),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'replays a partially applied table deletion from its prepared ledger',
    () async {
      final vault = _FailingVaultStore(MemoryVaultStore());
      final index = MemoryIndexDatabase();
      final repository = TableRepository(vault: vault, index: index);
      await repository.initialize();
      final table = await repository.createTable(title: '中断恢复');
      final now = DateTime.parse('2026-10-29T09:00:00+08:00');
      final entry = TableEntryDocument(
        id: 'nt_interrupted',
        type: TableContentType.note,
        tableId: table.id,
        title: '正文',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '保存前像',
      );
      await repository.createEntry(entry);
      vault.failOnNextManagedWrite = 2;

      await expectLater(
        repository.deleteTable(id: table.id, expectedRevision: 1, now: now),
        throwsStateError,
      );
      final pending = (await index.listTableRecoveryBatches(activeOnly: true))
          .single;
      expect(pending.status, TableRecoveryStatus.prepared);
      vault.failOnNextManagedWrite = null;

      final restarted = TableRepository(vault: vault, index: index);
      await restarted.initialize();
      expect(
        (await index.findTableRecoveryBatch(pending.id))?.status,
        TableRecoveryStatus.active,
      );
      expect((await restarted.readTable(table.id))?.deleted, isTrue);
      expect((await restarted.readEntry(entry.id))?.deleted, isTrue);
    },
  );

  test(
    'moves entries by stable ID and refuses to drop populated field values',
    () async {
      final vault = MemoryVaultStore();
      final index = MemoryIndexDatabase();
      final repository = TableRepository(vault: vault, index: index);
      await repository.initialize();
      final now = DateTime.parse('2026-10-29T09:00:00+08:00');
      final source = await repository.createTable(title: '作业');
      final sourceWithFields = await repository.updateTable(
        source.copyWith(
          fields: [
            TableFieldDefinition(
              id: 'fld_course',
              name: '课程',
              type: CustomFieldType.text,
            ),
            TableFieldDefinition(
              id: 'fld_optional',
              name: '备注',
              type: CustomFieldType.text,
            ),
          ],
        ),
        expectedRevision: source.revision,
      );
      final compatible = await repository.createTable(title: '考试');
      await repository.updateTable(
        compatible.copyWith(
          fields: [
            TableFieldDefinition(
              id: 'fld_course',
              name: '课程',
              type: CustomFieldType.text,
            ),
          ],
        ),
        expectedRevision: compatible.revision,
      );
      final incompatible = await repository.createTable(title: '归档');
      final note = TableEntryDocument(
        id: 'nt_stable_move',
        type: TableContentType.note,
        tableId: sourceWithFields.id,
        title: '复习安排',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '同一份正文',
        customValues: const {'fld_course': '信号与系统', 'fld_optional': null},
      );
      await repository.createEntry(note);

      final moved = await repository.moveEntry(
        id: note.id,
        tableId: compatible.id,
        expectedRevision: note.revision,
      );
      expect(moved.id, note.id);
      expect(moved.tableId, compatible.id);
      expect(moved.customValues, {'fld_course': '信号与系统'});
      await expectLater(
        repository.moveEntry(
          id: note.id,
          tableId: incompatible.id,
          expectedRevision: moved.revision,
        ),
        throwsStateError,
      );
      expect((await repository.readEntry(note.id))?.tableId, compatible.id);
      expect((await repository.readEntry(note.id))?.body, note.body);
    },
  );

  test('removes a populated field as one recoverable schema batch', () async {
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    final repository = TableRepository(vault: vault, index: index);
    await repository.initialize();
    final now = DateTime.parse('2026-10-29T09:00:00+08:00');
    final table = await repository.createTable(title: '字段恢复');
    final field = TableFieldDefinition(
      id: 'fld_course_recover',
      name: '课程',
      type: CustomFieldType.text,
    );
    final withField = await repository.updateTable(
      table.copyWith(fields: [field]),
      expectedRevision: table.revision,
    );
    final note = TableEntryDocument(
      id: 'nt_field_recover',
      type: TableContentType.note,
      tableId: table.id,
      title: '课程笔记',
      revision: 1,
      createdAt: now,
      updatedAt: now,
      body: '正文保留',
      customValues: {field.id: '信号与系统'},
    );
    await repository.createEntry(note);

    final batch = await repository.removeTableField(
      tableId: table.id,
      fieldId: field.id,
      expectedRevision: withField.revision,
      idempotencyKey: 'remove-course-field',
      now: now,
    );
    expect(batch.scope, TableRecoveryScope.fieldChange);
    expect((await repository.readTable(table.id))!.fields, isEmpty);
    expect((await repository.readEntry(note.id))!.customValues, isEmpty);
    expect(await repository.recoveryBatches(), isEmpty);
    expect(await repository.fieldChangeRecoveryBatches(tableId: table.id), [
      batch,
    ]);

    await repository.restoreRecoveryBatch(
      batch.id,
      now: now.add(const Duration(days: 29)),
    );
    expect((await repository.readTable(table.id))!.fields.single.id, field.id);
    expect(
      (await repository.readEntry(note.id))!.customValues[field.id],
      '信号与系统',
    );
    expect(
      await repository.fieldChangeRecoveryBatches(tableId: table.id),
      isEmpty,
    );

    final currentTable = (await repository.readTable(table.id))!;
    final expiring = await repository.removeTableField(
      tableId: table.id,
      fieldId: field.id,
      expectedRevision: currentTable.revision,
      idempotencyKey: 'remove-course-field-expiring',
      now: now.add(const Duration(days: 40)),
    );
    await repository.purgeExpiredRecoveryBatches(now: expiring.expiresAt);
    expect(
      (await index.findTableRecoveryBatch(expiring.id))?.status,
      TableRecoveryStatus.expired,
    );
    final survivingEntry = await repository.readEntry(note.id);
    expect(survivingEntry?.body, note.body);
    expect(survivingEntry?.deleted, isFalse);
    expect(survivingEntry?.customValues, isEmpty);
  });

  test(
    'moves mapped select values to different target field and option IDs',
    () async {
      final vault = MemoryVaultStore();
      final index = MemoryIndexDatabase();
      final repository = TableRepository(vault: vault, index: index);
      await repository.initialize();
      final now = DateTime.parse('2026-10-29T09:00:00+08:00');
      final source = await repository.createTable(title: '课程');
      final sourceField = TableFieldDefinition(
        id: 'fld_source_course',
        name: '科目',
        type: CustomFieldType.singleSelect,
        options: const [TableFieldOption(id: 'opt_source_math', label: '数学')],
      );
      await repository.updateTable(
        source.copyWith(fields: [sourceField]),
        expectedRevision: source.revision,
      );
      final target = await repository.createTable(title: '考试');
      final targetField = TableFieldDefinition(
        id: 'fld_target_subject',
        name: '考试科目',
        type: CustomFieldType.singleSelect,
        options: const [TableFieldOption(id: 'opt_target_math', label: '数学')],
      );
      await repository.updateTable(
        target.copyWith(fields: [targetField]),
        expectedRevision: target.revision,
      );
      final note = TableEntryDocument(
        id: 'nt_mapped_select_move',
        type: TableContentType.note,
        tableId: source.id,
        title: '数学考试',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '正文',
        customValues: const {'fld_source_course': 'opt_source_math'},
      );
      await repository.createEntry(note);

      final moved = await repository.moveEntry(
        id: note.id,
        tableId: target.id,
        expectedRevision: note.revision,
        fieldMapping: {sourceField.id: targetField.id},
        optionMapping: {
          sourceField.id: {'opt_source_math': 'opt_target_math'},
        },
      );
      expect(moved.id, note.id);
      expect(moved.tableId, target.id);
      expect(moved.customValues, {targetField.id: 'opt_target_math'});
    },
  );

  test('replays a partially applied field deletion after restart', () async {
    final vault = _FailingVaultStore(MemoryVaultStore());
    final index = MemoryIndexDatabase();
    final repository = TableRepository(vault: vault, index: index);
    await repository.initialize();
    final now = DateTime.parse('2026-10-29T09:00:00+08:00');
    final table = await repository.createTable(title: '字段删除重放');
    final field = TableFieldDefinition(
      id: 'fld_replay',
      name: '章节',
      type: CustomFieldType.text,
    );
    final withField = await repository.updateTable(
      table.copyWith(fields: [field]),
      expectedRevision: table.revision,
    );
    final note = TableEntryDocument(
      id: 'nt_field_replay',
      type: TableContentType.note,
      tableId: table.id,
      title: '正文',
      revision: 1,
      createdAt: now,
      updatedAt: now,
      body: '原文',
      customValues: {field.id: '第 2 章'},
    );
    await repository.createEntry(note);
    vault.failOnNextManagedWrite = 2;
    await expectLater(
      repository.removeTableField(
        tableId: table.id,
        fieldId: field.id,
        expectedRevision: withField.revision,
        idempotencyKey: 'field-replay',
        now: now,
      ),
      throwsStateError,
    );
    vault.failOnNextManagedWrite = null;

    final restarted = TableRepository(vault: vault, index: index);
    await restarted.initialize();
    final batch = (await index.listTableRecoveryBatches(activeOnly: true))
        .single;
    expect(batch.scope, TableRecoveryScope.fieldChange);
    expect((await restarted.readTable(table.id))!.fields, isEmpty);
    expect((await restarted.readEntry(note.id))!.customValues, isEmpty);
    await restarted.restoreRecoveryBatch(
      batch.id,
      now: now.add(const Duration(minutes: 1)),
    );
    expect((await restarted.readTable(table.id))!.fields.single.id, field.id);
    expect(
      (await restarted.readEntry(note.id))!.customValues[field.id],
      '第 2 章',
    );
  });

  test('rejects stale updates and missing table ownership', () async {
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    final repository = TableRepository(vault: vault, index: index);
    await repository.initialize();
    final table = await repository.createTable(title: '作业');
    final now = DateTime.parse('2026-10-29T09:00:00+08:00');
    final note = TableEntryDocument(
      id: 'nt_homework',
      type: TableContentType.note,
      tableId: table.id,
      title: '说明',
      revision: 1,
      createdAt: now,
      updatedAt: now,
      body: '初稿',
    );
    await repository.createEntry(note);
    await repository.updateEntry(
      note.copyWith(title: '说明更新'),
      expectedRevision: 1,
    );
    await expectLater(
      repository.updateEntry(note, expectedRevision: 1),
      throwsStateError,
    );
    await expectLater(
      repository.createEntry(
        TableEntryDocument(
          id: 'nt_missing_table',
          type: TableContentType.note,
          tableId: 'tb_missing',
          title: '说明',
          revision: 1,
          createdAt: now,
          updatedAt: now,
          body: '内容',
        ),
      ),
      throwsStateError,
    );
  });

  test(
    'reopens persisted tables and entries from Markdown and SQLite',
    () async {
      final directory = await Directory.systemTemp.createTemp('table-reopen');
      addTearDown(() => directory.delete(recursive: true));
      final vault = IoVaultStore.at(directory);
      final databasePath = '${directory.path}/index.sqlite3';
      final index = SqliteIndexDatabase(databasePath);
      await index.open();
      final first = TableRepository(
        vault: vault,
        index: index,
        deviceId: 'test-device',
      );
      await first.initialize();
      final table = await first.createTable(title: '持久化表');
      final now = DateTime.parse('2026-10-29T09:00:00+08:00');
      final note = TableEntryDocument(
        id: 'nt_persisted',
        type: TableContentType.note,
        tableId: table.id,
        title: '持久化笔记',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '保存在 Markdown',
      );
      await first.createEntry(note);
      await index.close();

      final reopenedIndex = SqliteIndexDatabase(databasePath);
      await reopenedIndex.open();
      final reopened = TableRepository(
        vault: vault,
        index: reopenedIndex,
        deviceId: 'test-device',
      );
      await reopened.initialize();
      expect((await reopened.readTable(table.id))?.body, '');
      expect((await reopened.readEntry(note.id))?.body, '保存在 Markdown');
      expect(await reopenedIndex.findTableEntry(note.id), isNotNull);
      await reopenedIndex.close();
    },
  );
}

class _FailingVaultStore implements VaultStore {
  _FailingVaultStore(this._inner);

  final MemoryVaultStore _inner;
  int? _failureWriteNumber;
  var _managedWrites = 0;

  set failOnNextManagedWrite(int? value) {
    _managedWrites = 0;
    _failureWriteNumber = value;
  }

  @override
  Future<void> initialize() => _inner.initialize();

  @override
  Future<T> exclusive<T>(Future<T> Function() operation) =>
      _inner.exclusive(operation);

  @override
  Future<String?> read(String relativePath) => _inner.read(relativePath);

  @override
  Future<void> write(String relativePath, String contents) async {
    if (relativePath.startsWith('vault/tables/') ||
        relativePath.startsWith('vault/items/')) {
      _managedWrites++;
      if (_managedWrites == _failureWriteNumber) {
        throw StateError('injected interrupted managed write');
      }
    }
    await _inner.write(relativePath, contents);
  }

  @override
  Future<void> delete(String relativePath) => _inner.delete(relativePath);

  @override
  Future<List<String>> listMarkdownFiles() => _inner.listMarkdownFiles();

  @override
  Future<String> describeRoot() => _inner.describeRoot();
}
