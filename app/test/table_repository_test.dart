import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/table_markdown_codec.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/io_vault_store.dart';
import 'package:personal_ai_inbox/data/sqlite_index_database.dart';
import 'package:personal_ai_inbox/data/table_repository.dart';

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
