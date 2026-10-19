import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/sqlite_conversation_store.dart';

void main() {
  test(
    'sqlite conversation store persists messages and auto actions',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'conversation-store',
      );
      final path = '${directory.path}${Platform.pathSeparator}chat.sqlite3';
      final store = SqliteConversationStore(path);
      await store.open();
      await store.open();

      final now = DateTime(2026, 10, 4, 23, 30);
      final conversation = Conversation(
        id: 'cnv_test',
        title: '测试会话',
        createdAt: now,
        updatedAt: now,
        autoTitle: false,
        preview: '你好',
        aiPermissions: const AiPermissions(
          read: false,
          create: true,
          modifyDelete: false,
        ),
      );
      await store.upsertConversation(conversation);
      final historyConversation = Conversation(
        id: 'cnv_history',
        title: '历史会话',
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(days: 1)),
        autoTitle: false,
      );
      await store.upsertConversation(historyConversation);
      await store.upsertMessage(
        ChatMessage(
          id: 'msg_history',
          conversationId: historyConversation.id,
          role: ChatRole.user,
          content: '本学期从九月一日开始，总共十六周。',
          status: ChatMessageStatus.complete,
          createdAt: historyConversation.createdAt,
          updatedAt: historyConversation.updatedAt,
        ),
      );
      await store.upsertMessage(
        ChatMessage(
          id: 'msg_test',
          conversationId: conversation.id,
          role: ChatRole.assistant,
          content: '已记录',
          status: ChatMessageStatus.complete,
          createdAt: now,
          updatedAt: now,
          attachments: [
            ChatAttachment(
              id: 'att_test',
              storageKey: 'cnv_test/msg_test/att_test.jpg',
              fileName: 'test.jpg',
              mimeType: 'image/jpeg',
              createdAt: now,
            ),
          ],
          actions: [
            AutoRecordAction(
              id: 'act_test',
              type: ResultType.todo,
              title: '测试待办',
              status: AutoRecordStatus.created,
              createdAt: now,
              resultId: 'td_test',
              undoUntil: now.add(const Duration(minutes: 10)),
              operation: AutoRecordOperation.update,
            ),
          ],
        ),
      );
      await store.upsertGeneration(
        GenerationRun(
          assistantMessageId: 'msg_test',
          conversationId: conversation.id,
          userMessageId: 'msg_user',
          status: GenerationStatus.responseReady,
          responseText: '已记录',
          toolCalls: const [
            {'index': '0', 'name': 'create_result', 'arguments': '{}'},
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );

      await store.close();
      final reopened = SqliteConversationStore(path);
      await reopened.open();

      final persistedConversation = (await reopened.findConversation(
        'cnv_test',
      ))!;
      expect(persistedConversation.title, '测试会话');
      expect(
        persistedConversation.aiPermissions,
        const AiPermissions(read: false, create: true, modifyDelete: false),
      );
      final message = (await reopened.listMessages('cnv_test')).single;
      expect(message.content, '已记录');
      expect(message.attachments.single.fileName, 'test.jpg');
      expect(message.actions.single.resultId, 'td_test');
      expect(message.actions.single.operation, AutoRecordOperation.update);
      expect(
        (await reopened.searchMessages(
          query: '十六周',
          excludedConversationId: 'cnv_test',
          limit: 5,
        )).map((item) => item.conversationId),
        ['cnv_history'],
      );
      expect((await reopened.findAutoRecordAction('act_test'))?.title, '测试待办');
      final generation = await reopened.findGeneration('msg_test');
      expect(generation?.status, GenerationStatus.responseReady);
      expect(generation?.toolCalls.single['name'], 'create_result');

      await reopened.deleteConversation('cnv_test');
      expect((await reopened.listConversations()).map((item) => item.id), [
        'cnv_history',
      ]);
      expect(await reopened.listMessages('cnv_test'), isEmpty);
      expect(await reopened.findGeneration('msg_test'), isNull);
      await reopened.close();
      await directory.delete(recursive: true);
    },
  );

  test('migrates v1 conversations with all AI permissions enabled', () async {
    final directory = await Directory.systemTemp.createTemp(
      'conversation-permission-migration',
    );
    final path = '${directory.path}${Platform.pathSeparator}chat.sqlite3';
    final oldDatabase = sqlite3.open(path);
    oldDatabase
      ..execute('''
        CREATE TABLE conversations (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          auto_title INTEGER NOT NULL,
          preview TEXT NOT NULL
        )
      ''')
      ..execute('''
        INSERT INTO conversations VALUES (
          'cnv_legacy', '旧会话', '2026-01-01T00:00:00.000',
          '2026-01-01T00:00:00.000', 0, ''
        )
      ''')
      ..execute('PRAGMA user_version = 1')
      ..close();

    final migrated = SqliteConversationStore(path);
    await migrated.open();
    expect(
      (await migrated.findConversation('cnv_legacy'))?.aiPermissions,
      const AiPermissions(),
    );

    final updated = (await migrated.findConversation('cnv_legacy'))!.copyWith(
      aiPermissions: const AiPermissions(read: false, modifyDelete: false),
    );
    await migrated.upsertConversation(updated);
    await migrated.close();

    final reopened = SqliteConversationStore(path);
    await reopened.open();
    expect(
      (await reopened.findConversation('cnv_legacy'))?.aiPermissions,
      const AiPermissions(read: false, create: true, modifyDelete: false),
    );
    await reopened.close();
    await directory.delete(recursive: true);
  });
}
