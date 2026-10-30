import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/calendar.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/core/table_models.dart';

void main() {
  test('projects only dated table actions and respects table visibility', () {
    final now = DateTime(2026, 10, 30, 14);
    final table = TableDocument(
      id: 'tb_course',
      role: TableRole.custom,
      title: '课程',
      revision: 1,
      createdAt: now,
      updatedAt: now,
      body: '',
    );
    final otherTable = TableDocument(
      id: 'tb_hidden',
      role: TableRole.custom,
      title: '未显示',
      revision: 1,
      createdAt: now,
      updatedAt: now,
      body: '',
    );
    final entries = [
      _tableEntry('nt_note', table.id, TableContentType.note, now),
      _tableEntry('td_no_date', table.id, TableContentType.todo, now),
      _tableEntry('td_date', table.id, TableContentType.todo, now, due: now),
      _tableEntry(
        'sc_exam',
        table.id,
        TableContentType.schedule,
        now,
        start: now,
      ),
      _tableEntry(
        'ev_change',
        table.id,
        TableContentType.event,
        now,
        occurredAt: now,
      ),
      _tableEntry(
        'sc_other',
        otherTable.id,
        TableContentType.schedule,
        now,
        start: now,
      ),
    ];

    final projected = projectTableCalendarDocuments(
      tables: [table, otherTable],
      entries: entries,
      visibleTableIds: [table.id],
    );

    expect(projected.map((item) => item.id), [
      'td_date',
      'sc_exam',
      'ev_change',
    ]);
    expect(projected.first.type, ResultType.todo);
    expect(projected[1].extensionFields['table_content_type'], 'schedule');
    expect(projected[2].extensionFields['table_content_type'], 'event');
  });

  test('expands daily recurrence and respects count', () {
    final event = _event(
      id: 'ev_daily',
      title: '每日复盘',
      start: DateTime(2026, 10, 1, 9),
      recurrence: 'FREQ=DAILY;COUNT=3',
    );
    final items = buildCalendarOccurrences(
      events: [event],
      todos: const [],
      rangeStart: DateTime(2026, 10, 1),
      rangeEnd: DateTime(2026, 10, 10),
    );

    expect(items, hasLength(3));
    expect(items.map((item) => item.start.day), [1, 2, 3]);
    expect(items.map((item) => item.instanceId).toSet(), hasLength(3));
  });

  test('expands weekly recurrence by weekday', () {
    final event = _event(
      id: 'ev_weekly',
      title: '周会',
      start: DateTime(2026, 10, 7, 10),
      recurrence: 'FREQ=WEEKLY;BYDAY=WE;COUNT=3',
    );
    final items = buildCalendarOccurrences(
      events: [event],
      todos: const [],
      rangeStart: DateTime(2026, 10, 1),
      rangeEnd: DateTime(2026, 11, 1),
    );

    expect(items, hasLength(3));
    expect(items.map((item) => item.start.day), [7, 14, 21]);
  });

  test('monthly recurrence skips months without the selected day', () {
    final event = _event(
      id: 'ev_monthly',
      title: '月末结算',
      start: DateTime(2026, 1, 31, 18),
      recurrence: 'FREQ=MONTHLY;COUNT=4;UNTIL=20261231',
    );
    final items = buildCalendarOccurrences(
      events: [event],
      todos: const [],
      rangeStart: DateTime(2026, 1, 1),
      rangeEnd: DateTime(2027, 1, 1),
    );

    expect(items, hasLength(4));
    expect(items.map((item) => '${item.start.month}-${item.start.day}'), [
      '1-31',
      '3-31',
      '5-31',
      '7-31',
    ]);
  });

  test('projects date-only and timed todos with distinct all-day state', () {
    final dateOnly = _todo(
      id: 'td_date',
      title: '交表',
      due: DateTime(2026, 10, 8),
    );
    final timed = _todo(
      id: 'td_time',
      title: '打电话',
      due: DateTime(2026, 10, 8, 14, 30),
    );
    final items = buildCalendarOccurrences(
      events: const [],
      todos: [dateOnly, timed],
      rangeStart: DateTime(2026, 10, 8),
      rangeEnd: DateTime(2026, 10, 9),
    );

    expect(items, hasLength(2));
    expect(
      items.firstWhere((item) => item.document.id == 'td_date').allDay,
      true,
    );
    expect(
      items.firstWhere((item) => item.document.id == 'td_time').allDay,
      false,
    );
  });

  test('month grid uses Monday as the first weekday', () {
    final start = calendarMonthGridStart(DateTime(2026, 10));
    expect(start.weekday, DateTime.monday);
    expect(start, DateTime(2026, 9, 28));
  });
}

TableEntryDocument _tableEntry(
  String id,
  String tableId,
  TableContentType type,
  DateTime now, {
  DateTime? due,
  DateTime? start,
  DateTime? occurredAt,
}) => TableEntryDocument(
  id: id,
  type: type,
  tableId: tableId,
  title: id,
  revision: 1,
  createdAt: now,
  updatedAt: now,
  body: '',
  due: due,
  start: start,
  occurredAt: occurredAt,
);

ResultDocument _event({
  required String id,
  required String title,
  required DateTime start,
  String? recurrence,
}) {
  return ResultDocument(
    id: id,
    type: ResultType.event,
    title: title,
    status: ResultStatus.canonical,
    originDevice: 'test-device',
    revision: 1,
    createdAt: start,
    updatedAt: start,
    body: '',
    start: start,
    end: start.add(const Duration(hours: 1)),
    recurrence: recurrence,
  );
}

ResultDocument _todo({
  required String id,
  required String title,
  required DateTime due,
}) {
  return ResultDocument(
    id: id,
    type: ResultType.todo,
    title: title,
    status: ResultStatus.canonical,
    originDevice: 'test-device',
    revision: 1,
    createdAt: due,
    updatedAt: due,
    body: '',
    due: due,
  );
}
