import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/ui/theme/app_theme.dart';
import 'package:personal_ai_inbox/ui/widgets/common.dart';

void main() {
  testWidgets('shared page frame fits a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
          home: const Scaffold(
            body: PageFrame(
              title: '今天安排与需要跟进的事项',
              subtitle: '10 月 25 日 · 星期日',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeading(title: '今日安排'),
                  SizedBox(height: 16),
                  SurfacePanel(child: Text('阅读并整理本周的重要安排。')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('今日安排'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
