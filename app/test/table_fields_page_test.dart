import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';

import 'test_support.dart';

void main() {
  testWidgets('adds a per-table text field and stores its entry value', (
    tester,
  ) async {
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(deviceId: 'table-field-test'),
    );
    final table = await runtime.tables.createTable(title: '课程表');

    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_matters')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('课程表'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('课程表').first);
    await tester.pumpAndSettle();
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

    final field = runtime.tables.findTable(table.id)!.fields.single;
    expect(field.name, '课程');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('table_add_content')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('table_add_content')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '笔记').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('table_entry_title')), '期末复习');
    await tester.enterText(find.byKey(const Key('table_entry_body')), '复习内容');
    await tester.enterText(
      find.byKey(ValueKey('custom_field_${field.id}')),
      '信号与系统',
    );
    await tester.tap(find.byKey(const Key('table_entry_save')));
    await tester.pumpAndSettle();

    final entry = runtime.tables.entries.singleWhere(
      (candidate) => candidate.title == '期末复习',
    );
    expect(entry.customValues[field.id], '信号与系统');

    await tester.scrollUntilVisible(
      find.byKey(const Key('manage_table_fields')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('manage_table_fields')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除字段'));
    await tester.pumpAndSettle();
    expect(find.text('删除字段？'), findsOneWidget);
    await tester.tap(find.text('删除字段和值'));
    await tester.pumpAndSettle();
    expect(runtime.tables.findTable(table.id)!.fields, isEmpty);
    expect(runtime.tables.entries.single.customValues, isEmpty);
    expect(find.text('可撤销的字段删除'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(runtime.tables.findTable(table.id)!.fields.single.id, field.id);
    expect(runtime.tables.entries.single.customValues[field.id], '信号与系统');

    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });

  testWidgets('edits number, select, multi-select and checkbox field values', (
    tester,
  ) async {
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(
        deviceId: 'table-field-values-test',
      ),
    );
    final table = await runtime.tables.createTable(title: '考试资料');
    await runtime.tables.updateTable(
      table.copyWith(
        fields: [
          TableFieldDefinition(
            id: 'fld_score',
            name: '分数',
            type: CustomFieldType.number,
          ),
          TableFieldDefinition(
            id: 'fld_exam_date',
            name: '考试日期',
            type: CustomFieldType.date,
          ),
          TableFieldDefinition(
            id: 'fld_kind',
            name: '科目',
            type: CustomFieldType.singleSelect,
            options: const [
              TableFieldOption(id: 'math', label: '数学'),
              TableFieldOption(id: 'signals', label: '信号与系统'),
            ],
          ),
          TableFieldDefinition(
            id: 'fld_materials',
            name: '资料',
            type: CustomFieldType.multiSelect,
            options: const [
              TableFieldOption(id: 'notes', label: '笔记'),
              TableFieldOption(id: 'past_papers', label: '历年卷'),
            ],
          ),
          TableFieldDefinition(
            id: 'fld_ready',
            name: '已准备',
            type: CustomFieldType.checkbox,
          ),
        ],
      ),
      expectedRevision: table.revision,
    );

    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_matters')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('考试资料'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('考试资料').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('table_add_content')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '笔记').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('table_entry_title')), '考试卡片');
    await tester.enterText(find.byKey(const Key('table_entry_body')), '考前复习');
    await tester.enterText(
      find.byKey(const ValueKey('custom_field_fld_score')),
      '98.5',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('custom_field_fld_exam_date')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byTooltip('选择时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('custom_field_fld_kind')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('custom_field_fld_kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('信号与系统').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '历年卷'));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('custom_field_fld_ready')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('custom_field_fld_ready')));
    await tester.tap(find.byKey(const Key('table_entry_save')));
    await tester.pumpAndSettle();

    final values = runtime.tables.entries.single.customValues;
    expect(values['fld_score'], 98.5);
    expect(DateTime.tryParse(values['fld_exam_date'] as String), isNotNull);
    expect(values['fld_kind'], 'signals');
    expect(values['fld_materials'], ['past_papers']);
    expect(values['fld_ready'], isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });

  testWidgets('creates select field options and renames without changing IDs', (
    tester,
  ) async {
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(
        deviceId: 'table-field-schema-test',
      ),
    );
    final table = await runtime.tables.createTable(title: '字段定义');
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_matters')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(table.title),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(table.title).first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('manage_table_fields')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('manage_table_fields')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add_table_field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('table_field_name')), '考试科目');
    await tester.tap(find.byKey(const Key('table_field_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('单选').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('table_field_options')),
      '数学\n信号与系统',
    );
    await tester.tap(find.byKey(const Key('table_field_save')));
    await tester.pumpAndSettle();
    final original = runtime.tables.findTable(table.id)!.fields.single;
    expect(original.type, CustomFieldType.singleSelect);
    expect(original.options.map((option) => option.label), ['数学', '信号与系统']);

    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('table_field_rename_name')),
      '科目',
    );
    await tester.tap(find.byKey(const Key('table_field_rename_save')));
    await tester.pumpAndSettle();
    final renamed = runtime.tables.findTable(table.id)!.fields.single;
    expect(renamed.id, original.id);
    expect(renamed.name, '科目');
    expect(
      renamed.options.map((option) => option.id),
      original.options.map((option) => option.id),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
}
