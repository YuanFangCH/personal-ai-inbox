import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/data/sync_engine.dart';
import 'package:personal_ai_inbox/data/sync_provider.dart';
import 'package:personal_ai_inbox/services/app_controller.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';
import 'package:personal_ai_inbox/services/chat_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'test_support.dart';

void main() {
  test('chat creates a high-confidence result and can undo it', () async {
    final due = DateTime.now().add(const Duration(days: 2));
    final harness = await _ChatHarness.create(
      toolPayload: {
        'type': 'todo',
        'title': '提交项目材料',
        'body': '在周五下午三点前提交。',
        'confidence': 0.94,
        'sensitive': false,
        'due': due.toIso8601String(),
      },
    );
    final conversationId = (await harness.controller.createConversation()).id;

    await harness.controller.sendChatMessage(
      conversationId,
      text: '记住周五下午三点提交项目材料',
    );

    expect(harness.controller.documents, hasLength(1));
    final message = harness.controller.messagesFor(conversationId).last;
    expect(message.content, '已记录');
    expect(message.actions.single.status, AutoRecordStatus.created);
    expect(message.actions.single.canUndo, true);

    await harness.controller.undoAutoRecord(message.actions.single.id);
    expect(harness.controller.documents, isEmpty);
    expect(
      harness.controller.messagesFor(conversationId).last.actions.single.status,
      AutoRecordStatus.undone,
    );
    harness.controller.dispose();
  });

  test('low-confidence tool calls fall back to review capture', () async {
    final harness = await _ChatHarness.create(
      toolPayload: {
        'type': 'event',
        'title': '可能存在的会议',
        'body': '日期不够明确。',
        'confidence': 0.4,
        'sensitive': false,
      },
    );
    final conversationId = (await harness.controller.createConversation()).id;

    await harness.controller.sendChatMessage(conversationId, text: '下周找时间开会');

    expect(harness.controller.documents, isEmpty);
    expect(harness.controller.reviewCaptures, hasLength(1));
    expect(
      harness.controller.messagesFor(conversationId).last.actions.single.status,
      AutoRecordStatus.review,
    );
    harness.controller.dispose();
  });

  test('context only contains the selected conversation', () async {
    final harness = await _ChatHarness.create(
      toolPayload: null,
      responseText: '只看到当前会话',
    );
    final first = (await harness.controller.createConversation()).id;
    await harness.controller.sendChatMessage(first, text: '第一条独有内容');
    final second = (await harness.controller.createConversation()).id;
    await harness.controller.sendChatMessage(second, text: '第二条独有内容');

    final secondRequest = harness.requests.last;
    final serialized = jsonEncode(secondRequest);
    expect(serialized, contains('第二条独有内容'));
    expect(serialized, isNot(contains('第一条独有内容')));
    harness.controller.dispose();
  });
}

class _ChatHarness {
  const _ChatHarness({required this.controller, required this.requests});

  final AppController controller;
  final List<Map<String, dynamic>> requests;

  static Future<_ChatHarness> create({
    required Map<String, dynamic>? toolPayload,
    String responseText = '已记录',
  }) async {
    final requests = <Map<String, dynamic>>[];
    final model = ModelClient(
      client: MockClient.streaming((request, bodyStream) async {
        requests.add(
          jsonDecode(await bodyStream.bytesToString()) as Map<String, dynamic>,
        );
        final events = <String>[
          'data: {"choices":[{"delta":{"content":${jsonEncode(responseText)}}}]}\n\n',
          if (toolPayload != null)
            'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_test',
                        'function': {'name': 'create_result', 'arguments': jsonEncode(toolPayload)},
                      },
                    ],
                  },
                },
              ],
            })}\n\n',
          'data: [DONE]\n\n',
        ];
        return http.StreamedResponse(
          Stream.fromIterable(events.map(utf8.encode)),
          200,
        );
      }),
    );

    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    await index.open();
    final settings = FakeSettingsService(modelKey: 'test-key');
    final repository = ResultRepository(
      vault: vault,
      index: index,
      deviceId: 'test-device',
    );
    final chatRepository = ChatRepository(
      store: MemoryConversationStore(),
      attachments: MemoryAttachmentStore(),
    );
    final controller = AppController(
      repository: repository,
      indexDatabase: index,
      captureService: CaptureService(
        settings: settings,
        parser: const DeterministicParser(),
      ),
      settingsService: settings,
      syncEngine: SyncEngine(
        repository: repository,
        provider: MemorySyncProvider(),
        deviceId: 'test-device',
      ),
      chatRepository: chatRepository,
      chatService: ChatService(
        settings: settings,
        repository: chatRepository,
        modelClient: model,
      ),
    );
    await controller.initialize();
    return _ChatHarness(controller: controller, requests: requests);
  }
}
