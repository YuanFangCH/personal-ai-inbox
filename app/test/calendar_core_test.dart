import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/calendar.dart';
import 'package:personal_ai_inbox/core/models.dart';

void main() {
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
