import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/chat_activity.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/services/model_client.dart';
import 'package:personal_ai_inbox/ui/theme/app_design_tokens.dart';

import '../test/test_support.dart';

enum SecretaryActivityScenario { completed, stopped, failed }

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final scenario in SecretaryActivityScenario.values) {
    testWidgets('secretary activity ${scenario.name}', (tester) async {
      await runSecretaryActivityScenario(tester, scenario: scenario);
      // ignore: avoid_print
      print('ACTIVITY_CASE_RESULT|${scenario.name}|passed');
    });
  }

  testWidgets('secretary activity themes and wide layout', (tester) async {
    await _runThemeAndWideLayoutTest(tester);
    // ignore: avoid_print
    print('ACTIVITY_CASE_RESULT|theme-layout|passed');
  });
}

Future<void> runSecretaryActivityScenario(
  WidgetTester tester, {
  required SecretaryActivityScenario scenario,
}) async {
  _setViewport(tester, const Size(320, 844), textScaleFactor: 1.5);
  final conversationStore = MemoryConversationStore();
  final attachments = MemoryAttachmentStore();
  final plan = _ActivityModelPlan(scenario);
  var runtime = await _bootRuntime(
    conversationStore: conversationStore,
    attachments: attachments,
    plan: plan,
  );
  var sawRunningTools = false;
  final observedWorkspace = runtime.conversations;
  void observeActivity() {
    final active = runtime.conversations;
    for (final conversation in active.conversations) {
      for (final message in active.messagesFor(conversation.id)) {
        if (message.role == ChatRole.assistant &&
            active.liveActivityFor(message.id)?.phase ==
                ChatActivityPhase.runningTools) {
          sawRunningTools = true;
        }
      }
    }
  }

  observedWorkspace.addListener(observeActivity);

  try {
    final conversation = await runtime.conversations.createConversation();
    await runtime.conversations.openConversation(conversation.id);
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    await _openSecretary(tester);

    await tester.enterText(find.byKey(const Key('chat_input')), '检查我的表');
    await tester.tap(find.byKey(const Key('chat_send')));
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pump();
    await _pumpUntil(
      tester,
      () => plan.requestStarted(1),
      reason: 'first model request did not start',
    );
    expect(find.text('等待模型响应'), findsOneWidget);

    plan.emitReasoning();
    await _pumpUntil(
      tester,
      () => find.text('正在思考').evaluate().isNotEmpty,
      reason: 'thinking phase was not rendered',
    );

    plan.emitToolCall();
    await _pumpUntil(
      tester,
      () => plan.requestStarted(2),
      reason: 'second model request did not start after the tool receipt',
    );
    if (scenario != SecretaryActivityScenario.failed) {
      await _pumpUntil(
        tester,
        () => find.text('工具已返回 · 查看表列表').evaluate().isNotEmpty,
        reason: 'completed tool row was not reconciled',
      );
    }

    if (scenario != SecretaryActivityScenario.failed) {
      final assistant = runtime.conversations
          .messagesFor(conversation.id)
          .singleWhere((message) => message.role == ChatRole.assistant);
      expect(
        runtime.conversations.liveActivityFor(assistant.id)?.runningTools,
        isEmpty,
      );
    }
    expect(sawRunningTools, isTrue);

    switch (scenario) {
      case SecretaryActivityScenario.completed:
        plan.completeFinalReply();
        break;
      case SecretaryActivityScenario.stopped:
        await tester.tap(find.byKey(const Key('chat_stop')));
        plan.cancelSecondRequest();
        break;
      case SecretaryActivityScenario.failed:
        break;
    }

    await _pumpUntil(
      tester,
      () => !runtime.conversations.isChatGenerating,
      reason: '${scenario.name} generation did not terminate',
    );
    await tester.pumpAndSettle();
    await _showLatestMessage(tester);
    final storedAssistant = runtime.conversations
        .messagesFor(conversation.id)
        .singleWhere((message) => message.role == ChatRole.assistant);
    expect(storedAssistant.status, switch (scenario) {
      SecretaryActivityScenario.completed => ChatMessageStatus.complete,
      SecretaryActivityScenario.stopped => ChatMessageStatus.interrupted,
      SecretaryActivityScenario.failed => ChatMessageStatus.failed,
    });
    expect(storedAssistant.toolTranscript, isNotEmpty);
    expect(runtime.conversations.liveActivityFor(storedAssistant.id), isNull);

    final fold = find.textContaining('运行过程 ·');
    expect(fold, findsOneWidget);
    expect(find.text('工具已返回 · 查看表列表'), findsNothing);
    await tester.ensureVisible(fold);
    await tester.pumpAndSettle();
    await tester.tap(fold);
    await tester.pumpAndSettle();
    expect(find.text('工具已返回 · 查看表列表'), findsOneWidget);
    for (final privateMarker in _ActivityModelPlan.privateMarkers) {
      expect(find.textContaining(privateMarker), findsNothing);
    }

    if (scenario == SecretaryActivityScenario.completed) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await runtime.shutdown();
      runtime = await _bootRuntime(
        conversationStore: conversationStore,
        attachments: attachments,
        plan: plan,
      );
      await runtime.conversations.openConversation(conversation.id);
      await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
      await tester.pumpAndSettle();
      await _openSecretary(tester);
      expect(find.text('运行过程 · 1 个工具调用'), findsOneWidget);
      expect(find.text('工具已返回 · 查看表列表'), findsNothing);
    }
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    observedWorkspace.removeListener(observeActivity);
    await runtime.shutdown();
    plan.close();
  }
}

Future<void> _showLatestMessage(WidgetTester tester) async {
  tester.binding.focusManager.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final jump = find.byKey(const Key('conversation_jump_to_latest'));
  if (jump.evaluate().isNotEmpty) {
    await tester.tap(jump);
    await tester.pumpAndSettle();
  }
}

Future<void> _runThemeAndWideLayoutTest(WidgetTester tester) async {
  for (final theme in [ThemePreference.light, ThemePreference.dark]) {
    _setViewport(tester, const Size(1000, 900));
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      conversationStoreOverride: MemoryConversationStore(),
      attachmentStoreOverride: MemoryAttachmentStore(),
      settingsOverride: FakeSettingsService(
        deviceId: 'secretary-activity-${theme.name}',
        themeMode: theme,
      ),
    );
    try {
      await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
      await tester.pumpAndSettle();
      await _openSecretary(tester);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        app.themeMode,
        theme == ThemePreference.dark ? ThemeMode.dark : ThemeMode.light,
      );
      final context = tester.element(find.byKey(const Key('chat_input')));
      final scheme = Theme.of(context).colorScheme;
      expect(
        scheme.primary,
        theme == ThemePreference.dark
            ? AppDesignTokens.primaryDark
            : AppDesignTokens.primary,
      );
      final sendButton = tester.widget<IconButton>(
        find.byKey(const Key('chat_send')),
      );
      expect(
        sendButton.style?.backgroundColor?.resolve({}),
        AppDesignTokens.primaryButton,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await runtime.shutdown();
    }
  }
}

Future<AppRuntime> _bootRuntime({
  required MemoryConversationStore conversationStore,
  required MemoryAttachmentStore attachments,
  required _ActivityModelPlan plan,
}) {
  return AppRuntime.bootstrap(
    vaultOverride: MemoryVaultStore(),
    indexOverride: MemoryIndexDatabase(),
    conversationStoreOverride: conversationStore,
    attachmentStoreOverride: attachments,
    settingsOverride: FakeSettingsService(
      deviceId: 'secretary-activity-phone',
      modelKey: 'test-key',
    ),
    modelClient: ModelClient(
      client: MockClient.streaming((request, body) async {
        expect(request.url.path, endsWith('/chat/completions'));
        await body.bytesToString();
        return plan.nextResponse();
      }),
    ),
  );
}

Future<void> _openSecretary(WidgetTester tester) async {
  final inbox = find.byKey(const Key('nav_inbox'));
  if (inbox.evaluate().isNotEmpty) {
    await tester.tap(inbox);
    await tester.pumpAndSettle();
  }
  expect(find.byKey(const Key('chat_input')), findsOneWidget);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required String reason,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(reason);
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void _setViewport(
  WidgetTester tester,
  Size size, {
  double textScaleFactor = 1,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

final class _ActivityModelPlan {
  _ActivityModelPlan(this.scenario);

  static const privateMarkers = [
    'PRIVATE_REASONING_MARKER',
    'PRIVATE_ARGUMENT_MARKER',
    'PRIVATE_RESULT_MARKER',
  ];

  final SecretaryActivityScenario scenario;
  final _first = StreamController<List<int>>();
  final _second = StreamController<List<int>>();
  final _started = <int, Completer<void>>{
    1: Completer<void>(),
    2: Completer<void>(),
  };
  var _requests = 0;

  bool requestStarted(int number) => _started[number]?.isCompleted ?? false;

  Future<http.StreamedResponse> nextResponse() async {
    _requests++;
    final current = _requests;
    if (current > 2) {
      throw StateError('Unexpected mock model request $current');
    }
    if (!_started[current]!.isCompleted) {
      _started[current]!.complete();
    }
    if (current == 2 && scenario == SecretaryActivityScenario.failed) {
      return http.StreamedResponse(
        const Stream.empty(),
        400,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.StreamedResponse(
      current == 1 ? _first.stream : _second.stream,
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  void emitReasoning() {
    _event(_first, {
      'choices': [
        {
          'delta': {'reasoning_content': privateMarkers[0]},
          'finish_reason': null,
        },
      ],
    });
  }

  void emitToolCall() {
    _event(_first, {
      'choices': [
        {
          'delta': {
            'tool_calls': [
              {
                'index': 0,
                'id': 'call_phone_table_list',
                'function': {
                  'name': 'table_list',
                  'arguments': jsonEncode({
                    'private': privateMarkers[1],
                    'result_label': privateMarkers[2],
                  }),
                },
              },
            ],
          },
          'finish_reason': 'tool_calls',
        },
      ],
    });
    _done(_first);
    if (!_first.isClosed) unawaited(_first.close());
  }

  void completeFinalReply() {
    _event(_second, {
      'choices': [
        {
          'delta': {'content': '表格检查完成。'},
          'finish_reason': 'stop',
        },
      ],
    });
    _done(_second);
    if (!_second.isClosed) unawaited(_second.close());
  }

  void cancelSecondRequest() {
    if (!_second.isClosed) unawaited(_second.close());
  }

  void close() {
    if (!_first.isClosed) unawaited(_first.close());
    if (!_second.isClosed) unawaited(_second.close());
  }

  static void _event(
    StreamController<List<int>> controller,
    Map<String, dynamic> event,
  ) {
    controller.add(utf8.encode('data: ${jsonEncode(event)}\n\n'));
  }

  static void _done(StreamController<List<int>> controller) {
    controller.add(utf8.encode('data: [DONE]\n\n'));
  }
}
