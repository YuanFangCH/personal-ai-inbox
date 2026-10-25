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

  testWidgets('Android phone shell renders and captures', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final runtime = await _runtime();
    addTearDown(runtime.dispose);
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsWidgets);
    await navigateSmokePage(tester, 'inbox');
    await navigateSmokePage(tester, 'calendar');
    await _tap(tester, const Key('calendar_section_todos'));
    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_knowledge')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_settings')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android tablet shell renders wide navigation', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final runtime = await _runtime();
    addTearDown(runtime.dispose);
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();

    for (final page in const [
      'inbox',
      'calendar',
      'matters',
      'knowledge',
      'sync',
      'settings',
    ]) {
      await navigateSmokePage(tester, page);
      if (page == 'calendar') {
        await _tap(tester, const Key('calendar_section_todos'));
      }
    }

    await navigateSmokePage(tester, 'knowledge');
    await tester.tap(find.byKey(const Key('capture_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('capture_text_field')),
      '周五下午两点和客户开会',
    );
    await _failIfException(tester, 'capture keyboard');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _failIfException(tester, 'capture keyboard dismissed');
    await tester.ensureVisible(find.byKey(const Key('capture_submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('capture_submit')));
    await tester.pumpAndSettle();

    expect(runtime.results.documents, isNotEmpty);
    await _failIfException(tester, 'capture submitted');
  });
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isNotEmpty) {
    await tester.drag(scrollables.first, const Offset(0, -600));
    await tester.pumpAndSettle();
  }
  await _failIfException(tester, '$key');
}

Future<void> _failIfException(WidgetTester tester, String context) async {
  final error = tester.takeException();
  if (error == null) {
    return;
  }
  if (error is FlutterError) {
    fail('$context:\n${error.toStringDeep()}');
  }
  fail('$context: $error');
}

Future<AppRuntime> _runtime() async {
  final runtime = await AppRuntime.bootstrap(
    vaultOverride: MemoryVaultStore(),
    indexOverride: MemoryIndexDatabase(),
    settingsOverride: FakeSettingsService(deviceId: 'android-test'),
  );
  await runtime.results.createManual(
    type: ResultType.knowledge,
    title: 'Android 长文',
    body: List.filled(120, '这是 Android 设备渲染的长文本压力内容。').join(),
  );
  return runtime;
}
