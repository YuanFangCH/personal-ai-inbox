import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/table_markdown_codec.dart';
import 'package:personal_ai_inbox/core/table_models.dart';

void main() {
  const codec = TableMarkdownCodec();
  final created = DateTime.parse('2026-10-29T09:00:00+08:00');

  test('round trips a table body and stable custom-field definitions', () {
    final table = TableDocument(
      id: 'tb_homework',
      role: TableRole.custom,
      title: '作业',
      revision: 2,
      createdAt: created,
      updatedAt: created,
      body: '本学期作业记录',
      fields: [
        TableFieldDefinition(
          id: 'fld_course',
          name: '课程',
          type: CustomFieldType.singleSelect,
          options: const [TableFieldOption(id: 'signals', label: '信号与系统')],
        ),
        TableFieldDefinition(
          id: 'fld_checked',
          name: '已提交',
          type: CustomFieldType.checkbox,
        ),
      ],
    );

    final decoded = codec.decodeTable(codec.encodeTable(table));

    expect(decoded.id, table.id);
    expect(decoded.role, table.role);
    expect(decoded.body, table.body);
    expect(decoded.fields.first.id, 'fld_course');
    expect(decoded.fields.first.options.single.label, '信号与系统');
  });

  test('round trips todo deadline without changing its type', () {
    final todo = TableEntryDocument(
      id: 'td_homework',
      type: TableContentType.todo,
      tableId: 'tb_homework',
      title: '交作业',
      revision: 1,
      createdAt: created,
      updatedAt: created,
      body: '',
      due: DateTime.parse('2026-10-30T23:00:00+08:00'),
      customValues: const {'fld_checked': false},
    );
    final fields = [
      TableFieldDefinition(
        id: 'fld_checked',
        name: '已提交',
        type: CustomFieldType.checkbox,
      ),
    ];

    final decoded = codec.decodeEntry(codec.encodeEntry(todo, fields: fields));

    expect(decoded.type, TableContentType.todo);
    expect(decoded.due!.isAtSameMomentAs(todo.due!), isTrue);
    expect(decoded.customValues['fld_checked'], isFalse);
  });

  test('round trips an event that affects its original schedule', () {
    final event = TableEntryDocument(
      id: 'ev_exam_moved',
      type: TableContentType.event,
      tableId: 'tb_exam',
      title: '考试改期通知',
      revision: 1,
      createdAt: created,
      updatedAt: created,
      body: '老师将考试改到周一',
      occurredAt: created,
      affects: const [ScheduleChange(scheduleId: 'sc_exam', summary: '周五改至周一')],
    );

    final decoded = codec.decodeEntry(codec.encodeEntry(event));

    expect(decoded.type, TableContentType.event);
    expect(decoded.affects.single.scheduleId, 'sc_exam');
    expect(decoded.affects.single.summary, '周五改至周一');
  });

  test('preserves unknown extension fields during table and entry edits', () {
    const rawTable = '''
---
id: tb_extensions
type: table
role: custom
title: Extensions
revision: 1
created_at: 2026-10-29T09:00:00+08:00
updated_at: 2026-10-29T09:00:00+08:00
future_table_flag:
  source: imported
---
Table body
''';
    const rawEntry = '''
---
id: nt_extensions
type: note
table_id: tb_extensions
title: Extensions
revision: 1
created_at: 2026-10-29T09:00:00+08:00
updated_at: 2026-10-29T09:00:00+08:00
future_entry_flag: [one, two]
---
Entry body
''';

    final table = codec.decodeTable(rawTable);
    final entry = codec.decodeEntry(rawEntry);
    final savedTable = codec.decodeTable(codec.encodeTable(table));
    final savedEntry = codec.decodeEntry(codec.encodeEntry(entry));

    expect(savedTable.extensionFields['future_table_flag'], {
      'source': 'imported',
    });
    expect(savedEntry.extensionFields['future_entry_flag'], ['one', 'two']);
  });

  test('rejects invalid custom values and unknown field ids', () {
    final entry = TableEntryDocument(
      id: 'nt_bad',
      type: TableContentType.note,
      tableId: 'tb_homework',
      title: '笔记',
      revision: 1,
      createdAt: created,
      updatedAt: created,
      body: '正文',
      customValues: const {'fld_course': 'not-an-option'},
    );
    final fields = [
      TableFieldDefinition(
        id: 'fld_course',
        name: '课程',
        type: CustomFieldType.singleSelect,
        options: const [TableFieldOption(id: 'signals', label: '信号与系统')],
      ),
    ];

    expect(
      () => codec.encodeEntry(entry, fields: fields),
      throwsFormatException,
    );
    expect(
      () => codec.encodeEntry(
        TableEntryDocument(
          id: entry.id,
          type: entry.type,
          tableId: entry.tableId,
          title: entry.title,
          revision: entry.revision,
          createdAt: entry.createdAt,
          updatedAt: entry.updatedAt,
          body: entry.body,
          customValues: const {'unknown_field': 'value'},
        ),
        fields: fields,
      ),
      throwsFormatException,
    );
  });

  test(
    'validates field types and required values without collapsing false',
    () {
      final falseValue = TableEntryDocument(
        id: 'nt_false',
        type: TableContentType.note,
        tableId: 'tb_homework',
        title: 'False is a value',
        revision: 1,
        createdAt: created,
        updatedAt: created,
        body: '',
        customValues: const {'fld_checked': false},
      );
      final checkbox = TableFieldDefinition(
        id: 'fld_checked',
        name: '已提交',
        type: CustomFieldType.checkbox,
        required: true,
      );
      expect(
        codec
            .decodeEntry(codec.encodeEntry(falseValue, fields: [checkbox]))
            .customValues['fld_checked'],
        isFalse,
      );

      final missingValue = TableEntryDocument(
        id: 'nt_missing',
        type: TableContentType.note,
        tableId: 'tb_homework',
        title: 'Missing checkbox',
        revision: 1,
        createdAt: created,
        updatedAt: created,
        body: '',
      );
      expect(
        () => codec.encodeEntry(missingValue, fields: [checkbox]),
        throwsFormatException,
      );
    },
  );

  test('round trips all six custom field value types', () {
    final fields = [
      TableFieldDefinition(
        id: 'fld_text',
        name: '章节',
        type: CustomFieldType.text,
      ),
      TableFieldDefinition(
        id: 'fld_number',
        name: '分数',
        type: CustomFieldType.number,
      ),
      TableFieldDefinition(
        id: 'fld_date',
        name: '提交日',
        type: CustomFieldType.date,
      ),
      TableFieldDefinition(
        id: 'fld_single',
        name: '课程',
        type: CustomFieldType.singleSelect,
        options: const [TableFieldOption(id: 'signals', label: '信号与系统')],
      ),
      TableFieldDefinition(
        id: 'fld_multi',
        name: '标签',
        type: CustomFieldType.multiSelect,
        options: const [
          TableFieldOption(id: 'read', label: '阅读'),
          TableFieldOption(id: 'write', label: '写作'),
        ],
      ),
      TableFieldDefinition(
        id: 'fld_checkbox',
        name: '已交',
        type: CustomFieldType.checkbox,
      ),
    ];
    final note = TableEntryDocument(
      id: 'nt_all_field_types',
      type: TableContentType.note,
      tableId: 'tb_homework',
      title: '字段样例',
      revision: 1,
      createdAt: created,
      updatedAt: created,
      body: '正文',
      customValues: const {
        'fld_text': '第二章',
        'fld_number': 95.5,
        'fld_date': '2026-11-02',
        'fld_single': 'signals',
        'fld_multi': ['read', 'write'],
        'fld_checkbox': false,
      },
    );

    final decoded = codec.decodeEntry(codec.encodeEntry(note, fields: fields));
    expect(decoded.customValues, note.customValues);
  });

  test('rejects schedules without start and notes with event fields', () {
    final base = TableEntryDocument(
      id: 'sc_bad',
      type: TableContentType.schedule,
      tableId: 'tb_exam',
      title: '考试',
      revision: 1,
      createdAt: created,
      updatedAt: created,
      body: '',
    );
    expect(() => codec.encodeEntry(base), throwsFormatException);

    const malformed = '''
---
id: nt_bad
type: note
table_id: tb_notes
title: 笔记
revision: 1
created_at: 2026-10-29T09:00:00+08:00
updated_at: 2026-10-29T09:00:00+08:00
start: 2026-10-30T09:00:00+08:00
---
正文
''';
    expect(() => codec.decodeEntry(malformed), throwsFormatException);
  });

  test('rejects unsupported schemas and legacy global-knowledge objects', () {
    expect(
      () => codec.decodeTable('''
---
schema_version: 99
id: tb_future
type: table
role: custom
title: Future
revision: 1
created_at: 2026-10-29T09:00:00+08:00
updated_at: 2026-10-29T09:00:00+08:00
---
'''),
      throwsFormatException,
    );
    expect(
      () => codec.decodeEntry('''
---
id: kn_global
type: knowledge
table_id: tb_event
title: 学期开始日
revision: 1
created_at: 2026-10-29T09:00:00+08:00
updated_at: 2026-10-29T09:00:00+08:00
---
'''),
      throwsFormatException,
    );
  });
}
