import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/calendar.dart';
import '../../../core/models.dart';
import '../common.dart';
import 'calendar_day_panel.dart';
import 'calendar_occurrence_widgets.dart';

class MonthCalendarView extends StatelessWidget {
  const MonthCalendarView({
    super.key,
    required this.month,
    required this.selectedDay,
    required this.density,
    required this.occurrences,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onDaySelected,
    required this.onOpenDocument,
  });

  final DateTime month;
  final DateTime selectedDay;
  final CalendarMonthDensity density;
  final List<CalendarOccurrence> occurrences;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<DateTime> onDaySelected;
  final ValueChanged<ResultDocument> onOpenDocument;

  @override
  Widget build(BuildContext context) {
    final gridStart = calendarMonthGridStart(month);
    final today = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '上个月',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                DateFormat('yyyy年MM月').format(month),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: '下个月',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
            TextButton(onPressed: onToday, child: const Text('今天')),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final day in const ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 42,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: density == CalendarMonthDensity.detailed
                ? 0.72
                : 1,
          ),
          itemBuilder: (context, index) {
            final day = gridStart.add(Duration(days: index));
            return CalendarDayCell(
              day: day,
              month: month,
              selected: isSameDay(day, selectedDay),
              today: isSameDay(day, today),
              density: density,
              occurrences: occurrencesForDay(occurrences, day),
              onTap: () => onDaySelected(day),
            );
          },
        ),
        const SizedBox(height: 14),
        CalendarDayPanel(
          day: selectedDay,
          occurrences: occurrencesForDay(occurrences, selectedDay),
          onOpenDocument: onOpenDocument,
        ),
      ],
    );
  }
}

class CalendarDayCell extends StatelessWidget {
  const CalendarDayCell({
    super.key,
    required this.day,
    required this.month,
    required this.selected,
    required this.today,
    required this.density,
    required this.occurrences,
    required this.onTap,
  });

  final DateTime day;
  final DateTime month;
  final bool selected;
  final bool today;
  final CalendarMonthDensity density;
  final List<CalendarOccurrence> occurrences;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inMonth = day.month == month.month;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxChips = constraints.maxHeight >= 88 ? 3 : 2;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primaryContainer
                  : today
                  ? scheme.secondaryContainer.withValues(alpha: 0.72)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected || today
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: inMonth
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant.withValues(alpha: 0.48),
                      ),
                    ),
                  ),
                  if (density == CalendarMonthDensity.overview)
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: CalendarOccurrenceDots(occurrences: occurrences),
                      ),
                    )
                  else
                    Expanded(
                      child: CalendarOccurrenceChips(
                        occurrences: occurrences,
                        maxChips: maxChips,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
