import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/markdown_codec.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/io_vault_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/settings_service.dart';
import 'package:personal_ai_inbox/data/sqlite_migration_coordinator.dart';
import 'package:personal_ai_inbox/data/table_migration_service.dart';
import 'package:personal_ai_inbox/data/table_repository.dart';
import 'package:personal_ai_inbox/data/vault_store.dart';
import 'package:sqlite3/sqlite3.dart';

final _now = DateTime.parse('2026-10-30T09:00:00+08:00');

void main() {
  test(
    'file-backed migration snapshots, promotes, reopens and rolls back',
    () async {
      final root = await Directory.systemTemp.createTemp('table-migration-io');
      addTearDown(() => root.delete(recursive: true));
      final vaultRoot = Directory('${root.path}/vault');
      final supportRoot = Directory('${root.path}/support');
      await vaultRoot.create();
      await supportRoot.create();
      _createDatabase('${supportRoot.path}/index.sqlite3', 10, 'result_rows');
      _createDatabase(
        '${supportRoot.path}/conversations.sqlite3',
        5,
        'chat_rows',
      );

      final settings = _MigrationSettings({'device_id': 'io-migration'});
      final migrationCoordinator = SqliteMigrationCoordinator(
        supportPath: supportRoot.path,
        settings: settings,
      );
      final vault = IoVaultStore.at(vaultRoot);
      await vault.initialize();
      final matter = _legacy(
        id: 'matter_io_course',
        type: ResultType.matter,
        title: 'IO 文件迁移',
        body: '保留真实文件正文',
      );
      final todo = _legacy(
        id: 'todo_io_course',
        type: ResultType.todo,
        title: '提交报告',
        body: '原文保持不变',
        matterId: matter.id,
      );
      const codec = MarkdownCodec();
      final matterSource = codec.encode(matter);
      final todoSource = codec.encode(todo);
      await vault.write(matter.markdownPath, matterSource);
      await vault.write(todo.markdownPath, todoSource);

      TableMigrationService service(VaultStore store) => TableMigrationService(
        vault: store,
        index: MemoryIndexDatabase(),
        createDatabaseSnapshot:
            migrationCoordinator.createTableMigrationSnapshot,
        estimateDatabaseSnapshotBytes:
            migrationCoordinator.estimateTableMigrationSnapshotBytes,
        availableSpaceProbe: (_) async => 1 << 30,
        runWithWriteBarrier: (operation) => operation(),
        clock: () => _now,
      );

      final firstPlan = await service(vault).preview();
      expect(firstPlan.canApply, isTrue, reason: _issues(firstPlan.issues));
      final firstReceipt = await service(vault).apply(firstPlan);
      expect(firstReceipt.status, 'complete');
      expect(await vault.read(matter.markdownPath), matterSource);
      expect(await vault.read(todo.markdownPath), todoSource);
      expect(await vault.read(TableRepository.tablePath(matter.id)), isNotNull);
      expect(await vault.read(TableRepository.entryPath(todo.id)), isNotNull);
      expect(await vault.read(firstReceipt.backupManifestPath), isNotNull);
      expect(
        await File(firstReceipt.databaseBackupManifestPath).exists(),
        isTrue,
      );

      final reopenedVault = IoVaultStore.at(vaultRoot);
      await reopenedVault.initialize();
      final reopenedService = service(reopenedVault);
      final repeatedPlan = await reopenedService.preview();
      expect(
        repeatedPlan.canApply,
        isTrue,
        reason: _issues(repeatedPlan.issues),
      );
      final repeatedReceipt = await reopenedService.apply(repeatedPlan);
      expect(repeatedReceipt.migrationId, firstReceipt.migrationId);
      await reopenedService.rollback(firstPlan.migrationId);
      expect(
        await reopenedVault.read(TableRepository.tablePath(matter.id)),
        isNull,
      );
      expect(
        await reopenedVault.read(TableRepository.entryPath(todo.id)),
        isNull,
      );
      expect(await reopenedVault.read(matter.markdownPath), matterSource);
      expect(await reopenedVault.read(todo.markdownPath), todoSource);
    },
  );

  test('file-backed partial promotion replays after a new service instance', () async {
    final root = await Directory.systemTemp.createTemp(
      'table-migration-io-replay',
    );
    addTearDown(() => root.delete(recursive: true));
    final vaultRoot = Directory('${root.path}/vault');
    final supportRoot = Directory('${root.path}/support');
    await vaultRoot.create();
    await supportRoot.create();
    _createDatabase('${supportRoot.path}/index.sqlite3', 10, 'result_rows');
    _createDatabase(
      '${supportRoot.path}/conversations.sqlite3',
      5,
      'chat_rows',
    );
    final coordinator = SqliteMigrationCoordinator(
      supportPath: supportRoot.path,
      settings: _MigrationSettings({'device_id': 'io-replay'}),
    );
    final inner = IoVaultStore.at(vaultRoot);
    await inner.initialize();
    final matter = _legacy(
      id: 'matter_io_replay',
      type: ResultType.matter,
      title: '中断后恢复',
      body: '旧源保留',
    );
    final todo = _legacy(
      id: 'todo_io_replay',
      type: ResultType.todo,
      title: '恢复待办',
      body: '稳定正文',
      matterId: matter.id,
    );
    const codec = MarkdownCodec();
    final matterSource = codec.encode(matter);
    final todoSource = codec.encode(todo);
    await inner.write(matter.markdownPath, matterSource);
    await inner.write(todo.markdownPath, todoSource);

    TableMigrationService service(VaultStore vault) => TableMigrationService(
      vault: vault,
      index: MemoryIndexDatabase(),
      createDatabaseSnapshot: coordinator.createTableMigrationSnapshot,
      estimateDatabaseSnapshotBytes:
          coordinator.estimateTableMigrationSnapshotBytes,
      availableSpaceProbe: (_) async => 1 << 30,
      runWithWriteBarrier: (operation) => operation(),
      clock: () => _now,
    );

    final failing = _FailingIoVault(inner, TableRepository.entryPath(todo.id));
    final first = service(failing);
    final plan = await first.preview();
    expect(plan.canApply, isTrue, reason: _issues(plan.issues));
    await expectLater(first.apply(plan), throwsStateError);
    expect(await inner.read(TableRepository.tablePath(matter.id)), isNotNull);
    expect(await inner.read(TableRepository.entryPath(todo.id)), isNull);

    final restarted = service(IoVaultStore.at(vaultRoot));
    final retryPlan = await restarted.preview();
    expect(retryPlan.canApply, isTrue, reason: _issues(retryPlan.issues));
    final receipt = await restarted.apply(retryPlan);
    expect(receipt.status, 'complete');
    expect(await inner.read(TableRepository.entryPath(todo.id)), isNotNull);
    expect(await inner.read(matter.markdownPath), matterSource);
    expect(await inner.read(todo.markdownPath), todoSource);
    await restarted.cleanupLegacySources(retryPlan);
    expect(await inner.read(matter.markdownPath), isNull);
    expect(await inner.read(todo.markdownPath), isNull);
    expect(
      await inner.read(
        'vault/.table-migrations/backups/${receipt.migrationId}/${todo.markdownPath}',
      ),
      todoSource,
    );
    final afterCleanup = service(IoVaultStore.at(vaultRoot));
    await afterCleanup.resumeSourceCleanup();
    final cleanedPlan = await afterCleanup.preview();
    expect(cleanedPlan.hasLegacyContent, isFalse);
    expect(
      (await afterCleanup.completedReceipt(cleanedPlan))!.migrationId,
      receipt.migrationId,
    );
    expect(await inner.read(TableRepository.entryPath(todo.id)), isNotNull);
  });
}

String _issues(List<TableMigrationIssue> issues) =>
    issues.map((issue) => '${issue.path}: ${issue.message}').join('\n');

void _createDatabase(String path, int version, String table) {
  final database = sqlite3.open(path)
    ..execute('CREATE TABLE $table (value TEXT NOT NULL)')
    ..execute('INSERT INTO $table (value) VALUES (?)', ['preserve'])
    ..execute('PRAGMA user_version = $version');
  database.close();
}

ResultDocument _legacy({
  required String id,
  required ResultType type,
  required String title,
  required String body,
  String? matterId,
}) => ResultDocument(
  id: id,
  type: type,
  title: title,
  status: ResultStatus.canonical,
  originDevice: 'migration-io-test',
  revision: 1,
  createdAt: _now,
  updatedAt: _now,
  body: body,
  matterId: matterId,
);

class _MigrationSettings extends SettingsService {
  _MigrationSettings(this._values);

  final Map<String, Object?> _values;

  @override
  Future<Map<String, Object?>> exportMigrationPreferences() async =>
      Map<String, Object?>.of(_values);

  @override
  Future<void> restoreMigrationPreferences(
    Map<String, dynamic> snapshot,
  ) async {
    _values
      ..clear()
      ..addAll(snapshot);
  }
}

class _FailingIoVault implements VaultStore {
  _FailingIoVault(this._inner, this._failPath);

  final VaultStore _inner;
  String? _failPath;

  @override
  Future<T> exclusive<T>(Future<T> Function() operation) =>
      _inner.exclusive(operation);

  @override
  Future<void> initialize() => _inner.initialize();

  @override
  Future<String?> read(String relativePath) => _inner.read(relativePath);

  @override
  Future<void> write(String relativePath, String contents) async {
    if (relativePath == _failPath) {
      _failPath = null;
      throw StateError('injected IO promotion failure');
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
