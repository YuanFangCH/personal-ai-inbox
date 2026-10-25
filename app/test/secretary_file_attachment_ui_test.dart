import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/services/file_input_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'test_support.dart';

void main() {
  testWidgets('selected local file is extracted and sent as bounded text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    Map<String, dynamic>? requestBody;
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(
        deviceId: 'file-input-ui',
        modelKey: 'test-key',
      ),
      fileInputService: FileInputService(
        pickFileBytes: () async => PickedFileBytes(
          fileName: '课程.txt',
          bytes: Uint8List.fromList(utf8.encode('本学期从九月一日开始，共 16 周。')),
        ),
      ),
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          requestBody =
              jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
          final event = {
            'choices': [
              {
                'delta': {'content': '我已阅读这份课程文件。'},
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
    expect(
      tester.widget<IconButton>(find.byKey(const Key('chat_send'))).onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('chat_attachment_menu')));
    await tester.pumpAndSettle();
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('相册'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.byKey(const Key('chat_attachment_menu')));
    await tester.pumpAndSettle();
    expect(find.text('拍照'), findsNothing);
    await tester.tap(find.byKey(const Key('chat_attachment_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat_file_课程.txt')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pumpAndSettle();

    final conversation = runtime.conversations.conversations.single;
    final userMessage = runtime.conversations
        .messagesFor(conversation.id)
        .firstWhere((message) => message.isUser);
    expect(userMessage.content, contains('课程.txt'));
    expect(userMessage.content, contains('共 16 周'));
    expect(
      userMessage.attachments,
      isEmpty,
      reason: 'the original file bytes stay local and are not uploaded',
    );
    final sentMessages = requestBody!['messages'] as List;
    final sentUserMessage = sentMessages.cast<Map>().lastWhere(
      (message) => message['role'] == 'user',
    );
    expect(sentUserMessage['content'], contains('课程.txt'));
    expect(sentUserMessage['content'], contains('共 16 周'));
    expect(jsonEncode(requestBody), isNot(contains('image_url')));
    expect(requestBody!['messages'].toString(), isNot(contains('base64,')));
    expect(
      runtime.conversations.messagesFor(conversation.id).last.content,
      '我已阅读这份课程文件。',
    );
  });
}
