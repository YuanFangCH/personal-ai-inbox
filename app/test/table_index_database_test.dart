import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/index_database.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/sqlite_index_database.dart';

void main() {
  final time = DateTime.parse('2026-10-29T09:00:00+08:00');

  test(
    'memory and SQLite index table-owned entries with bounded filters',
    () async {
      final directory = await Directory.systemTemp.createTemp('table-index');
      addTearDown(() => directory.delete(recursive: true));
      final sqlite = SqliteIndexDatabase('${directory.path}/index.sqlite3');
      final memory = MemoryIndexDatabase();
      await sqlite.open();
      await memory.open();
      addTearDown(sqlite.close);
      addTearDown(memory.close);

      final exam = IndexedTable(
        id: 'tb_exam',
        role: TableRole.custom,
        title: '考试',
        revision: 1,
        updatedAt: time,
        deleted: false,
        mdPath: 'vault/tables/tb_exam.md',
        localHash: 'sha256:table',
        searchText: '考试地点 3教101',
      );
      final homework = IndexedTable(
        id: 'tb_homework',
        role: TableRole.custom,
        title: '作业',
        revision: 1,
        updatedAt: time,
        deleted: false,
        mdPath: 'vault/tables/tb_homework.md',
        localHash: 'sha256:homework',
        searchText: '信号作业',
      );
      final schedule = IndexedTableEntry(
        id: 'sc_exam',
        type: TableContentType.schedule,
        tableId: 'tb_exam',
        title: '期中考试',
        revision: 3,
        updatedAt: time,
        businessAt: time,
        done: false,
        deleted: false,
        mdPath: 'vault/items/sc_exam.md',
        localHash: 'sha256:schedule',
        searchText: '期中考试地点 3教101',
        customValuesJson: '{}',
      );
      final todo = IndexedTableEntry(
        id: 'td_homework',
        type: TableContentType.todo,
        tableId: 'tb_homework',
        title: '交作业',
        revision: 1,
        updatedAt: time,
        done: false,
        deleted: false,
        mdPath: 'vault/items/td_homework.md',
        localHash: 'sha256:todo',
        searchText: '信号与系统 交作业',
        customValuesJson: '{"course":"signals"}',
      );
      final databases = <IndexDatabase>[memory, sqlite];
      for (final database in databases) {
        await database.upsertTable(exam);
        await database.upsertTable(homework);
        await database.upsertTableEntry(schedule);
        await database.upsertTableEntry(todo);

        expect((await database.findTable('tb_exam'))?.role, TableRole.custom);
        expect(await database.listTables(), hasLength(2));
        expect(
          await database.searchTables(query: '考试', limit: 10, offset: 0),
          hasLength(1),
        );
        expect(
          await database.listTableEntries(tableId: 'tb_exam'),
          hasLength(1),
        );
        expect(
          await database.searchTableEntries(
            query: '3教101',
            tableId: 'tb_exam',
            type: TableContentType.schedule,
            from: time.subtract(const Duration(days: 1)),
            through: time.add(const Duration(days: 1)),
            limit: 5,
            offset: 0,
          ),
          hasLength(1),
        );
        expect(
          await database.searchTableEntries(
            query: '作业',
            tableId: 'tb_exam',
            limit: 5,
            offset: 0,
          ),
          isEmpty,
        );
        expect(
          await database.searchTableEntries(
            query: '信号',
            tableId: 'tb_homework',
            fieldFilters: const {'course': 'signals'},
            limit: 1,
            offset: 0,
          ),
          hasLength(1),
        );
        expect(
          await database.searchTableEntries(
            query: '',
            fieldFilters: const {'course': 'missing'},
            limit: 10,
            offset: 0,
          ),
          isEmpty,
        );
      }
    },
  );

  test('SQLite schema upgrades v6 and preserves old object rows', () async {
    final directory = await Directory.systemTemp.createTemp(
      'table-index-migration',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/index.sqlite3';
    final raw = sqlite3.open(path);
    raw.execute('''
      CREATE TABLE objects (
        id TEXT PRIMARY KEY, type TEXT NOT NULL, title TEXT NOT NULL,
        status TEXT NOT NULL, revision INTEGER NOT NULL,
        updated_at TEXT NOT NULL, deleted INTEGER NOT NULL,
        md_path TEXT NOT NULL, local_hash TEXT NOT NULL,
        last_synced_hash TEXT, remote_etag TEXT, matter_id TEXT,
        sync_state TEXT NOT NULL
      )
    ''');
    raw.execute('PRAGMA user_version = 6');
    raw.close();

    final database = SqliteIndexDatabase(path);
    await database.open();
    addTearDown(database.close);
    final check = sqlite3.open(path);
    expect(check.select('PRAGMA user_version').single['user_version'], 10);
    expect(
      check.select('SELECT name FROM sqlite_master WHERE name = ?', [
        'notebook_tables',
      ]),
      hasLength(1),
    );
    check.close();
  });

  test('SQLite persists and filters recovery ledger states', () async {
    final directory = await Directory.systemTemp.createTemp(
      'table-recovery-index',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/index.sqlite3';
    final now = DateTime.parse('2026-10-29T09:00:00+08:00');
    final batch = TableRecoveryBatch(
      id: 'rb_delete_exam',
      scope: TableRecoveryScope.table,
      tableId: 'tb_exam',
      status: TableRecoveryStatus.prepared,
      createdAt: now,
      expiresAt: now.add(const Duration(days: 30)),
      manifestJson: '{"objects":[]}',
    );
    final first = SqliteIndexDatabase(path);
    await first.open();
    await first.upsertTableRecoveryBatch(batch);
    expect(
      (await first.findTableRecoveryBatch(batch.id))?.status,
      TableRecoveryStatus.prepared,
    );
    expect(
      await first.listTableRecoveryBatches(activeOnly: true),
      hasLength(1),
    );
    await first.upsertTableRecoveryBatch(
      batch.copyWith(status: TableRecoveryStatus.restored),
    );
    expect(await first.listTableRecoveryBatches(activeOnly: true), isEmpty);
    await first.close();

    final reopened = SqliteIndexDatabase(path);
    await reopened.open();
    final stored = await reopened.findTableRecoveryBatch(batch.id);
    expect(stored?.scope, TableRecoveryScope.table);
    expect(stored?.status, TableRecoveryStatus.restored);
    expect(stored?.manifestJson, '{"objects":[]}');
    await reopened.close();
  });

  test('SQLite v8 recovery scope migration preserves batches and accepts current scopes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'table-recovery-v8-migration',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/index.sqlite3';
    final raw = sqlite3.open(path);
    raw.execute('''
      CREATE TABLE table_recovery_batches (
        id TEXT PRIMARY KEY,
        scope TEXT NOT NULL CHECK (scope IN ('entry', 'table')),
        table_id TEXT NOT NULL,
        status TEXT NOT NULL CHECK (
          status IN ('prepared', 'active', 'restoring', 'restored', 'expired', 'failed')
        ),
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        manifest_json TEXT NOT NULL,
        error TEXT
      )
    ''');
    raw.execute(
      'CREATE INDEX table_recovery_expiration ON table_recovery_batches(status, expires_at)',
    );
    raw.execute('''
      INSERT INTO table_recovery_batches VALUES (
        'rb_keep', 'table', 'tb_exam', 'active',
        '2026-10-29T01:00:00.000Z', '2026-11-28T01:00:00.000Z', '{"objects":[]}', NULL
      )
    ''');
    raw.execute('PRAGMA user_version = 8');
    raw.close();

    final database = SqliteIndexDatabase(path);
    await database.open();
    expect(
      (await database.findTableRecoveryBatch('rb_keep'))?.scope,
      TableRecoveryScope.table,
    );
    final scheduleChange = TableRecoveryBatch(
      id: 'rb_schedule_change',
      scope: TableRecoveryScope.scheduleChange,
      tableId: 'tb_exam',
      status: TableRecoveryStatus.active,
      createdAt: DateTime.parse('2026-10-29T09:00:00+08:00'),
      expiresAt: DateTime.parse('2026-10-29T09:10:00+08:00'),
      manifestJson: '{"objects":[]}',
    );
    await database.upsertTableRecoveryBatch(scheduleChange);
    final fieldChange = TableRecoveryBatch(
      id: 'rb_field_change',
      scope: TableRecoveryScope.fieldChange,
      tableId: 'tb_exam',
      status: TableRecoveryStatus.active,
      createdAt: DateTime.parse('2026-10-29T09:00:00+08:00'),
      expiresAt: DateTime.parse('2026-11-28T09:00:00+08:00'),
      manifestJson: '{"objects":[]}',
    );
    await database.upsertTableRecoveryBatch(fieldChange);
    await database.close();

    final migrated = sqlite3.open(path);
    expect(migrated.select('PRAGMA user_version').single['user_version'], 10);
    expect(
      migrated.select('SELECT id FROM table_recovery_batches ORDER BY id'),
      hasLength(3),
    );
    migrated.close();
  });

  test('SQLite v9 migration adds field-change recovery scope', () async {
    final directory = await Directory.systemTemp.createTemp(
      'table-recovery-v9-migration',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/index.sqlite3';
    final raw = sqlite3.open(path);
    raw.execute('''
      CREATE TABLE table_recovery_batches (
        id TEXT PRIMARY KEY,
        scope TEXT NOT NULL CHECK (scope IN ('entry', 'table', 'scheduleChange')),
        table_id TEXT NOT NULL,
        status TEXT NOT NULL CHECK (
          status IN ('prepared', 'active', 'restoring', 'restored', 'expired', 'failed')
        ),
        created_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        manifest_json TEXT NOT NULL,
        error TEXT
      )
    ''');
    raw.execute(
      'CREATE INDEX table_recovery_expiration ON table_recovery_batches(status, expires_at)',
    );
    raw.execute('''
      INSERT INTO table_recovery_batches VALUES (
        'rb_schedule_v9', 'scheduleChange', 'tb_exam', 'active',
        '2026-10-29T01:00:00.000Z', '2026-10-29T01:10:00.000Z', '{"objects":[]}', NULL
      )
    ''');
    raw.execute('PRAGMA user_version = 9');
    raw.close();

    final database = SqliteIndexDatabase(path);
    await database.open();
    expect(
      (await database.findTableRecoveryBatch('rb_schedule_v9'))?.scope,
      TableRecoveryScope.scheduleChange,
    );
    final fieldChange = TableRecoveryBatch(
      id: 'rb_field_change_v10',
      scope: TableRecoveryScope.fieldChange,
      tableId: 'tb_exam',
      status: TableRecoveryStatus.active,
      createdAt: time,
      expiresAt: time.add(const Duration(days: 30)),
      manifestJson: '{"objects":[]}',
    );
    await database.upsertTableRecoveryBatch(fieldChange);
    await database.close();
    final migrated = sqlite3.open(path);
    expect(migrated.select('PRAGMA user_version').single['user_version'], 10);
    expect(
      migrated.select('SELECT id FROM table_recovery_batches ORDER BY id'),
      hasLength(2),
    );
    migrated.close();
  });
}
