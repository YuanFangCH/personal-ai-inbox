import 'package:flutter/material.dart';

import '../../../core/calendar.dart';
import '../common.dart';

class YearCalendarView extends StatelessWidget {
  const YearCalendarView({
    super.key,
    required this.year,
    required this.selectedDay,
    required this.occurrences,
    required this.onDaySelected,
  });

  final int year;
  final DateTime selectedDay;
  final List<CalendarOccurrence> occurrences;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 4 : 3;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 12,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.78,
          ),
          itemBuilder: (context, index) {
            return CalendarMiniMonth(
              month: DateTime(year, index + 1),
              selectedDay: selectedDay,
              occurrences: occurrences,
              onDaySelected: onDaySelected,
            );
          },
        );
      },
    );
  }
}

class CalendarMiniMonth extends StatelessWidget {
  const CalendarMiniMonth({
    super.key,
    required this.month,
    required this.selectedDay,
    required this.occurrences,
    required this.onDaySelected,
  });

  final DateTime month;
  final DateTime selectedDay;
  final List<CalendarOccurrence> occurrences;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final start = calendarMonthGridStart(month);
    return SurfacePanel(
      padding: const EdgeInsets.all(7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${month.month}月',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 49,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
              ),
              itemBuilder: (context, index) {
                if (index < 7) {
                  return Center(
                    child: Text(
                      const ['一', '二', '三', '四', '五', '六', '日'][index],
                      style: TextStyle(
                        fontSize: 8,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                final day = start.add(Duration(days: index - 7));
                final selected = isSameDay(day, selectedDay);
                final hasItems = occurrencesForDay(occurrences, day).isNotEmpty;
                return InkWell(
                  onTap: () => onDaySelected(day),
                  borderRadius: BorderRadius.circular(4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected && day.month == month.month
                          ? scheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: day.month == month.month
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant.withValues(
                                      alpha: 0.35,
                                    ),
                            ),
                          ),
                          if (hasItems)
                            Positioned(
                              bottom: 0,
                              child: Container(
                                width: 3,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: scheme.secondary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
