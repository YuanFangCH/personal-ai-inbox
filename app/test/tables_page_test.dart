import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
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

  testWidgets('moves a note between tables without changing its identity', (
    tester,
  ) async {
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(deviceId: 'table-move-test'),
    );
    final source = await runtime.tables.createTable(title: '作业表');
    final target = await runtime.tables.createTable(title: '考试表');
    final now = DateTime.now();
    final note = await runtime.tables.createEntry(
      TableEntryDocument(
        id: 'nt_move_test',
        type: TableContentType.note,
        tableId: source.id,
        title: '课程安排',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '转移后保留同一个 ID',
      ),
    );

    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_matters')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('作业表'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('作业表').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程安排').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('move_table_entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('考试表').last);
    await tester.pumpAndSettle();

    final moved = runtime.tables.entries.singleWhere(
      (entry) => entry.id == note.id,
    );
    expect(moved.id, note.id);
    expect(moved.tableId, target.id);
    expect(moved.body, note.body);
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });

  testWidgets('blocks field-losing moves and allows compatible field moves', (
    tester,
  ) async {
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(deviceId: 'table-field-move-test'),
    );
    final source = await runtime.tables.createTable(title: '课程表');
    final withField = source.copyWith(
      fields: [
        TableFieldDefinition(
          id: 'fld_course',
          name: '课程',
          type: CustomFieldType.text,
        ),
      ],
    );
    await runtime.tables.updateTable(
      withField,
      expectedRevision: source.revision,
    );
    final compatible = await runtime.tables.createTable(title: '复习表');
    await runtime.tables.updateTable(
      compatible.copyWith(
        fields: [
          TableFieldDefinition(
            id: 'fld_course_target',
            name: '课程信息',
            type: CustomFieldType.text,
          ),
        ],
      ),
      expectedRevision: compatible.revision,
    );
    final incompatible = await runtime.tables.createTable(title: '归档表');
    final now = DateTime.now();
    final note = await runtime.tables.createEntry(
      TableEntryDocument(
        id: 'nt_field_move',
        type: TableContentType.note,
        tableId: source.id,
        title: '复习安排',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '保留字段值',
        customValues: const {'fld_course': '信号与系统'},
      ),
    );

    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_matters')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('课程表'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('课程表').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('复习安排').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('move_table_entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('归档表').last);
    await tester.pumpAndSettle();
    expect(find.text('目标表字段不兼容'), findsOneWidget);
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(runtime.tables.entries.single.tableId, source.id);
    expect(runtime.tables.findTable(incompatible.id)?.title, '归档表');

    await tester.tap(find.byKey(const Key('move_table_entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复习表').last);
    await tester.pumpAndSettle();
    expect(find.text('映射自定义字段'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('map_field_fld_course')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程信息').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_field_mapping')));
    await tester.pumpAndSettle();
    final moved = runtime.tables.entries.single;
    expect(moved.id, note.id);
    expect(moved.tableId, compatible.id);
    expect(moved.customValues['fld_course_target'], '信号与系统');
    expect(find.text('复习表'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
}
