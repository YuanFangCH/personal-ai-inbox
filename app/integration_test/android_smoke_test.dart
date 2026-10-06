import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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

import '../test/test_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android phone shell renders and captures', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;

    final controller = await _controller('honor-phone');
    await tester.pumpWidget(PersonalAiInboxApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsWidgets);
    await _tap(tester, const Key('nav_inbox'));
    await _tap(tester, const Key('nav_calendar'));
    await _tap(tester, const Key('nav_todos'));
    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_knowledge')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_settings')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android tablet shell renders wide navigation', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;

    final controller = await _controller('galaxy-tab');
    await tester.pumpWidget(PersonalAiInboxApp(controller: controller));
    await tester.pumpAndSettle();

    for (final key in const [
      'nav_inbox',
      'nav_calendar',
      'nav_todos',
      'nav_matters',
      'nav_knowledge',
      'nav_review',
      'nav_sync',
      'nav_settings',
    ]) {
      await _tap(tester, Key(key));
    }

    await tester.tap(find.byKey(const Key('capture_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('capture_text_field')),
      '周五下午两点和客户开会',
    );
    await _failIfException(tester, 'capture keyboard');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _failIfException(tester, 'capture keyboard dismissed');
    await tester.ensureVisible(find.byKey(const Key('capture_submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('capture_submit')));
    await tester.pumpAndSettle();

    expect(controller.documents, isNotEmpty);
    await _failIfException(tester, 'capture submitted');
  });
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isNotEmpty) {
    await tester.drag(scrollables.first, const Offset(0, -600));
    await tester.pumpAndSettle();
  }
  await _failIfException(tester, '$key');
}

Future<void> _failIfException(WidgetTester tester, String context) async {
  final error = tester.takeException();
  if (error == null) {
    return;
  }
  if (error is FlutterError) {
    fail('$context:\n${error.toStringDeep()}');
  }
  fail('$context: $error');
}

Future<AppController> _controller(String deviceId) async {
  final vault = MemoryVaultStore();
  final index = MemoryIndexDatabase();
  final settings = FakeSettingsService(deviceId: deviceId);
  final repository = ResultRepository(
    vault: vault,
    index: index,
    deviceId: deviceId,
  );
  await repository.initialize();
  await repository.create(
    type: ResultType.knowledge,
    title: 'Android 长文',
    body: List.filled(120, '这是 Android 设备渲染的长文本压力内容。').join(),
  );
  final provider = MemorySyncProvider();
  final engine = SyncEngine(
    repository: repository,
    provider: provider,
    deviceId: deviceId,
  );
  final controller = AppController(
    repository: repository,
    indexDatabase: index,
    captureService: CaptureService(
      settings: settings,
      parser: const DeterministicParser(),
    ),
    settingsService: settings,
    syncEngine: engine,
  );
  await controller.initialize();
  return controller;
}
