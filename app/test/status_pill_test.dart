import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/ui/widgets/common.dart';

/// Regression for the 7.1px overflow the realistic matrix found on a phone at
/// 1.15x text scale: a review reason pill inside a bounded row.
void main() {
  testWidgets('StatusPill ellipsizes instead of overflowing', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.15;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            // Wrap gives children a finite max width, like the review queue.
            child: SizedBox(
              width: 180,
              child: const StatusPill(
                label: '内容或时间表达需要确认，请人工核对后再生成成果',
                icon: Icons.info_outline,
                tone: StatusTone.warning,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
