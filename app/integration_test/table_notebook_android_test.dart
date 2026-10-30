import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/io_vault_store.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/sqlite_index_database.dart';

import '../test/test_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('creates a notebook table and note, then reopens them', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('table-notebook-ui');
    addTearDown(() => root.delete(recursive: true));
    final vault = IoVaultStore.at(Directory('${root.path}/vault'));
    final indexPath = '${root.path}/index.sqlite3';
    final firstIndex = SqliteIndexDatabase(indexPath);
    await firstIndex.open();
    final first = await AppRuntime.bootstrap(
      vaultOverride: vault,
      indexOverride: firstIndex,
      conversationStoreOverride: MemoryConversationStore(),
      attachmentStoreOverride: MemoryAttachmentStore(),
      settingsOverride: FakeSettingsService(deviceId: 'notebook-android-test'),
    );
    await tester.pumpWidget(PersonalAiInboxApp(runtime: first));
    await tester.pumpAndSettle();
    expect(find.text('今日安排'), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_matters')));
    await tester.pumpAndSettle();
    expect(find.text('表与笔记'), findsOneWidget);
    await tester.tap(find.byKey(const Key('capture_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('capture_text_field')),
      '2020年10月1日 09:00 老师调整了考试范围',
    );
    await tester.tap(find.byKey(const Key('capture_submit')));
    await _waitFor(
      tester,
      () => first.tables.entries.any(
        (entry) =>
            entry.type == TableContentType.event &&
            entry.body.contains('老师调整了考试范围'),
      ),
    );
    final capturedEvent = first.tables.entries.singleWhere(
      (entry) => entry.body.contains('老师调整了考试范围'),
    );
    expect(capturedEvent.type, TableContentType.event);
    expect(capturedEvent.occurredAt, isNotNull);

    await tester.tap(find.byKey(const Key('create_table_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('table_name_input')),
      'AVD 作业表',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('table_name_input')))
          .controller
          ?.text,
      'AVD 作业表',
    );
    await tester.tap(find.byKey(const Key('table_name_save')));
    await _waitFor(
      tester,
      () => first.tables.tables.any((table) => table.title == 'AVD 作业表'),
    );
    expect(
      first.tables.tables.any((table) => table.title == 'AVD 作业表'),
      isTrue,
      reason: tester.takeException()?.toString(),
    );
    if (find.byKey(const Key('table_body_edit')).evaluate().isEmpty) {
      expect(find.text('AVD 作业表'), findsOneWidget);
      await tester.tap(find.text('AVD 作业表'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('table_body_edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('table_body_dialog_input')),
      '数字信号处理作业安排。',
    );
    await tester.tap(find.byKey(const Key('table_body_dialog_save')));
    await _waitFor(
      tester,
      () => first.tables.tables.any(
        (table) => table.title == 'AVD 作业表' && table.body == '数字信号处理作业安排。',
      ),
    );
    await tester.tap(find.byKey(const Key('table_add_content')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '笔记').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('table_entry_title')), '实验报告');
    await tester.enterText(
      find.byKey(const Key('table_entry_body')),
      '提交前检查图表。',
    );
    await tester.tap(find.byKey(const Key('table_entry_save')));
    await _waitFor(
      tester,
      () => first.tables.entries.any((entry) => entry.title == '实验报告'),
    );
    expect(find.text('实验报告'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('manage_table_fields')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('manage_table_fields')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add_table_field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('table_field_name')), '课程');
    await tester.tap(find.byKey(const Key('table_field_save')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('实验报告'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('实验报告').last);
    await tester.pumpAndSettle();
    final fieldId = first.tables.tables
        .singleWhere((candidate) => candidate.title == 'AVD 作业表')
        .fields
        .single
        .id;
    await tester.enterText(
      find.byKey(ValueKey('custom_field_$fieldId')),
      '信号与系统',
    );
    await tester.tap(find.byKey(const Key('table_entry_save')));
    await _waitFor(
      tester,
      () => first.tables.entries.any(
        (entry) => entry.customValues[fieldId] == '信号与系统',
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await first.shutdown();

    final secondIndex = SqliteIndexDatabase(indexPath);
    await secondIndex.open();
    final reopened = await AppRuntime.bootstrap(
      vaultOverride: IoVaultStore.at(Directory('${root.path}/vault')),
      indexOverride: secondIndex,
      conversationStoreOverride: MemoryConversationStore(),
      attachmentStoreOverride: MemoryAttachmentStore(),
      settingsOverride: FakeSettingsService(deviceId: 'notebook-android-test'),
    );
    final table = reopened.tables.tables.singleWhere(
      (candidate) => candidate.title == 'AVD 作业表',
    );
    expect(table.body, '数字信号处理作业安排。');
    expect(
      reopened.tables.entries
          .singleWhere((entry) => entry.title == '实验报告')
          .body,
      '提交前检查图表。',
    );
    final reopenedFieldId = reopened.tables
        .findTable(table.id)!
        .fields
        .single
        .id;
    expect(
      reopened.tables.entries
          .singleWhere((entry) => entry.title == '实验报告')
          .customValues[reopenedFieldId],
      '信号与系统',
    );

    await tester.pumpWidget(PersonalAiInboxApp(runtime: reopened));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('home_add_table_module')));
    await tester.tap(find.byKey(const Key('home_add_table_module')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AVD 作业表').last);
    await tester.pumpAndSettle();
    expect(reopened.preferences.settings.homeTableOrder, [table.id]);

    await reopened.preferences.update(calendarVisibleTableIds: [table.id]);
    await tester.tap(find.byKey(const Key('nav_calendar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar_quick_create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('table_entry_title')),
      'AVD 考试安排',
    );
    await tester.tap(find.byKey(const Key('table_entry_save')));
    await _waitFor(
      tester,
      () => reopened.tables.entries.any(
        (entry) => entry.title == 'AVD 考试安排' && entry.tableId == table.id,
      ),
    );
    expect(find.text('AVD 考试安排'), findsWidgets);

    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_matters')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(PopupMenuButton<String>).last,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除表和内容'));
    await _waitFor(tester, () => reopened.tables.findTable(table.id) == null);
    await tester.tap(find.text('回收站'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AVD 作业表'));
    await tester.pumpAndSettle();
    expect(find.text('实验报告'), findsOneWidget);
    await tester.tap(find.text('恢复整表'));
    await _waitFor(tester, () => reopened.tables.findTable(table.id) != null);
    expect(
      reopened.tables.entries.any((entry) => entry.title == '实验报告'),
      isTrue,
    );
    await reopened.shutdown();
  });
}

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Timed out waiting for app vault write.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  await tester.pumpAndSettle();
}
