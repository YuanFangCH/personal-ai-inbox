import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/calendar.dart';
import '../../core/models.dart';
import '../../services/app_controller.dart';
import '../app_scope.dart';
import '../widgets/calendar_views.dart';
import '../widgets/common.dart';
import '../widgets/quick_create_sheet.dart';
import '../widgets/todos_pane.dart';
import 'document_detail_page.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  CalendarSection _section = CalendarSection.calendar;
  CalendarRangeMode _mode = CalendarRangeMode.month;
  late DateTime _selectedDay;
  int _agendaDays = 90;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final detailed = app.settings?.calendarMonthDetailed ?? true;
    final density = detailed
        ? CalendarMonthDensity.detailed
        : CalendarMonthDensity.overview;
    final range = _occurrenceRange();
    final occurrences = range == null
        ? const <CalendarOccurrence>[]
        : buildCalendarOccurrences(
            events: app.events,
            todos: app.todos,
            rangeStart: range.$1,
            rangeEnd: range.$2,
          );
    final page = PageFrame(
      title: _pageTitle(),
      subtitle: _pageSubtitle(app),
      actions: [
        if (_section == CalendarSection.calendar &&
            _mode == CalendarRangeMode.month)
          PopupMenuButton<CalendarMonthDensity>(
            key: const Key('calendar_density_menu'),
            initialValue: density,
            onSelected: (value) {
              app.saveSettings(
                calendarMonthDetailed: value == CalendarMonthDensity.detailed,
              );
            },
            itemBuilder: (context) => [
              for (final value in CalendarMonthDensity.values)
                PopupMenuItem(
                  value: value,
                  child: Row(
                    children: [
                      Icon(
                        value == density
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text('${value.label}模式'),
                    ],
                  ),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.view_agenda_outlined, size: 18),
                  const SizedBox(width: 7),
                  Text(density.label),
                ],
              ),
            ),
          ),
      ],
      child: _buildSection(app, occurrences, density),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (_section == CalendarSection.calendar &&
              _mode == CalendarRangeMode.agenda &&
              notification.metrics.axis == Axis.vertical &&
              notification.metrics.extentAfter < 320) {
            _loadMoreAgenda();
          }
          return false;
        },
        child: page,
      ),
      bottomNavigationBar: CalendarSectionBar(
        selected: _section,
        onSelected: (value) => setState(() => _section = value),
        onQuickCreate: _quickCreate,
      ),
    );
  }

  Widget _buildSection(
    AppController app,
    List<CalendarOccurrence> occurrences,
    CalendarMonthDensity density,
  ) {
    return switch (_section) {
      CalendarSection.calendar => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CalendarModeBar(
            selected: _mode,
            onSelected: (value) => setState(() => _mode = value),
          ),
          const SizedBox(height: 16),
          _buildCalendarMode(occurrences, density),
        ],
      ),
      CalendarSection.myDay => _MyDayView(
        day: _selectedDay,
        occurrences: occurrences,
        onOpenDocument: _openDocument,
      ),
      CalendarSection.todos => const TodosPane(),
    };
  }

  Widget _buildCalendarMode(
    List<CalendarOccurrence> occurrences,
    CalendarMonthDensity density,
  ) {
    return switch (_mode) {
      CalendarRangeMode.year => YearCalendarView(
        year: _selectedDay.year,
        selectedDay: _selectedDay,
        occurrences: occurrences,
        onDaySelected: (day) {
          setState(() {
            _selectedDay = day;
            _mode = CalendarRangeMode.month;
          });
        },
      ),
      CalendarRangeMode.month => MonthCalendarView(
        month: DateTime(_selectedDay.year, _selectedDay.month),
        selectedDay: _selectedDay,
        density: density,
        occurrences: occurrences,
        onPrevious: () => _shiftMonth(-1),
        onNext: () => _shiftMonth(1),
        onToday: _goToday,
        onDaySelected: (day) => setState(() => _selectedDay = day),
        onOpenDocument: _openDocument,
      ),
      CalendarRangeMode.week => WeekTimelineView(
        days: List.generate(
          7,
          (index) => calendarWeekStart(_selectedDay).add(Duration(days: index)),
        ),
        occurrences: occurrences,
        onTimeSelected: (value) => _quickCreate(initialStart: value),
        onOpenDocument: _openDocument,
      ),
      CalendarRangeMode.day => WeekTimelineView(
        days: [_selectedDay],
        occurrences: occurrences,
        onTimeSelected: (value) => _quickCreate(initialStart: value),
        onOpenDocument: _openDocument,
      ),
      CalendarRangeMode.agenda => AgendaCalendarView(
        startDate: _selectedDay,
        days: _agendaDays,
        occurrences: occurrences,
        loadingMore: false,
        onOpenDocument: _openDocument,
      ),
    };
  }

  (DateTime, DateTime)? _occurrenceRange() {
    if (_section == CalendarSection.myDay) {
      final start = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day,
      );
      return (start, start.add(const Duration(days: 1)));
    }
    if (_section == CalendarSection.todos) {
      return null;
    }
    return switch (_mode) {
      CalendarRangeMode.year => (
        DateTime(_selectedDay.year),
        DateTime(_selectedDay.year + 1),
      ),
      CalendarRangeMode.month => (
        calendarMonthGridStart(_selectedDay),
        calendarMonthGridEnd(_selectedDay),
      ),
      CalendarRangeMode.week => (
        calendarWeekStart(_selectedDay),
        calendarWeekStart(_selectedDay).add(const Duration(days: 7)),
      ),
      CalendarRangeMode.day => (
        DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day),
        DateTime(
          _selectedDay.year,
          _selectedDay.month,
          _selectedDay.day,
        ).add(const Duration(days: 1)),
      ),
      CalendarRangeMode.agenda => (
        DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day),
        DateTime(
          _selectedDay.year,
          _selectedDay.month,
          _selectedDay.day,
        ).add(Duration(days: _agendaDays)),
      ),
    };
  }

  String _pageTitle() {
    return switch (_section) {
      CalendarSection.calendar => switch (_mode) {
        CalendarRangeMode.year => DateFormat('yyyy年').format(_selectedDay),
        CalendarRangeMode.month => DateFormat('yyyy年MM月').format(_selectedDay),
        CalendarRangeMode.week => _weekTitle(),
        CalendarRangeMode.day => DateFormat('yyyy年MM月dd日').format(_selectedDay),
        CalendarRangeMode.agenda => '日程',
      },
      CalendarSection.myDay => '我的一天',
      CalendarSection.todos => '待办',
    };
  }

  String _pageSubtitle(AppController app) {
    return switch (_section) {
      CalendarSection.calendar => monthDayHeader(_selectedDay),
      CalendarSection.myDay => fullDateHeader(_selectedDay),
      CalendarSection.todos =>
        '${app.todos.where((todo) => !todo.done).length} 项未完成',
    };
  }

  String _weekTitle() {
    final start = calendarWeekStart(_selectedDay);
    final end = start.add(const Duration(days: 6));
    if (start.year == end.year && start.month == end.month) {
      return '${DateFormat('yyyy年MM月').format(start)}${start.day}日 - ${end.day}日';
    }
    return '${DateFormat('yyyy年MM月dd日').format(start)} - ${DateFormat('MM月dd日').format(end)}';
  }

  void _shiftMonth(int offset) {
    setState(() {
      _selectedDay = DateTime(
        _selectedDay.year,
        _selectedDay.month + offset,
        1,
      );
    });
  }

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _selectedDay = DateTime(now.year, now.month, now.day);
    });
  }

  void _loadMoreAgenda() {
    if (_agendaDays >= 720) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _agendaDays += 90);
      }
    });
  }

  Future<void> _quickCreate({DateTime? initialStart}) async {
    final created = await showQuickCreateSheet(
      context,
      initialDate: initialStart ?? _selectedDay,
      type: _section == CalendarSection.todos
          ? ResultType.todo
          : ResultType.event,
      initialStart: initialStart,
    );
    if (created == null || !mounted) {
      return;
    }
    final date = created.start ?? created.due;
    if (date != null) {
      setState(() {
        _selectedDay = DateTime(date.year, date.month, date.day);
      });
    }
  }

  void _openDocument(ResultDocument document) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentDetailPage(documentId: document.id),
      ),
    );
  }
}

class _MyDayView extends StatelessWidget {
  const _MyDayView({
    required this.day,
    required this.occurrences,
    required this.onOpenDocument,
  });

  final DateTime day;
  final List<CalendarOccurrence> occurrences;
  final ValueChanged<ResultDocument> onOpenDocument;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = isSameDay(day, now);
    final openTodos = occurrences
        .where((item) => item.kind == CalendarItemKind.todo && !item.done)
        .toList(growable: false);
    final overdue = isToday
        ? openTodos
              .where((item) => item.start.isBefore(now))
              .toList(growable: false)
        : const <CalendarOccurrence>[];
    final events = occurrences
        .where((item) => item.kind == CalendarItemKind.event)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 16) / 3;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: width,
                  child: _MyDayMetric(
                    icon: Icons.event_available_outlined,
                    label: '事件',
                    value: '$events',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _MyDayMetric(
                    icon: Icons.check_circle_outline,
                    label: '待办',
                    value: '${openTodos.length}',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _MyDayMetric(
                    icon: Icons.warning_amber_outlined,
                    label: '逾期',
                    value: '${overdue.length}',
                  ),
                ),
              ],
            );
          },
        ),
        if (overdue.isNotEmpty) ...[
          const SizedBox(height: 12),
          SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeading(title: '待办提醒'),
                const SizedBox(height: 4),
                for (final item in overdue)
                  InkWell(
                    onTap: () => onOpenDocument(item.document),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.document.title),
                                if (item.document.due != null)
                                  Text(
                                    DateFormat('MM月dd日 HH:mm')
                                        .format(item.document.due!),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        WeekTimelineView(
          days: [day],
          occurrences: occurrences,
          onTimeSelected: (_) {},
          onOpenDocument: onOpenDocument,
        ),
      ],
    );
  }
}

class _MyDayMetric extends StatelessWidget {
  const _MyDayMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurfacePanel(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
