import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../core/chat_models.dart';
import 'conversation_store.dart';

class SqliteConversationStore implements ConversationStore {
  SqliteConversationStore(this.path);

  final String path;
  late final Database _database;
  bool _opened = false;

  @override
  Future<void> open() async {
    if (_opened) {
      return;
    }
    final parent = Directory(p.dirname(path));
    await parent.create(recursive: true);
    _database = sqlite3.open(path);
    _database
      ..execute('PRAGMA journal_mode = WAL')
      ..execute('PRAGMA foreign_keys = ON')
      ..execute('''
        CREATE TABLE IF NOT EXISTS conversations (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          auto_title INTEGER NOT NULL,
          preview TEXT NOT NULL
        )
      ''')
      ..execute('''
        CREATE TABLE IF NOT EXISTS chat_messages (
          id TEXT PRIMARY KEY,
          conversation_id TEXT NOT NULL,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          status TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          attachments_json TEXT NOT NULL,
          actions_json TEXT NOT NULL,
          error TEXT,
          FOREIGN KEY (conversation_id)
            REFERENCES conversations(id) ON DELETE CASCADE
        )
      ''')
      ..execute(
        'CREATE INDEX IF NOT EXISTS idx_chat_messages_conversation '
        'ON chat_messages(conversation_id, created_at)',
      );
    _opened = true;
  }

  @override
  Future<void> close() async {
    _database.close();
    _opened = false;
  }

  @override
  Future<List<Conversation>> listConversations() async {
    final rows = _database.select(
      'SELECT * FROM conversations ORDER BY updated_at DESC',
    );
    return rows.map(_conversationFromRow).toList(growable: false);
  }

  @override
  Future<Conversation?> findConversation(String id) async {
    final rows = _database.select('SELECT * FROM conversations WHERE id = ?', [
      id,
    ]);
    return rows.isEmpty ? null : _conversationFromRow(rows.first);
  }

  @override
  Future<void> upsertConversation(Conversation conversation) async {
    _database.execute(
      '''
      INSERT INTO conversations (
        id, title, created_at, updated_at, auto_title, preview
      ) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        updated_at = excluded.updated_at,
        auto_title = excluded.auto_title,
        preview = excluded.preview
      ''',
      [
        conversation.id,
        conversation.title,
        conversation.createdAt.toIso8601String(),
        conversation.updatedAt.toIso8601String(),
        conversation.autoTitle ? 1 : 0,
        conversation.preview,
      ],
    );
  }

  @override
  Future<void> deleteConversation(String id) async {
    _database.execute('DELETE FROM conversations WHERE id = ?', [id]);
  }

  @override
  Future<List<ChatMessage>> listMessages(String conversationId) async {
    final rows = _database.select(
      '''
      SELECT * FROM chat_messages
      WHERE conversation_id = ?
      ORDER BY created_at ASC
      ''',
      [conversationId],
    );
    return rows.map(_messageFromRow).toList(growable: false);
  }

  @override
  Future<ChatMessage?> findMessage(String id) async {
    final rows = _database.select('SELECT * FROM chat_messages WHERE id = ?', [
      id,
    ]);
    return rows.isEmpty ? null : _messageFromRow(rows.first);
  }

  @override
  Future<void> upsertMessage(ChatMessage message) async {
    _database.execute(
      '''
      INSERT INTO chat_messages (
        id, conversation_id, role, content, status, created_at, updated_at,
        attachments_json, actions_json, error
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        content = excluded.content,
        status = excluded.status,
        updated_at = excluded.updated_at,
        attachments_json = excluded.attachments_json,
        actions_json = excluded.actions_json,
        error = excluded.error
      ''',
      [
        message.id,
        message.conversationId,
        message.role.wireName,
        message.content,
        message.status.wireName,
        message.createdAt.toIso8601String(),
        message.updatedAt.toIso8601String(),
        jsonEncode(
          message.attachments.map((attachment) => attachment.toJson()).toList(),
        ),
        jsonEncode(message.actions.map((action) => action.toJson()).toList()),
        message.error,
      ],
    );
  }

  @override
  Future<void> deleteMessage(String id) async {
    _database.execute('DELETE FROM chat_messages WHERE id = ?', [id]);
  }

  @override
  Future<AutoRecordAction?> findAutoRecordAction(String id) async {
    final rows = _database.select('SELECT actions_json FROM chat_messages');
    for (final row in rows) {
      final actions = _decodeList(row['actions_json']);
      for (final value in actions) {
        if (value is Map) {
          final action = AutoRecordAction.fromJson(
            value.map((key, value) => MapEntry(key.toString(), value)),
          );
          if (action.id == id) {
            return action;
          }
        }
      }
    }
    return null;
  }

  @override
  Future<void> clear() async {
    _database
      ..execute('DELETE FROM chat_messages')
      ..execute('DELETE FROM conversations');
  }

  Conversation _conversationFromRow(Row row) {
    return Conversation(
      id: row['id'] as String,
      title: row['title'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      autoTitle: row['auto_title'] == 1,
      preview: row['preview'] as String,
    );
  }

  ChatMessage _messageFromRow(Row row) {
    return ChatMessage(
      id: row['id'] as String,
      conversationId: row['conversation_id'] as String,
      role: ChatRole.parse(row['role'] as String),
      content: row['content'] as String,
      status: ChatMessageStatus.parse(row['status'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      attachments: _decodeList(row['attachments_json'])
          .whereType<Map>()
          .map(
            (value) => ChatAttachment.fromJson(
              value.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(growable: false),
      actions: _decodeList(row['actions_json'])
          .whereType<Map>()
          .map(
            (value) => AutoRecordAction.fromJson(
              value.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(growable: false),
      error: row['error'] as String?,
    );
  }

  List<dynamic> _decodeList(Object? value) {
    if (value is! String || value.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(value);
    return decoded is List ? decoded : const [];
  }
}
