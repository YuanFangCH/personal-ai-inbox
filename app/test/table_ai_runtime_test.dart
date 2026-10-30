import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'test_support.dart';

void main() {
  test(
    'startup recovery never replays legacy result writes in table mode',
    () async {
      final store = MemoryConversationStore();
      final now = DateTime.now();
      const conversationId = 'cnv_legacy_pending_recovery';
      const userMessageId = 'msg_legacy_pending_user';
      const assistantMessageId = 'msg_legacy_pending_assistant';
      await store.upsertConversation(
        Conversation(
          id: conversationId,
          title: '旧格式待恢复会话',
          createdAt: now,
          updatedAt: now,
          autoTitle: false,
        ),
      );
      await store.upsertMessage(
        ChatMessage(
          id: userMessageId,
          conversationId: conversationId,
          role: ChatRole.user,
          content: '帮我创建待办',
          status: ChatMessageStatus.complete,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await store.upsertMessage(
        ChatMessage(
          id: assistantMessageId,
          conversationId: conversationId,
          role: ChatRole.assistant,
          content: '',
          status: ChatMessageStatus.streaming,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await store.upsertGeneration(
        GenerationRun(
          assistantMessageId: assistantMessageId,
          conversationId: conversationId,
          userMessageId: userMessageId,
          status: GenerationStatus.responseReady,
          responseText: '已记录旧格式待办',
          toolCalls: [
            {
              'index': '0',
              'id': 'call_legacy_pending',
              'name': 'create_result',
              'arguments': jsonEncode({
                'type': 'todo',
                'title': '不得回放为旧待办',
                'body': '迁移后的会话恢复必须使用表格式工具。',
                'confidence': 0.99,
                'sensitive': false,
                'due': now.add(const Duration(days: 2)).toIso8601String(),
              }),
            },
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );

      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        conversationStoreOverride: store,
        attachmentStoreOverride: MemoryAttachmentStore(),
        settingsOverride: FakeSettingsService(deviceId: 'legacy-recovery'),
      );
      addTearDown(runtime.shutdown);

      expect(runtime.results.documents, isEmpty);
      expect(runtime.tables.entries, isEmpty);
      await runtime.conversations.openConversation(conversationId);
      final recovered = runtime.conversations
          .messagesFor(conversationId)
          .singleWhere((message) => message.id == assistantMessageId);
      expect(recovered.status, ChatMessageStatus.complete);
      expect(recovered.actions, isEmpty);
    },
  );

  test(
    'complete model response applies table content without confirmation',
    () async {
      late final AppRuntime runtime;
      runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(modelKey: 'table-ai-test'),
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            final payload =
                jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            final names = (payload['tools'] as List)
                .map((tool) => (tool as Map)['function']['name'])
                .toSet();
            expect(names, contains('content.create'));
            expect(names, contains('table.propose'));
            expect(names, isNot(contains('create_result')));
            return _stream({
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_create_table_note',
                        'function': {
                          'name': 'content.create',
                          'arguments': jsonEncode({
                            'table_id': runtime.tables.tables
                                .singleWhere(
                                  (table) => table.role == TableRole.inboxEvent,
                                )
                                .id,
                            'type': 'note',
                            'title': '考试范围',
                            'body': '第三章到第五章',
                            'idempotency_key': 'create-exam-note',
                          }),
                        },
                      },
                    ],
                  },
                },
              ],
            }, finish: 'tool_calls');
          }),
        ),
      );
      addTearDown(runtime.shutdown);
      final conversation = await runtime.conversations.createConversation();
      await runtime.conversations.sendChatMessage(
        conversation.id,
        text: '把考试范围记下来',
      );

      final entry = runtime.tables.entries.singleWhere(
        (item) => item.title == '考试范围',
      );
      expect(entry.type, TableContentType.note);
      expect(
        entry.tableId,
        runtime.tables.tables
            .singleWhere((table) => table.role == TableRole.inboxEvent)
            .id,
      );
      expect(entry.body, '第三章到第五章');
      final assistant = runtime.conversations.messagesFor(conversation.id).last;
      expect(assistant.status, ChatMessageStatus.complete);
      expect(
        assistant.tableActions.single.status,
        TableChatActionStatus.applied,
      );
      expect(assistant.actions, isEmpty);
    },
  );

  test(
    'model table structure call waits, then confirms through the workspace',
    () async {
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(
          modelKey: 'table-structure-ai-test',
        ),
        modelClient: ModelClient(
          client: MockClient.streaming(
            (request, body) async => _stream({
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_propose_table',
                        'function': {
                          'name': 'table.propose',
                          'arguments': jsonEncode({
                            'operation': 'create',
                            'payload': {'title': '课程安排'},
                            'idempotency_key': 'propose-course-table',
                          }),
                        },
                      },
                    ],
                  },
                },
              ],
            }, finish: 'tool_calls'),
          ),
        ),
      );
      addTearDown(runtime.shutdown);
      final conversation = await runtime.conversations.createConversation();
      await runtime.conversations.sendChatMessage(
        conversation.id,
        text: '新建课程安排表',
      );
      final assistant = runtime.conversations.messagesFor(conversation.id).last;
      final proposal = assistant.tableActions.single;
      expect(proposal.status, TableChatActionStatus.pendingConfirmation);
      expect(
        runtime.tables.tables.any((table) => table.title == '课程安排'),
        isFalse,
      );

      await runtime.conversations.confirmTableStructureAction(proposal.id);
      expect(
        runtime.tables.tables.any((table) => table.title == '课程安排'),
        isTrue,
      );
      expect(
        runtime.conversations
            .messagesFor(conversation.id)
            .last
            .tableActions
            .single
            .status,
        TableChatActionStatus.applied,
      );
    },
  );

  test('injected legacy result tool cannot bypass table mode', () async {
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(modelKey: 'legacy-tool-denial'),
      modelClient: ModelClient(
        client: MockClient.streaming(
          (request, body) async => _stream({
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_legacy_create',
                      'function': {
                        'name': 'create_result',
                        'arguments': jsonEncode({
                          'type': 'knowledge',
                          'title': '旧工具写入',
                          'body': '不得写入旧成果库',
                          'confidence': 1,
                          'sensitive': false,
                        }),
                      },
                    },
                  ],
                },
              },
            ],
          }, finish: 'tool_calls'),
        ),
      ),
    );
    addTearDown(runtime.shutdown);
    final conversation = await runtime.conversations.createConversation();
    await runtime.conversations.sendChatMessage(
      conversation.id,
      text: '测试旧工具拒绝',
    );
    expect(runtime.results.documents, isEmpty);
    expect(runtime.tables.entries, isEmpty);
    expect(
      runtime.conversations.messagesFor(conversation.id).last.actions,
      isEmpty,
    );
    expect(
      runtime.conversations.messagesFor(conversation.id).last.tableActions,
      isEmpty,
    );
  });
}

http.StreamedResponse _stream(Map<String, dynamic> event, {String? finish}) {
  final choices = (event['choices'] as List)
      .map((choice) => Map<String, dynamic>.from(choice as Map))
      .toList();
  if (finish != null) choices.first['finish_reason'] = finish;
  return http.StreamedResponse(
    Stream.fromIterable([
      utf8.encode('data: ${jsonEncode({...event, 'choices': choices})}\n\n'),
      utf8.encode('data: [DONE]\n\n'),
    ]),
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}
