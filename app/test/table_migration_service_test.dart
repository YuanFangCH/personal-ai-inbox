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

void main() {
  final now = DateTime.parse('2026-10-30T09:00:00+08:00');

  test(
    'previews and copies legacy records with deterministic table mapping',
    () async {
      final vault = MemoryVaultStore();
      final index = MemoryIndexDatabase();
      final legacyCodec = const MarkdownCodec();
      final migration = TableMigrationService(vault: vault, index: index);
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

  test(
    'preflight blocks ambiguous, deleted, draft and conflicted legacy records',
    () async {
      final vault = MemoryVaultStore();
      final index = MemoryIndexDatabase();
      final codec = const MarkdownCodec();
      final migration = TableMigrationService(vault: vault, index: index);
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

      final plan = await migration.preview(now: now);
      expect(plan.canApply, isFalse);
      expect(plan.outputs, isEmpty);
      expect(
        plan.skippedIds,
        containsAll([
          draft.id,
          deleted.id,
          conflict.id,
          pastCalendarItem.id,
          undatedCalendarItem.id,
        ]),
      );
      expect(plan.issues, hasLength(6));
      expect(await vault.read(missingMatter.markdownPath), isNotNull);
      await expectLater(migration.apply(plan), throwsStateError);
    },
  );

  test('replays an interrupted table migration and rolls back only matching targets', () async {
    final vault = _FailingMigrationVault(MemoryVaultStore());
    final index = MemoryIndexDatabase();
    final codec = const MarkdownCodec();
    final migration = TableMigrationService(vault: vault, index: index);
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
    final plan = await migration.preview(now: now);
    vault.failOnNextPath = TableRepository.entryPath(todo.id);
    await expectLater(migration.apply(plan), throwsStateError);
    expect(await vault.read(TableRepository.tablePath(matter.id)), isNotNull);
    expect(await vault.read(TableRepository.entryPath(todo.id)), isNull);

    vault.failOnNextPath = null;
    final receipt = await migration.apply(await migration.preview(now: now));
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
    final migration = TableMigrationService(vault: vault, index: index);
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

    final plan = await migration.preview(now: now);
    expect(plan.canApply, isFalse);
    expect(plan.issues.any((issue) => issue.path == targetPath), isTrue);
    await expectLater(migration.apply(plan), throwsStateError);
    expect(await vault.read(targetPath), targetSource);
  });
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
  Future<void> delete(String relativePath) => _inner.delete(relativePath);

  @override
  Future<List<String>> listMarkdownFiles() => _inner.listMarkdownFiles();

  @override
  Future<String> describeRoot() => _inner.describeRoot();
}
