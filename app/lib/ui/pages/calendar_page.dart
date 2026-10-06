import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import 'document_detail_page.dart';
import 'document_editor_page.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _month;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final events = app.events
        .where((event) => event.start != null)
        .toList(growable: false);
    final selectedEvents =
        events.where((event) => isSameDay(event.start!, _selectedDay)).toList()
          ..sort((a, b) => a.start!.compareTo(b.start!));
    return PageFrame(
      title: '日历',
      subtitle: DateFormat('yyyy年MM月').format(_month),
      actions: [
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const DocumentEditorPage.create(type: ResultType.event),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text('新建事件'),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final month = _MonthPanel(
            month: _month,
            selectedDay: _selectedDay,
            events: events,
            onPrevious: () => setState(
              () => _month = DateTime(_month.year, _month.month - 1),
            ),
            onNext: () => setState(
              () => _month = DateTime(_month.year, _month.month + 1),
            ),
            onToday: () {
              final now = DateTime.now();
              setState(() {
                _month = DateTime(now.year, now.month);
                _selectedDay = DateTime(now.year, now.month, now.day);
              });
            },
            onSelected: (day) => setState(() => _selectedDay = day),
          );
          final agenda = _DayAgenda(day: _selectedDay, events: selectedEvents);
          if (constraints.maxWidth < 900) {
            return Column(
              children: [month, const SizedBox(height: 16), agenda],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: month),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: agenda),
            ],
          );
        },
      ),
    );
  }
}

class _MonthPanel extends StatelessWidget {
  const _MonthPanel({
    required this.month,
    required this.selectedDay,
    required this.events,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onSelected,
  });

  final DateTime month;
  final DateTime selectedDay;
  final List<ResultDocument> events;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday % 7;
    final cellCount = ((leading + daysInMonth + 6) ~/ 7) * 7;
    final today = DateTime.now();
    return SurfacePanel(
      child: Column(
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
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
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
          const Divider(height: 18),
          Row(
            children: [
              for (final day in ['日', '一', '二', '三', '四', '五', '六'])
                Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cellCount,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 5,
              crossAxisSpacing: 5,
              childAspectRatio: MediaQuery.textScalerOf(context).scale(1) >= 1.3
                  ? 0.78
                  : 0.9,
            ),
            itemBuilder: (context, index) {
              final dayNumber = index - leading + 1;
              if (dayNumber < 1 || dayNumber > daysInMonth) {
                return const SizedBox.shrink();
              }
              final day = DateTime(month.year, month.month, dayNumber);
              final dayEvents = events
                  .where((event) => isSameDay(event.start!, day))
                  .toList(growable: false);
              final selected = isSameDay(day, selectedDay);
              final isToday = isSameDay(day, today);
              return _DayCell(
                day: day,
                selected: selected,
                isToday: isToday,
                eventCount: dayEvents.length,
                hasTodo: false,
                onTap: () => onSelected(day),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.eventCount,
    required this.hasTodo,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final int eventCount;
  final bool hasTodo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final dayTextScaler = TextScaler.linear(
      textScale.clamp(1.0, 1.2).toDouble(),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer
              : isToday
              ? scheme.secondaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                day.day.toString(),
                textScaler: dayTextScaler,
                style: TextStyle(
                  fontWeight: selected || isToday
                      ? FontWeight.w800
                      : FontWeight.w500,
                ),
              ),
              if (eventCount > 0)
                Positioned(
                  bottom: 0,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayAgenda extends StatelessWidget {
  const _DayAgenda({required this.day, required this.events});

  final DateTime day;
  final List<ResultDocument> events;

  @override
  Widget build(BuildContext context) {
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            title: monthDayHeader(day),
            trailing: Text('${events.length} 项'),
          ),
          const SizedBox(height: 8),
          if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('这一天没有事件')),
            )
          else
            for (var index = 0; index < events.length; index++) ...[
              DocumentListTile(
                document: events[index],
                showType: false,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        DocumentDetailPage(documentId: events[index].id),
                  ),
                ),
              ),
              if (index != events.length - 1) const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}
