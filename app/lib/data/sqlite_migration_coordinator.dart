import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'settings_service.dart';
import 'migration_coordinator.dart';

/// Takes a consistent pre-migration snapshot and coordinates rollback across
/// the local index database, conversation database, and non-secret settings.
class SqliteMigrationCoordinator implements MigrationCoordinator {
  SqliteMigrationCoordinator({
    required this.supportPath,
    required SettingsService settings,
  }) : _settings = settings;

  static const _indexFile = 'index.sqlite3';
  static const _conversationFile = 'conversations.sqlite3';
  static const _supportedVersions = {_indexFile: 9, _conversationFile: 5};

  final String supportPath;
  final SettingsService _settings;

  RandomAccessFile? _startupLock;
  Map<String, dynamic>? _pendingState;

  @override
  Future<void> prepare() async {
    await Directory(supportPath).create(recursive: true);
    final lock = File(p.join(supportPath, '.migration-startup.lock'));
    _startupLock = await lock.open(mode: FileMode.append);
    await _startupLock!.lock(FileLock.exclusive);

    final stateFile = File(p.join(supportPath, '.migration-state.json'));
    if (await stateFile.exists()) {
      final state = jsonDecode(await stateFile.readAsString());
      if (state is! Map<String, dynamic> || state['schema_version'] != 1) {
        throw StateError('本地数据库迁移状态损坏；应用保持停止，备份文件已保留。');
      }
      if (!const {
        'pending',
        'complete',
        'rolled_back',
      }.contains(state['status'])) {
        throw StateError('本地数据库迁移状态未知；应用保持停止，备份文件已保留。');
      }
      if (state['status'] == 'pending') {
        await _restore(state);
        await _writeState({...state, 'status': 'rolled_back'});
      }
    }

    final databases = [
      _indexFile,
      _conversationFile,
    ].map((name) => p.join(supportPath, name)).toList(growable: false);
    final versions = <String, int>{};
    for (final database in databases) {
      versions[database] = await _readUserVersion(database) ?? 0;
      final supported = _supportedVersions[p.basename(database)]!;
      if (versions[database]! > supported) {
        throw StateError(
          '数据库 ${p.basename(database)} 版本 ${versions[database]} '
          '高于当前应用支持的版本 $supported。',
        );
      }
    }
    if (versions.entries.every(
      (entry) => entry.value == _supportedVersions[p.basename(entry.key)],
    )) {
      return;
    }

    final backupRoot = Directory(
      p.join(
        supportPath,
        '.migration-backups',
        const Uuid().v4().replaceAll('-', ''),
      ),
    );
    await backupRoot.create(recursive: true);
    final snapshots = <Map<String, Object?>>[];
    for (var index = 0; index < databases.length; index++) {
      final databasePath = databases[index];
      final exists = await File(databasePath).exists();
      String? backupPath;
      String? backupHash;
      if (exists) {
        backupPath = p.join(backupRoot.path, p.basename(databasePath));
        await _snapshotDatabase(databasePath, backupPath);
        backupHash = await _sha256File(backupPath);
      }
      snapshots.add({
        'path': databasePath,
        'existed': exists,
        'backup': backupPath,
        'backup_sha256': backupHash,
      });
    }
    final settingsBackup = p.join(backupRoot.path, 'preferences.json');
    final settingsJson = jsonEncode(
      await _settings.exportMigrationPreferences(),
    );
    await File(settingsBackup).writeAsString(settingsJson, flush: true);
    final state = <String, dynamic>{
      'schema_version': 1,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
      'databases': snapshots,
      'settings_backup': settingsBackup,
      'settings_backup_sha256': sha256
          .convert(utf8.encode(settingsJson))
          .toString(),
    };
    await _writeState(state);
    _pendingState = state;
  }

  @override
  Future<void> complete() async {
    final pending = _pendingState;
    if (pending == null) {
      await _releaseLock();
      return;
    }
    for (final entry in _supportedVersions.entries) {
      final version = await _readUserVersion(p.join(supportPath, entry.key));
      if (version != entry.value) {
        throw StateError('数据库 ${entry.key} migration 未到达版本 ${entry.value}。');
      }
    }
    await _writeState({...pending, 'status': 'complete'});
    _pendingState = null;
    await _releaseLock();
  }

  @override
  Future<void> rollback() async {
    final pending = _pendingState;
    if (pending == null) {
      await _releaseLock();
      return;
    }
    await _restore(pending);
    await _writeState({...pending, 'status': 'rolled_back'});
    _pendingState = null;
    await _releaseLock();
  }

  /// Creates a durable database/settings snapshot for a table migration.
  ///
  /// Callers must pause writes across the vault and local databases while this
  /// manifest is prepared. The method owns the startup lock and is idempotent
  /// for one migration ID.
  @override
  Future<String> createTableMigrationSnapshot(String migrationId) async {
    if (!RegExp(r'^tm_[a-f0-9]{24}$').hasMatch(migrationId)) {
      throw ArgumentError.value(migrationId, 'migrationId');
    }
    final ownsLock = _startupLock == null;
    if (ownsLock) {
      await Directory(supportPath).create(recursive: true);
      final lockFile = File(p.join(supportPath, '.migration-startup.lock'));
      _startupLock = await lockFile.open(mode: FileMode.append);
      await _startupLock!.lock(FileLock.exclusive);
    }
    try {
      final backupRoot = Directory(
        p.join(supportPath, '.migration-backups', 'table-$migrationId'),
      );
      await backupRoot.create(recursive: true);
      final manifestPath = p.join(backupRoot.path, 'manifest.json');
      final existingManifest = File(manifestPath);
      if (await existingManifest.exists()) {
        await _validateTableMigrationSnapshot(
          await existingManifest.readAsString(),
          migrationId,
        );
        return manifestPath;
      }

      // A crash before the manifest commit leaves an incomplete snapshot set.
      // Discard those per-migration files and take every source again under
      // this lock so databases and settings cannot come from mixed attempts.
      for (final name in [_indexFile, _conversationFile, 'preferences.json']) {
        final partial = File(p.join(backupRoot.path, name));
        if (await partial.exists()) await partial.delete();
      }
      final partialManifest = File('$manifestPath.tmp');
      if (await partialManifest.exists()) await partialManifest.delete();

      final databases = <Map<String, Object?>>[];
      for (final name in [_indexFile, _conversationFile]) {
        final source = p.join(supportPath, name);
        final sourceFile = File(source);
        final exists = await sourceFile.exists();
        String? backupPath;
        String? backupHash;
        int? userVersion;
        if (exists) {
          backupPath = p.join(backupRoot.path, name);
          final backupFile = File(backupPath);
          if (!await backupFile.exists()) {
            await _snapshotDatabase(source, backupPath);
          } else {
            final snapshot = sqlite3.open(backupPath);
            try {
              if (snapshot.select('PRAGMA quick_check').first.values.first !=
                  'ok') {
                throw StateError('既有 SQLite 迁移快照损坏：$name');
              }
            } finally {
              snapshot.close();
            }
          }
          backupHash = await _sha256File(backupPath);
          userVersion = await _readUserVersion(backupPath);
        }
        databases.add({
          'name': name,
          'existed': exists,
          'source': source,
          'backup': backupPath,
          'backup_sha256': backupHash,
          'user_version': userVersion,
        });
      }
      final settingsPath = p.join(backupRoot.path, 'preferences.json');
      final settingsJson = jsonEncode(
        await _settings.exportMigrationPreferences(),
      );
      final settingsFile = File(settingsPath);
      if (!await settingsFile.exists()) {
        await settingsFile.writeAsString(settingsJson, flush: true);
      }
      final storedSettings = await settingsFile.readAsString();
      final manifest = jsonEncode({
        'schema_version': 1,
        'migration_id': migrationId,
        'created_at': DateTime.now().toIso8601String(),
        'databases': databases,
        'settings_backup': settingsPath,
        'settings_backup_sha256': sha256
            .convert(utf8.encode(storedSettings))
            .toString(),
      });
      await File('$manifestPath.tmp').writeAsString(manifest, flush: true);
      await File('$manifestPath.tmp').rename(manifestPath);
      await _validateTableMigrationSnapshot(manifest, migrationId);
      return manifestPath;
    } finally {
      if (ownsLock) await _releaseLock();
    }
  }

  @override
  Future<int> estimateTableMigrationSnapshotBytes() async {
    var bytes = 0;
    for (final name in [_indexFile, _conversationFile]) {
      for (final suffix in const ['', '-wal', '-shm']) {
        final file = File(p.join(supportPath, '$name$suffix'));
        if (await file.exists()) bytes += await file.length();
      }
    }
    final settingsJson = jsonEncode(
      await _settings.exportMigrationPreferences(),
    );
    return bytes + utf8.encode(settingsJson).length;
  }

  Future<void> _validateTableMigrationSnapshot(
    String manifestSource,
    String migrationId,
  ) async {
    final value = jsonDecode(manifestSource);
    if (value is! Map<String, dynamic> ||
        value['schema_version'] != 1 ||
        value['migration_id'] != migrationId ||
        value['databases'] is! List ||
        value['settings_backup'] is! String ||
        value['settings_backup_sha256'] is! String) {
      throw StateError('表迁移数据库备份清单损坏：$migrationId');
    }
    final root = p.normalize(
      p.join(supportPath, '.migration-backups', 'table-$migrationId'),
    );
    for (final raw in value['databases'] as List) {
      if (raw is! Map ||
          raw['name'] is! String ||
          raw['existed'] is! bool ||
          !(const {_indexFile, _conversationFile}.contains(raw['name']))) {
        throw StateError('表迁移数据库项损坏。');
      }
      if (raw['existed'] == false) continue;
      final backup = raw['backup'];
      final expectedHash = raw['backup_sha256'];
      if (backup is! String || expectedHash is! String) {
        throw StateError('表迁移数据库快照缺失。');
      }
      if (!p.isWithin(root, p.normalize(backup)) ||
          !await File(backup).exists() ||
          await _sha256File(backup) != expectedHash) {
        throw StateError('表迁移数据库快照校验失败：${raw['name']}');
      }
    }
    final settingsPath = value['settings_backup'] as String;
    final settingsHash = value['settings_backup_sha256'] as String;
    if (!p.isWithin(root, p.normalize(settingsPath)) ||
        !await File(settingsPath).exists() ||
        sha256.convert(await File(settingsPath).readAsBytes()).toString() !=
            settingsHash) {
      throw StateError('表迁移端配置快照校验失败。');
    }
  }

  Future<void> _restore(Map<String, dynamic> state) async {
    final rawDatabases = state['databases'];
    final rawSettingsBackup = state['settings_backup'];
    final settingsBackupHash = state['settings_backup_sha256'];
    if (rawDatabases is! List ||
        rawSettingsBackup is! String ||
        settingsBackupHash is! String) {
      throw StateError('迁移备份清单损坏；应用保持停止，备份文件已保留。');
    }
    for (final raw in rawDatabases) {
      if (raw is! Map) {
        throw StateError('迁移数据库备份清单损坏。');
      }
      final databasePath = raw['path'];
      final existed = raw['existed'];
      final backupPath = raw['backup'];
      final backupHash = raw['backup_sha256'];
      if (databasePath is! String || existed is! bool) {
        throw StateError('迁移数据库备份清单损坏。');
      }
      final allowedDatabasePaths = {
        p.normalize(p.join(supportPath, _indexFile)),
        p.normalize(p.join(supportPath, _conversationFile)),
      };
      if (!allowedDatabasePaths.contains(p.normalize(databasePath))) {
        throw StateError('迁移清单引用了未知数据库路径。');
      }
      if (!existed) {
        await _removeSqliteSidecars(databasePath);
        final databaseFile = File(databasePath);
        if (await databaseFile.exists()) {
          await databaseFile.delete();
        }
        continue;
      }
      if (backupPath is! String ||
          backupHash is! String ||
          !await File(backupPath).exists()) {
        throw StateError('找不到迁移备份：${p.basename(databasePath)}');
      }
      final canonicalRoot = p.normalize(supportPath);
      final canonicalBackup = p.normalize(backupPath);
      if (!p.isWithin(canonicalRoot, canonicalBackup)) {
        throw StateError('迁移备份路径超出应用数据目录。');
      }
      if (await _sha256File(backupPath) != backupHash) {
        throw StateError('迁移数据库备份校验失败：${p.basename(databasePath)}');
      }
      await _removeSqliteSidecars(databasePath);
      final staged = File('$databasePath.restore.tmp');
      if (await staged.exists()) {
        await staged.delete();
      }
      await File(backupPath).copy(staged.path);
      final original = File(databasePath);
      if (await original.exists()) {
        await original.delete();
      }
      await staged.rename(databasePath);
    }

    if (!await File(rawSettingsBackup).exists()) {
      throw StateError('找不到端配置迁移备份。');
    }
    if (!p.isWithin(p.normalize(supportPath), p.normalize(rawSettingsBackup)) ||
        sha256
                .convert(await File(rawSettingsBackup).readAsBytes())
                .toString() !=
            settingsBackupHash) {
      throw StateError('端配置迁移备份校验失败。');
    }
    final settings = jsonDecode(await File(rawSettingsBackup).readAsString());
    if (settings is! Map<String, dynamic>) {
      throw StateError('端配置迁移备份损坏。');
    }
    await _settings.restoreMigrationPreferences(settings);
  }

  Future<void> _snapshotDatabase(String source, String destination) async {
    final database = sqlite3.open(source);
    try {
      final check = database.select('PRAGMA quick_check').first.values.first;
      if (check != 'ok') {
        throw StateError('数据库完整性检查失败：${p.basename(source)}');
      }
      final escapedDestination = destination.replaceAll("'", "''");
      database.execute("VACUUM INTO '$escapedDestination'");
    } finally {
      database.close();
    }
    final snapshot = sqlite3.open(destination);
    try {
      final check = snapshot.select('PRAGMA quick_check').first.values.first;
      if (check != 'ok') {
        throw StateError('数据库快照校验失败：${p.basename(source)}');
      }
    } finally {
      snapshot.close();
    }
  }

  Future<String> _sha256File(String path) async {
    return sha256.convert(await File(path).readAsBytes()).toString();
  }

  Future<int?> _readUserVersion(String path) async {
    if (!await File(path).exists()) {
      return null;
    }
    final database = sqlite3.open(path);
    try {
      return database.select('PRAGMA user_version').single['user_version']
          as int;
    } finally {
      database.close();
    }
  }

  Future<void> _removeSqliteSidecars(String path) async {
    for (final suffix in const ['', '-wal', '-shm']) {
      final file = File('$path$suffix');
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> _writeState(Map<String, dynamic> value) async {
    final file = File(p.join(supportPath, '.migration-state.json'));
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
  }

  Future<void> _releaseLock() async {
    final lock = _startupLock;
    _startupLock = null;
    if (lock != null) {
      await lock.unlock();
      await lock.close();
    }
  }
}
