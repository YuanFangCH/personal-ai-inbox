import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/sqlite_conversation_store.dart';
import 'package:personal_ai_inbox/data/sqlite_index_database.dart';
import 'package:personal_ai_inbox/data/settings_service.dart';
import 'package:personal_ai_inbox/data/sqlite_migration_coordinator.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
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
      _markMigrated(indexPath, version: 6);
      _markMigrated(conversationPath, version: 3);
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
      _markMigrated(indexPath, version: 6);
      await expectLater(migration.complete(), throwsA(isA<StateError>()));
      _markMigrated(conversationPath, version: 3);
      await migration.complete();

      final state = jsonDecode(
        await File('${directory.path}/.migration-state.json').readAsString(),
      ) as Map<String, dynamic>;
      expect(state['status'], 'complete');
    },
  );

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
