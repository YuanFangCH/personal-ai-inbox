import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/table_repository.dart';
import 'package:personal_ai_inbox/modules/home_widgets/home_widget_contract.dart';
import 'package:personal_ai_inbox/modules/home_widgets/home_widget_projection.dart';

void main() {
  final now = DateTime(2026, 11, 10, 8);

  test('filters by type, todo state, and local business-day window', () {
    final table = _table(
      id: 'tb_work',
      title: '作业',
      fields: [
        TableFieldDefinition(
          id: 'fld_course',
          name: '课程',
          type: CustomFieldType.text,
        ),
      ],
    );
    final entries = [
      _entry(
        id: 'todo_open',
        tableId: table.id,
        type: TableContentType.todo,
        title: '提交练习',
        due: DateTime(2026, 11, 10, 10),
        customValues: const {'fld_course': '数学'},
      ),
      _entry(
        id: 'todo_done',
        tableId: table.id,
        type: TableContentType.todo,
        title: '已完成',
        due: DateTime(2026, 11, 10, 11),
        done: true,
      ),
      _entry(
        id: 'schedule_today',
        tableId: table.id,
        type: TableContentType.schedule,
        title: '今日课程',
        start: DateTime(2026, 11, 10, 12),
      ),
      _entry(
        id: 'todo_tomorrow',
        tableId: table.id,
        type: TableContentType.todo,
        title: '明日截止',
        due: DateTime(2026, 11, 11, 9),
      ),
      _entry(
        id: 'note_untimed',
        tableId: table.id,
        type: TableContentType.note,
        title: '普通笔记',
      ),
    ];
    final card = CardDefinition(
      cardId: 'card_work',
      revision: 1,
      archived: false,
      visibility: WidgetVisibility.fields,
      spec: CardSpec(
        title: '学习总览',
        sections: [
          SectionSpec(
            tableId: table.id,
            types: const [TableContentType.todo],
            todoState: WidgetTodoState.open,
            daysAhead: 1,
            sort: const WidgetSort(
              key: WidgetSortKey.businessTime,
              direction: WidgetSortDirection.asc,
            ),
            limit: 4,
            fields: [
              const WidgetField.builtin(WidgetBuiltinField.time),
              WidgetField.custom('fld_course'),
            ],
          ),
        ],
      ),
    );

    final projection = projectCardDetails(
      card,
      source: _source([table], entries),
      localNow: now,
    );

    expect(projection.matchingCount, 1);
    expect(projection.snapshot.dataDay, '2026-11-10');
    expect(projection.snapshot.rows, hasLength(2));
    final row = projection.snapshot.rows.last;
    expect(row.entryId, 'todo_open');
    expect(row.detail, contains('2026-11-10 10:00'));
    expect(row.detail, contains('课程: 数学'));
  });

  test('projectCard enforces hidden and titles visibility itself', () {
    final table = _table(id: 'tb_work', title: '作业');
    final entry = _entry(
      id: 'todo_1',
      tableId: table.id,
      type: TableContentType.todo,
      title: '提交练习',
      due: DateTime(2026, 11, 10, 20),
    );
    final source = _source([table], [entry]);
    final baseSpec = CardSpec(
      title: '学习',
      sections: [SectionSpec(tableId: table.id, limit: 4)],
    );

    final hidden = projectCard(
      CardDefinition(
        cardId: 'hidden',
        revision: 1,
        archived: false,
        visibility: WidgetVisibility.hidden,
        spec: baseSpec,
      ),
      source: source,
      localNow: now,
    );
    final titles = projectCard(
      CardDefinition(
        cardId: 'titles',
        revision: 1,
        archived: false,
        visibility: WidgetVisibility.titles,
        spec: baseSpec,
      ),
      source: source,
      localNow: now,
    );

    expect(hidden.rows, isEmpty);
    expect(hidden.title, '桌面小组件');
    expect(hidden.dataDay, isNull);
    expect(titles.rows.last.title, '提交练习');
    expect(titles.rows.last.detail, isNull);
  });

  test('sets data day only when a section uses days_ahead', () {
    final table = _table(id: 'tb_work', title: '作业');
    final card = CardDefinition(
      cardId: 'card_work',
      revision: 1,
      archived: false,
      spec: CardSpec(
        title: '学习',
        sections: [SectionSpec(tableId: table.id)],
      ),
    );

    final snapshot = projectCard(
      card,
      source: _source([table], const []),
      localNow: now,
    );

    expect(snapshot.dataDay, isNull);
  });

  test('caps at 48 rows, retains every section header, and marks hasMore', () {
    final tables = [
      for (var index = 0; index < 7; index++)
        _table(id: 'tb_$index', title: '表 $index'),
    ];
    final entries = [
      for (final table in tables)
        for (var index = 0; index < 10; index++)
          _entry(
            id: '${table.id}_todo_$index',
            tableId: table.id,
            type: TableContentType.todo,
            title: '事项 $index',
          ),
    ];
    final card = CardDefinition(
      cardId: 'card_all',
      revision: 1,
      archived: false,
      spec: CardSpec(
        title: '全部',
        sourceMode: WidgetSourceMode.allTables,
        sections: [
          for (final table in tables) SectionSpec(tableId: table.id, limit: 10),
        ],
      ),
    );

    final snapshot = projectCard(
      card,
      source: _source(tables, entries),
      localNow: now,
    );

    expect(snapshot.rows, hasLength(48));
    expect(snapshot.hasMore, isTrue);
    expect(
      snapshot.rows.where((row) => row.kind == WidgetRowKind.section),
      hasLength(7),
    );
  });

  test('returns Chinese warnings for removed tables and fields', () {
    final table = _table(id: 'tb_work', title: '作业');
    final card = CardDefinition(
      cardId: 'card_work',
      revision: 1,
      archived: false,
      spec: CardSpec(
        title: '学习',
        sections: [
          SectionSpec(
            tableId: table.id,
            fields: [WidgetField.custom('fld_missing')],
          ),
          SectionSpec(tableId: 'tb_deleted'),
        ],
      ),
    );

    final projection = projectCardDetails(
      card,
      source: _source([table], const []),
      localNow: now,
    );

    expect(projection.warnings, hasLength(2));
    expect(projection.warnings.first, contains('字段'));
    expect(projection.warnings.last, contains('已删除或不可用'));
  });

  test('trims the envelope to 512 KiB from the last card first', () {
    final cards = [
      for (var cardIndex = 0; cardIndex < 3; cardIndex++)
        WidgetSnapshot(
          cardId: 'card_$cardIndex',
          revision: 1,
          title: '卡片 $cardIndex',
          theme: WidgetTheme.system,
          state: WidgetCardState.ready,
          generatedAtMs: now.millisecondsSinceEpoch,
          dataDay: null,
          rows: [
            for (var rowIndex = 0; rowIndex < 16; rowIndex++)
              WidgetRow.entry(
                tableId: 'tb',
                entryId: 'entry_$rowIndex',
                title: '事项 $rowIndex',
                detail: 'x' * 24000,
              ),
          ],
          hasMore: false,
        ),
    ];

    final constrained = constrainWidgetSnapshots(cards);
    final bytes = utf8.encode(constrained.toJsonString()).length;

    expect(bytes, lessThanOrEqualTo(512 * 1024));
    expect(constrained.cards.any((card) => card.hasMore), isTrue);
    expect(constrained.cards.every((card) => card.rows.length <= 48), isTrue);
  });
}

TableDocument _table({
  required String id,
  required String title,
  List<TableFieldDefinition> fields = const [],
}) => TableDocument(
  id: id,
  role: TableRole.custom,
  title: title,
  revision: 1,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 9),
  body: '',
  fields: fields,
);

TableEntryDocument _entry({
  required String id,
  required String tableId,
  required TableContentType type,
  required String title,
  DateTime? due,
  DateTime? start,
  bool done = false,
  Map<String, Object?> customValues = const {},
}) => TableEntryDocument(
  id: id,
  tableId: tableId,
  type: type,
  title: title,
  revision: 1,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 9),
  body: '',
  due: due,
  start: start,
  done: done,
  customValues: customValues,
);

TableContentSnapshot _source(
  List<TableDocument> tables,
  List<TableEntryDocument> entries,
) => TableContentSnapshot(
  tables: tables,
  entries: entries,
  signature: 'signature',
);
