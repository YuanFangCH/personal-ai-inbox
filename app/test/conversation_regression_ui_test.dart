import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/services/model_client.dart';
import 'package:personal_ai_inbox/services/voice_service.dart';

import 'test_support.dart';

void main() {
  testWidgets('repeated send while stopping speech only submits once', (
    tester,
  ) async {
    _setView(tester, const Size(390, 844));
    final voice = _PausedVoiceService();
    final runtime = await _runtime('收到', voice: voice);
    addTearDown(runtime.dispose);
    addTearDown(voice.finishStopping);
    await _open(tester, runtime);
    await tester.tap(find.byKey(const Key('chat_voice_input')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.tap(find.byKey(const Key('chat_send')));
    final stopCalls = voice.stopCalls;
    voice.finishStopping();
    await tester.pumpAndSettle();
    expect(stopCalls, 1);
    expect(runtime.conversations.conversations, hasLength(1));
    final conversation = runtime.conversations.conversations.single;
    expect(
      runtime.conversations
          .messagesFor(conversation.id)
          .where((item) => item.isUser),
      hasLength(1),
    );
    expect(
      runtime.conversations.messagesFor(conversation.id).first.content,
      '口述的完整草稿',
    );
  });

  testWidgets('short phone window keeps the attachment composer accessible', (
    tester,
  ) async {
    _setView(tester, const Size(390, 420));
    final runtime = await _runtime('收到');
    addTearDown(runtime.dispose);
    await _open(tester, runtime);
    await tester.enterText(
      find.byKey(const Key('chat_input')),
      '第一行\n第二行\n第三行\n第四行\n第五行\n第六行',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat_attachment_menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat_send')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'short desktop window can expand a multiline attachment composer',
    (tester) async {
      _setView(tester, const Size(1200, 420));
      final runtime = await _runtime('收到');
      addTearDown(runtime.dispose);
      await _open(tester, runtime);
      await tester.enterText(
        find.byKey(const Key('chat_input')),
        '第一行\n第二行\n第三行\n第四行\n第五行\n第六行',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat_attachment_menu')));
      await tester.pumpAndSettle();
      expect(find.text('拍照'), findsOneWidget);
      expect(find.byKey(const Key('chat_send')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('short tablet drawer keeps navigation and history reachable', (
    tester,
  ) async {
    _setView(tester, const Size(768, 360));
    final runtime = await _runtime('收到');
    addTearDown(runtime.dispose);
    await _open(tester, runtime);
    await tester.tap(find.byKey(const Key('conversation_manage')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation_return_home')), findsOneWidget);
    expect(find.byKey(const Key('secretary_history_open')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop multiline composer does not cover the latest reply', (
    tester,
  ) async {
    _setView(tester, const Size(1200, 800));
    final reply = List.generate(28, (index) => '回复段落 $index').join('\n\n');
    final runtime = await _runtime(reply);
    addTearDown(runtime.dispose);
    await _open(tester, runtime);
    await tester.enterText(find.byKey(const Key('chat_input')), '整理内容');
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pumpAndSettle();
    final conversation = runtime.conversations.conversations.single;
    final message = runtime.conversations.messagesFor(conversation.id).last;
    final messageFinder = find.byKey(ValueKey('message_${message.id}'));

    await tester.enterText(
      find.byKey(const Key('chat_input')),
      '第一行\n第二行\n第三行\n第四行\n第五行\n第六行',
    );
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(
      find.ancestor(of: messageFinder, matching: find.byType(ListView)).first,
    );
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(
      tester.getBottomLeft(messageFinder).dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const Key('chat_input'))).dy - 12,
      ),
      reason:
          'the complete reply and its actions must remain above the composer',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('resizing the conversation preserves the active input element', (
    tester,
  ) async {
    _setView(tester, const Size(1200, 800));
    final runtime = await _runtime('收到');
    addTearDown(runtime.dispose);
    await _open(tester, runtime);
    final input = find.byKey(const Key('chat_input'));
    await tester.enterText(input, '继续编辑的草稿');
    final originalState = tester.state(input);
    final originalController = tester.widget<TextField>(input).controller;
    tester.view.physicalSize = const Size(800, 700);
    await tester.pumpAndSettle();
    expect(identical(tester.state(input), originalState), isTrue);
    expect(
      tester.widget<TextField>(input).controller,
      same(originalController),
    );
    expect(originalController!.text, '继续编辑的草稿');
    expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
    expect(runtime.conversations.conversations, isEmpty);
  });

  testWidgets(
    'desktop Shift Enter inserts a newline and Enter sends in a narrow window',
    (tester) async {
      _setView(tester, const Size(800, 700));
      final runtime = await _runtime('收到');
      addTearDown(runtime.dispose);
      await _open(tester, runtime);
      final input = find.byKey(const Key('chat_input'));
      await tester.enterText(input, '草稿');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(runtime.conversations.conversations, isEmpty);
      expect(tester.widget<TextField>(input).controller!.text, '草稿\n');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final conversation = runtime.conversations.conversations.single;
      expect(
        runtime.conversations.messagesFor(conversation.id).first.content,
        '草稿',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('desktop submit action does not send an active IME composition', (
    tester,
  ) async {
    _setView(tester, const Size(800, 700));
    final runtime = await _runtime('收到');
    addTearDown(runtime.dispose);
    await _open(tester, runtime);
    final input = find.byKey(const Key('chat_input'));
    await tester.enterText(input, 'ni');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(runtime.conversations.conversations, isEmpty);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(runtime.conversations.conversations, isEmpty);
    expect(tester.widget<TextField>(input).controller!.text, 'ni');

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '你',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    final conversation = runtime.conversations.conversations.single;
    expect(
      runtime.conversations.messagesFor(conversation.id).first.content,
      '你',
    );
    expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}

void _setView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _open(WidgetTester tester, AppRuntime runtime) async {
  await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('nav_inbox')));
  await tester.pumpAndSettle();
}

Future<AppRuntime> _runtime(String reply, {VoiceService? voice}) =>
    AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(
        deviceId: 'conversation-regression-ui',
        modelKey: 'test-key',
      ),
      voiceService: voice,
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          await body.bytesToString();
          final event = {
            'choices': [
              {
                'delta': {'content': reply},
              },
            ],
          };
          return http.StreamedResponse(
            Stream.fromIterable([
              utf8.encode('data: ${jsonEncode(event)}\n\n'),
              utf8.encode('data: [DONE]\n\n'),
            ]),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      ),
    );

class _PausedVoiceService extends VoiceService {
  final _stopped = Completer<void>();
  bool _listening = false;
  int stopCalls = 0;
  SpeechTextCallback? _onResult;

  @override
  bool get canTrySpeechInput => true;

  @override
  bool get isListening => _listening;

  @override
  bool get canSpeak => false;

  @override
  bool get isSpeaking => false;

  @override
  String? get lastError => null;

  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stopSpeaking() async {}

  @override
  Future<bool> startListening(SpeechTextCallback onResult) async {
    _onResult = onResult;
    _listening = true;
    notifyListeners();
    onResult('口述的草稿', false);
    return true;
  }

  @override
  Future<void> stopListening() async {
    stopCalls++;
    await _stopped.future;
    _onResult?.call('口述的完整草稿', true);
    _listening = false;
    notifyListeners();
  }

  void finishStopping() {
    if (!_stopped.isCompleted) _stopped.complete();
  }

  @override
  Future<void> close() async {
    finishStopping();
    _listening = false;
  }
}
