import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
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
    await _waitFor(tester, () =>
        first.tables.tables.any((table) => table.title == 'AVD 作业表'));
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
    await _waitFor(tester, () =>
        first.tables.tables.any(
          (table) =>
              table.title == 'AVD 作业表' &&
              table.body == '数字信号处理作业安排。',
        ));
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
    await _waitFor(tester, () =>
        first.tables.entries.any((entry) => entry.title == '实验报告'));
    expect(find.text('实验报告'), findsOneWidget);

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
