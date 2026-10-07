import 'package:flutter/material.dart';

import '../../../core/calendar.dart';
import '../../../core/models.dart';
import '../common.dart';
import 'calendar_agenda_item.dart';

class AgendaCalendarView extends StatelessWidget {
  const AgendaCalendarView({
    super.key,
    required this.startDate,
    required this.days,
    required this.occurrences,
    required this.loadingMore,
    required this.onOpenDocument,
  });

  final DateTime startDate;
  final int days;
  final List<CalendarOccurrence> occurrences;
  final bool loadingMore;
  final ValueChanged<ResultDocument> onOpenDocument;

  @override
  Widget build(BuildContext context) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = start.add(Duration(days: days));
    final entries = <DateTime, List<CalendarOccurrence>>{};
    for (var offset = 0; offset < days; offset++) {
      final day = start.add(Duration(days: offset));
      final items = occurrencesForDay(occurrences, day)
          .where((item) => item.start.isBefore(end) && item.end.isAfter(start))
          .toList(growable: false);
      if (items.isNotEmpty) {
        entries[day] = items;
      }
    }
    if (entries.isEmpty && !loadingMore) {
      return const EmptyState(
        icon: Icons.event_note_outlined,
        title: '近期没有安排',
        message: '切换日期或在下方新建事件和待办。',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 10, 2, 7),
            child: Text(
              monthDayHeader(entry.key),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          SurfacePanel(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Column(
              children: [
                for (var index = 0; index < entry.value.length; index++) ...[
                  CalendarAgendaItem(
                    item: entry.value[index],
                    onTap: () => onOpenDocument(entry.value[index].document),
                  ),
                  if (index != entry.value.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        ],
        if (loadingMore)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}
