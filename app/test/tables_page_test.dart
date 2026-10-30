import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';

import 'test_support.dart';

void main() {
  testWidgets('replaces the matters page with tables and creates a note', (
    tester,
  ) async {
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(deviceId: 'tables-page-test'),
    );
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();

    // The existing home agenda remains in place.
    expect(find.text('今日安排'), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_matters')));
    await tester.pumpAndSettle();
    expect(find.text('表与笔记'), findsOneWidget);
    expect(find.text('待办'), findsWidgets);
    expect(find.text('日程'), findsWidgets);
    expect(find.text('事件'), findsWidgets);

    await tester.tap(find.byKey(const Key('create_table_button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('table_name_input')), '作业表');
    await tester.tap(find.byKey(const Key('table_name_save')));
    await tester.pumpAndSettle();
    expect(find.text('作业表'), findsWidgets);

    await tester.tap(find.byKey(const Key('table_body_edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('table_body_dialog_input')),
      '本周需要完成的课程作业。',
    );
    await tester.tap(find.byKey(const Key('table_body_dialog_save')));
    await tester.pumpAndSettle();
    expect(find.text('本周需要完成的课程作业。'), findsOneWidget);

    await tester.tap(find.byKey(const Key('table_add_content')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '笔记').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('table_entry_title')), '复习清单');
    await tester.enterText(
      find.byKey(const Key('table_entry_body')),
      '整理第三章笔记',
    );
    await tester.tap(find.byKey(const Key('table_entry_save')));
    await tester.pumpAndSettle();
    expect(find.text('复习清单'), findsOneWidget);
    expect(find.text('整理第三章笔记'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
}
