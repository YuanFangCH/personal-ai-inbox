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
    'generating conversation accepts steering while stop stays independent',
    (tester) async {
      final firstResponse = StreamController<List<int>>();
      var requestCount = 0;
      final index = MemoryIndexDatabase();
      await index.open();
      final settings = FakeSettingsService(
        deviceId: 'steering-ui',
        modelKey: 'test-key',
      );
      final repository = ResultRepository(
        vault: MemoryVaultStore(),
        index: index,
        deviceId: 'steering-ui',
      );
      await repository.initialize();
      final chats = ChatRepository(
        store: MemoryConversationStore(),
        attachments: MemoryAttachmentStore(),
      );
      final modelClient = ModelClient(
        client: MockClient.streaming((request, body) async {
          requestCount++;
          if (requestCount == 1) {
            return http.StreamedResponse(
              firstResponse.stream,
              200,
              headers: {'content-type': 'text/event-stream'},
            );
          }
          return _streamText('补充已处理');
        }),
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
          deviceId: 'steering-ui',
        ),
        chatRepository: chats,
        chatService: ChatService(
          settings: settings,
          repository: chats,
          modelClient: modelClient,
        ),
      );
      await controller.initialize();
      final runtime = controller.runtime;
      addTearDown(() async {
        try {
          await runtime.conversations.cancelGeneration().timeout(
            const Duration(seconds: 2),
          );
        } on Object {
          // Best-effort teardown for a deliberately open SSE response.
        }
        if (!firstResponse.isClosed) await firstResponse.close();
        controller.dispose();
      });

      await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
      await _pumpUntil(
        tester,
        () => find.byKey(const Key('nav_inbox')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('nav_inbox')));
      await _pumpUntil(
        tester,
        () => find.byKey(const Key('chat_input')).evaluate().isNotEmpty,
      );

      await tester.enterText(find.byKey(const Key('chat_input')), '开始长任务');
      final inputController = tester
          .widget<TextField>(find.byKey(const Key('chat_input')))
          .controller!;
      inputController.value = const TextEditingValue(
        text: '开始长任务',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('chat_send')));
      await _pumpUntil(
        tester,
        () =>
            runtime.conversations.isChatGenerating &&
            runtime.conversations.conversations.isNotEmpty,
      );
      expect(inputController.text, isEmpty);
      final conversation = runtime.conversations.conversations.single;
      expect(find.byKey(const Key('chat_stop')), findsOneWidget);
      expect(find.byKey(const Key('chat_send')), findsOneWidget);
      expect(
        tester.widget<IconButton>(find.byKey(const Key('chat_stop'))).onPressed,
        isNotNull,
      );

      await tester.enterText(find.byKey(const Key('chat_input')), '补充：只看周六');
      await tester.pump();
      expect(
        tester.widget<IconButton>(find.byKey(const Key('chat_send'))).onPressed,
        isNotNull,
      );
      final send = find.byKey(const Key('chat_send'));
      await tester.tap(send);
      await tester.tap(send);
      await _pumpUntil(
        tester,
        () =>
            runtime.conversations
                .messagesFor(conversation.id)
                .where(
                  (message) =>
                      message.role == ChatRole.user &&
                      message.content.contains('只看周六'),
                )
                .length ==
            1,
      );

      expect(
        runtime.conversations.isConversationSteering(conversation.id),
        isTrue,
      );
      expect(
        runtime.conversations
            .messagesFor(conversation.id)
            .where((message) => message.role == ChatRole.user)
            .length,
        2,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('chat_input')))
            .controller!
            .text,
        isEmpty,
      );

      await tester.tap(find.byKey(const Key('chat_stop')));
      await _pumpUntil(
        tester,
        () =>
            !runtime.conversations.isChatGenerating &&
            find.byKey(const Key('chat_stop')).evaluate().isEmpty,
      );
      firstResponse.add(utf8.encode('data: [DONE]\n\n'));
      await firstResponse.close();
      await tester.pump();

      expect(find.byKey(const Key('chat_stop')), findsNothing);
      expect(find.byKey(const Key('chat_send')), findsOneWidget);
      expect(tester.takeException(), isNull);
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

http.StreamedResponse _streamText(String text) => http.StreamedResponse(
  Stream.fromIterable([
    utf8.encode(
      'data: ${jsonEncode({
        'choices': [
          {
            'delta': {'content': text},
          },
        ],
      })}\n\n',
    ),
    utf8.encode('data: [DONE]\n\n'),
  ]),
  200,
  headers: {'content-type': 'text/event-stream'},
);
