import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';

import 'test_support.dart';

void main() {
  testWidgets('home lays out content without capture or count cards', (
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
      settingsOverride: FakeSettingsService(deviceId: 'home-page-ui'),
    );
    addTearDown(runtime.dispose);

    final now = DateTime.now();
    await runtime.results.createManual(
      type: ResultType.event,
      title: '今天的评审',
      start: DateTime(now.year, now.month, now.day, 15),
    );
    ResultDocument? firstTodoDocument;
    for (var index = 0; index < 5; index++) {
      final todo = await runtime.results.createManual(
        type: ResultType.todo,
        title: '待办 $index',
        due: now.add(Duration(days: index + 1)),
      );
      firstTodoDocument ??= todo;
      await runtime.results.createManual(
        type: ResultType.knowledge,
        title: '知识 $index',
        body: '知识摘要内容',
      );
    }

    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsWidgets);
    expect(find.text('今日安排'), findsOneWidget);
    expect(find.text('今天的评审'), findsOneWidget);
    expect(find.text('要做的'), findsOneWidget);
    expect(find.text('最近知识'), findsOneWidget);
    expect(find.text('收下内容'), findsNothing);
    expect(find.text('今日日程'), findsNothing);
    expect(find.text('未完成'), findsNothing);
    expect(find.text('待确认'), findsNothing);
    expect(find.textContaining('待办 '), findsNWidgets(4));
    expect(find.textContaining('知识 '), findsNWidgets(3));

    final firstTodoCheckbox = find.byKey(
      Key('home_todo_checkbox_${firstTodoDocument!.id}'),
    );
    await tester.ensureVisible(firstTodoCheckbox);
    await tester.tap(firstTodoCheckbox);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();
    expect(runtime.results.findDocument(firstTodoDocument.id)!.done, isTrue);
    expect(firstTodoCheckbox, findsNothing);
    expect(find.text('待办 0'), findsNothing);

    final todoSectionAction = find.text('查看全部').at(1);
    await tester.ensureVisible(todoSectionAction);
    await tester.tap(todoSectionAction);
    await tester.pumpAndSettle();
    expect(find.text('待办'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
