import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';
import 'package:personal_ai_inbox/services/chat_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'test_support.dart';

void main() {
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
