import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/sqlite_conversation_store.dart';
import 'package:personal_ai_inbox/data/sqlite_index_database.dart';
import 'package:personal_ai_inbox/data/settings_service.dart';
import 'package:personal_ai_inbox/data/sqlite_migration_coordinator.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'rollback restores task checkpoint bytes from the migration group',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'inbox-task-checkpoint-migration',
      );
      addTearDown(() => directory.delete(recursive: true));
      final checkpoint = File(
        p.join(
          directory.path,
          'vault',
          '.local',
          'agent-task-checkpoint.json',
        ),
      );
      final missingBeforeMigration = File(
        p.join(directory.path, 'vault', '.local', 'new-checkpoint.json'),
      );
      await checkpoint.parent.create(recursive: true);
      final originalBytes = utf8.encode(
        '{"schema_version":1,"legacy":"preserve exact bytes"}',
      );
      await checkpoint.writeAsBytes(originalBytes, flush: true);

      final migration = SqliteMigrationCoordinator(
        supportPath: directory.path,
        settings: _MigrationSettings({'device_id': 'before-upgrade'}),
        additionalFilePaths: [checkpoint.path, missingBeforeMigration.path],
      );
      addTearDown(migration.rollback);
      await migration.prepare();
      final state = jsonDecode(
        await File(p.join(directory.path, '.migration-state.json'))
            .readAsString(),
      ) as Map<String, dynamic>;
      expect(state['files'], isA<List<dynamic>>());
      final snapshots = (state['files'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(snapshots, hasLength(2));
      final snapshot = snapshots.singleWhere(
        (item) => item['path'] == checkpoint.path,
      );
      expect(
        snapshots.singleWhere(
          (item) => item['path'] == missingBeforeMigration.path,
        )['existed'],
        isFalse,
      );
      final backupPath = snapshot['backup'] as String;
      expect(snapshot['existed'], isTrue);
      expect(
        sha256.convert(await File(backupPath).readAsBytes()).toString(),
        snapshot['backup_sha256'],
      );
      expect(await File(backupPath).readAsBytes(), originalBytes);

      await checkpoint.writeAsString('{"schema_version":2}', flush: true);
      await missingBeforeMigration.writeAsString('created during upgrade');
      await migration.rollback();

      expect(await checkpoint.readAsBytes(), originalBytes);
      expect(await missingBeforeMigration.exists(), isFalse);
      expect(await File(backupPath).exists(), isTrue);
    },
  );

  test(
    'rollback validates every backup before restoring database or earlier files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'inbox-migration-prevalidate-all-backups',
      );
      addTearDown(() => directory.delete(recursive: true));
      final indexPath = p.join(directory.path, 'index.sqlite3');
      final conversationPath = p.join(directory.path, 'conversations.sqlite3');
      _markMigrated(indexPath, version: 10);
      _markMigrated(conversationPath, version: 5);

      final firstFile = File(
        p.join(directory.path, 'vault', '.local', 'first-checkpoint.json'),
      );
      final secondFile = File(
        p.join(directory.path, 'vault', '.local', 'second-checkpoint.json'),
      );
      await firstFile.parent.create(recursive: true);
      await firstFile.writeAsString('first-before', flush: true);
      await secondFile.writeAsString('second-before', flush: true);
      final settings = _MigrationSettings({'device_id': 'before'});
      final migration = SqliteMigrationCoordinator(
        supportPath: directory.path,
        settings: settings,
        additionalFilePaths: [firstFile.path, secondFile.path],
      );
      addTearDown(() async {
        try {
          await migration.rollback();
        } on Object {
          // A deliberately corrupted backup keeps the durable manifest pending.
        }
      });
      await migration.prepare();

      final stateFile = File(p.join(directory.path, '.migration-state.json'));
      final state = jsonDecode(await stateFile.readAsString())
          as Map<String, dynamic>;
      final fileSnapshots = (state['files'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final firstBackup = fileSnapshots.first['backup'] as String;
      final secondBackup = fileSnapshots.last['backup'] as String;

      _markMigrated(indexPath, version: 99);
      _markMigrated(conversationPath, version: 99);
      await firstFile.writeAsString('first-after', flush: true);
      await secondFile.writeAsString('second-after', flush: true);
      settings.values['device_id'] = 'after';
      await File(secondBackup).writeAsString('corrupt backup', flush: true);

      await expectLater(migration.rollback(), throwsStateError);

      expect(_readVersion(indexPath), 99);
      expect(_readVersion(conversationPath), 99);
      expect(await firstFile.readAsString(), 'first-after');
      expect(await secondFile.readAsString(), 'second-after');
      expect(settings.values['device_id'], 'after');
      expect(
        (jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>)['status'],
        'pending',
      );
      expect(await File(firstBackup).exists(), isTrue);
      expect(await File(secondBackup).readAsString(), 'corrupt backup');
    },
  );

  for (final (name, corruptFiles) in [
    ('missing entries', (List<dynamic> files) => <dynamic>[]),
    ('missing list', (List<dynamic> files) => null),
    ('duplicate path', (List<dynamic> files) => [files.single, files.single]),
  ]) {
    test(
      'new migration manifest rejects $name additional file entries before rollback',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'inbox-migration-manifest-$name',
        );
        addTearDown(() => directory.delete(recursive: true));
        final checkpoint = File(
          p.join(directory.path, 'vault', '.local', 'checkpoint.json'),
        );
        await checkpoint.parent.create(recursive: true);
        const original = '{"checkpoint":"preserve exact source"}';
        await checkpoint.writeAsString(original, flush: true);

        final settings = _MigrationSettings({'device_id': 'before'});
        final originalMigration = SqliteMigrationCoordinator(
          supportPath: directory.path,
          settings: settings,
          additionalFilePaths: [checkpoint.path],
        );
        await originalMigration.prepare();
        await originalMigration.rollback();

        final stateFile = File(
          p.join(directory.path, '.migration-state.json'),
        );
        final state = jsonDecode(await stateFile.readAsString())
            as Map<String, dynamic>;
        expect(state['schema_version'], 2);
        final fileEntries = (state['files'] as List<dynamic>);
        final backupPath =
            (fileEntries.single as Map<String, dynamic>)['backup'] as String;
        state['status'] = 'pending';
        final corruptedFiles = corruptFiles(fileEntries);
        if (corruptedFiles == null) {
          state.remove('files');
        } else {
          state['files'] = corruptedFiles;
        }
        await stateFile.writeAsString(jsonEncode(state), flush: true);

        final recovery = SqliteMigrationCoordinator(
          supportPath: directory.path,
          settings: settings,
          additionalFilePaths: [checkpoint.path],
        );
        addTearDown(recovery.rollback);
        await expectLater(recovery.prepare(), throwsStateError);

        final retained = jsonDecode(await stateFile.readAsString())
            as Map<String, dynamic>;
        expect(retained['status'], 'pending');
        if (corruptedFiles == null) {
          expect(retained.containsKey('files'), isFalse);
        } else {
          expect(
            retained['files'],
            hasLength(name == 'missing entries' ? 0 : 2),
          );
        }
        expect(await checkpoint.readAsString(), original);
        expect(await File(backupPath).exists(), isTrue);
      },
    );
  }

  test('legacy pending migration manifest without files remains readable', () async {
    final directory = await Directory.systemTemp.createTemp(
      'inbox-legacy-migration-manifest',
    );
    addTearDown(() => directory.delete(recursive: true));
    final checkpoint = File(
      p.join(directory.path, 'vault', '.local', 'checkpoint.json'),
    );
    await checkpoint.parent.create(recursive: true);
    await checkpoint.writeAsString('{"legacy":true}', flush: true);
    final settings = _MigrationSettings({'device_id': 'before'});
    final migration = SqliteMigrationCoordinator(
      supportPath: directory.path,
      settings: settings,
      additionalFilePaths: [checkpoint.path],
    );
    await migration.prepare();
    await migration.rollback();

    final stateFile = File(p.join(directory.path, '.migration-state.json'));
    final state = jsonDecode(await stateFile.readAsString())
        as Map<String, dynamic>;
    state
      ..['schema_version'] = 1
      ..['status'] = 'pending'
      ..remove('files');
    await stateFile.writeAsString(jsonEncode(state), flush: true);

    final recovery = SqliteMigrationCoordinator(
      supportPath: directory.path,
      settings: settings,
      additionalFilePaths: [checkpoint.path],
    );
    addTearDown(recovery.rollback);
    await expectLater(recovery.prepare(), completes);
    await recovery.rollback();
    expect(await checkpoint.readAsString(), '{"legacy":true}');
  });

  test('v10 index upgrade rollback restores the entire database group and backup hashes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'inbox-v10-migration-rollback',
    );
    addTearDown(() => directory.delete(recursive: true));
    final indexPath = '${directory.path}/index.sqlite3';
    final conversationPath = '${directory.path}/conversations.sqlite3';
    final index = SqliteIndexDatabase(indexPath);
    await index.open();
    final createdAt = DateTime(2026, 11, 5);
    final candidate = GlobalKnowledgeCandidate(
      id: 'gkc_v10_rollback',
      operation: GlobalKnowledgeOperation.create,
      status: GlobalKnowledgeCandidateStatus.pending,
      authorizationSource: GlobalKnowledgeAuthorizationSource.none,
      proposal: const {
        'title': '迁移前候选',
        'body': '保留待确认状态',
        'facts': {'owner': 'user'},
      },
      digest: 'digest-v10',
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    await index.upsertGlobalKnowledgeCandidate(candidate);
    await index.close();
    final legacyIndex = sqlite3.open(indexPath)
      ..execute('PRAGMA user_version = 10');
    legacyIndex.close();

    final conversations = SqliteConversationStore(conversationPath);
    await conversations.open();
    final conversation = Conversation(
      id: 'cnv_v10_rollback',
      title: '迁移恢复检查',
      createdAt: createdAt,
      updatedAt: createdAt,
      autoTitle: false,
    );
    await conversations.upsertConversation(conversation);
    await conversations.close();
    final legacyConversations = sqlite3.open(conversationPath)
      ..execute('PRAGMA user_version = 5');
    legacyConversations.close();

    final settings = _MigrationSettings({'device_id': 'before-upgrade'});
    final migration = SqliteMigrationCoordinator(
      supportPath: directory.path,
      settings: settings,
    );
    await migration.prepare();
    final state = jsonDecode(
      await File('${directory.path}/.migration-state.json').readAsString(),
    ) as Map<String, dynamic>;
    final snapshots = (state['databases'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    for (final snapshot in snapshots) {
      final backupPath = snapshot['backup'] as String;
      expect(
        sha256.convert(await File(backupPath).readAsBytes()).toString(),
        snapshot['backup_sha256'],
      );
    }

    final upgradedIndex = SqliteIndexDatabase(indexPath);
    await upgradedIndex.open();
    final upgradedCandidate = (await upgradedIndex.findGlobalKnowledgeCandidate(
      candidate.id,
    ))!;
    await upgradedIndex.upsertGlobalKnowledgeCandidate(
      upgradedCandidate.copyWith(status: GlobalKnowledgeCandidateStatus.failed),
    );
    await upgradedIndex.close();
    final upgradedConversations = SqliteConversationStore(conversationPath);
    await upgradedConversations.open();
    await upgradedConversations.close();
    settings.values['device_id'] = 'after-upgrade';
    await migration.rollback();

    expect(_readVersion(indexPath), 10);
    expect(_readVersion(conversationPath), 5);
    expect(settings.values['device_id'], 'before-upgrade');
    final restoredIndex = SqliteIndexDatabase(indexPath);
    await restoredIndex.open();
    final restoredCandidate = await restoredIndex.findGlobalKnowledgeCandidate(
      candidate.id,
    );
    expect(restoredCandidate?.status, GlobalKnowledgeCandidateStatus.pending);
    expect(
      restoredCandidate?.authorizationSource,
      GlobalKnowledgeAuthorizationSource.none,
    );
    await restoredIndex.close();
    final restoredConversations = SqliteConversationStore(conversationPath);
    await restoredConversations.open();
    expect(
      (await restoredConversations.listConversations()).single.id,
      conversation.id,
    );
    await restoredConversations.close();
    for (final snapshot in snapshots) {
      final backupPath = snapshot['backup'] as String;
      expect(
        sha256.convert(await File(backupPath).readAsBytes()).toString(),
        snapshot['backup_sha256'],
      );
    }
  });

  test(
    'rollback restores both database snapshots and non-secret settings',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'inbox-migration',
      );
      addTearDown(() => directory.delete(recursive: true));
      final indexPath = '${directory.path}/index.sqlite3';
      final conversationPath = '${directory.path}/conversations.sqlite3';
      _createLegacyDatabase(indexPath, 'legacy_index');
      _createLegacyDatabase(conversationPath, 'legacy_conversations');
      final settings = _MigrationSettings({'device_id': 'device-before'});
      final migration = SqliteMigrationCoordinator(
        supportPath: directory.path,
        settings: settings,
      );

      await migration.prepare();
      _markMigrated(indexPath);
      _markMigrated(conversationPath, version: 5);
      settings.values['device_id'] = 'device-after';
      await migration.rollback();

      expect(_readVersion(indexPath), 0);
      expect(_readVersion(conversationPath), 0);
      expect(_tableExists(indexPath, 'legacy_index'), isTrue);
      expect(_tableExists(conversationPath, 'legacy_conversations'), isTrue);
      expect(_tableExists(indexPath, 'migration_change'), isFalse);
      expect(settings.values['device_id'], 'device-before');
      expect(settings.values.containsKey('model_api_key'), isFalse);
    },
  );

  test(
    'a pending migration is rolled back before another startup snapshot',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'inbox-migration',
      );
      addTearDown(() => directory.delete(recursive: true));
      final indexPath = '${directory.path}/index.sqlite3';
      _createLegacyDatabase(indexPath, 'legacy_index');
      final settings = _MigrationSettings({'device_id': 'device-original'});
      final first = SqliteMigrationCoordinator(
        supportPath: directory.path,
        settings: settings,
      );
      await first.prepare();
      await first.rollback();
      final stateFile = File('${directory.path}/.migration-state.json');
      final state =
          jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
      await stateFile.writeAsString(
        jsonEncode({...state, 'status': 'pending'}),
      );
      _markMigrated(indexPath);
      settings.values['device_id'] = 'uncommitted';

      final next = SqliteMigrationCoordinator(
        supportPath: directory.path,
        settings: settings,
      );
      await next.prepare();
      expect(_readVersion(indexPath), 0);
      expect(settings.values['device_id'], 'device-original');
      await next.rollback();
    },
  );

  test(
    'completes only after both databases reach the supported version',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'inbox-migration',
      );
      addTearDown(() => directory.delete(recursive: true));
      final migration = SqliteMigrationCoordinator(
        supportPath: directory.path,
        settings: _MigrationSettings(const {}),
      );
      await migration.prepare();
      final indexPath = '${directory.path}/index.sqlite3';
      final conversationPath = '${directory.path}/conversations.sqlite3';
      _markMigrated(indexPath, version: 11);
      await expectLater(migration.complete(), throwsA(isA<StateError>()));
      _markMigrated(conversationPath, version: 5);
      await expectLater(migration.complete(), throwsA(isA<StateError>()));
      _markMigrated(conversationPath, version: 6);
      await migration.complete();

      final state = jsonDecode(
        await File('${directory.path}/.migration-state.json').readAsString(),
      ) as Map<String, dynamic>;
      expect(state['status'], 'complete');
    },
  );

  test('table migration snapshot backs up both databases and settings idempotently', () async {
    final directory = await Directory.systemTemp.createTemp(
      'inbox-table-migration-snapshot',
    );
    addTearDown(() => directory.delete(recursive: true));
    final indexPath = '${directory.path}/index.sqlite3';
    final conversationPath = '${directory.path}/conversations.sqlite3';
    _createLegacyDatabase(indexPath, 'index_payload');
    _createLegacyDatabase(conversationPath, 'conversation_payload');
    _markMigrated(indexPath, version: 11);
    _markMigrated(conversationPath, version: 5);
    final settings = _MigrationSettings({'device_id': 'snapshot-device'});
    final migration = SqliteMigrationCoordinator(
      supportPath: directory.path,
      settings: settings,
    );
    const migrationId = 'tm_0123456789abcdef01234567';

    expect(
      await migration.estimateTableMigrationSnapshotBytes(),
      greaterThan(0),
    );
    final manifestPath = await migration.createTableMigrationSnapshot(
      migrationId,
    );
    final manifest = jsonDecode(
      await File(manifestPath).readAsString(),
    ) as Map<String, dynamic>;
    expect(manifest['migration_id'], migrationId);
    expect(manifest['databases'], hasLength(2));
    for (final raw in manifest['databases'] as List<dynamic>) {
      final row = raw as Map<String, dynamic>;
      expect(row['user_version'], row['name'] == 'index.sqlite3' ? 11 : 5);
      final snapshot = sqlite3.open(row['backup'] as String);
      expect(snapshot.select('PRAGMA quick_check').single.values.single, 'ok');
      expect(
        snapshot.select("SELECT name FROM sqlite_master WHERE type = 'table'"),
        hasLength(2),
      );
      snapshot.close();
    }
    final settingsSnapshot = jsonDecode(
      await File(manifest['settings_backup'] as String).readAsString(),
    ) as Map<String, dynamic>;
    expect(settingsSnapshot['device_id'], 'snapshot-device');
    expect(
      await migration.createTableMigrationSnapshot(migrationId),
      manifestPath,
    );
  });

  test(
    'schema upgrade preserves legacy result, capture and conversation rows',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'inbox-migration',
      );
      addTearDown(() => directory.delete(recursive: true));
      final indexPath = '${directory.path}/index.sqlite3';
      final conversationPath = '${directory.path}/conversations.sqlite3';
      final timestamp = DateTime(2026, 10, 13, 10);

      final index = SqliteIndexDatabase(indexPath);
      await index.open();
      final result = IndexedResult(
        id: 'kn_20261013_12345678',
        type: ResultType.knowledge,
        title: '迁移知识',
        status: ResultStatus.canonical,
        revision: 1,
        updatedAt: timestamp,
        deleted: false,
        mdPath: 'vault/knowledge/kn_20261013_12345678.md',
        localHash: 'sha256:legacy',
        lastSyncedHash: null,
        syncState: SyncState.pendingUpload,
      );
      await index.upsertResult(result);
      await index.insertCapture(
        CaptureRecord(
          id: 'cap_legacy',
          deviceId: 'device_before',
          capturedAt: timestamp,
          sourceType: CaptureSourceType.text,
          text: '保留的捕获',
          status: CaptureStatus.needsReview,
        ),
      );
      await index.close();
      final legacyIndex = sqlite3.open(indexPath)
        ..execute('DROP TABLE actions')
        ..execute('PRAGMA user_version = 0');
      legacyIndex.close();

      final chat = SqliteConversationStore(conversationPath);
      await chat.open();
      final conversation = Conversation(
        id: 'cnv_legacy',
        title: '旧会话',
        createdAt: timestamp,
        updatedAt: timestamp,
        autoTitle: false,
      );
      await chat.upsertConversation(conversation);
      await chat.upsertMessage(
        ChatMessage(
          id: 'msg_legacy',
          conversationId: conversation.id,
          role: ChatRole.user,
          content: '不能丢失',
          status: ChatMessageStatus.complete,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      await chat.close();
      final legacyChat = sqlite3.open(conversationPath)
        ..execute('DROP TABLE generation_runs')
        ..execute('DROP TRIGGER IF EXISTS chat_messages_fts_insert')
        ..execute('DROP TRIGGER IF EXISTS chat_messages_fts_update')
        ..execute('DROP TRIGGER IF EXISTS chat_messages_fts_delete')
        ..execute('DROP TABLE chat_messages_fts')
        ..execute('ALTER TABLE conversations DROP COLUMN ai_permissions_json')
        ..execute('ALTER TABLE chat_messages DROP COLUMN reasoning_content')
        ..execute('ALTER TABLE chat_messages DROP COLUMN tool_transcript_json')
        ..execute('PRAGMA user_version = 0');
      legacyChat.close();

      final migration = SqliteMigrationCoordinator(
        supportPath: directory.path,
        settings: _MigrationSettings({'device_id': 'device_before'}),
      );
      await migration.prepare();
      final upgradedIndex = SqliteIndexDatabase(indexPath);
      final upgradedChat = SqliteConversationStore(conversationPath);
      await upgradedIndex.open();
      await upgradedChat.open();
      await migration.complete();

      expect((await upgradedIndex.findResult(result.id))?.title, '迁移知识');
      expect((await upgradedIndex.listCaptures()).single.text, '保留的捕获');
      expect(
        (await upgradedChat.listMessages(conversation.id)).single.content,
        '不能丢失',
      );
      await upgradedIndex.close();
      await upgradedChat.close();
    },
  );
}

void _createLegacyDatabase(String path, String table) {
  final database = sqlite3.open(path)
    ..execute('CREATE TABLE $table (value TEXT NOT NULL)')
    ..execute('INSERT INTO $table (value) VALUES (?)', ['legacy']);
  database.close();
}

void _markMigrated(String path, {int version = 1}) {
  final database = sqlite3.open(path)
    ..execute('CREATE TABLE IF NOT EXISTS migration_change (value TEXT)')
    ..execute('PRAGMA user_version = $version');
  database.close();
}

int _readVersion(String path) {
  final database = sqlite3.open(path);
  final version =
      database.select('PRAGMA user_version').single['user_version'] as int;
  database.close();
  return version;
}

bool _tableExists(String path, String table) {
  final database = sqlite3.open(path);
  final rows = database.select(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    [table],
  );
  database.close();
  return rows.isNotEmpty;
}

class _MigrationSettings extends SettingsService {
  _MigrationSettings(Map<String, Object?> values)
    : values = Map<String, Object?>.of(values);

  Map<String, Object?> values;

  @override
  Future<Map<String, Object?>> exportMigrationPreferences() async {
    return Map<String, Object?>.of(values);
  }

  @override
  Future<void> restoreMigrationPreferences(
    Map<String, dynamic> snapshot,
  ) async {
    values = Map<String, Object?>.from(snapshot);
  }
}
