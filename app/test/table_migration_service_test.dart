import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/markdown_codec.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/core/table_markdown_codec.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/index_database.dart';
import 'package:personal_ai_inbox/data/table_migration_service.dart';
import 'package:personal_ai_inbox/data/table_repository.dart';
import 'package:personal_ai_inbox/data/vault_store.dart';
import 'package:personal_ai_inbox/modules/tables/table_migration_gate.dart';

void main() {
  final now = DateTime.parse('2026-10-30T09:00:00+08:00');
  const availableBytes = 1 << 30;

  for (final failure in [
    'none',
    'interrupted',
    'bad-backup',
    'changed-source',
  ]) {
    test('source cleanup protects data: $failure', () async {
      final memory = MemoryVaultStore();
      final vault = _FailingMigrationVault(memory);
      final index = MemoryIndexDatabase();
      TableMigrationService service() => TableMigrationService(
        vault: vault,
        index: index,
        createDatabaseSnapshot: (id) async => 'db/$id.json',
        estimateDatabaseSnapshotBytes: () async => 128,
        availableSpaceProbe: (_) async => availableBytes,
        runWithWriteBarrier: (operation) => operation(),
      );
      final matter = _legacy(
        id: 'cleanup_matter',
        type: ResultType.matter,
        title: '旧表',
        body: '表正文',
        now: now,
      );
      final todo = _legacy(
        id: 'cleanup_todo',
        type: ResultType.todo,
        title: '旧待办',
        body: '旧正文',
        now: now,
      );
      final deleted = _legacy(
        id: 'cleanup_deleted',
        type: ResultType.event,
        title: '已删除',
        body: '',
        deleted: true,
        now: now,
      );
      final global = _legacy(
        id: 'cleanup_global',
        type: ResultType.knowledge,
        title: '全局知识',
        body: '保留活动源',
        now: now,
        extensionFields: const {
          globalKnowledgeScopeKey: globalKnowledgeScopeValue,
        },
      );
      const codec = MarkdownCodec();
      for (final doc in [matter, todo, deleted, global]) {
        await vault.write(doc.markdownPath, codec.encode(doc));
      }
      final migration = service();
      final plan = await migration.preview();
      await expectLater(migration.cleanupLegacySources(plan), throwsStateError);
      await migration.apply(plan);
      final repository = TableRepository(vault: vault, index: index);
      await repository.initialize();
      final migrated = (await repository.readEntry(todo.id))!;
      await repository.updateEntry(
        migrated.copyWith(body: '迁移后修改'),
        expectedRevision: migrated.revision,
      );
      final backupPath =
          'vault/.table-migrations/backups/${plan.migrationId}/${todo.markdownPath}';
      if (failure == 'bad-backup') {
        await vault.write(backupPath, '损坏备份');
      } else if (failure == 'changed-source') {
        await vault.write(
          todo.markdownPath,
          codec.encode(todo.copyWith(body: '旧源后来变化')),
        );
      } else if (failure == 'interrupted') {
        vault.failOnDeletePath = todo.markdownPath;
      }
      if (failure == 'bad-backup' || failure == 'changed-source') {
        await expectLater(
          migration.cleanupLegacySources(plan),
          throwsStateError,
        );
        for (final doc in [matter, todo, deleted, global]) {
          expect(await vault.read(doc.markdownPath), isNotNull);
        }
        expect((await repository.readEntry(todo.id))!.body, '迁移后修改');
        return;
      }
      if (failure == 'interrupted') {
        await expectLater(
          migration.cleanupLegacySources(plan),
          throwsStateError,
        );
        expect(await vault.read(matter.markdownPath), isNull);
        await service().resumeSourceCleanup();
      } else {
        await migration.cleanupLegacySources(plan);
      }
      for (final doc in [matter, todo, deleted]) {
        expect(await vault.read(doc.markdownPath), isNull);
      }
      expect(await vault.read(backupPath), codec.encode(todo));
      expect(await vault.read(global.markdownPath), codec.encode(global));
      expect((await repository.readEntry(todo.id))!.body, '迁移后修改');
      final gate = TableMigrationGate(service: service());
      await gate.initialize();
      expect(gate.error, isNull);
      expect(gate.migrationComplete, isTrue);
      expect(gate.requiresReadOnly, isFalse);
      expect(gate.preview!.hasLegacyContent, isFalse);
      await gate.refresh();
      expect(gate.migrationComplete, isTrue);
      gate.dispose();
      await expectLater(migration.rollback(plan.migrationId), throwsStateError);
    });
  }

  test(
    'dated legacy schedules remain migratable after their start time',
    () async {
      final vault = MemoryVaultStore();
      final index = MemoryIndexDatabase();
      final migration = TableMigrationService(
        vault: vault,
        index: index,
        createDatabaseSnapshot: (id) async => 'database-backups/$id.json',
        estimateDatabaseSnapshotBytes: () async => 128,
        availableSpaceProbe: (_) async => availableBytes,
        runWithWriteBarrier: (operation) => operation(),
      );
      final legacy = _legacy(
        id: 'event_elapsed_schedule',
        type: ResultType.event,
        title: '原有考试安排',
        body: '是否实际参加未知，保留原安排',
        start: now.subtract(const Duration(days: 1)),
        now: now,
      );
      final source = const MarkdownCodec().encode(legacy);
      await vault.write(legacy.markdownPath, source);
      final tombstone = _legacy(
        id: 'deleted_old_calendar',
        type: ResultType.event,
        title: '已删除安排',
        body: '',
        deleted: true,
        now: now,
      );
      final tombstoneSource = const MarkdownCodec().encode(tombstone);
      await vault.write(tombstone.markdownPath, tombstoneSource);
      final plan = await migration.preview(
        now: now,
        availableBytes: availableBytes,
      );
      expect(
        plan.canApply,
        isTrue,
        reason: plan.issues.map((e) => e.message).join('\n'),
      );
      final entry = plan.entries.single;
      expect(entry.type, TableContentType.schedule);
      expect(entry.start!.isAtSameMomentAs(legacy.start!), isTrue);
      expect(entry.occurredAt, isNull);
      expect(entry.body, legacy.body);
      await migration.apply(plan);
      final repository = TableRepository(vault: vault, index: index);
      await repository.initialize();
      final migrated = (await repository.readEntry(legacy.id))!;
      await repository.updateEntry(
        migrated.copyWith(body: '迁移后正常编辑'),
        expectedRevision: migrated.revision,
      );
      expect(await vault.read(legacy.markdownPath), source);
      expect(await vault.read(tombstone.markdownPath), tombstoneSource);
      expect(await vault.read(TableRepository.entryPath(tombstone.id)), isNull);
      expect(
        await migration.completedReceipt(
          await migration.preview(
            now: now.add(const Duration(days: 10)),
            availableBytes: availableBytes,
          ),
        ),
        isNotNull,
      );
      expect((await repository.readEntry(legacy.id))!.body, '迁移后正常编辑');
      final restartedGate = TableMigrationGate(service: migration);
      await restartedGate.initialize();
      expect(restartedGate.error, isNull);
      expect(restartedGate.requiresReadOnly, isFalse);
      expect(restartedGate.migrationComplete, isTrue);
      expect(restartedGate.preview!.issues, isEmpty);
      restartedGate.dispose();
      await expectLater(migration.apply(plan), throwsStateError);
      await expectLater(migration.rollback(plan.migrationId), throwsStateError);
      expect((await repository.readEntry(legacy.id))!.body, '迁移后正常编辑');
    },
  );

  test(
    'previews and copies legacy records with deterministic table mapping',
    () async {
      final vault = MemoryVaultStore();
      final index = MemoryIndexDatabase();
      final legacyCodec = const MarkdownCodec();
      final migration = TableMigrationService(
        vault: vault,
        index: index,
        createDatabaseSnapshot: (id) async => 'database-backups/$id.json',
        estimateDatabaseSnapshotBytes: () async => 128,
        availableSpaceProbe: (path) async => availableBytes,
        runWithWriteBarrier: (operation) => operation(),
      );
      final matter = _legacy(
        id: 'matter_course',
        type: ResultType.matter,
        title: '信号与系统',
        body: '事项正文保留',
        now: now,
      );
      final todo = _legacy(
        id: 'todo_homework',
        type: ResultType.todo,
        title: '完成作业',
        body: '第 1 章练习',
        matterId: matter.id,
        due: now.add(const Duration(days: 1)),
        now: now,
      );
      final event = _legacy(
        id: 'event_exam',
        type: ResultType.event,
        title: '期中考试',
        body: '考试安排正文',
        matterId: matter.id,
        start: now.add(const Duration(days: 5)),
        now: now,
      );
      final knowledge = _legacy(
        id: 'knowledge_notes',
        type: ResultType.knowledge,
        title: '课程笔记',
        body: '笔记正文',
        links: [matter.id],
        now: now,
      );
      final inboxTodo = _legacy(
        id: 'todo_unassigned',
        type: ResultType.todo,
        title: '买笔记本',
        body: '',
        now: now,
      );
      final global = _legacy(
        id: 'knowledge_global',
        type: ResultType.knowledge,
        title: '学期开始日',
        body: '9 月 1 日',
        extensionFields: const {
          globalKnowledgeScopeKey: globalKnowledgeScopeValue,
        },
        now: now,
      );
      for (final document in [
        matter,
        todo,
        event,
        knowledge,
        inboxTodo,
        global,
      ]) {
        await vault.write(document.markdownPath, legacyCodec.encode(document));
      }

      final plan = await migration.preview(now: now);
      expect(
        plan.canApply,
        isTrue,
        reason: plan.issues
            .map((issue) => '${issue.path}: ${issue.message}')
            .join('\n'),
      );
      expect(plan.availableBytes, availableBytes);
      expect(plan.tables.map((table) => table.id), [matter.id]);
      expect(
        {
          for (final entry in plan.entries)
            entry.id: (entry.type, entry.tableId),
        },
        {
          todo.id: (TableContentType.todo, matter.id),
          event.id: (TableContentType.schedule, matter.id),
          knowledge.id: (TableContentType.note, matter.id),
          inboxTodo.id: (TableContentType.todo, 'tb_default_todo'),
        },
      );
      expect(plan.retainedGlobalKnowledgeIds, [global.id]);
      expect(plan.estimatedBackupBytes, greaterThan(0));
      expect(plan.estimatedOutputBytes, greaterThan(0));
      expect(
        plan.estimatedRequiredBytes,
        greaterThan(plan.estimatedOutputBytes),
      );

      final receipt = await migration.apply(plan);
      expect(receipt.status, 'complete');
      expect(receipt.targets, hasLength(5));
      expect(
        receipt.databaseBackupManifestPath,
        'database-backups/${plan.migrationId}.json',
      );
      expect(
        receipt.databaseBackupManifestPath,
        'database-backups/${plan.migrationId}.json',
      );
      expect(await vault.read(matter.markdownPath), isNotNull);
      expect(await vault.read(global.markdownPath), isNotNull);
      final backupManifest = await vault.read(receipt.backupManifestPath);
      expect(backupManifest, contains(matter.markdownPath));
      expect(backupManifest, contains(global.markdownPath));
      final repeated = await migration.apply(plan);
      expect(repeated.migrationId, receipt.migrationId);
      expect(repeated.status, receipt.status);

      final tableRepository = TableRepository(vault: vault, index: index);
      await tableRepository.initialize();
      expect((await tableRepository.readTable(matter.id))?.body, matter.body);
      expect((await tableRepository.readEntry(todo.id))?.body, todo.body);
      expect(
        (await tableRepository.readEntry(event.id))?.type,
        TableContentType.schedule,
      );
      expect(
        (await tableRepository.readEntry(knowledge.id))?.type,
        TableContentType.note,
      );

      await migration.rollback(plan.migrationId);
      expect(await vault.read(TableRepository.tablePath(matter.id)), isNull);
      expect(await vault.read(TableRepository.entryPath(todo.id)), isNull);
      expect(await vault.read(matter.markdownPath), isNotNull);
    },
  );

  test('confirmed global knowledge changes do not reopen completed table migration', () async {
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    const codec = MarkdownCodec();
    final migration = TableMigrationService(
      vault: vault,
      index: index,
      createDatabaseSnapshot: (id) async => 'database-backups/$id.json',
      estimateDatabaseSnapshotBytes: () async => 128,
      availableSpaceProbe: (path) async => availableBytes,
      runWithWriteBarrier: (operation) => operation(),
    );
    final matter = _legacy(
      id: 'matter_global_migration',
      type: ResultType.matter,
      title: '课程表',
      body: '课程表正文',
      now: now,
    );
    final global = _legacy(
      id: 'knowledge_global_migration',
      type: ResultType.knowledge,
      title: '学期开始日',
      body: '2026-09-01',
      extensionFields: const {
        globalKnowledgeScopeKey: globalKnowledgeScopeValue,
      },
      now: now,
    );
    final matterSource = codec.encode(matter);
    await vault.write(matter.markdownPath, matterSource);
    await vault.write(global.markdownPath, codec.encode(global));

    final initial = await migration.preview(
      now: now,
      availableBytes: availableBytes,
    );
    expect(initial.canApply, isTrue);
    await migration.apply(initial);

    final updatedGlobal = global.copyWith(body: '2026-09-08');
    final updatedGlobalSource = codec.encode(updatedGlobal);
    await vault.write(global.markdownPath, updatedGlobalSource);
    final afterGlobalApproval = await migration.preview(
      now: now,
      availableBytes: availableBytes,
    );

    expect(afterGlobalApproval.migrationId, initial.migrationId);
    expect(await migration.completedReceipt(afterGlobalApproval), isNotNull);
    expect(await vault.read(matter.markdownPath), matterSource);
    expect(await vault.read(global.markdownPath), updatedGlobalSource);
  });

  test('preflight retains tombstones and blocks undated, draft and conflicted records', () async {
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    final codec = const MarkdownCodec();
    final migration = TableMigrationService(
      vault: vault,
      index: index,
      createDatabaseSnapshot: (id) async => 'database-backups/$id.json',
      estimateDatabaseSnapshotBytes: () async => 128,
      runWithWriteBarrier: (operation) => operation(),
    );
    final missingMatter = _legacy(
      id: 'todo_orphan',
      type: ResultType.todo,
      title: '孤立待办',
      body: '正文',
      matterId: 'matter_missing',
      now: now,
    );
    final draft = _legacy(
      id: 'knowledge_draft',
      type: ResultType.knowledge,
      title: '草稿',
      body: '草稿正文',
      status: ResultStatus.draft,
      now: now,
    );
    final deleted = _legacy(
      id: 'todo_deleted',
      type: ResultType.todo,
      title: '已删除',
      body: '保留旧格式',
      deleted: true,
      now: now,
    );
    final conflict = _legacy(
      id: 'knowledge_conflict',
      type: ResultType.knowledge,
      title: '冲突',
      body: '保留冲突状态',
      now: now,
    );
    final pastCalendarItem = _legacy(
      id: 'event_past_unknown',
      type: ResultType.event,
      title: '过去的安排',
      body: '是否发生未知',
      start: now.subtract(const Duration(days: 1)),
      now: now,
    );
    final undatedCalendarItem = _legacy(
      id: 'event_undated_unknown',
      type: ResultType.event,
      title: '无日期安排',
      body: '是否事实未知',
      now: now,
    );
    for (final document in [
      missingMatter,
      draft,
      deleted,
      conflict,
      pastCalendarItem,
      undatedCalendarItem,
    ]) {
      await vault.write(document.markdownPath, codec.encode(document));
    }
    await index.upsertConflict(
      SyncConflictRecord(
        resultId: conflict.id,
        remoteHash: 'remote',
        remoteEtag: 'etag',
        localHash: 'local',
        copyPath: 'conflicts/${conflict.id}.md',
        createdAt: now,
      ),
    );

    final plan = await migration.preview(
      now: now,
      availableBytes: availableBytes,
    );
    expect(plan.canApply, isFalse);
    expect(plan.outputs.keys, [TableRepository.entryPath(pastCalendarItem.id)]);
    expect(
      plan.skippedIds,
      containsAll([draft.id, deleted.id, conflict.id, undatedCalendarItem.id]),
    );
    expect(plan.skippedIds, isNot(contains(pastCalendarItem.id)));
    expect(
      plan.issues.map((issue) => issue.path),
      isNot(contains(deleted.markdownPath)),
    );
    expect(plan.issues, hasLength(4));
    expect(await vault.read(missingMatter.markdownPath), isNotNull);
    await expectLater(migration.apply(plan), throwsStateError);
  });

  test('replays an interrupted table migration and rolls back only matching targets', () async {
    final vault = _FailingMigrationVault(MemoryVaultStore());
    final index = MemoryIndexDatabase();
    final codec = const MarkdownCodec();
    final migration = TableMigrationService(
      vault: vault,
      index: index,
      createDatabaseSnapshot: (id) async => 'database-backups/$id.json',
      estimateDatabaseSnapshotBytes: () async => 128,
      runWithWriteBarrier: (operation) => operation(),
    );
    final matter = _legacy(
      id: 'matter_replay',
      type: ResultType.matter,
      title: '可重放迁移',
      body: '原正文',
      now: now,
    );
    final todo = _legacy(
      id: 'todo_replay',
      type: ResultType.todo,
      title: '关联作业',
      body: '待迁移',
      matterId: matter.id,
      now: now,
    );
    await vault.write(matter.markdownPath, codec.encode(matter));
    await vault.write(todo.markdownPath, codec.encode(todo));
    final plan = await migration.preview(
      now: now,
      availableBytes: availableBytes,
    );
    vault.failOnNextPath = TableRepository.entryPath(todo.id);
    await expectLater(migration.apply(plan), throwsStateError);
    expect(await vault.read(TableRepository.tablePath(matter.id)), isNotNull);
    expect(await vault.read(TableRepository.entryPath(todo.id)), isNull);

    vault.failOnNextPath = null;
    final receipt = await migration.apply(
      await migration.preview(now: now, availableBytes: availableBytes),
    );
    expect(receipt.status, 'complete');
    expect(await vault.read(TableRepository.entryPath(todo.id)), isNotNull);
    await migration.rollback(plan.migrationId);
    expect(await vault.read(TableRepository.tablePath(matter.id)), isNull);
    expect(await vault.read(matter.markdownPath), isNotNull);
  });

  test('preflight refuses even identical pre-existing target files', () async {
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    final legacyCodec = const MarkdownCodec();
    const tableCodec = TableMarkdownCodec();
    final migration = TableMigrationService(
      vault: vault,
      index: index,
      createDatabaseSnapshot: (id) async => 'database-backups/$id.json',
      estimateDatabaseSnapshotBytes: () async => 128,
      runWithWriteBarrier: (operation) => operation(),
    );
    final matter = _legacy(
      id: 'matter_existing_target',
      type: ResultType.matter,
      title: '同内容目标也不可冒认',
      body: '原正文',
      now: now,
    );
    final target = TableDocument(
      id: matter.id,
      role: TableRole.custom,
      title: matter.title,
      revision: matter.revision,
      createdAt: matter.createdAt,
      updatedAt: matter.updatedAt,
      body: matter.body,
    );
    final targetPath = TableRepository.tablePath(matter.id);
    final targetSource = tableCodec.encodeTable(target);
    await vault.write(targetPath, targetSource);
    await vault.write(matter.markdownPath, legacyCodec.encode(matter));

    final plan = await migration.preview(
      now: now,
      availableBytes: availableBytes,
    );
    expect(plan.canApply, isFalse);
    expect(plan.issues.any((issue) => issue.path == targetPath), isTrue);
    await expectLater(migration.apply(plan), throwsStateError);
    expect(await vault.read(targetPath), targetSource);
  });

  test(
    'preflight blocks when the supplied free-space reading is insufficient',
    () async {
      final vault = MemoryVaultStore();
      final index = MemoryIndexDatabase();
      final codec = const MarkdownCodec();
      final migration = TableMigrationService(
        vault: vault,
        index: index,
        createDatabaseSnapshot: (id) async => 'database-backups/$id.json',
        estimateDatabaseSnapshotBytes: () async => 128,
        runWithWriteBarrier: (operation) => operation(),
      );
      final matter = _legacy(
        id: 'matter_low_space',
        type: ResultType.matter,
        title: '空间不足',
        body: '需要备份和新文件',
        now: now,
      );
      await vault.write(matter.markdownPath, codec.encode(matter));

      final unavailable = await migration.preview(now: now);
      expect(unavailable.canApply, isFalse);
      expect(unavailable.issues.single.message, contains('未提供 vault 可用磁盘空间读数'));

      final plan = await migration.preview(now: now, availableBytes: 0);
      expect(plan.canApply, isFalse);
      expect(plan.availableBytes, 0);
      expect(plan.estimatedRequiredBytes, greaterThan(0));
      expect(plan.issues.single.message, contains('可用空间不足'));
      await expectLater(migration.apply(plan), throwsStateError);

      final withoutDatabaseBackup = TableMigrationService(
        vault: vault,
        index: index,
        estimateDatabaseSnapshotBytes: () async => 128,
        runWithWriteBarrier: (operation) => operation(),
      );
      final noBackupPlan = await withoutDatabaseBackup.preview(
        now: now,
        availableBytes: availableBytes,
      );
      expect(noBackupPlan.canApply, isFalse);
      expect(
        noBackupPlan.issues.any((issue) => issue.path == 'databases'),
        isTrue,
      );
      await expectLater(
        withoutDatabaseBackup.apply(noBackupPlan),
        throwsStateError,
      );

      final withoutWriteBarrier = TableMigrationService(
        vault: vault,
        index: index,
        createDatabaseSnapshot: (id) async => 'database-backups/$id.json',
        estimateDatabaseSnapshotBytes: () async => 128,
        availableSpaceProbe: (path) async => availableBytes,
      );
      final noBarrierPlan = await withoutWriteBarrier.preview(now: now);
      expect(noBarrierPlan.canApply, isFalse);
      expect(
        noBarrierPlan.issues.any((issue) => issue.path == 'runtime'),
        isTrue,
      );
      await expectLater(
        withoutWriteBarrier.apply(noBarrierPlan),
        throwsStateError,
      );
    },
  );
}

ResultDocument _legacy({
  required String id,
  required ResultType type,
  required String title,
  required String body,
  required DateTime now,
  ResultStatus status = ResultStatus.canonical,
  bool deleted = false,
  String? matterId,
  DateTime? due,
  DateTime? start,
  List<String> links = const [],
  Map<String, Object?> extensionFields = const {},
}) => ResultDocument(
  id: id,
  type: type,
  title: title,
  status: status,
  originDevice: 'migration-fixture',
  revision: 2,
  createdAt: now,
  updatedAt: now,
  body: body,
  deleted: deleted,
  matterId: matterId,
  due: due,
  start: start,
  links: links,
  extensionFields: extensionFields,
);

class _FailingMigrationVault implements VaultStore {
  _FailingMigrationVault(this._inner);

  final MemoryVaultStore _inner;
  String? failOnNextPath;
  String? failOnDeletePath;

  @override
  Future<T> exclusive<T>(Future<T> Function() operation) =>
      _inner.exclusive(operation);

  @override
  Future<void> initialize() => _inner.initialize();

  @override
  Future<String?> read(String relativePath) => _inner.read(relativePath);

  @override
  Future<void> write(String relativePath, String contents) async {
    if (relativePath == failOnNextPath) {
      failOnNextPath = null;
      throw StateError('injected migration promotion failure');
    }
    await _inner.write(relativePath, contents);
  }

  @override
  Future<void> delete(String relativePath) async {
    if (relativePath == failOnDeletePath) {
      failOnDeletePath = null;
      throw StateError('injected source cleanup interruption');
    }
    await _inner.delete(relativePath);
  }

  @override
  Future<List<String>> listMarkdownFiles() => _inner.listMarkdownFiles();

  @override
  Future<String> describeRoot() => _inner.describeRoot();
}
