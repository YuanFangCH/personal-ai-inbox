import 'dart:convert';
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
          tableActions: [
            TableChatAction(
              id: 'tbl_act_test',
              operation: 'table.create',
              title: '考试表',
              status: TableChatActionStatus.pendingConfirmation,
              createdAt: now,
              tableId: 'tb_exam',
              proposal: const {
                'operation': 'create',
                'table_id': 'tb_exam',
                'payload': {'title': '考试表'},
              },
            ),
          ],
          reasoningContent: 'hidden model reasoning',
          toolTranscript: const [
            {
              'role': 'assistant',
              'reasoning_content': 'hidden tool reasoning',
              'tool_calls': [
                {
                  'id': 'call_search',
                  'type': 'function',
                  'function': {'name': 'search_results', 'arguments': '{}'},
                },
              ],
            },
            {
              'role': 'tool',
              'tool_call_id': 'call_search',
              'name': 'search_results',
              'content': '{"hits":[]}',
            },
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
      expect(message.tableActions.single.id, 'tbl_act_test');
      expect(
        message.tableActions.single.status,
        TableChatActionStatus.pendingConfirmation,
      );
      expect(message.reasoningContent, 'hidden model reasoning');
      expect(message.toolTranscript, hasLength(2));
      expect(
        (await reopened.searchMessages(
          query: '十六周',
          excludedConversationId: 'cnv_test',
          limit: 5,
        )).map((item) => item.conversationId),
        ['cnv_history'],
      );
      expect((await reopened.findAutoRecordAction('act_test'))?.title, '测试待办');
      expect(await reopened.findAutoRecordAction('tbl_act_test'), isNull);
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
    expect(
      (await migrated.findConversation('cnv_legacy'))?.effectiveAiPolicy
          .decisionFor(AiPermissionAction.tableDelete),
      AiPolicyDecision.ask,
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

  test('migrates v5 conversations and persists action-level policy', () async {
    final directory = await Directory.systemTemp.createTemp(
      'conversation-policy-migration',
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
          preview TEXT NOT NULL,
          ai_permissions_json TEXT NOT NULL
        )
      ''')
      ..execute('''
        INSERT INTO conversations VALUES (
          'cnv_v5', 'v5会话', '2026-01-01T00:00:00.000',
          '2026-01-01T00:00:00.000', 0, '',
          '{"read":false,"create":true,"modify_delete":false}'
        )
      ''')
      ..execute('PRAGMA user_version = 5')
      ..close();

    final migrated = SqliteConversationStore(path);
    await migrated.open();
    final legacy = (await migrated.findConversation('cnv_v5'))!;
    expect(legacy.aiPolicy, isNull);
    expect(
      legacy.effectiveAiPolicy.decisionFor(AiPermissionAction.tableRead),
      AiPolicyDecision.deny,
    );

    final standard = AiPolicy.forPreset(
      AiPolicyPreset.standard,
      version: 2,
      tableScope: AiResourceScope.selected(const ['tb_v5']),
      knowledgeReadScope: const AiResourceScope.none(),
    );
    await migrated.upsertConversation(legacy.copyWith(aiPolicy: standard));
    await migrated.close();

    final reopened = SqliteConversationStore(path);
    await reopened.open();
    final restored = (await reopened.findConversation('cnv_v5'))!;
    expect(restored.aiPolicy, isNotNull);
    expect(restored.aiPolicy!.preset, AiPolicyPreset.standard);
    expect(restored.aiPolicy!.version, 2);
    expect(restored.aiPolicy!.tableScope.covers('tb_v5'), isTrue);
    expect(restored.aiPolicy!.tableScope.covers('tb_other'), isFalse);
    expect(restored.aiPolicy!.knowledgeReadScope.isNone, isTrue);
    expect(
      restored.effectiveAiPolicy.decisionFor(AiPermissionAction.tableDelete),
      AiPolicyDecision.ask,
    );
    await reopened.close();

    final database = sqlite3.open(path);
    expect(database.select('PRAGMA user_version').single['user_version'], 6);
    expect(
      database
          .select('PRAGMA table_info(conversations)')
          .map((row) => row['name']),
      contains('ai_policy_json'),
    );
    final stored = database.select(
      'SELECT ai_permissions_json FROM conversations WHERE id = ?',
      ['cnv_v5'],
    ).single;
    expect(jsonDecode(stored['ai_permissions_json'] as String), {
      'read': true,
      'create': true,
      'modify_delete': true,
    });
    database.close();
    await directory.delete(recursive: true);
  });
}
