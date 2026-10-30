import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
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
    final scheduleTable = runtime.tables.tables.singleWhere(
      (table) => table.role == TableRole.inboxSchedule,
    );
    final todoTable = runtime.tables.tables.singleWhere(
      (table) => table.role == TableRole.inboxTodo,
    );
    final noteTable = runtime.tables.tables.singleWhere(
      (table) => table.role == TableRole.inboxEvent,
    );
    await runtime.tables.createEntry(
      _entry(
        id: 'sc_today',
        tableId: scheduleTable.id,
        type: TableContentType.schedule,
        title: '今天的评审',
        now: now,
        start: DateTime(now.year, now.month, now.day, 15),
      ),
    );
    TableEntryDocument? firstTodoDocument;
    for (var index = 0; index < 5; index++) {
      final todo = await runtime.tables.createEntry(
        _entry(
          id: 'td_home_$index',
          tableId: todoTable.id,
          type: TableContentType.todo,
          title: '待办 $index',
          now: now,
          due: now.add(Duration(days: index + 1)),
        ),
      );
      firstTodoDocument ??= todo;
      await runtime.tables.createEntry(
        _entry(
          id: 'nt_home_$index',
          tableId: noteTable.id,
          type: TableContentType.note,
          title: '知识 $index',
          now: now,
          body: '知识摘要内容',
        ),
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
    expect(
      runtime.tables.entries
          .singleWhere((entry) => entry.id == firstTodoDocument!.id)
          .done,
      isTrue,
    );
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
    final table = runtime.tables.tables.singleWhere(
      (candidate) => candidate.role == TableRole.inboxTodo,
    );
    final todo = await runtime.tables.createEntry(
      _entry(
        id: 'td_fail',
        tableId: table.id,
        type: TableContentType.todo,
        title: '待办保存失败',
        now: DateTime.now(),
      ),
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
    expect(
      runtime.tables.entries.singleWhere((entry) => entry.id == todo.id).done,
      isFalse,
    );
    expect(find.text('待办未能更新，请稍后重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'home table modules can be added, expanded, reordered and hidden',
    (tester) async {
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(
          deviceId: 'home-table-modules-ui',
        ),
      );
      addTearDown(runtime.dispose);
      final first = await runtime.tables.createTable(title: '作业表');
      final second = await runtime.tables.createTable(title: '考试表');
      final now = DateTime.now();
      for (var index = 0; index < 7; index++) {
        await runtime.tables.createEntry(
          _entry(
            id: 'nt_home_module_$index',
            tableId: first.id,
            type: TableContentType.note,
            title: '作业笔记 $index',
            now: now.add(Duration(minutes: index)),
          ),
        );
      }

      await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('home_add_table_module')),
      );
      await tester.tap(find.byKey(const Key('home_add_table_module')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('作业表').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('home_add_table_module')),
      );
      await tester.tap(find.byKey(const Key('home_add_table_module')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('考试表').last);
      await tester.pumpAndSettle();
      expect(runtime.preferences.settings.homeTableOrder, [
        first.id,
        second.id,
      ]);

      final secondCard = find.byKey(ValueKey('home_table_card_${second.id}'));
      await tester.ensureVisible(secondCard);
      await tester.tap(
        find.descendant(of: secondCard, matching: find.byTooltip('上移')),
      );
      await tester.pumpAndSettle();
      expect(runtime.preferences.settings.homeTableOrder, [
        second.id,
        first.id,
      ]);

      final firstCard = find.byKey(ValueKey('home_table_card_${first.id}'));
      await tester.ensureVisible(firstCard);
      expect(find.text('作业笔记 6'), findsWidgets);
      expect(find.text('作业笔记 1'), findsNothing);
      await tester.tap(find.text('展开全部 7 条'));
      await tester.pumpAndSettle();
      expect(find.text('作业笔记 1'), findsWidgets);

      await tester.ensureVisible(secondCard);
      await tester.tap(
        find.descendant(of: secondCard, matching: find.byTooltip('从首页移除')),
      );
      await tester.pumpAndSettle();
      expect(runtime.preferences.settings.homeTableOrder, [first.id]);
      expect(runtime.tables.findTable(second.id), isNotNull);
    },
  );
}

TableEntryDocument _entry({
  required String id,
  required String tableId,
  required TableContentType type,
  required String title,
  required DateTime now,
  DateTime? due,
  DateTime? start,
  String body = '',
}) => TableEntryDocument(
  id: id,
  type: type,
  tableId: tableId,
  title: title,
  revision: 1,
  createdAt: now,
  updatedAt: now,
  body: body,
  due: due,
  start: start,
);

class _FailingWriteVaultStore extends MemoryVaultStore {
  bool failWrites = false;

  @override
  Future<void> write(String relativePath, String contents) async {
    if (failWrites) throw StateError('simulated vault write failure');
    await super.write(relativePath, contents);
  }
}
