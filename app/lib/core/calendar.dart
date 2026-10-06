import 'models.dart';

enum CalendarSection {
  calendar('日程'),
  myDay('我的一天'),
  todos('待办');

  const CalendarSection(this.label);

  final String label;
}

enum CalendarRangeMode {
  year('年'),
  month('月'),
  week('周'),
  day('日'),
  agenda('日程');

  const CalendarRangeMode(this.label);

  final String label;
}

enum CalendarMonthDensity {
  overview('概要'),
  detailed('详细');

  const CalendarMonthDensity(this.label);

  final String label;
}

enum CalendarItemKind { event, todo }

class CalendarOccurrence {
  const CalendarOccurrence({
    required this.document,
    required this.kind,
    required this.start,
    required this.end,
    required this.allDay,
  });

  final ResultDocument document;
  final CalendarItemKind kind;
  final DateTime start;
  final DateTime end;
  final bool allDay;

  bool get done => kind == CalendarItemKind.todo && document.done;
}

List<CalendarOccurrence> buildCalendarOccurrences({
  required Iterable<ResultDocument> events,
  required Iterable<ResultDocument> todos,
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  if (!rangeEnd.isAfter(rangeStart)) {
    return const [];
  }
  final occurrences = <CalendarOccurrence>[];
  for (final event in events) {
    occurrences.addAll(_eventOccurrences(event, rangeStart, rangeEnd));
  }
  for (final todo in todos) {
    final item = _todoOccurrence(todo);
    if (item != null) {
      occurrences.add(item);
    }
  }
  occurrences
    ..removeWhere((item) => !_intersects(item, rangeStart, rangeEnd))
    ..sort(compareCalendarOccurrences);
  return occurrences;
}

int compareCalendarOccurrences(CalendarOccurrence a, CalendarOccurrence b) {
  if (a.allDay != b.allDay) {
    return a.allDay ? -1 : 1;
  }
  final byStart = a.start.compareTo(b.start);
  if (byStart != 0) {
    return byStart;
  }
  if (a.kind != b.kind) {
    return a.kind == CalendarItemKind.event ? -1 : 1;
  }
  return a.document.title.compareTo(b.document.title);
}

List<CalendarOccurrence> occurrencesForDay(
  Iterable<CalendarOccurrence> occurrences,
  DateTime day,
) {
  final result =
      occurrences
          .where((item) => occurrenceOccursOnDay(item, day))
          .toList(growable: false)
        ..sort(compareCalendarOccurrences);
  return result;
}

bool occurrenceOccursOnDay(CalendarOccurrence item, DateTime day) {
  final target = _dateOnly(day);
  final start = _dateOnly(item.start);
  final end = _dateOnly(item.end);
  final exclusiveEnd = end.isAfter(start)
      ? end
      : start.add(const Duration(days: 1));
  return !target.isBefore(start) && target.isBefore(exclusiveEnd);
}

DateTime calendarWeekStart(DateTime day) {
  final date = _dateOnly(day);
  return date.subtract(Duration(days: date.weekday - DateTime.monday));
}

DateTime calendarMonthGridStart(DateTime month) {
  return calendarWeekStart(DateTime(month.year, month.month));
}

DateTime calendarMonthGridEnd(DateTime month) {
  final next = DateTime(month.year, month.month + 1);
  return calendarWeekStart(next).add(const Duration(days: 7));
}

String recurrenceWeekdayCode(int weekday) {
  return switch (weekday) {
    DateTime.monday => 'MO',
    DateTime.tuesday => 'TU',
    DateTime.wednesday => 'WE',
    DateTime.thursday => 'TH',
    DateTime.friday => 'FR',
    DateTime.saturday => 'SA',
    DateTime.sunday => 'SU',
    _ => 'MO',
  };
}

int recurrenceWeekday(String value) {
  return switch (value.toUpperCase()) {
    'MO' => DateTime.monday,
    'TU' => DateTime.tuesday,
    'WE' => DateTime.wednesday,
    'TH' => DateTime.thursday,
    'FR' => DateTime.friday,
    'SA' => DateTime.saturday,
    'SU' => DateTime.sunday,
    _ => DateTime.monday,
  };
}

List<CalendarOccurrence> _eventOccurrences(
  ResultDocument event,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  final start = event.start;
  if (start == null) {
    return const [];
  }
  final duration = _eventDuration(event, start);
  final recurrence = event.recurrence?.trim();
  if (recurrence == null || recurrence.isEmpty) {
    return [
      CalendarOccurrence(
        document: event,
        kind: CalendarItemKind.event,
        start: start,
        end: start.add(duration),
        allDay: event.allDay,
      ),
    ];
  }

  return _expandedRecurrences(
        baseStart: start,
        duration: duration,
        rule: recurrence,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      )
      .map(
        (candidate) => CalendarOccurrence(
          document: event,
          kind: CalendarItemKind.event,
          start: candidate,
          end: candidate.add(duration),
          allDay: event.allDay,
        ),
      )
      .toList(growable: false);
}

CalendarOccurrence? _todoOccurrence(ResultDocument todo) {
  final due = todo.due;
  if (due == null) {
    return null;
  }
  final dateOnly = due.hour == 0 && due.minute == 0 && due.second == 0;
  return CalendarOccurrence(
    document: todo,
    kind: CalendarItemKind.todo,
    start: dateOnly ? _dateOnly(due) : due,
    end: dateOnly
        ? _dateOnly(due).add(const Duration(days: 1))
        : due.add(const Duration(hours: 1)),
    allDay: dateOnly || todo.allDay,
  );
}

Duration _eventDuration(ResultDocument event, DateTime start) {
  final end = event.end;
  if (end != null && end.isAfter(start)) {
    return end.difference(start);
  }
  return event.allDay ? const Duration(days: 1) : const Duration(hours: 1);
}

bool _intersects(
  CalendarOccurrence item,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  return item.start.isBefore(rangeEnd) && item.end.isAfter(rangeStart);
}

List<DateTime> _expandedRecurrences({
  required DateTime baseStart,
  required Duration duration,
  required String rule,
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  final parts = <String, String>{};
  for (final segment in rule.split(';')) {
    final separator = segment.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    parts[segment.substring(0, separator).trim().toUpperCase()] = segment
        .substring(separator + 1)
        .trim()
        .toUpperCase();
  }

  final frequency = parts['FREQ'];
  final interval = int.tryParse(parts['INTERVAL'] ?? '') ?? 1;
  if (interval < 1 ||
      !const {'DAILY', 'WEEKLY', 'MONTHLY'}.contains(frequency)) {
    return const [];
  }

  final count = int.tryParse(parts['COUNT'] ?? '');
  final until = _parseRecurrenceDate(parts['UNTIL']);
  final generated = <DateTime>[];
  var accepted = 0;
  var attempts = 0;

  bool shouldStop(DateTime candidate) {
    if (until != null && candidate.isAfter(until)) {
      return true;
    }
    if (candidate.isBefore(rangeEnd)) {
      return false;
    }
    return !candidate.subtract(duration).isBefore(rangeEnd);
  }

  void addCandidate(DateTime candidate) {
    if (candidate.isBefore(baseStart)) {
      return;
    }
    if (count != null && accepted >= count) {
      return;
    }
    accepted++;
    if (_intersectsRange(
      candidate,
      candidate.add(duration),
      rangeStart,
      rangeEnd,
    )) {
      generated.add(candidate);
    }
  }

  switch (frequency) {
    case 'DAILY':
      for (var index = 0; attempts < 10000; index++) {
        attempts++;
        final candidate = baseStart.add(Duration(days: index * interval));
        if (shouldStop(candidate)) {
          break;
        }
        addCandidate(candidate);
        if (count != null && accepted >= count) {
          break;
        }
      }
      break;
    case 'WEEKLY':
      final byDay =
          (parts['BYDAY'] ?? '')
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .map(recurrenceWeekday)
              .toSet()
              .toList()
            ..sort();
      final days = byDay.isEmpty ? [baseStart.weekday] : byDay;
      final firstWeek = calendarWeekStart(baseStart);
      for (var weekIndex = 0; attempts < 10000; weekIndex++) {
        attempts++;
        final week = firstWeek.add(Duration(days: weekIndex * interval * 7));
        if (week.isAfter(rangeEnd) && weekIndex > 0) {
          break;
        }
        for (final weekday in days) {
          final candidate = DateTime(
            week.year,
            week.month,
            week.day,
            baseStart.hour,
            baseStart.minute,
            baseStart.second,
            baseStart.millisecond,
            baseStart.microsecond,
          ).add(Duration(days: weekday - DateTime.monday));
          if (count != null && accepted >= count) {
            break;
          }
          if (shouldStop(candidate)) {
            break;
          }
          addCandidate(candidate);
        }
        if (until != null && week.isAfter(until)) {
          break;
        }
        if (count != null && accepted >= count) {
          break;
        }
      }
      break;
    case 'MONTHLY':
      for (var index = 0; attempts < 10000; index++) {
        attempts++;
        final anchor = DateTime(
          baseStart.year,
          baseStart.month + index * interval,
        );
        if (anchor.day != 1) {
          break;
        }
        final candidate = DateTime(
          anchor.year,
          anchor.month,
          baseStart.day,
          baseStart.hour,
          baseStart.minute,
          baseStart.second,
          baseStart.millisecond,
          baseStart.microsecond,
        );
        if (candidate.month != anchor.month || candidate.day != baseStart.day) {
          continue;
        }
        if (shouldStop(candidate)) {
          break;
        }
        addCandidate(candidate);
        if (count != null && accepted >= count) {
          break;
        }
      }
      break;
  }

  return generated..sort();
}

DateTime? _parseRecurrenceDate(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final digits = RegExp(r'^\d{8}$');
  if (digits.hasMatch(value)) {
    return DateTime(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(4, 6)),
      int.parse(value.substring(6, 8)),
      23,
      59,
      59,
      999,
    );
  }
  return DateTime.tryParse(value)?.toLocal();
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

bool _intersectsRange(
  DateTime start,
  DateTime end,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  return start.isBefore(rangeEnd) && end.isAfter(rangeStart);
}
