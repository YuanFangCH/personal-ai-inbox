import 'package:flutter/material.dart';

import '../../../core/calendar.dart';

class CalendarOccurrenceDots extends StatelessWidget {
  const CalendarOccurrenceDots({super.key, required this.occurrences});

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

class CalendarOccurrenceChips extends StatelessWidget {
  const CalendarOccurrenceChips({
    super.key,
    required this.occurrences,
    required this.maxChips,
  });

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
          return CalendarOccurrenceDots(occurrences: occurrences);
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
                  child: CalendarOccurrenceChip(item: item),
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

class CalendarOccurrenceChip extends StatelessWidget {
  const CalendarOccurrenceChip({super.key, required this.item});

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
