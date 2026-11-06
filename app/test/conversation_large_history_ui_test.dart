import 'dart:async';
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
import 'package:personal_ai_inbox/data/sync_engine.dart';
import 'package:personal_ai_inbox/data/sync_provider.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';
import 'package:personal_ai_inbox/services/chat_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'test_support.dart';
import 'support/test_app_host.dart';

void main() {
  testWidgets(
    'large history remains scrollable and responsive during a long stream',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final response = StreamController<List<int>>();
      final store = MemoryConversationStore();
      await store.open();
      final now = DateTime.parse('2026-11-04T09:00:00+08:00');
      const conversationId = 'cnv_large_history';
      await store.upsertConversation(
        Conversation(
          id: conversationId,
          title: '大历史回归',
          createdAt: now,
          updatedAt: now,
          autoTitle: false,
        ),
      );
      for (var index = 0; index < 220; index++) {
        final user = index.isEven;
        await store.upsertMessage(
          ChatMessage(
            id: 'msg_history_${index.toString().padLeft(3, '0')}',
            conversationId: conversationId,
            role: user ? ChatRole.user : ChatRole.assistant,
            content: user
                ? '历史用户消息 $index'
                : '历史助手回复 $index：${List.filled(12, '较长历史内容').join('、')}',
            status: ChatMessageStatus.complete,
            createdAt: now.add(Duration(minutes: index)),
            updatedAt: now.add(Duration(minutes: index)),
          ),
        );
      }

      final index = MemoryIndexDatabase();
      await index.open();
      final settings = FakeSettingsService(
        deviceId: 'large-history-ui',
        modelKey: 'test-key',
      );
      final repository = ResultRepository(
        vault: MemoryVaultStore(),
        index: index,
        deviceId: 'large-history-ui',
      );
      await repository.initialize();
      final chats = ChatRepository(
        store: store,
        attachments: MemoryAttachmentStore(),
      );
      var requests = 0;
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
          deviceId: 'large-history-ui',
        ),
        chatRepository: chats,
        chatService: ChatService(
          settings: settings,
          repository: chats,
          modelClient: ModelClient(
            client: MockClient.streaming((request, body) async {
              requests++;
              return http.StreamedResponse(
                response.stream,
                200,
                headers: {'content-type': 'text/event-stream'},
              );
            }),
          ),
        ),
      );
      await controller.initialize();
      addTearDown(() async {
        try {
          await controller.cancelChatGeneration().timeout(
            const Duration(seconds: 2),
          );
        } on Object {
          // Best-effort cleanup for the deliberately open stream.
        }
        if (!response.isClosed) await response.close();
        controller.dispose();
      });

      await tester.pumpWidget(PersonalAiInboxApp(runtime: controller.runtime));
      await _pumpUntil(
        tester,
        () => find.byKey(const Key('nav_inbox')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('nav_inbox')));
      await _pumpUntil(
        tester,
        () =>
            find.byKey(const Key('conversation_manage')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('conversation_manage')));
      final conversationRow = find.byKey(
        const Key('conversation_$conversationId'),
      );
      await _pumpUntil(
        tester,
        () => conversationRow.hitTestable().evaluate().isNotEmpty,
      );
      await tester.tap(conversationRow);
      await _pumpUntil(
        tester,
        () =>
            controller.conversationWorkspace
                    .messagesFor(conversationId)
                    .length ==
                220 &&
            find.byKey(const Key('chat_input')).evaluate().isNotEmpty &&
            find.textContaining('历史助手回复 219').evaluate().isNotEmpty,
      );

      final visibleMessage = find.byWidgetPredicate(
        (widget) =>
            widget is KeyedSubtree &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('message_'),
      );
      expect(visibleMessage, findsWidgets);
      final messageList = find.ancestor(
        of: visibleMessage.first,
        matching: find.byType(ListView),
      );
      expect(messageList, findsOneWidget);
      final messageScrollable = find.descendant(
        of: messageList,
        matching: find.byType(Scrollable),
      );
      final scrollState = tester.state<ScrollableState>(
        messageScrollable.first,
      );
      scrollState.position.jumpTo(0);
      await tester.pump();
      final oldest = find.byKey(const ValueKey('message_msg_history_000'));
      expect(oldest, findsOneWidget);
      expect(scrollState.position.pixels, 0);

      final input = find.byKey(const Key('chat_input'));
      expect(input.hitTestable(), findsOneWidget);
      await tester.enterText(input, '基于全部历史继续整理');
      expect(tester.widget<TextField>(input).controller!.text, '基于全部历史继续整理');

      await tester.tap(find.byKey(const Key('chat_send')));
      await _pumpUntil(
        tester,
        () => controller.conversationWorkspace.isChatGenerating,
      );
      expect(requests, 1);
      expect(find.byKey(const Key('chat_stop')), findsOneWidget);

      const chunk = '这是一段用于验证长回复滚动和交互的生成文本。';
      for (var index = 0; index < 220; index++) {
        response.add(
          utf8.encode(
            'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': chunk},
                },
              ],
            })}\n\n',
          ),
        );
        if (index % 12 == 11) {
          await tester.pump(const Duration(milliseconds: 60));
        }
      }
      await tester.pump(const Duration(milliseconds: 60));

      final streamingAssistant = controller.conversationWorkspace
          .messagesFor(conversationId)
          .lastWhere(
            (message) =>
                message.role == ChatRole.assistant &&
                message.status == ChatMessageStatus.streaming,
          );
      expect(streamingAssistant.content.length, greaterThan(4000));
      expect(
        find.byKey(ValueKey('message_${streamingAssistant.id}')),
        findsOneWidget,
      );

      await tester.enterText(input, '停止前仍可输入');
      expect(tester.widget<TextField>(input).controller!.text, '停止前仍可输入');
      expect(input.hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const Key('chat_stop')));
      await _pumpUntil(
        tester,
        () =>
            !controller.conversationWorkspace.isChatGenerating &&
            find.byKey(const Key('chat_stop')).evaluate().isEmpty,
      );
      expect(tester.widget<TextField>(input).controller!.text, '停止前仍可输入');
      expect(tester.takeException(), isNull);

      response.add(utf8.encode('data: [DONE]\n\n'));
      await response.close();
      await tester.pump();
    },
  );
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('UI condition was not met before timeout.');
}
