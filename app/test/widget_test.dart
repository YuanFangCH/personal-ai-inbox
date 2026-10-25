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

import 'support/test_app_host.dart';

import 'package:personal_ai_inbox/services/capture_service.dart';

import 'test_support.dart';

void main() {
  testWidgets('captures text and shows the generated result', (tester) async {
    final controller = await _controller();
    await tester.pumpWidget(PersonalAiInboxApp(runtime: controller.runtime));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_knowledge')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('capture_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('capture_text_field')),
      '明天下午三点提醒我交材料',
    );
    await tester.tap(find.byKey(const Key('capture_submit')));
    await tester.pumpAndSettle();

    expect(controller.documents, hasLength(1));
    expect(controller.documents.single.type, ResultType.event);
    expect(find.textContaining('已生成事件'), findsOneWidget);
  });

  testWidgets('renders core navigation on a compact viewport', (tester) async {
    final controller = await _controller();
    await controller.createManual(
      type: ResultType.todo,
      title: '买牛奶',
      due: DateTime(2026, 10, 5, 18),
    );
    await tester.pumpWidget(PersonalAiInboxApp(runtime: controller.runtime));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav_calendar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar_section_todos')));
    await tester.pumpAndSettle();

    expect(find.text('买牛奶'), findsOneWidget);
  });

  testWidgets('more sheet remains scrollable at 320x568', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await _controller();
    await tester.pumpWidget(PersonalAiInboxApp(runtime: controller.runtime));
    await tester.pumpAndSettle();

    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<TestAppHost> _controller() async {
  final vault = MemoryVaultStore();
  final index = MemoryIndexDatabase();
  final settings = FakeSettingsService();
  final repository = ResultRepository(
    vault: vault,
    index: index,
    deviceId: 'test-device',
  );
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
