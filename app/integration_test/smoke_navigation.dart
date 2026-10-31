import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> navigateSmokePage(WidgetTester tester, String page) async {
  final primary = find.byKey(Key('nav_$page'));
  if (primary.evaluate().isNotEmpty) {
    await tapSmokeControl(tester, Key('nav_$page'));
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
