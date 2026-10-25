import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';

import 'test_support.dart';

void main() {
  testWidgets('wide home hides capture while other workspaces keep it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(deviceId: 'wide-home-capture-ui'),
    );
    addTearDown(runtime.dispose);
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture_button')), findsNothing);
    await tester.tap(find.byKey(const Key('nav_knowledge')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture_button')), findsOneWidget);
  });

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('待办 0'), findsOneWidget);
    expect(find.text('待办 4'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(runtime.results.findDocument(firstTodoDocument.id)!.done, isTrue);
    expect(firstTodoCheckbox, findsNothing);
    expect(find.text('待办 0'), findsNothing);
    expect(find.text('待办 4'), findsOneWidget);

    final todoSectionAction = find.text('查看全部').at(1);
    await tester.ensureVisible(todoSectionAction);
    await tester.tap(todoSectionAction);
    await tester.pumpAndSettle();
    expect(find.text('待办'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home keeps a todo row when saving completion fails', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final vault = _FailingWriteVaultStore();
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: vault,
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(deviceId: 'home-todo-failure-ui'),
    );
    addTearDown(runtime.dispose);
    final todo = await runtime.results.createManual(
      type: ResultType.todo,
      title: '待办保存失败',
    );
    vault.failWrites = true;

    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    final checkbox = find.byKey(Key('home_todo_checkbox_${todo.id}'));
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();

    expect(find.text('待办保存失败'), findsOneWidget);
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
    expect(runtime.results.findDocument(todo.id)!.done, isFalse);
    expect(find.text('待办未能更新，请稍后重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FailingWriteVaultStore extends MemoryVaultStore {
  bool failWrites = false;

  @override
  Future<void> write(String relativePath, String contents) async {
    if (failWrites) throw StateError('simulated vault write failure');
    await super.write(relativePath, contents);
  }
}
