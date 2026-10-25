import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';

import '../test/test_support.dart';
import 'smoke_navigation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows desktop renderer survives the full navigation smoke', (
    tester,
  ) async {
    final runtime = await _runtime();
    addTearDown(runtime.dispose);
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsWidgets);
    expect(tester.takeException(), isNull);

    for (final page in const [
      'inbox',
      'calendar',
      'matters',
      'knowledge',
      'sync',
      'settings',
      'home',
    ]) {
      await navigateSmokePage(tester, page);
      if (page == 'calendar') {
        await tester.tap(find.byKey(const Key('calendar_section_todos')));
        await tester.pumpAndSettle();
      }
      final scrollables = find.byType(Scrollable);
      if (scrollables.evaluate().isNotEmpty) {
        await tester.drag(scrollables.first, const Offset(0, -500));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull, reason: 'page $page');
    }

    expect(find.byKey(const Key('capture_button')), findsNothing);
    await navigateSmokePage(tester, 'knowledge');
    await tester.tap(find.byKey(const Key('capture_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('capture_text_field')),
      '明天下午三点提醒我交材料',
    );
    await tester.tap(find.byKey(const Key('capture_submit')));
    await tester.pumpAndSettle();

    expect(runtime.results.documents, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<AppRuntime> _runtime() async {
  final runtime = await AppRuntime.bootstrap(
    vaultOverride: MemoryVaultStore(),
    indexOverride: MemoryIndexDatabase(),
    settingsOverride: FakeSettingsService(deviceId: 'windows-test'),
  );
  await runtime.results.createManual(
    type: ResultType.knowledge,
    title: 'Windows 长文',
    body: List.filled(80, '这是 Windows 桌面渲染的长文本压力内容。').join(),
  );
  return runtime;
}
