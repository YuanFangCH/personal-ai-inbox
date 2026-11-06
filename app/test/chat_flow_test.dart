import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

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

import 'support/test_app_host.dart';

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

  test('missing sensitive flag is rejected before auto-record', () async {
    final harness = await _ChatHarness.create(
      toolPayload: {
        'type': 'knowledge',
        'title': '不得自动创建',
        'body': '测试缺少安全字段',
        'confidence': 0.99,
      },
    );
    final conversationId = (await harness.controller.createConversation()).id;

    await harness.controller.sendChatMessage(conversationId, text: '记住测试');

    expect(harness.controller.documents, isEmpty);
    expect(
      harness.controller.messagesFor(conversationId).last.actions.single.status,
      AutoRecordStatus.skipped,
    );
    expect(harness.controller.reviewCaptures, isEmpty);
    harness.controller.dispose();
  });

  test('an out-of-range confidence cannot auto-record', () async {
    final harness = await _ChatHarness.create(
      toolPayload: {
        'type': 'knowledge',
        'title': '越界置信度',
        'body': '不应被视为高置信',
        'confidence': 1.2,
        'sensitive': false,
      },
    );
    final conversationId = (await harness.controller.createConversation()).id;

    await harness.controller.sendChatMessage(conversationId, text: '记住测试');

    expect(harness.controller.documents, isEmpty);
    expect(
      harness.controller.messagesFor(conversationId).last.actions.single.status,
      AutoRecordStatus.skipped,
    );
    harness.controller.dispose();
  });

  test(
    'EOF without DONE preserves the reply and never runs auto-record',
    () async {
      final harness = await _ChatHarness.create(
        toolPayload: {
          'type': 'knowledge',
          'title': 'EOF 不可创建',
          'body': '响应未完整',
          'confidence': 0.99,
          'sensitive': false,
        },
        omitDoneOnFirstRequest: true,
      );
      final conversationId = (await harness.controller.createConversation()).id;

      await harness.controller.sendChatMessage(conversationId, text: '记住这条');

      expect(harness.controller.documents, isEmpty);
      expect(
        harness.controller.messagesFor(conversationId).last.status,
        ChatMessageStatus.failed,
      );
      harness.controller.dispose();
    },
  );

  test(
    'retry keeps the original user and failed reply without duplicating input',
    () async {
      final harness = await _ChatHarness.create(
        toolPayload: null,
        omitDoneOnFirstRequest: true,
      );
      final conversationId = (await harness.controller.createConversation()).id;
      await harness.controller.sendChatMessage(
        conversationId,
        text: '保留这条用户消息',
      );
      final failed = harness.controller.messagesFor(conversationId).last;

      await harness.controller.retryAssistantMessage(failed.id);

      final messages = harness.controller.messagesFor(conversationId);
      expect(messages.where((message) => message.isUser), hasLength(1));
      expect(
        messages.where((message) => message.id == failed.id),
        hasLength(1),
      );
      expect(messages.last.status, ChatMessageStatus.complete);
      final secondRequest = jsonEncode(harness.requests.last['messages']);
      expect(secondRequest, contains('保留这条用户消息'));
      expect(secondRequest.split('保留这条用户消息'), hasLength(2));
      harness.controller.dispose();
    },
  );

  test(
    'stop cancels the active stream and preserves an interrupted reply',
    () async {
      final harness = await _ChatHarness.create(
        toolPayload: null,
        holdResponseOpen: true,
      );
      final conversationId = (await harness.controller.createConversation()).id;
      final sending = harness.controller.sendChatMessage(
        conversationId,
        text: '发送后手动停止',
      );
      for (
        var attempt = 0;
        attempt < 50 && !harness.controller.isChatGenerating;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(harness.controller.isChatGenerating, isTrue);

      await harness.controller.cancelChatGeneration();
      await sending;

      expect(harness.controller.isChatGenerating, isFalse);
      expect(
        harness.controller.messagesFor(conversationId).last.status,
        ChatMessageStatus.interrupted,
      );
      harness.controller.dispose();
    },
  );

  test(
    'stop after first SSE chunk cancels HTTP body and allows follow-up',
    () async {
      final responseCancelled = Completer<void>();
      final response = StreamController<List<int>>(
        onCancel: () {
          if (!responseCancelled.isCompleted) responseCancelled.complete();
        },
      );
      final harness = await _ChatHarness.create(
        toolPayload: null,
        firstResponseStream: response.stream,
      );
      final conversationId = (await harness.controller.createConversation()).id;
      final firstSend = harness.controller.sendChatMessage(
        conversationId,
        text: '停止后流应取消',
      );
      await _waitUntil(() => harness.requests.isNotEmpty);
      response.add(
        utf8.encode('data: {"choices":[{"delta":{"content":"首段"}}]}\n\n'),
      );
      await _waitUntil(
        () =>
            harness.controller.messagesFor(conversationId).last.content == '首段',
      );

      final stopClock = Stopwatch()..start();
      await harness.controller.cancelChatGeneration();
      stopClock.stop();
      expect(stopClock.elapsed, lessThan(const Duration(seconds: 1)));
      await firstSend.timeout(const Duration(seconds: 2));

      await responseCancelled.future.timeout(const Duration(seconds: 1));
      expect(
        harness.controller.messagesFor(conversationId).last.status,
        ChatMessageStatus.interrupted,
      );
      response.add(
        utf8.encode('data: {"choices":[{"delta":{"content":"迟到旧数据"}}]}\n\n'),
      );
      await harness.controller.sendChatMessage(conversationId, text: '再问一轮');
      final messages = harness.controller.messagesFor(conversationId);
      expect(messages.last.status, ChatMessageStatus.complete);
      expect(messages.last.content, '已记录');
      expect(messages[messages.length - 2].content, '再问一轮');
      expect(messages.firstWhere((message) => !message.isUser).content, '首段');
      expect(harness.requests, hasLength(2));
      await response.close();
      harness.controller.dispose();
    },
  );

  test('completion wins a concurrent stop without leaking callbacks into next turn', () async {
    final generationReachedResponseReady = Completer<void>();
    final releaseResponseReady = Completer<void>();
    final store = _ResponseReadyGateStore(
      reached: generationReachedResponseReady,
      release: releaseResponseReady,
    );
    final responseCancelled = Completer<void>();
    final response = StreamController<List<int>>(
      onCancel: () {
        if (!responseCancelled.isCompleted) responseCancelled.complete();
      },
    );
    final harness = await _ChatHarness.create(
      toolPayload: null,
      conversationStore: store,
      firstResponseStream: response.stream,
    );
    final conversationId = (await harness.controller.createConversation()).id;
    final firstSend = harness.controller.sendChatMessage(
      conversationId,
      text: '第一轮问题',
    );
    for (
      var attempt = 0;
      attempt < 100 && harness.requests.isEmpty;
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(harness.requests, hasLength(1));
    response.add(
      utf8.encode('data: {"choices":[{"delta":{"content":"第一轮已完成"}}]}\n\n'),
    );
    for (
      var attempt = 0;
      attempt < 100 &&
          harness.controller.messagesFor(conversationId).last.content !=
              '第一轮已完成';
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final firstAssistantId = harness.controller
        .messagesFor(conversationId)
        .last
        .id;
    expect(
      harness.controller.messagesFor(conversationId).last.content,
      '第一轮已完成',
    );
    response.add(
      utf8.encode(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call_stop_race',
                    'function': {
                      'name': 'create_result',
                      'arguments': jsonEncode({'type': 'knowledge', 'title': '停止后不得执行', 'body': '终止与工具提交竞争', 'confidence': 0.99, 'sensitive': false}),
                    },
                  },
                ],
              },
            },
          ],
        })}\n\n',
      ),
    );

    response.add(utf8.encode('data: [DONE]\n\n'));
    await generationReachedResponseReady.future.timeout(
      const Duration(seconds: 2),
    );
    final stopping = harness.controller.cancelChatGeneration();
    var stopFinished = false;
    unawaited(stopping.then((_) => stopFinished = true));
    await Future<void>.delayed(Duration.zero);
    expect(stopFinished, isFalse);
    releaseResponseReady.complete();
    await Future.wait([firstSend, stopping])
        .timeout(const Duration(seconds: 2));
    await responseCancelled.future.timeout(const Duration(seconds: 2));
    response.add(
      utf8.encode('data: {"choices":[{"delta":{"content":"旧回调不得追加"}}]}\n\n'),
    );
    await response.close();

    final firstAssistant = harness.controller
        .messagesFor(conversationId)
        .singleWhere((message) => message.id == firstAssistantId);
    final firstGeneration = await harness.chatRepository.findGeneration(
      firstAssistantId,
    );
    expect(firstAssistant.status, ChatMessageStatus.complete);
    expect(firstAssistant.content, '第一轮已完成');
    expect(firstGeneration?.status, GenerationStatus.completed);
    expect(harness.controller.documents, isEmpty);
    expect(
      firstGeneration!.toolCalls.single['completed_receipt_json'],
      contains('cancelled_before_dispatch'),
    );

    expect(harness.controller.documents, isEmpty);
    await harness.controller.sendChatMessage(conversationId, text: '第二轮问题');
    final messages = harness.controller.messagesFor(conversationId);
    final secondAssistant = messages.last;
    expect(secondAssistant.role, ChatRole.assistant);
    expect(secondAssistant.id, isNot(firstAssistantId));
    expect(secondAssistant.status, ChatMessageStatus.complete);
    expect(secondAssistant.content, '已记录');
    expect(
      harness.controller
          .messagesFor(conversationId)
          .singleWhere((message) => message.id == firstAssistantId)
          .content,
      '第一轮已完成',
    );
    expect(
      (await harness.conversationStore.findGeneration(firstAssistantId))
          ?.status,
      GenerationStatus.completed,
    );
    expect(harness.requests, hasLength(2));
    harness.controller.dispose();
  });

  test(
    'closed image egress omits historical image bytes but keeps local image',
    () async {
      final harness = await _ChatHarness.create(
        toolPayload: null,
        responseText: '只处理文字',
        allowImageEgress: false,
      );
      final conversationId = (await harness.controller.createConversation()).id;

      await harness.controller.sendChatMessage(
        conversationId,
        text: '只把文字发出',
        attachments: [
          ChatAttachmentInput(
            bytes: Uint8List.fromList([1, 2, 3, 4]),
            fileName: 'local.png',
            mimeType: 'image/png',
          ),
        ],
      );

      expect(jsonEncode(harness.requests.last), contains('只把文字发出'));
      expect(jsonEncode(harness.requests.last), isNot(contains('data:image/')));
      expect(
        harness.controller.messagesFor(conversationId).first.attachments,
        hasLength(1),
      );
      harness.controller.dispose();
    },
  );

  test('image-only message stays local when image egress is closed', () async {
    final harness = await _ChatHarness.create(
      toolPayload: null,
      allowImageEgress: false,
    );
    final conversationId = (await harness.controller.createConversation()).id;

    await harness.controller.sendChatMessage(
      conversationId,
      attachments: [
        ChatAttachmentInput(
          bytes: Uint8List.fromList([5, 6, 7, 8]),
          fileName: 'private.png',
          mimeType: 'image/png',
        ),
      ],
    );

    expect(harness.requests, isEmpty);
    final messages = harness.controller.messagesFor(conversationId);
    expect(messages.first.attachments, hasLength(1));
    expect(messages.last.error, contains('出网已关闭'));
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
  const _ChatHarness({
    required this.controller,
    required this.requests,
    required this.chatRepository,
    required this.conversationStore,
    required this.vault,
  });

  final TestAppHost controller;
  final List<Map<String, dynamic>> requests;
  final ChatRepository chatRepository;
  final MemoryConversationStore conversationStore;
  final MemoryVaultStore vault;

  static Future<_ChatHarness> create({
    required Map<String, dynamic>? toolPayload,
    String responseText = '已记录',
    bool allowImageEgress = true,
    bool omitDoneOnFirstRequest = false,
    bool holdResponseOpen = false,
    MemoryConversationStore? conversationStore,
    MemoryVaultStore? vaultStore,
    Stream<List<int>>? firstResponseStream,
  }) async {
    final requests = <Map<String, dynamic>>[];
    final model = ModelClient(
      client: MockClient.streaming((request, bodyStream) async {
        requests.add(
          jsonDecode(await bodyStream.bytesToString()) as Map<String, dynamic>,
        );
        if (requests.length == 1 && firstResponseStream != null) {
          return http.StreamedResponse(firstResponseStream, 200);
        }
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
          if (!omitDoneOnFirstRequest || requests.length > 1)
            'data: [DONE]\n\n',
        ];
        if (holdResponseOpen) {
          final stream = StreamController<List<int>>();
          for (final event in events.where(
            (value) => value != 'data: [DONE]\n\n',
          )) {
            stream.add(utf8.encode(event));
          }
          return http.StreamedResponse(stream.stream, 200);
        }
        return http.StreamedResponse(
          Stream.fromIterable(events.map(utf8.encode)),
          200,
        );
      }),
    );

    final vault = vaultStore ?? MemoryVaultStore();
    final index = MemoryIndexDatabase();
    await index.open();
    final settings = FakeSettingsService(modelKey: 'test-key');
    if (!allowImageEgress) {
      await settings.saveGeneral(allowImageEgress: false);
    }
    final repository = ResultRepository(
      vault: vault,
      index: index,
      deviceId: 'test-device',
    );
    final resolvedConversationStore =
        conversationStore ?? MemoryConversationStore();
    final chatRepository = ChatRepository(
      store: resolvedConversationStore,
      attachments: MemoryAttachmentStore(),
    );
    final controller = TestAppHost(
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
    return _ChatHarness(
      controller: controller,
      requests: requests,
      chatRepository: chatRepository,
      conversationStore: resolvedConversationStore,
      vault: vault,
    );
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 200 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}

class _ResponseReadyGateStore extends MemoryConversationStore {
  _ResponseReadyGateStore({required this.reached, required this.release});

  final Completer<void> reached;
  final Completer<void> release;

  @override
  Future<void> upsertGeneration(GenerationRun generation) async {
    if (generation.status == GenerationStatus.responseReady &&
        !reached.isCompleted) {
      reached.complete();
      await release.future;
    }
    await super.upsertGeneration(generation);
  }
}
