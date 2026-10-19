import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';

import 'test_support.dart';

void main() {
  testWidgets('conversation drawer and permissions are session scoped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    expect(find.byKey(const Key('chat_input')), findsOneWidget);
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
}
