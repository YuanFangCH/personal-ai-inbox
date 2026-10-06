import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/data/sync_engine.dart';
import 'package:personal_ai_inbox/data/sync_provider.dart';
import 'package:personal_ai_inbox/services/app_controller.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';

import 'test_support.dart';

void main() {
  testWidgets('calendar page defaults to month and exposes all modes', (
    tester,
  ) async {
    final controller = await _controller();
    await tester.pumpWidget(PersonalAiInboxApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_calendar')));
    await tester.pumpAndSettle();

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
    await tester.pumpWidget(PersonalAiInboxApp(controller: controller));
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

  testWidgets('quick create preloads the selected day and saves an event', (
    tester,
  ) async {
    final controller = await _controller();
    await tester.pumpWidget(PersonalAiInboxApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_calendar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar_quick_create')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('quick_create_title')), findsOneWidget);
    expect(find.byKey(const Key('quick_create_start')), findsOneWidget);
    expect(find.byKey(const Key('quick_create_end')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('quick_create_title')), '快速事件');
    await tester.tap(find.byKey(const Key('quick_create_save')));
    await tester.pumpAndSettle();

    expect(controller.events, hasLength(1));
    final created = controller.events.single;
    expect(created.title, '快速事件');
    final now = DateTime.now();
    expect(created.start?.year, now.year);
    expect(created.start?.month, now.month);
    expect(created.start?.day, now.day);
    expect(created.end?.difference(created.start!), const Duration(hours: 1));
  });

  testWidgets(
    'quick create can switch to todo and save through more settings',
    (tester) async {
      final controller = await _controller();
      await tester.pumpWidget(PersonalAiInboxApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_calendar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('calendar_section_todos')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('calendar_quick_create')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('待办').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('quick_create_title')),
        '快速待办',
      );
      await tester.tap(find.byKey(const Key('quick_create_more')));
      await tester.pumpAndSettle();
      expect(find.text('所属事项'), findsOneWidget);
      await tester.tap(find.byKey(const Key('quick_create_save')));
      await tester.pumpAndSettle();

      expect(controller.todos, hasLength(1));
      expect(controller.todos.single.title, '快速待办');
    },
  );

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
    await tester.pumpWidget(PersonalAiInboxApp(controller: controller));
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
}

Future<AppController> _controller({
  List<ResultDocument> seed = const [],
}) async {
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
  final controller = AppController(
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
