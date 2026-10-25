import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> navigateSmokePage(WidgetTester tester, String page) async {
  final primary = find.byKey(Key('nav_$page'));
  if (primary.evaluate().isNotEmpty) {
    await tapSmokeControl(tester, Key('nav_$page'));
    return;
  }
  final secretary = find.byKey(Key('secretary_nav_$page'));
  if (secretary.evaluate().isNotEmpty) {
    await tapSmokeControl(tester, Key('secretary_nav_$page'));
    return;
  }
  if (find.byKey(const Key('conversation_manage')).evaluate().isNotEmpty) {
    await tapSmokeControl(tester, const Key('conversation_manage'));
    if (secretary.evaluate().isNotEmpty) {
      await tapSmokeControl(tester, Key('secretary_nav_$page'));
      return;
    }
    await tapSmokeControl(tester, const Key('conversation_return_home'));
    if (page == 'home') return;
    await navigateSmokePage(tester, page);
    return;
  }
  await tapSmokeControl(tester, const Key('nav_more'));
  await tapSmokeControl(tester, Key('sheet_nav_$page'));
}

Future<void> tapSmokeControl(WidgetTester tester, Key key) async {
  final control = find.byKey(key);
  expect(control, findsOneWidget, reason: 'Missing smoke-test control: $key');
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'control $key');
}
