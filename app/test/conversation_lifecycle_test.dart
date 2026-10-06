import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/data/share_payload.dart';
import 'package:personal_ai_inbox/data/sync_engine.dart';
import 'package:personal_ai_inbox/data/sync_provider.dart';
import 'package:personal_ai_inbox/services/app_controller.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';
import 'package:personal_ai_inbox/services/chat_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'test_support.dart';

void main() {
  test(
    'startup removes empty conversations and keeps conversations with data',
    () async {
      final store = MemoryConversationStore();
      await store.open();
      final now = DateTime(2026, 10, 6, 9);
      final empty = Conversation(
        id: 'cnv_empty',
        title: '空会话',
        createdAt: now,
        updatedAt: now,
        autoTitle: true,
      );
      final failed = Conversation(
        id: 'cnv_failed',
        title: '失败会话',
        createdAt: now,
        updatedAt: now,
        autoTitle: false,
      );
      await store.upsertConversation(empty);
      await store.upsertConversation(failed);
      await store.upsertMessage(
        ChatMessage(
          id: 'msg_failed',
          conversationId: failed.id,
          role: ChatRole.assistant,
          content: '',
          status: ChatMessageStatus.failed,
          createdAt: now,
          updatedAt: now,
          error: '测试失败',
        ),
      );

      final harness = await _LifecycleHarness.create(store: store);
      expect(harness.controller.conversations.map((item) => item.id), [
        failed.id,
      ]);
      harness.controller.dispose();
    },
  );

  testWidgets('the first sent message creates exactly one conversation', (
    tester,
  ) async {
    final harness = await _LifecycleHarness.create();
    await tester.pumpWidget(PersonalAiInboxApp(controller: harness.controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav_inbox')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inbox_new_conversation')));
    await tester.pumpAndSettle();

    expect(harness.controller.conversations, isEmpty);
    await tester.enterText(find.byKey(const Key('chat_input')), '明天下午三点和客户开会');
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pumpAndSettle();

    expect(harness.controller.conversations, hasLength(1));
    final conversation = harness.controller.conversations.single;
    expect(conversation.title, '明天下午三点和客户开会');
    expect(harness.controller.messagesFor(conversation.id), hasLength(2));

    await tester.pumpWidget(PersonalAiInboxApp(controller: harness.controller));
    await tester.pumpAndSettle();
    expect(harness.controller.conversations, hasLength(1));
    harness.controller.dispose();
  });

  test(
    'shared text creates a conversation and empty payloads do not',
    () async {
      final harness = await _LifecycleHarness.create();
      await harness.controller.handleSharedPayload(
        const SharedCapturePayload(),
      );
      expect(harness.controller.conversations, isEmpty);

      await harness.controller.handleSharedPayload(
        const SharedCapturePayload(text: '来自系统分享'),
      );
      await _waitFor(
        () =>
            harness.controller.conversations.isNotEmpty &&
            harness.controller
                    .messagesFor(harness.controller.conversations.single.id)
                    .length ==
                2,
      );

      final conversation = harness.controller.conversations.single;
      expect(conversation.title, '来自系统分享');
      expect(
        harness.controller.consumePendingConversationId(),
        conversation.id,
      );
      harness.controller.dispose();
    },
  );
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition was not met before timeout');
}

class _LifecycleHarness {
  const _LifecycleHarness({required this.controller});

  final AppController controller;

  static Future<_LifecycleHarness> create({
    MemoryConversationStore? store,
  }) async {
    final model = ModelClient(
      client: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': '已记录'},
                  },
                ],
              })}\n\n',
            ),
            utf8.encode('data: [DONE]\n\n'),
          ]),
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
      store: store ?? MemoryConversationStore(),
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
    return _LifecycleHarness(controller: controller);
  }
}
