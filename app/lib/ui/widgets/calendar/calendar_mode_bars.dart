import 'package:flutter/material.dart';

import '../../../core/calendar.dart';

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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
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
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 160),
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
                          ? FontWeight.w600
                          : FontWeight.w400,
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

class CalendarSectionSwitcher extends StatelessWidget {
  const CalendarSectionSwitcher({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final CalendarSection selected;
  final ValueChanged<CalendarSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            for (final section in CalendarSection.values)
              Expanded(
                child: InkWell(
                  key: Key('calendar_section_${section.name}'),
                  onTap: () => onSelected(section),
                  borderRadius: BorderRadius.circular(11),
                  child: AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 160),
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: selected == section
                          ? scheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      section.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: selected == section
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected == section
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
