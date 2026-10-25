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

import 'test_support.dart';

void main() {
  testWidgets('conversation drawer and permissions are session scoped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(
        deviceId: 'secretary-chat-ui',
        modelKey: 'test-key',
      ),
    );
    addTearDown(runtime.dispose);
    final existing = await runtime.conversations.createConversation();
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_inbox')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav_home')), findsNothing);
    await tester.enterText(find.byKey(const Key('chat_input')), '未发送的草稿');
    await tester.tap(find.byKey(const Key('conversation_manage')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation_return_home')), findsOneWidget);
    await tester.tap(find.byKey(const Key('conversation_return_home')));
    await tester.pumpAndSettle();
    expect(find.text('丢弃未发送内容？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.text('未发送的草稿'), findsOneWidget);
    await tester.tap(find.byKey(const Key('conversation_return_home')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('丢弃并离开'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav_home')), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav_inbox')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation_manage')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav_home')), findsNothing);
    expect(find.byKey(const Key('conversation_search')), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav_home')), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav_inbox')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat_input')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('chat_input')))
          .controller!
          .text,
      isEmpty,
    );
    final thinkingChip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, '深度思考'),
    );
    final webSearchChip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, '智能搜索'),
    );
    expect(thinkingChip.onSelected, isNotNull);
    expect(thinkingChip.selected, isFalse);
    expect(webSearchChip.onSelected, isNull);
    await tester.tap(find.widgetWithText(FilterChip, '深度思考'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '深度思考'))
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('conversation_manage')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation_search')), findsOneWidget);
    await tester.tap(find.byKey(Key('conversation_${existing.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation_permissions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile).at(0));
    await tester.pumpAndSettle();
    expect(
      runtime.conversations.findConversation(existing.id)!.aiPermissions.read,
      isFalse,
    );
    await tester.tap(find.byKey(const Key('conversation_permissions_close')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('inbox_new_conversation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation_permissions')));
    await tester.pumpAndSettle();
    expect(
      (tester.widget<SwitchListTile>(find.byType(SwitchListTile).first)).value,
      isTrue,
      reason: 'a blank new conversation starts from global defaults',
    );
    await tester.tap(find.byKey(const Key('conversation_permissions_close')));
    await tester.pumpAndSettle();
    expect(runtime.conversations.conversations, hasLength(1));
  });

  testWidgets('desktop secretary sidebar keeps app navigation and history', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          const event = {
            'choices': [
              {
                'delta': {'content': '今天的安排已经整理好了。'},
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
      settingsOverride: FakeSettingsService(
        deviceId: 'secretary-desktop-sidebar-ui',
        modelKey: 'test-key',
      ),
    );
    addTearDown(runtime.dispose);
    final history = await runtime.conversations.createConversation();
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_inbox')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nav_home')), findsNothing);
    expect(find.byKey(const Key('secretary_nav_home')), findsOneWidget);
    expect(find.byKey(const Key('secretary_nav_more')), findsOneWidget);
    expect(find.byKey(const Key('conversation_search')), findsOneWidget);
    expect(find.byKey(const Key('conversation_pending_page')), findsNothing);
    expect(
      find.byKey(const Key('conversation_global_knowledge')),
      findsNothing,
    );
    expect(find.byKey(Key('conversation_${history.id}')), findsOneWidget);

    final emptyComposerY = tester
        .getCenter(find.byKey(const Key('chat_input')))
        .dy;
    expect(emptyComposerY, lessThan(350));
    await tester.enterText(find.byKey(const Key('chat_input')), '梳理今天的安排');
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pumpAndSettle();
    expect(find.text('今天的安排已经整理好了。'), findsWidgets);
    expect(
      tester.getCenter(find.byKey(const Key('chat_input'))).dy,
      greaterThan(emptyComposerY),
    );

    await tester.ensureVisible(find.byKey(const Key('secretary_nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('secretary_nav_more')));
    await tester.pumpAndSettle();
    expect(find.text('全局知识库'), findsOneWidget);
    expect(find.text('待处理'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('同步'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet assistant drawer retains the main app sections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(768, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(
        deviceId: 'secretary-tablet-navigation-ui',
      ),
    );
    addTearDown(runtime.dispose);

    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_inbox')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav_home')), findsNothing);

    await tester.tap(find.byKey(const Key('conversation_manage')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation_return_home')), findsOneWidget);
    expect(find.byKey(const Key('secretary_nav_calendar')), findsOneWidget);
    expect(find.byKey(const Key('secretary_nav_matters')), findsOneWidget);
    expect(find.byKey(const Key('secretary_nav_knowledge')), findsOneWidget);
    await tester.tap(find.byKey(const Key('secretary_nav_calendar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav_calendar')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
