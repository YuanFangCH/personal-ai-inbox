import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/calendar.dart';
import '../../core/models.dart';
import '../../core/table_models.dart';
import '../app_scope.dart';
import '../widgets/calendar_views.dart';
import '../widgets/common.dart';
import 'table_detail_page.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({
    super.key,
    this.initialSection = CalendarSection.calendar,
  });

  final CalendarSection initialSection;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late CalendarSection _section;
  CalendarRangeMode _mode = CalendarRangeMode.month;
  late DateTime _selectedDay;
  int _agendaDays = 90;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppScope.tables(context),
        AppScope.preferences(context),
      ]),
      builder: (context, _) => _buildCalendar(context),
    );
  }

  Widget _buildCalendar(BuildContext context) {
    final library = AppScope.tables(context);
    final preferences = AppScope.preferences(context);
    final tableDocuments = projectTableCalendarDocuments(
      tables: library.tables,
      entries: library.entries,
      visibleTableIds: preferences.settings.calendarVisibleTableIds,
    );
    final events = tableDocuments.where(
      (item) => item.type == ResultType.event,
    );
    final todos = tableDocuments.where((item) => item.type == ResultType.todo);
    final detailed = preferences.settings.calendarMonthDetailed;
    final density = detailed
        ? CalendarMonthDensity.detailed
        : CalendarMonthDensity.overview;
    final range = _occurrenceRange();
    final occurrences = range == null
        ? const <CalendarOccurrence>[]
        : buildCalendarOccurrences(
            events: events,
            todos: todos,
            rangeStart: range.$1,
            rangeEnd: range.$2,
          );
    final page = PageFrame(
      title: _pageTitle(),
      subtitle: _pageSubtitle(todos),
      actions: [
        OutlinedButton.icon(
          key: const Key('calendar_table_filter'),
          onPressed: () => _showTableFilter(context),
          icon: const Icon(Icons.filter_list),
          label: Text(_filterLabel(library.tables)),
        ),
        FilledButton.icon(
          key: const Key('calendar_quick_create'),
          onPressed: _quickCreate,
          icon: const Icon(Icons.add),
          label: Text(_section == CalendarSection.todos ? '新建待办' : '新建日程'),
        ),
        if (_section == CalendarSection.calendar &&
            _mode == CalendarRangeMode.month)
          PopupMenuButton<CalendarMonthDensity>(
            key: const Key('calendar_density_menu'),
            initialValue: density,
            onSelected: (value) {
              preferences.update(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CalendarSectionSwitcher(
            selected: _section,
            onSelected: (value) => setState(() => _section = value),
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.015),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey('${_section.name}_${_mode.name}'),
              child: _buildSection(occurrences, density, todos.toList()),
            ),
          ),
        ],
      ),
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
    );
  }

  Widget _buildSection(
    List<CalendarOccurrence> occurrences,
    CalendarMonthDensity density,
    List<ResultDocument> todos,
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
      CalendarSection.todos => _TableTodosPane(
        todos: todos,
        onOpen: _openDocument,
      ),
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

  String _pageSubtitle(Iterable<ResultDocument> todos) {
    return switch (_section) {
      CalendarSection.calendar => monthDayHeader(_selectedDay),
      CalendarSection.myDay => fullDateHeader(_selectedDay),
      CalendarSection.todos =>
        '${todos.where((todo) => !todo.done).length} 项未完成',
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
    final library = AppScope.tables(context);
    final type = _section == CalendarSection.todos
        ? TableContentType.todo
        : TableContentType.schedule;
    final settings = AppScope.preferences(context).settings;
    final visibleTables = settings.calendarVisibleTableIds.contains('*')
        ? library.tables
        : library.tables
              .where(
                (table) => settings.calendarVisibleTableIds.contains(table.id),
              )
              .toList(growable: false);
    final defaultRole = type == TableContentType.todo
        ? TableRole.inboxTodo
        : TableRole.inboxSchedule;
    final candidates = visibleTables.isEmpty ? library.tables : visibleTables;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('还没有可保存的表，请先在表与笔记中创建表。')));
      return;
    }
    final target = candidates.length == 1
        ? candidates.single
        : await showModalBottomSheet<TableDocument>(
            context: context,
            builder: (context) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(title: Text('保存到哪张表？')),
                  for (final table in candidates)
                    ListTile(
                      leading: Icon(
                        table.role == defaultRole
                            ? Icons.inbox_outlined
                            : Icons.table_chart_outlined,
                      ),
                      title: Text(table.title),
                      onTap: () => Navigator.pop(context, table),
                    ),
                ],
              ),
            ),
          );
    if (!mounted || target == null) return;
    final date = initialStart ?? _selectedDay;
    final initialDate = type == TableContentType.schedule
        ? DateTime(
            date.year,
            date.month,
            date.day,
            date.hour == 0 ? 9 : date.hour,
            date.minute,
          )
        : DateTime(date.year, date.month, date.day);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TableEntryEditorPage(
          tableId: target.id,
          type: type,
          initialDate: initialDate,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _openDocument(ResultDocument document) {
    final tableId = document.extensionFields['table_id'];
    TableEntryDocument? entry;
    for (final candidate in AppScope.tables(context).entries) {
      if (candidate.id == document.id) entry = candidate;
    }
    if (tableId is! String || entry == null) return;
    final currentEntry = entry;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TableEntryEditorPage(
          tableId: tableId,
          type: currentEntry.type,
          entry: currentEntry,
        ),
      ),
    );
  }

  String _filterLabel(List<TableDocument> tables) {
    final selected = AppScope.preferences(context)
        .settings
        .calendarVisibleTableIds;
    if (selected.contains('*')) return '全部表';
    return '显示 ${selected.length}/${tables.length} 张表';
  }

  Future<void> _showTableFilter(BuildContext context) async {
    final library = AppScope.tables(context);
    final preferences = AppScope.preferences(context);
    final existing = preferences.settings.calendarVisibleTableIds;
    final selected = existing.contains('*')
        ? library.tables.map((table) => table.id).toSet()
        : existing.toSet();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('日历显示哪些表'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final table in library.tables)
                  CheckboxListTile(
                    value: selected.contains(table.id),
                    title: Text(table.title),
                    onChanged: (value) => setDialogState(() {
                      if (value == true) {
                        selected.add(table.id);
                      } else {
                        selected.remove(table.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setDialogState(() {
                selected
                  ..clear()
                  ..addAll(library.tables.map((table) => table.id));
              }),
              child: const Text('全选'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, Set.of(selected)),
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final allIds = library.tables.map((table) => table.id).toSet();
    await preferences.update(
      calendarVisibleTableIds:
          result.length == allIds.length && result.containsAll(allIds)
          ? const ['*']
          : result.toList(growable: false),
    );
  }
}

enum _TableTodoFilter { open, today, upcoming, completed }

class _TableTodosPane extends StatefulWidget {
  const _TableTodosPane({required this.todos, required this.onOpen});

  final List<ResultDocument> todos;
  final ValueChanged<ResultDocument> onOpen;

  @override
  State<_TableTodosPane> createState() => _TableTodosPaneState();
}

class _TableTodosPaneState extends State<_TableTodosPane> {
  _TableTodoFilter _filter = _TableTodoFilter.open;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final filtered =
        widget.todos.where((todo) {
          return switch (_filter) {
            _TableTodoFilter.open => !todo.done,
            _TableTodoFilter.today =>
              !todo.done && todo.due != null && isSameDay(todo.due!, now),
            _TableTodoFilter.upcoming =>
              !todo.done && todo.due != null && todo.due!.isAfter(now),
            _TableTodoFilter.completed => todo.done,
          };
        }).toList()..sort(
          (a, b) => (a.due ?? a.updatedAt).compareTo(b.due ?? b.updatedAt),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_TableTodoFilter>(
            segments: const [
              ButtonSegment(value: _TableTodoFilter.open, label: Text('未完成')),
              ButtonSegment(value: _TableTodoFilter.today, label: Text('今天')),
              ButtonSegment(
                value: _TableTodoFilter.upcoming,
                label: Text('即将到期'),
              ),
              ButtonSegment(
                value: _TableTodoFilter.completed,
                label: Text('已完成'),
              ),
            ],
            selected: {_filter},
            onSelectionChanged: (value) =>
                setState(() => _filter = value.first),
          ),
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          const EmptyState(
            icon: Icons.task_alt,
            title: '这里没有待办',
            message: '切换筛选条件，或在日历中添加一条待办。',
          )
        else
          SurfacePanel(
            child: Column(
              children: [
                for (var index = 0; index < filtered.length; index++) ...[
                  _TableTodoTile(
                    document: filtered[index],
                    onOpen: widget.onOpen,
                  ),
                  if (index != filtered.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _TableTodoTile extends StatelessWidget {
  const _TableTodoTile({required this.document, required this.onOpen});

  final ResultDocument document;
  final ValueChanged<ResultDocument> onOpen;

  @override
  Widget build(BuildContext context) {
    final library = AppScope.tables(context);
    final id = document.id;
    TableEntryDocument? entry;
    for (final candidate in library.entries) {
      if (candidate.id == id) entry = candidate;
    }
    final overdue =
        document.due != null &&
        !document.done &&
        document.due!.isBefore(DateTime.now());
    final tableTitle = document.extensionFields['table_title'];
    return ListTile(
      leading: Checkbox(
        value: document.done,
        onChanged: entry == null
            ? null
            : (value) async {
                await library.updateEntry(
                  entry!.copyWith(done: value ?? false),
                  expectedRevision: entry.revision,
                );
              },
      ),
      title: Text(
        document.title,
        style: TextStyle(
          decoration: document.done ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Wrap(
        spacing: 6,
        children: [
          if (tableTitle is String) StatusPill(label: tableTitle),
          if (document.due != null)
            StatusPill(
              label:
                  '${friendlyDate(document.due!)} ${DateFormat('HH:mm').format(document.due!)}',
              icon: Icons.schedule,
              tone: overdue ? StatusTone.danger : StatusTone.neutral,
            ),
        ],
      ),
      onTap: () => onOpen(document),
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
