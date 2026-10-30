import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/data/sync_engine.dart';
import 'package:personal_ai_inbox/data/sync_provider.dart';

import 'support/test_app_host.dart';

import 'package:personal_ai_inbox/services/capture_service.dart';

import 'test_support.dart';

void main() {
  testWidgets('calendar page defaults to month and exposes all modes', (
    tester,
  ) async {
    final controller = await _controller();
    await tester.pumpWidget(PersonalAiInboxApp(runtime: controller.runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_calendar')));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const Key('calendar_mode_month')), findsOneWidget);
    expect(find.byKey(const Key('calendar_mode_year')), findsOneWidget);
    expect(find.byKey(const Key('calendar_mode_week')), findsOneWidget);
    expect(find.byKey(const Key('calendar_mode_day')), findsOneWidget);
    expect(find.byKey(const Key('calendar_mode_agenda')), findsOneWidget);
    expect(find.byKey(const Key('calendar_section_calendar')), findsOneWidget);
    expect(find.byKey(const Key('calendar_section_myDay')), findsOneWidget);
    expect(find.byKey(const Key('calendar_section_todos')), findsOneWidget);

    await tester.tap(find.text('年'));
    await tester.pumpAndSettle();
    expect(find.text('1月'), findsOneWidget);
    expect(find.text('12月'), findsOneWidget);
  });

  testWidgets('month density persists through settings', (tester) async {
    final controller = await _controller();
    await tester.pumpWidget(PersonalAiInboxApp(runtime: controller.runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_calendar')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('详细'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('概要模式'));
    await tester.pumpAndSettle();

    expect(controller.settings?.calendarMonthDetailed, false);
    expect(find.text('概要'), findsOneWidget);
  });

  testWidgets('calendar quick create writes a dated schedule into a table', (
    tester,
  ) async {
    final controller = await _controller();
    final scheduleTable = controller.runtime.tables.tables.singleWhere(
      (table) => table.role == TableRole.inboxSchedule,
    );
    await tester.pumpWidget(PersonalAiInboxApp(runtime: controller.runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_calendar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar_quick_create')));
    await tester.pumpAndSettle();
    expect(find.text('保存到哪张表？'), findsOneWidget);
    await tester.tap(find.text(scheduleTable.title).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('table_entry_title')), '快速日程');
    await tester.tap(find.byKey(const Key('table_entry_save')));
    await tester.pumpAndSettle();

    final created = controller.runtime.tables.entries.singleWhere(
      (entry) => entry.title == '快速日程',
    );
    expect(created.type, TableContentType.schedule);
    expect(created.tableId, scheduleTable.id);
    final now = DateTime.now();
    expect(created.start!.year, now.year);
    expect(created.start!.month, now.month);
    expect(created.start!.day, now.day);
  });

  testWidgets('calendar quick create carries the selected date into its table', (
    tester,
  ) async {
    final controller = await _controller();
    final scheduleTable = controller.runtime.tables.tables.singleWhere(
      (table) => table.role == TableRole.inboxSchedule,
    );
    final selected = DateTime.now().add(const Duration(days: 2));
    final selectedDay = DateTime(selected.year, selected.month, selected.day);
    await tester.pumpWidget(PersonalAiInboxApp(runtime: controller.runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_calendar')));
    await tester.pumpAndSettle();
    final selectedDayCell = find.byKey(
      Key(
        'calendar_day_${selectedDay.year}-${selectedDay.month.toString().padLeft(2, '0')}-${selectedDay.day.toString().padLeft(2, '0')}',
      ),
    );
    await tester.ensureVisible(selectedDayCell);
    await tester.tap(selectedDayCell);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('calendar_quick_create')));
    await tester.tap(find.byKey(const Key('calendar_quick_create')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(scheduleTable.title).last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('table_entry_title')),
      '选中日期日程',
    );
    await tester.tap(find.byKey(const Key('table_entry_save')));
    await tester.pumpAndSettle();

    final created = controller.runtime.tables.entries.singleWhere(
      (entry) => entry.title == '选中日期日程',
    );
    expect(created.tableId, scheduleTable.id);
    expect(created.start!.year, selectedDay.year);
    expect(created.start!.month, selectedDay.month);
    expect(created.start!.day, selectedDay.day);
  });

  testWidgets('calendar todo quick create writes into the default todo table', (
    tester,
  ) async {
    final controller = await _controller();
    final todoTable = controller.runtime.tables.tables.singleWhere(
      (table) => table.role == TableRole.inboxTodo,
    );
    await tester.pumpWidget(PersonalAiInboxApp(runtime: controller.runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_calendar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar_section_todos')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar_quick_create')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(todoTable.title).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('table_entry_title')), '快速待办');
    await tester.tap(find.byKey(const Key('table_entry_save')));
    await tester.pumpAndSettle();

    final created = controller.runtime.tables.entries.singleWhere(
      (entry) => entry.title == '快速待办',
    );
    expect(created.type, TableContentType.todo);
    expect(created.tableId, todoTable.id);
    expect(created.due, isNotNull);
  });

  testWidgets('calendar filter projects one table and excludes timed notes', (
    tester,
  ) async {
    final controller = await _controller();
    final table = await controller.runtime.tables.createTable(title: '考试表');
    final now = DateTime.now();
    await controller.runtime.tables.createEntry(
      TableEntryDocument(
        id: 'sc_projection_test',
        type: TableContentType.schedule,
        tableId: table.id,
        title: '表内考试',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '',
        start: DateTime(now.year, now.month, now.day, 14),
      ),
    );
    await controller.runtime.tables.createEntry(
      TableEntryDocument(
        id: 'nt_timed_note_test',
        type: TableContentType.note,
        tableId: table.id,
        title: '带时间笔记',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '周五下午',
      ),
    );
    await tester.pumpWidget(PersonalAiInboxApp(runtime: controller.runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_calendar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar_table_filter')));
    await tester.pumpAndSettle();
    for (final defaultName in const ['待办', '日程', '事件']) {
      await tester.tap(find.widgetWithText(CheckboxListTile, defaultName));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(controller.runtime.preferences.settings.calendarVisibleTableIds, [
      table.id,
    ]);
    expect(find.text('表内考试'), findsWidgets);
    expect(find.text('带时间笔记'), findsNothing);
  });

  testWidgets('all calendar modes and sections render at high text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final now = DateTime.now();
    final controller = await _controller(
      seed: [
        ResultDocument(
          id: 'ev_today',
          type: ResultType.event,
          title: '今天的事件',
          status: ResultStatus.canonical,
          originDevice: 'test-device',
          revision: 1,
          createdAt: now,
          updatedAt: now,
          body: '',
          start: DateTime(now.year, now.month, now.day, 9),
          end: DateTime(now.year, now.month, now.day, 10),
        ),
        ResultDocument(
          id: 'td_today',
          type: ResultType.todo,
          title: '今天的待办',
          status: ResultStatus.canonical,
          originDevice: 'test-device',
          revision: 1,
          createdAt: now,
          updatedAt: now,
          body: '',
          due: DateTime(now.year, now.month, now.day, 14),
        ),
      ],
    );
    await tester.pumpWidget(PersonalAiInboxApp(runtime: controller.runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_calendar')));
    await tester.pumpAndSettle();

    for (final label in const ['年', '月', '周', '日', '日程']) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'calendar mode $label');
    }
    for (final key in const [
      'calendar_section_myDay',
      'calendar_section_todos',
      'calendar_section_calendar',
    ]) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: key);
    }
  });

  testWidgets('calendar fits phone and wide workspace layouts', (tester) async {
    final controller = await _controller();
    await tester.pumpWidget(PersonalAiInboxApp(runtime: controller.runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_calendar')));
    await tester.pumpAndSettle();
    for (final size in const [
      Size(320, 760),
      Size(800, 900),
      Size(1280, 900),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      for (final mode in const ['年', '月', '周', '日', '日程']) {
        await tester.tap(find.text(mode).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$mode at $size');
      }
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}

Future<TestAppHost> _controller({List<ResultDocument> seed = const []}) async {
  final vault = MemoryVaultStore();
  final index = MemoryIndexDatabase();
  final settings = FakeSettingsService();
  final repository = ResultRepository(
    vault: vault,
    index: index,
    deviceId: 'test-device',
  );
  await repository.initialize();
  for (final document in seed) {
    await repository.save(document, incrementRevision: false);
  }
  final controller = TestAppHost(
    repository: repository,
    indexDatabase: index,
    captureService: CaptureService(
      settings: settings,
      parser: const DeterministicParser(),
    ),
    settingsService: settings,
    syncEngine: SyncEngine(
      repository: repository,
      provider: MemorySyncProvider(),
      deviceId: 'test-device',
    ),
  );
  await controller.initialize();
  return controller;
}
