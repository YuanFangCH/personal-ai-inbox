import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/calendar.dart';
import '../../core/models.dart';
import 'common.dart';

const _hourHeight = 56.0;

class CalendarModeBar extends StatelessWidget {
  const CalendarModeBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final CalendarRangeMode selected;
  final ValueChanged<CalendarRangeMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final mode in CalendarRangeMode.values)
            Expanded(
              child: InkWell(
                key: Key('calendar_mode_${mode.name}'),
                onTap: () => onSelected(mode),
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: selected == mode
                        ? scheme.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    mode.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: selected == mode
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: selected == mode
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CalendarSectionBar extends StatelessWidget {
  const CalendarSectionBar({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.onQuickCreate,
  });

  final CalendarSection selected;
  final ValueChanged<CalendarSection> onSelected;
  final VoidCallback onQuickCreate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Align(
        heightFactor: 1,
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Material(
            elevation: 8,
            color: scheme.surfaceContainerHigh,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(30),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  for (final section in CalendarSection.values)
                    Expanded(
                      child: InkWell(
                        key: Key('calendar_section_${section.name}'),
                        onTap: () => onSelected(section),
                        borderRadius: BorderRadius.circular(24),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selected == section
                                ? scheme.primaryContainer
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _sectionIcon(section),
                                size: 19,
                                color: selected == section
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  section.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: selected == section
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: selected == section
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  InkWell(
                    key: const Key('calendar_quick_create'),
                    onTap: onQuickCreate,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.add, color: scheme.onPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _sectionIcon(CalendarSection section) {
    return switch (section) {
      CalendarSection.calendar => Icons.calendar_month_outlined,
      CalendarSection.myDay => Icons.wb_sunny_outlined,
      CalendarSection.todos => Icons.check_circle_outline,
    };
  }
}

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
            return _CalendarDayCell(
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

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
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
                        child: _OccurrenceDots(occurrences: occurrences),
                      ),
                    )
                  else
                    Expanded(
                      child: _OccurrenceChips(
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

class _OccurrenceDots extends StatelessWidget {
  const _OccurrenceDots({required this.occurrences});

  final List<CalendarOccurrence> occurrences;

  @override
  Widget build(BuildContext context) {
    if (occurrences.isEmpty) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      children: [
        for (final item in occurrences.take(4))
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: item.kind == CalendarItemKind.event
                  ? scheme.primary
                  : scheme.secondary,
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}

class _OccurrenceChips extends StatelessWidget {
  const _OccurrenceChips({required this.occurrences, required this.maxChips});

  final List<CalendarOccurrence> occurrences;
  final int maxChips;

  @override
  Widget build(BuildContext context) {
    if (occurrences.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final itemHeight = 14 * textScale;
        final fitting = (constraints.maxHeight / itemHeight).floor();
        final visibleCount = fitting.clamp(0, maxChips);
        if (visibleCount == 0) {
          return _OccurrenceDots(occurrences: occurrences);
        }
        final visible = occurrences.take(visibleCount).toList(growable: false);
        final remaining = occurrences.length - visible.length;
        final showRemaining =
            remaining > 0 &&
            constraints.maxHeight >= itemHeight * (visible.length + 1);
        return ClipRect(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: _OccurrenceChip(item: item),
                ),
              if (showRemaining)
                Text(
                  '+$remaining',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _OccurrenceChip extends StatelessWidget {
  const _OccurrenceChip({required this.item});

  final CalendarOccurrence item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = item.kind == CalendarItemKind.event
        ? scheme.primaryContainer
        : scheme.secondaryContainer;
    final foreground = item.kind == CalendarItemKind.event
        ? scheme.onPrimaryContainer
        : scheme.onSecondaryContainer;
    return Tooltip(
      message: item.document.title,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        decoration: BoxDecoration(
          color: background.withValues(alpha: item.done ? 0.48 : 1),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          item.document.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9,
            height: 1.05,
            fontWeight: FontWeight.w700,
            color: foreground,
            decoration: item.done ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }
}

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
            return _MiniMonth(
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

class _MiniMonth extends StatelessWidget {
  const _MiniMonth({
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
                      child: _AllDayItems(
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
          child: _TimelineBlock(
            item: item,
            onTap: () => onOpenDocument(item.document),
          ),
        ),
      );
    }
    return widgets;
  }
}

class _AllDayItems extends StatelessWidget {
  const _AllDayItems({required this.items, required this.onOpenDocument});

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
                child: _OccurrenceChip(item: item),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineBlock extends StatelessWidget {
  const _TimelineBlock({required this.item, required this.onTap});

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
                  _AgendaItem(
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

class _AgendaItem extends StatelessWidget {
  const _AgendaItem({required this.item, required this.onTap});

  final CalendarOccurrence item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = item.allDay ? '全天' : DateFormat('HH:mm').format(item.start);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 38,
              decoration: BoxDecoration(
                color: item.kind == CalendarItemKind.event
                    ? scheme.primary
                    : scheme.secondary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              item.kind == CalendarItemKind.event
                  ? Icons.event_outlined
                  : item.done
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.document.title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  decoration: item.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              time,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class CalendarDayPanel extends StatelessWidget {
  const CalendarDayPanel({
    super.key,
    required this.day,
    required this.occurrences,
    required this.onOpenDocument,
  });

  final DateTime day;
  final List<CalendarOccurrence> occurrences;
  final ValueChanged<ResultDocument> onOpenDocument;

  @override
  Widget build(BuildContext context) {
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            title: monthDayHeader(day),
            trailing: Text('${occurrences.length} 项'),
          ),
          const SizedBox(height: 6),
          if (occurrences.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('这一天没有事件或待办')),
            )
          else
            for (var index = 0; index < occurrences.length; index++) ...[
              _AgendaItem(
                item: occurrences[index],
                onTap: () => onOpenDocument(occurrences[index].document),
              ),
              if (index != occurrences.length - 1) const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}
