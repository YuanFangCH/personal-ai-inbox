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
