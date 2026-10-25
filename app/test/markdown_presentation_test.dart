import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/ui/presentation/markdown_presentation.dart';
import 'package:personal_ai_inbox/ui/theme/app_theme.dart';

void main() {
  testWidgets('shared Markdown preview keeps code local and copyable', (
    tester,
  ) async {
    final platformCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownBody(
              data: '''
一段正文。

```dart
final descriptiveValue = 'a very long code line that should scroll in its own block';
```

| 左侧列 | 右侧列 |
| --- | --- |
| 一段较长的表格文字 | 另一段较长的表格文字 |
''',
              selectable: true,
              styleSheet: MarkdownPresentation.styleSheet(AppTheme.light()),
              builders: MarkdownPresentation.builders,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('dart'), findsOneWidget);
    expect(find.byTooltip('复制代码'), findsOneWidget);
    expect(find.textContaining('一段正文。'), findsOneWidget);
    final copyCode = find.byTooltip('复制代码');
    await tester.ensureVisible(copyCode);
    await tester.tap(copyCode);
    await tester.pumpAndSettle();
    expect(
      platformCalls.where((call) => call.method == 'Clipboard.setData'),
      hasLength(1),
    );
    expect(find.text('代码已复制'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
