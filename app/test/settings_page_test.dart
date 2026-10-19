import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';

import 'test_support.dart';

void main() {
  testWidgets(
    'permission defaults affect only conversations created afterward',
    (tester) async {
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(deviceId: 'ai-permission-page'),
      );
      addTearDown(runtime.dispose);
      final existing = await runtime.conversations.createConversation();
      await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet_nav_settings')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('读取'));
      await tester.pumpAndSettle();

      final switches = find.byType(SwitchListTile);
      await tester.tap(switches.at(0));
      await tester.tap(switches.at(1));
      await tester.tap(switches.at(2));
      _scrollToTop(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(
        runtime.preferences.settings.defaultAiPermissions,
        const AiPermissions(read: false, create: false, modifyDelete: false),
      );
      expect(
        runtime.conversations.findConversation(existing.id)!.aiPermissions,
        const AiPermissions(),
      );
      final next = await runtime.conversations.createConversation();
      expect(
        next.aiPermissions,
        const AiPermissions(read: false, create: false, modifyDelete: false),
      );
    },
  );

  testWidgets(
    'advanced settings expose request limits and reject invalid URL',
    (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(deviceId: 'settings-page-test'),
      );
      await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet_nav_settings')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('高级模型设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('高级模型设置'));
      await tester.pumpAndSettle();

      expect(find.text('响应头等待（5–120 秒）'), findsOneWidget);
      expect(find.text('上下文消息数（2–20）'), findsOneWidget);
      expect(find.text('图片能力'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).at(0),
        'https://user:pass@example.com/v1?token=x',
      );
      _scrollToTop(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.textContaining('不能包含凭据'), findsOneWidget);
      expect(
        runtime.preferences.settings.modelBaseUrl,
        'https://api.deepseek.com',
      );
    },
  );
}

void _scrollToTop(WidgetTester tester) {
  for (final element in find.byType(Scrollable).evaluate()) {
    final state = (element as StatefulElement).state as ScrollableState;
    if (state.position.hasContentDimensions && state.position.pixels != 0) {
      state.position.jumpTo(0);
    }
  }
}
