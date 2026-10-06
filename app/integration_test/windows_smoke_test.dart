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

  testWidgets('Windows desktop renderer survives the full navigation smoke', (
    tester,
  ) async {
    final controller = await _controller();
    await tester.pumpWidget(PersonalAiInboxApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (final key in const [
      'nav_inbox',
      'nav_calendar',
      'nav_todos',
      'nav_matters',
      'nav_knowledge',
      'nav_review',
      'nav_sync',
      'nav_settings',
      'nav_home',
    ]) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      final scrollables = find.byType(Scrollable);
      if (scrollables.evaluate().isNotEmpty) {
        await tester.drag(scrollables.first, const Offset(0, -500));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull, reason: 'page $key');
    }

    await tester.tap(find.byKey(const Key('capture_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('capture_text_field')),
      '明天下午三点提醒我交材料',
    );
    await tester.tap(find.byKey(const Key('capture_submit')));
    await tester.pumpAndSettle();

    expect(controller.documents, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<AppController> _controller() async {
  final vault = MemoryVaultStore();
  final index = MemoryIndexDatabase();
  final settings = FakeSettingsService(deviceId: 'win-desktop');
  final repository = ResultRepository(
    vault: vault,
    index: index,
    deviceId: 'win-desktop',
  );
  await repository.initialize();
  await repository.create(
    type: ResultType.knowledge,
    title: 'Windows 长文',
    body: List.filled(80, '这是 Windows 桌面渲染的长文本压力内容。').join(),
  );
  final provider = MemorySyncProvider();
  final engine = SyncEngine(
    repository: repository,
    provider: provider,
    deviceId: 'win-desktop',
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
