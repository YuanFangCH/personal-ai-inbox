import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/ai_policy.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/data/table_repository.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';
import 'package:personal_ai_inbox/modules/tables/table_library.dart';
import 'package:personal_ai_inbox/services/chat_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'test_support.dart';

void main() {
  test('cancelling ChatService reply cancels the HTTP response body', () async {
    final chats = ChatRepository(
      store: MemoryConversationStore(),
      attachments: MemoryAttachmentStore(),
    );
    await chats.initialize();
    final conversation = await chats.createConversation();
    await chats.saveMessage(
      ChatMessage(
        id: 'msg_cancel_propagation_user',
        conversationId: conversation.id,
        role: ChatRole.user,
        content: '停止测试',
        status: ChatMessageStatus.complete,
        createdAt: conversation.createdAt,
        updatedAt: conversation.updatedAt,
      ),
    );
    final bodyCancelled = Completer<void>();
    final body = StreamController<List<int>>(
      onCancel: () {
        if (!bodyCancelled.isCompleted) bodyCancelled.complete();
      },
    );
    final service = ChatService(
      settings: FakeSettingsService(modelKey: 'cancel-propagation'),
      repository: chats,
      modelClient: ModelClient(
        client: MockClient.streaming((request, requestBody) async {
          await requestBody.bytesToString();
          return http.StreamedResponse(body.stream, 200);
        }),
      ),
    );
    final reply = await service.streamReply(conversationId: conversation.id);
    final firstDelta = Completer<void>();
    final subscription = reply.listen((delta) {
      if (delta.content.isNotEmpty && !firstDelta.isCompleted) {
        firstDelta.complete();
      }
    });
    body.add(utf8.encode('data: {"choices":[{"delta":{"content":"首段"}}]}\n\n'));
    await firstDelta.future.timeout(const Duration(seconds: 1));
    await subscription.cancel();

    await bodyCancelled.future.timeout(const Duration(seconds: 1));
    await body.close();
  });

  test(
    'cancel after tool intent yield fences local executor dispatch',
    () async {
      final chats = ChatRepository(
        store: MemoryConversationStore(),
        attachments: MemoryAttachmentStore(),
      );
      await chats.initialize();
      final conversation = await chats.createConversation(
        aiPolicy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
      );
      await chats.saveMessage(
        ChatMessage(
          id: 'msg_tool_cancel_race',
          conversationId: conversation.id,
          role: ChatRole.user,
          content: '创建一张表',
          status: ChatMessageStatus.complete,
          createdAt: conversation.createdAt,
          updatedAt: conversation.updatedAt,
        ),
      );
      var cancelled = false;
      var executorCalls = 0;
      final service = ChatService(
        settings: FakeSettingsService(modelKey: 'cancel-race'),
        repository: chats,
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            await body.bytesToString();
            return _stream({
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_cancel_race',
                        'function': {
                          'name': 'table_propose',
                          'arguments': jsonEncode({
                            'operation': 'create',
                            'payload': {'title': '不应创建'},
                            'idempotency_key': 'cancel-race-create',
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
        writeToolExecutor: (_) async {
          executorCalls++;
          return ChatWriteToolReceipt.succeeded(operationId: 'act_cancel_race');
        },
      );

      final iterator = StreamIterator(
        await service.streamReply(
          conversationId: conversation.id,
          isCancelled: () => cancelled,
        ),
      );
      while (await iterator.moveNext()) {
        if (iterator.current.toolCallIndex != null) {
          cancelled = true;
        }
      }

      expect(cancelled, isTrue);
      expect(executorCalls, 0);
    },
  );

  test(
    'table mode searches indexed table content and offers no legacy writes',
    () async {
      final chats = ChatRepository(
        store: MemoryConversationStore(),
        attachments: MemoryAttachmentStore(),
      );
      await chats.initialize();
      final conversation = await chats.createConversation(
        createdAt: DateTime(2026, 10, 30),
      );
      await chats.saveMessage(
        ChatMessage(
          id: 'msg_table_question',
          conversationId: conversation.id,
          role: ChatRole.user,
          content: '期中考试在哪里？',
          status: ChatMessageStatus.complete,
          createdAt: conversation.createdAt,
          updatedAt: conversation.updatedAt,
        ),
      );
      final results = ResultLibrary(
        repository: ResultRepository(
          vault: MemoryVaultStore(),
          index: MemoryIndexDatabase(),
          deviceId: 'chat-table-test',
        ),
      );
      await results.initialize();
      final tables = TableLibrary(
        repository: TableRepository(
          vault: MemoryVaultStore(),
          index: MemoryIndexDatabase(),
        ),
      );
      await tables.initialize();
      final examTable = await tables.createTable(title: '考试表');
      final now = DateTime(2026, 11, 2, 14);
      await tables.createEntry(
        TableEntryDocument(
          id: 'sc_midterm_a',
          type: TableContentType.schedule,
          tableId: examTable.id,
          title: '期中考试',
          revision: 1,
          createdAt: now,
          updatedAt: now,
          body: '第三教学楼 101 室',
          start: now,
        ),
      );
      await tables.createEntry(
        TableEntryDocument(
          id: 'sc_midterm_z',
          type: TableContentType.schedule,
          tableId: examTable.id,
          title: '期中考试',
          revision: 1,
          createdAt: now,
          updatedAt: now,
          body: '第四教学楼 202 室',
          start: now,
        ),
      );
      final requests = <Map<String, dynamic>>[];
      final service = ChatService(
        settings: FakeSettingsService(modelKey: 'test-key'),
        repository: chats,
        results: results,
        tables: tables,
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            final payload =
                jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            requests.add(payload);
            if (requests.length == 1) {
              return _stream({
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_table_search',
                          'function': {
                            'name': 'content_search',
                            'arguments': jsonEncode({
                              'query': '期中考试',
                              'table_ids': [examTable.id],
                              'types': ['schedule'],
                              'offset': 1,
                              'limit': 1,
                            }),
                          },
                        },
                      ],
                    },
                  },
                ],
              }, finish: 'tool_calls');
            }
            if (requests.length == 2) {
              return _stream({
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_content_read',
                          'function': {
                            'name': 'content_read',
                            'arguments': jsonEncode({
                              'id': 'sc_midterm_z',
                              'if_revision': 1,
                              'offset': 2,
                              'length': 3,
                            }),
                          },
                        },
                      ],
                    },
                  },
                ],
              }, finish: 'tool_calls');
            }
            return _stream({
              'choices': [
                {
                  'delta': {'content': '在第四教学楼 202 室。'},
                },
              ],
            });
          }),
        ),
      );

      final deltas = await (await service.streamReply(
        conversationId: conversation.id,
      )).toList();
      final tools = requests.first['tools'] as List;
      final toolNames = tools
          .map((entry) => (entry as Map)['function']['name'])
          .toSet();
      expect(
        toolNames,
        containsAll([
          'table_list',
          'table_search',
          'content_search',
          'content_read',
        ]),
      );
      expect(
        toolNames.every(
          (name) =>
              name is String && RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name),
        ),
        isTrue,
      );
      expect(toolNames, isNot(contains('create_result')));
      expect(toolNames, isNot(contains('search_results')));
      final scheduleChangeTool = tools.cast<Map>().singleWhere(
        (entry) => entry['function']['name'] == 'schedule_change',
      );
      expect(
        scheduleChangeTool['function']['description'],
        contains('原通知发生时间'),
      );
      final contentSearchTool = tools.cast<Map>().singleWhere(
        (entry) => entry['function']['name'] == 'content_search',
      );
      final contentSearchProperties =
          contentSearchTool['function']['parameters']['properties'] as Map;
      expect(contentSearchProperties, contains('offset'));
      expect(contentSearchProperties, contains('cursor'));
      final contentReadTool = tools.cast<Map>().singleWhere(
        (entry) => entry['function']['name'] == 'content_read',
      );
      final contentReadProperties =
          contentReadTool['function']['parameters']['properties'] as Map;
      expect(contentReadProperties, contains('offset'));
      expect(contentReadProperties, contains('length'));
      expect(contentReadProperties, contains('cursor'));
      final searchToolMessage = (requests[1]['messages'] as List)
          .cast<Map>()
          .singleWhere((message) => message['role'] == 'tool');
      expect(searchToolMessage['content'], contains('"offset":1'));
      expect(searchToolMessage['content'], contains('sc_midterm_z'));
      expect(searchToolMessage['content'], contains('第四教学楼 202 室'));
      final detailToolMessage = (requests.last['messages'] as List)
          .cast<Map>()
          .where((message) => message['role'] == 'tool')
          .last;
      expect(detailToolMessage['content'], contains('"bodyOffset":2'));
      expect(detailToolMessage['content'], contains('"bodyLength":3'));
      expect(detailToolMessage['content'], contains('教学楼'));
      expect(deltas.map((delta) => delta.content).join(), '在第四教学楼 202 室。');
      expect(requests, hasLength(3));

      service.close();
      await chats.close();
      tables.dispose();
      await results.shutdown();
      results.dispose();
    },
  );

  test(
    'reads only requested history then sends bounded snippets to model',
    () async {
      final store = MemoryConversationStore();
      final chats = ChatRepository(
        store: store,
        attachments: MemoryAttachmentStore(),
      );
      await chats.initialize();
      final current = await chats.createConversation(
        createdAt: DateTime(2026, 10, 20),
      );
      final previous = await chats.createConversation(
        createdAt: DateTime(2026, 10, 18),
      );
      await chats.saveMessage(
        ChatMessage(
          id: 'msg_history_math',
          conversationId: previous.id,
          role: ChatRole.user,
          content: '数学作业在周五提交，题目范围是第三章。',
          status: ChatMessageStatus.complete,
          createdAt: previous.createdAt,
          updatedAt: previous.updatedAt,
        ),
      );
      await chats.saveMessage(
        ChatMessage(
          id: 'msg_question',
          conversationId: current.id,
          role: ChatRole.user,
          content: '上次对话里数学作业什么时候提交？',
          status: ChatMessageStatus.complete,
          createdAt: current.createdAt,
          updatedAt: current.updatedAt,
        ),
      );
      final results = ResultLibrary(
        repository: ResultRepository(
          vault: MemoryVaultStore(),
          index: MemoryIndexDatabase(),
          deviceId: 'chat-tool-test',
        ),
      );
      await results.initialize();

      final requests = <Map<String, dynamic>>[];
      final client = MockClient.streaming((request, body) async {
        final payload =
            jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
        requests.add(payload);
        if (requests.length == 1) {
          return _stream({
            'choices': [
              {
                'delta': {
                  'reasoning_content': '内部推理不得展示。',
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_history_search',
                      'type': 'function',
                      'function': {
                        'name': 'search_other_conversations',
                        'arguments': '{"query":"数学作业"}',
                      },
                    },
                  ],
                },
              },
            ],
          }, finish: 'tool_calls');
        }
        return _stream({
          'choices': [
            {
              'delta': {'content': '上次记录为周五提交。'},
            },
          ],
        });
      });
      final service = ChatService(
        settings: FakeSettingsService(modelKey: 'test-key'),
        repository: chats,
        results: results,
        modelClient: ModelClient(client: client),
      );

      final deltas = await (await service.streamReply(
        conversationId: current.id,
        thinkingEnabled: true,
      )).toList();
      expect(requests, hasLength(2));
      final firstTools = requests.first['tools'] as List;
      expect(
        firstTools.map((entry) => (entry as Map)['function']['name']),
        contains('search_other_conversations'),
      );
      final secondMessages = requests.last['messages'] as List;
      expect(requests.first['thinking'], {'type': 'enabled'});
      expect(requests.first['reasoning_effort'], 'high');
      expect(requests.last['thinking'], {'type': 'enabled'});
      final assistantToolMessage = secondMessages.cast<Map>().singleWhere(
        (message) =>
            message['role'] == 'assistant' && message['tool_calls'] != null,
      );
      expect(assistantToolMessage['reasoning_content'], '内部推理不得展示。');
      final toolMessage = secondMessages.cast<Map>().singleWhere(
        (message) => message['role'] == 'tool',
      );
      expect(toolMessage['content'], contains('数学作业在周五提交'));
      expect(toolMessage['content'], contains(previous.id));
      expect(deltas.map((delta) => delta.content).join(), '上次记录为周五提交。');
      expect(
        deltas.map((delta) => delta.reasoningContent).join(),
        isNot(contains('内部推理')),
      );
      expect(deltas.last.termination, ChatStreamTermination.completed);
      service.close();
      await chats.close();
      await results.shutdown();
      results.dispose();
    },
  );

  test(
    'closed read permission omits search tools and blocks injected calls',
    () async {
      final chats = ChatRepository(
        store: MemoryConversationStore(),
        attachments: MemoryAttachmentStore(),
      );
      await chats.initialize();
      final current = await chats.createConversation(
        aiPermissions: const AiPermissions(read: false),
        createdAt: DateTime(2026, 10, 20),
      );
      await chats.saveMessage(
        ChatMessage(
          id: 'msg_question_closed',
          conversationId: current.id,
          role: ChatRole.user,
          content: '上次对话说了什么？',
          status: ChatMessageStatus.complete,
          createdAt: current.createdAt,
          updatedAt: current.updatedAt,
        ),
      );
      final results = ResultLibrary(
        repository: ResultRepository(
          vault: MemoryVaultStore(),
          index: MemoryIndexDatabase(),
          deviceId: 'chat-tool-test',
        ),
      );
      await results.initialize();
      Map<String, dynamic>? firstRequest;
      Map<String, dynamic>? secondRequest;
      var requests = 0;
      final service = ChatService(
        settings: FakeSettingsService(modelKey: 'test-key'),
        repository: chats,
        results: results,
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            final payload =
                jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            requests++;
            if (requests == 1) {
              firstRequest = payload;
              return _stream({
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_denied',
                          'function': {
                            'name': 'search_other_conversations',
                            'arguments': '{"query":"secret"}',
                          },
                        },
                      ],
                    },
                  },
                ],
              }, finish: 'tool_calls');
            }
            secondRequest = payload;
            return _stream({
              'choices': [
                {
                  'delta': {'content': '没有读取权限，我不能查阅其他对话。'},
                },
              ],
            });
          }),
        ),
      );

      await (await service.streamReply(conversationId: current.id))
          .drain<void>();
      final tools = firstRequest!['tools'] as List;
      expect(
        tools.map((entry) => (entry as Map)['function']['name']),
        isNot(contains('search_other_conversations')),
      );
      final toolMessage = (secondRequest!['messages'] as List)
          .cast<Map>()
          .singleWhere((message) => message['role'] == 'tool');
      expect(toolMessage['content'], contains('关闭读取权限'));
      expect(toolMessage['content'], isNot(contains('secret')));
      service.close();
      await chats.close();
      await results.shutdown();
      results.dispose();
    },
  );
}

http.StreamedResponse _stream(Map<String, dynamic> event, {String? finish}) {
  final choices = (event['choices'] as List)
      .map((choice) => Map<String, dynamic>.from(choice as Map))
      .toList();
  if (finish != null) choices.first['finish_reason'] = finish;
  final payload = {...event, 'choices': choices};
  return http.StreamedResponse(
    Stream.fromIterable([
      utf8.encode('data: ${jsonEncode(payload)}\n\n'),
      utf8.encode('data: [DONE]\n\n'),
    ]),
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}
