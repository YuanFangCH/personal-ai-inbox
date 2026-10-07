import 'package:flutter/material.dart';

import '../../../core/calendar.dart';
import '../../../core/models.dart';
import '../common.dart';
import 'calendar_occurrence_widgets.dart';

const _hourHeight = 56.0;

class WeekTimelineView extends StatelessWidget {
  const WeekTimelineView({
    super.key,
    required this.days,
    required this.occurrences,
    required this.onTimeSelected,
    required this.onOpenDocument,
  });

  final List<DateTime> days;
  final List<CalendarOccurrence> occurrences;
  final ValueChanged<DateTime> onTimeSelected;
  final ValueChanged<ResultDocument> onOpenDocument;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allDayHeight = _allDayHeight(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 46),
            for (final day in days)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    children: [
                      Text(
                        ['一', '二', '三', '四', '五', '六', '日'][day.weekday - 1],
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: isSameDay(day, DateTime.now())
                              ? FontWeight.w900
                              : FontWeight.w700,
                          color: isSameDay(day, DateTime.now())
                              ? scheme.primary
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        SurfacePanel(
          padding: EdgeInsets.zero,
          child: SizedBox(
            height: allDayHeight,
            child: Row(
              children: [
                const SizedBox(
                  width: 46,
                  child: Center(
                    child: Text(
                      '全天',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                for (final day in days)
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: scheme.outlineVariant),
                        ),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: CalendarAllDayItems(
                        items: occurrencesForDay(
                          occurrences,
                          day,
                        ).where((item) => item.allDay).toList(growable: false),
                        onOpenDocument: onOpenDocument,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        SurfacePanel(
          padding: EdgeInsets.zero,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 46,
                height: _hourHeight * 24,
                child: Column(
                  children: [
                    for (var hour = 0; hour < 24; hour++)
                      SizedBox(
                        height: _hourHeight,
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: Text(
                              '${hour.toString().padLeft(2, '0')}:00',
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              for (final day in days)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) {
                      final minutes =
                          (details.localPosition.dy / _hourHeight * 60)
                              .round()
                              .clamp(0, 23 * 60 + 59);
                      onTimeSelected(
                        DateTime(
                          day.year,
                          day.month,
                          day.day,
                          minutes ~/ 60,
                          minutes % 60,
                        ),
                      );
                    },
                    child: SizedBox(
                      height: _hourHeight * 24,
                      child: Stack(
                        children: [
                          for (var hour = 0; hour < 24; hour++)
                            Positioned(
                              top: hour * _hourHeight,
                              left: 0,
                              right: 0,
                              child: Divider(
                                height: 1,
                                color: scheme.outlineVariant,
                              ),
                            ),
                          ..._timedBlocks(
                            context,
                            day,
                            occurrencesForDay(occurrences, day)
                                .where((item) => !item.allDay)
                                .toList(growable: false),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  double _allDayHeight(BuildContext context) {
    final hasItems = occurrences.any(
      (item) => item.allDay && occurrenceOccursOnDay(item, item.start),
    );
    return hasItems ? 62 : 42;
  }

  List<Widget> _timedBlocks(
    BuildContext context,
    DateTime day,
    List<CalendarOccurrence> items,
  ) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final widgets = <Widget>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final visibleStart = item.start.isBefore(dayStart)
          ? dayStart
          : item.start;
      final visibleEnd = item.end.isAfter(dayEnd) ? dayEnd : item.end;
      final top =
          visibleStart.difference(dayStart).inMinutes / 60 * _hourHeight;
      final height =
          (visibleEnd.difference(visibleStart).inMinutes / 60 * _hourHeight)
              .clamp(26, _hourHeight * 24)
              .toDouble();
      widgets.add(
        Positioned(
          top: top,
          left: 3 + (index % 2) * 5.0,
          right: 3,
          height: height,
          child: CalendarTimelineBlock(
            item: item,
            onTap: () => onOpenDocument(item.document),
          ),
        ),
      );
    }
    return widgets;
  }
}

class CalendarAllDayItems extends StatelessWidget {
  const CalendarAllDayItems({
    super.key,
    required this.items,
    required this.onOpenDocument,
  });

  final List<CalendarOccurrence> items;
  final ValueChanged<ResultDocument> onOpenDocument;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: InkWell(
                onTap: () => onOpenDocument(item.document),
                borderRadius: BorderRadius.circular(4),
                child: CalendarOccurrenceChip(item: item),
              ),
            ),
        ],
      ),
    );
  }
}

class CalendarTimelineBlock extends StatelessWidget {
  const CalendarTimelineBlock({
    super.key,
    required this.item,
    required this.onTap,
  });

  final CalendarOccurrence item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = item.kind == CalendarItemKind.event
        ? scheme.primary
        : scheme.secondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: item.done ? 0.35 : 0.88),
          borderRadius: BorderRadius.circular(4),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Text(
          item.document.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: scheme.onPrimary,
            fontSize: 10,
            height: 1.1,
            fontWeight: FontWeight.w700,
            decoration: item.done ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }
}
