import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';

import 'test_support.dart';

void main() {
  testWidgets('global knowledge management confirms add, edit and delete', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(deviceId: 'global-knowledge-page'),
    );
    addTearDown(runtime.dispose);
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_settings')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('settings_global_knowledge')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_global_knowledge')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('global_knowledge_add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '秋季学期');
    await tester.enterText(find.byType(TextField).at(1), '用于计算教学周数。');
    await tester.enterText(
      find.byType(TextField).at(2),
      '{"semester_start":"2026-09-01","week_count":16}',
    );
    await tester.tap(find.byKey(const Key('global_knowledge_confirm_save')));
    await tester.pumpAndSettle();

    var document = runtime.results.knowledge.single;
    expect(document.isGlobalKnowledge, isTrue);
    expect(document.revision, 1);
    expect(find.text('秋季学期'), findsOneWidget);

    await tester.tap(find.byTooltip('修改'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '本学期共有 17 周。');
    await tester.enterText(
      find.byType(TextField).at(2),
      '{"semester_start":"2026-09-01","week_count":17}',
    );
    await tester.tap(find.byKey(const Key('global_knowledge_confirm_save')));
    await tester.pumpAndSettle();
    document = runtime.results.knowledge.single;
    expect(document.revision, 2);
    expect(document.body, '本学期共有 17 周。');

    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect((await runtime.results.readDocument(document.id))?.deleted, isTrue);
    expect(runtime.results.knowledge, isEmpty);
  });
}
