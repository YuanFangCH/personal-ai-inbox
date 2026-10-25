import 'dart:convert';

import 'package:flutter/material.dart';
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
  testWidgets(
    'system back stops speech input before leaving the conversation',
    (tester) async {
      tester.view.physicalSize = const Size(480, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final voice = _FakeVoiceService();
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(
          deviceId: 'voice-back-ui-test',
          modelKey: 'test-key',
        ),
        voiceService: voice,
      );
      addTearDown(runtime.dispose);

      await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_inbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat_voice_input')));
      await tester.pumpAndSettle();
      expect(voice.isListening, isTrue);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(voice.isListening, isFalse);
      expect(find.byKey(const Key('nav_home')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('chat_input')))
            .controller!
            .text,
        '口述的草稿',
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('丢弃未发送内容？'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('chat_input')))
            .controller!
            .text,
        '口述的草稿',
      );
    },
  );

  testWidgets(
    'voice text remains editable before send and reply can be read aloud',
    (tester) async {
      tester.view.physicalSize = const Size(480, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final voice = _FakeVoiceService();
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(
          deviceId: 'voice-ui-test',
          modelKey: 'test-key',
        ),
        voiceService: voice,
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            await body.bytesToString();
            final event = {
              'choices': [
                {
                  'delta': {'content': '这是秘书的回复。'},
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
      addTearDown(runtime.dispose);
      await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_inbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat_voice_input')));
      await tester.pumpAndSettle();
      expect(voice.isListening, isTrue);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('chat_input')))
            .controller!
            .text,
        '口述的草稿',
      );

      await tester.enterText(
        find.byKey(const Key('chat_input')),
        '口述的草稿，已人工修改',
      );
      await tester.tap(find.byKey(const Key('chat_voice_input')));
      await tester.pumpAndSettle();
      expect(voice.isListening, isFalse);
      await tester.tap(find.byKey(const Key('chat_send')));
      await tester.pumpAndSettle();

      final conversation = runtime.conversations.conversations.single;
      final user = runtime.conversations
          .messagesFor(conversation.id)
          .firstWhere((message) => message.isUser);
      expect(user.content, '口述的草稿，已人工修改');
      final reply = runtime.conversations.messagesFor(conversation.id).last;
      await tester.tap(find.byKey(Key('reply_speech_${reply.id}')));
      await tester.pumpAndSettle();
      expect(voice.isSpeaking, isTrue);
      expect(voice.spokenText, '这是秘书的回复。');
      await tester.tap(find.byKey(Key('reply_speech_${reply.id}')));
      await tester.pumpAndSettle();
      expect(voice.isSpeaking, isFalse);
    },
  );
}

class _FakeVoiceService extends VoiceService {
  bool _listening = false;
  bool _speaking = false;
  String? _spokenText;

  @override
  bool get canTrySpeechInput => true;

  @override
  bool get canSpeak => true;

  @override
  bool get isListening => _listening;

  @override
  bool get isSpeaking => _speaking;

  @override
  String? get lastError => null;

  String? get spokenText => _spokenText;

  @override
  Future<bool> startListening(SpeechTextCallback onResult) async {
    _listening = true;
    notifyListeners();
    onResult('口述的草稿', false);
    return true;
  }

  @override
  Future<void> stopListening() async {
    _listening = false;
    notifyListeners();
  }

  @override
  Future<void> speak(String text) async {
    _spokenText = text;
    _speaking = true;
    notifyListeners();
  }

  @override
  Future<void> stopSpeaking() async {
    _speaking = false;
    notifyListeners();
  }

  @override
  Future<void> close() async {
    _listening = false;
    _speaking = false;
  }
}
