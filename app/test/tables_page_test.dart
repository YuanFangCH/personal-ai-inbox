import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/table_repository.dart';

import 'test_support.dart';

void main() {
  testWidgets('third-state review disables table, recovery, and field writes', (
    tester,
  ) async {
    final vault = MemoryVaultStore();
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: vault,
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(deviceId: 'table-review-ui-test'),
    );
    final deleted = await runtime.tables.createTable(title: '待恢复表');
    await runtime.tables.deleteTable(
      id: deleted.id,
      expectedRevision: deleted.revision,
    );
    final todoTable = runtime.tables.tableForInboxAssignment(
      InboxAssignmentKind.todo,
    )!;
    final entryCreatedAt = DateTime.now();
    await runtime.tables.createEntry(
      TableEntryDocument(
        id: 'td_review_ui',
        type: TableContentType.todo,
        tableId: todoTable.id,
        title: '只读待办',
        body: '',
        revision: 1,
        createdAt: entryCreatedAt,
        updatedAt: entryCreatedAt,
      ),
    );
    final beforeRaw = (await vault.read(TableRepository.inboxAssignmentsPath))!;
    final before = jsonDecode(beforeRaw) as Map<String, dynamic>;
    final expectedAssignments = Map<String, dynamic>.from(
      before['assignments'] as Map,
    )..['todo'] = 'tb_default_event';
    final after = jsonEncode({
      ...before,
      'revision': (before['revision'] as int) + 1,
      'assignments': expectedAssignments,
    });
    final externalAssignments = Map<String, dynamic>.from(
      before['assignments'] as Map,
    )..['todo'] = 'tb_default_schedule';
    await vault.write(
      TableRepository.inboxAssignmentsPath,
      jsonEncode({
        ...before,
        'revision': (before['revision'] as int) + 2,
        'assignments': externalAssignments,
      }),
    );
    await vault.write(
      TableRepository.writeJournalPath,
      jsonEncode({
        'schema_version': 2,
        'kind': 'inbox_assignments',
        'operation_id': 'act_review_ui',
        'request_signature': 'review-ui-signature',
        'before': beforeRaw,
        'after': after,
        'receipt': {
          'operation_id': 'act_review_ui',
          'kind': InboxAssignmentKind.todo.wireName,
          'previous_table_id': before['assignments']['todo'],
          'table_id': 'tb_default_event',
          'previous_revision': before['revision'],
          'revision': (before['revision'] as int) + 1,
        },
      }),
    );
    await runtime.tables.initialize();
    expect(await runtime.tables.recoveryBatches(), isNotEmpty);
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_matters')));
    await tester.pumpAndSettle();
    await _openTablesView(tester);

    expect(find.textContaining('状态待核对'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('create_table_button')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('inbox_assignments')))
          .onPressed,
      isNull,
    );
    expect(find.byTooltip('表选项'), findsNothing);
    await tester.tap(find.byKey(ValueKey('table_${todoTable.id}')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('table_add_content')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('table_body_edit')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('manage_table_fields')))
          .onPressed,
      isNull,
    );
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notebook_recycle_bin')));
    await tester.pumpAndSettle();
    expect(find.text('回收站'), findsNWidgets(2));
    expect(find.text('待恢复表'), findsOneWidget);
    await tester.tap(find.text('待恢复表'));
    await tester.pumpAndSettle();
    expect(find.text('核对后可恢复'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '核对后可恢复'))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });

  testWidgets('replaces the matters page with tables and creates a note', (
    tester,
  ) async {
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(deviceId: 'tables-page-test'),
    );
    final eventTable = runtime.tables.tables.singleWhere(
      (table) => table.role == TableRole.inboxEvent,
    );
    final noteTime = DateTime.now();
    await runtime.tables.createEntry(
      TableEntryDocument(
        id: 'nt_all_notes_page',
        type: TableContentType.note,
        tableId: eventTable.id,
        title: '迁移计划笔记',
        revision: 1,
        createdAt: noteTime,
        updatedAt: noteTime,
        body: '作业表、考试表与日历入口的说明。',
      ),
    );
    final olderNoteTime = noteTime.subtract(const Duration(days: 30));
    await runtime.tables.createEntry(
      TableEntryDocument(
        id: 'nt_older_all_notes_page',
        type: TableContentType.note,
        tableId: eventTable.id,
        title: '上月考试笔记',
        revision: 1,
        createdAt: olderNoteTime,
        updatedAt: olderNoteTime,
        body: '归档后的复习提纲。',
      ),
    );
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();

    // The existing home agenda remains in place.
    expect(find.text('今日安排'), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_matters')));
    await tester.pumpAndSettle();
    expect(find.text('全部笔记'), findsOneWidget);
    expect(find.text('2 条笔记'), findsOneWidget);
    expect(find.text('最近 7 天'), findsOneWidget);
    expect(
      find.byKey(const Key('notebook_note_nt_all_notes_page')),
      findsOneWidget,
    );
    expect(find.text('${olderNoteTime.month}月'), findsOneWidget);
    expect(
      find.byKey(const Key('notebook_note_nt_older_all_notes_page')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('notebook_note_nt_all_notes_page')));
    await tester.pumpAndSettle();
    expect(find.text('迁移计划笔记'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _openTablesView(tester);
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

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(PopupMenuButton<String>).last,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除表'));
    await tester.pumpAndSettle();
    expect(find.text('删除这张表？'), findsOneWidget);
    await tester.tap(find.text('删除表和内容'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('notebook_recycle_bin')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notebook_recycle_bin')));
    await tester.pumpAndSettle();
    expect(find.text('作业表'), findsOneWidget);
    expect(find.textContaining('1 条内容 · 剩余'), findsOneWidget);
    await tester.tap(find.text('作业表'));
    await tester.pumpAndSettle();
    expect(find.text('复习清单'), findsOneWidget);
    await tester.tap(find.text('恢复整表'));
    await tester.pumpAndSettle();
    expect(runtime.tables.tables.any((table) => table.title == '作业表'), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });

  testWidgets(
    'table list, detail and field editor fit phone tablet and desktop widths',
    (tester) async {
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(deviceId: 'table-responsive-ui'),
      );
      final table = await runtime.tables.createTable(title: '响应式考试表');
      await runtime.tables.updateTable(
        table.copyWith(
          fields: [
            TableFieldDefinition(
              id: 'fld_long_responsive',
              name: '跨页面长度较长的自定义字段名称',
              type: CustomFieldType.text,
            ),
          ],
        ),
        expectedRevision: table.revision,
      );
      await runtime.tables.createEntry(
        TableEntryDocument(
          id: 'nt_responsive',
          type: TableContentType.note,
          tableId: table.id,
          title: '带长标题的响应式条目与内容',
          revision: 1,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          body: '正文在窄屏和宽屏都能滚动读取。',
        ),
      );
      await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
      await tester.pumpAndSettle();

      for (final size in const [
        Size(320, 780),
        Size(800, 900),
        Size(1280, 900),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpAndSettle();
        if (size.width >= 1024) {
          await tester.tap(find.byKey(const Key('nav_matters')));
        } else {
          await tester.tap(find.byKey(const Key('nav_more')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('sheet_nav_matters')));
        }
        await tester.pumpAndSettle();
        await _openTablesView(tester);
        expect(find.text('响应式考试表'), findsWidgets);
        expect(tester.takeException(), isNull, reason: 'table list at $size');
        await tester.scrollUntilVisible(
          find.text('响应式考试表').last,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('响应式考试表').first);
        await tester.pumpAndSettle();
        expect(find.text('带长标题的响应式条目与内容'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'table detail at $size');
        await tester.ensureVisible(
          find.byKey(const Key('manage_table_fields')),
        );
        await tester.tap(find.byKey(const Key('manage_table_fields')));
        await tester.pumpAndSettle();
        expect(find.text('跨页面长度较长的自定义字段名称'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'field editor at $size');
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('table_add_content')));
        await tester.tap(find.byKey(const Key('table_add_content')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, '笔记').last);
        await tester.pumpAndSettle();
        final entryTitle = '窄宽屏编辑 ${size.width.toInt()}';
        await tester.enterText(
          find.byKey(const Key('table_entry_title')),
          entryTitle,
        );
        await tester.enterText(
          find.byKey(const Key('table_entry_body')),
          '编辑器在宽度 ${size.width.toInt()} 下保持可滚动。',
        );
        await tester.tap(find.byKey(const Key('table_entry_save')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        if (find.text('发现可能重复的内容').evaluate().isNotEmpty) {
          await tester.tap(find.byKey(const Key('manual_duplicate_keep_both')));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        }
        expect(find.text(entryTitle), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'entry editor at $size');
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      await runtime.shutdown();
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );

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
    await _openTablesView(tester);
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

  testWidgets(
    'manual editor shows local exact duplicates and reuses the existing entry',
    (tester) async {
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(deviceId: 'manual-dedupe-ui'),
      );
      final table = await runtime.tables.createTable(title: '手工查重表');
      final now = DateTime.now();
      await runtime.tables.createEntry(
        TableEntryDocument(
          id: 'nt_manual_ui_original',
          type: TableContentType.note,
          tableId: table.id,
          title: '重复笔记',
          revision: 1,
          createdAt: now,
          updatedAt: now,
          body: '这是一条完全相同的本地记录。',
        ),
      );
      await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet_nav_matters')));
      await tester.pumpAndSettle();
      await _openTablesView(tester);
      await tester.ensureVisible(find.text('手工查重表').last);
      await tester.tap(find.text('手工查重表').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('table_add_content')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '笔记').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('table_entry_title')),
        '重复笔记',
      );
      await tester.enterText(
        find.byKey(const Key('table_entry_body')),
        '这是一条完全相同的本地记录。',
      );
      await tester.tap(find.byKey(const Key('table_entry_save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('发现可能重复的内容'), findsOneWidget);
      expect(find.textContaining('完全相同 ·'), findsOneWidget);
      await tester.tap(find.byKey(const Key('manual_duplicate_reuse')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        await runtime.tables.readEntry('nt_manual_ui_original'),
        isNotNull,
      );
      expect(
        runtime.tables.entries.where((entry) => entry.title == '重复笔记'),
        hasLength(1),
      );
      expect(find.textContaining('未新增条目'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
    },
  );

  testWidgets('manual duplicate review can retain both with its credential', (
    tester,
  ) async {
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(deviceId: 'manual-keep-both-ui'),
    );
    final table = await runtime.tables.createTable(title: '保留两条测试表');
    final now = DateTime.now();
    await runtime.tables.createEntry(
      TableEntryDocument(
        id: 'nt_keep_both_original',
        type: TableContentType.note,
        tableId: table.id,
        title: '信号系统考试范围',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '周五复习信号系统第二章。',
      ),
    );
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_matters')));
    await tester.pumpAndSettle();
    await _openTablesView(tester);
    await tester.ensureVisible(find.text('保留两条测试表').last);
    await tester.tap(find.text('保留两条测试表').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('table_add_content')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '笔记').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('table_entry_title')),
      '信号系统考试范围',
    );
    await tester.enterText(
      find.byKey(const Key('table_entry_body')),
      '周五复习信号系统第二章，并补充第三章。',
    );
    await tester.tap(find.byKey(const Key('table_entry_save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('发现可能重复的内容'), findsOneWidget);
    await tester.tap(find.byKey(const Key('manual_duplicate_keep_both')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final entries = runtime.tables.entries
        .where((entry) => entry.title == '信号系统考试范围')
        .toList(growable: false);
    expect(entries, hasLength(2));
    final added = entries.singleWhere(
      (entry) => entry.id != 'nt_keep_both_original',
    );
    final credential =
        added.extensionFields['manual_duplicate_exception'] as Map;
    expect(credential['decision'], 'keep_both');
    expect(
      (credential['candidates'] as List).single['id'],
      'nt_keep_both_original',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
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
    await _openTablesView(tester);
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

  testWidgets('legacy drafts remain readable and can be copied into a table', (
    tester,
  ) async {
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(deviceId: 'legacy-draft-route'),
    );
    final draft = await runtime.results.createManual(
      type: ResultType.knowledge,
      title: '旧草稿复习计划',
      body: '周三整理考试资料。',
      status: ResultStatus.draft,
    );
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_matters')));
    await tester.pumpAndSettle();
    expect(find.text('旧格式草稿'), findsOneWidget);
    await tester.tap(find.byKey(Key('legacy_draft_copy_${draft.id}')));
    await tester.pumpAndSettle();
    final copied = runtime.tables.entries.singleWhere(
      (entry) => entry.extensionFields['legacy_source_id'] == draft.id,
    );
    expect(copied.type, TableContentType.note);
    expect(copied.body, draft.body);
    expect(runtime.results.findDocument(draft.id)!.status, ResultStatus.draft);
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });

  testWidgets('table search finds entry titles and body across tables', (
    tester,
  ) async {
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(deviceId: 'table-entry-search-ui'),
    );
    final table = runtime.tables.tables.singleWhere(
      (item) => item.role == TableRole.inboxEvent,
    );
    await runtime.tables.createEntry(
      TableEntryDocument(
        id: 'nt_search_entry_ui',
        type: TableContentType.note,
        tableId: table.id,
        title: '期中考试资料',
        revision: 1,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        body: '查找关键词：滨海教室。',
      ),
    );
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_matters')));
    await tester.pumpAndSettle();
    await _openTablesView(tester);
    await tester.enterText(find.byType(TextField).first, '滨海教室');
    await tester.pumpAndSettle();
    expect(find.text('期中考试资料'), findsOneWidget);
    expect(
      find.byKey(const Key('table_search_entry_nt_search_entry_ui')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('table_search_entry_nt_search_entry_ui')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('table_entry_title')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('table_entry_title')))
          .controller!
          .text,
      '期中考试资料',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
}

Future<void> _openTablesView(WidgetTester tester) async {
  final toggle = find.byKey(const Key('notebook_show_tables'));
  if (toggle.evaluate().isNotEmpty) {
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  }
}
