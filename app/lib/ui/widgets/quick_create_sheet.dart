import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/calendar.dart';
import '../../core/models.dart';
import '../app_scope.dart';
import 'common.dart';

Future<ResultDocument?> showQuickCreateSheet(
  BuildContext context, {
  required DateTime initialDate,
  ResultType type = ResultType.event,
  DateTime? initialStart,
}) {
  return showModalBottomSheet<ResultDocument?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _QuickCreateSheet(
      initialDate: initialDate,
      initialType: type,
      initialStart: initialStart,
    ),
  );
}

enum _RepeatFrequency { none, daily, weekly, monthly }

enum _RepeatEnd { until, count }

class _QuickCreateSheet extends StatefulWidget {
  const _QuickCreateSheet({
    required this.initialDate,
    required this.initialType,
    this.initialStart,
  });

  final DateTime initialDate;
  final ResultType initialType;
  final DateTime? initialStart;

  @override
  State<_QuickCreateSheet> createState() => _QuickCreateSheetState();
}

class _QuickCreateSheetState extends State<_QuickCreateSheet> {
  late final TextEditingController _title;
  late final TextEditingController _tags;
  late final TextEditingController _body;
  late final TextEditingController _repeatCount;
  late ResultType _type;
  late DateTime _start;
  late DateTime _end;
  late DateTime _due;
  late DateTime _repeatUntil;
  late _RepeatFrequency _repeatFrequency;
  _RepeatEnd _repeatEnd = _RepeatEnd.until;
  ResultStatus _status = ResultStatus.canonical;
  String? _matterId;
  bool _allDay = false;
  bool _expanded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType == ResultType.todo
        ? ResultType.todo
        : ResultType.event;
    final now = DateTime.now();
    final initial =
        widget.initialStart ??
        DateTime(
          widget.initialDate.year,
          widget.initialDate.month,
          widget.initialDate.day,
          now.hour,
          now.minute,
        );
    _start = initial;
    _end = initial.add(const Duration(hours: 1));
    _due = initial;
    _repeatUntil = initial.add(const Duration(days: 90));
    _repeatFrequency = _RepeatFrequency.none;
    _title = TextEditingController();
    _tags = TextEditingController();
    _body = TextEditingController();
    _repeatCount = TextEditingController(text: '10');
  }

  @override
  void dispose() {
    _title.dispose();
    _tags.dispose();
    _body.dispose();
    _repeatCount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: FractionallySizedBox(
        heightFactor: bottomInset > 0 ? 0.98 : 0.88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '关闭',
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                  const Expanded(
                    child: Text(
                      '快速新建',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    key: const Key('quick_create_save'),
                    tooltip: '保存',
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('quick_create_title'),
                      controller: _title,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: '标题',
                        hintText: '输入日程或待办内容',
                        prefixIcon: Icon(Icons.edit_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SegmentedButton<ResultType>(
                      segments: const [
                        ButtonSegment(
                          value: ResultType.event,
                          icon: Icon(Icons.event_outlined),
                          label: Text('事件'),
                        ),
                        ButtonSegment(
                          value: ResultType.todo,
                          icon: Icon(Icons.check_circle_outline),
                          label: Text('待办'),
                        ),
                      ],
                      selected: {_type},
                      onSelectionChanged: (value) {
                        setState(() => _type = value.first);
                      },
                    ),
                    const SizedBox(height: 14),
                    SurfacePanel(
                      child: Column(
                        children: [
                          if (_type == ResultType.event)
                            Row(
                              children: [
                                Expanded(
                                  child: _QuickDateTimeField(
                                    key: const Key('quick_create_start'),
                                    label: '开始',
                                    value: _start,
                                    allDay: _allDay,
                                    onChanged: (value) {
                                      setState(() {
                                        _start = value;
                                        if (!_end.isAfter(_start)) {
                                          _end = _start.add(
                                            const Duration(hours: 1),
                                          );
                                        }
                                      });
                                    },
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Icon(Icons.arrow_forward),
                                ),
                                Expanded(
                                  child: _QuickDateTimeField(
                                    key: const Key('quick_create_end'),
                                    label: '结束',
                                    value: _end,
                                    allDay: _allDay,
                                    onChanged: (value) =>
                                        setState(() => _end = value),
                                  ),
                                ),
                              ],
                            )
                          else
                            _QuickDateTimeField(
                              key: const Key('quick_create_due'),
                              label: '截止',
                              value: _due,
                              allDay: false,
                              onChanged: (value) =>
                                  setState(() => _due = value),
                            ),
                          const SizedBox(height: 4),
                          TextButton.icon(
                            key: const Key('quick_create_more'),
                            onPressed: () =>
                                setState(() => _expanded = !_expanded),
                            icon: Icon(
                              _expanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                            ),
                            label: Text(_expanded ? '收起设置' : '更多设置'),
                          ),
                        ],
                      ),
                    ),
                    if (_expanded)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: _MoreSettings(
                          type: _type,
                          allDay: _allDay,
                          start: _start,
                          end: _end,
                          due: _due,
                          repeatFrequency: _repeatFrequency,
                          repeatEnd: _repeatEnd,
                          repeatUntil: _repeatUntil,
                          repeatCount: _repeatCount,
                          tags: _tags,
                          body: _body,
                          status: _status,
                          matterId: _matterId,
                          matters: app.matters,
                          onAllDayChanged: (value) {
                            setState(() {
                              _allDay = value;
                              if (value) {
                                _start = DateTime(
                                  _start.year,
                                  _start.month,
                                  _start.day,
                                );
                                _end = _start.add(const Duration(days: 1));
                              }
                            });
                          },
                          onStartChanged: (value) => setState(() {
                            _start = value;
                            if (!_end.isAfter(_start)) {
                              _end = _start.add(const Duration(hours: 1));
                            }
                          }),
                          onEndChanged: (value) => setState(() => _end = value),
                          onDueChanged: (value) => setState(() => _due = value),
                          onRepeatFrequencyChanged: (value) =>
                              setState(() => _repeatFrequency = value),
                          onRepeatEndChanged: (value) =>
                              setState(() => _repeatEnd = value),
                          onRepeatUntilChanged: (value) =>
                              setState(() => _repeatUntil = value),
                          onStatusChanged: (value) =>
                              setState(() => _status = value),
                          onMatterChanged: (value) =>
                              setState(() => _matterId = value),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('标题不能为空')));
      return;
    }
    if (_type == ResultType.event && !_end.isAfter(_start)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('结束时间必须晚于开始时间')));
      return;
    }
    setState(() => _saving = true);
    final app = AppScope.of(context);
    try {
      final tags = _tags.text
          .split(RegExp(r'[,，\s]+'))
          .map((tag) => tag.trim().replaceFirst('#', ''))
          .where((tag) => tag.isNotEmpty)
          .toList(growable: false);
      final document = await app.createManual(
        type: _type,
        title: title,
        body: _body.text,
        status: _status,
        due: _type == ResultType.todo ? _due : null,
        matterId: _matterId,
        start: _type == ResultType.event ? _start : null,
        end: _type == ResultType.event ? _end : null,
        allDay: _type == ResultType.event && _allDay,
        recurrence: _type == ResultType.event ? _recurrenceRule() : null,
        tags: tags,
      );
      if (mounted) {
        Navigator.pop(context, document);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String? _recurrenceRule() {
    final parts = <String>[];
    switch (_repeatFrequency) {
      case _RepeatFrequency.none:
        return null;
      case _RepeatFrequency.daily:
        parts.add('FREQ=DAILY');
      case _RepeatFrequency.weekly:
        parts
          ..add('FREQ=WEEKLY')
          ..add('BYDAY=${recurrenceWeekdayCode(_start.weekday)}');
      case _RepeatFrequency.monthly:
        parts.add('FREQ=MONTHLY');
    }
    switch (_repeatEnd) {
      case _RepeatEnd.until:
        parts.add('UNTIL=${DateFormat('yyyyMMdd').format(_repeatUntil)}');
      case _RepeatEnd.count:
        final count = int.tryParse(_repeatCount.text.trim());
        parts.add('COUNT=${count != null && count > 0 ? count : 10}');
    }
    return parts.join(';');
  }
}

class _MoreSettings extends StatelessWidget {
  const _MoreSettings({
    required this.type,
    required this.allDay,
    required this.start,
    required this.end,
    required this.due,
    required this.repeatFrequency,
    required this.repeatEnd,
    required this.repeatUntil,
    required this.repeatCount,
    required this.tags,
    required this.body,
    required this.status,
    required this.matterId,
    required this.matters,
    required this.onAllDayChanged,
    required this.onStartChanged,
    required this.onEndChanged,
    required this.onDueChanged,
    required this.onRepeatFrequencyChanged,
    required this.onRepeatEndChanged,
    required this.onRepeatUntilChanged,
    required this.onStatusChanged,
    required this.onMatterChanged,
  });

  final ResultType type;
  final bool allDay;
  final DateTime start;
  final DateTime end;
  final DateTime due;
  final _RepeatFrequency repeatFrequency;
  final _RepeatEnd repeatEnd;
  final DateTime repeatUntil;
  final TextEditingController repeatCount;
  final TextEditingController tags;
  final TextEditingController body;
  final ResultStatus status;
  final String? matterId;
  final List<ResultDocument> matters;
  final ValueChanged<bool> onAllDayChanged;
  final ValueChanged<DateTime> onStartChanged;
  final ValueChanged<DateTime> onEndChanged;
  final ValueChanged<DateTime> onDueChanged;
  final ValueChanged<_RepeatFrequency> onRepeatFrequencyChanged;
  final ValueChanged<_RepeatEnd> onRepeatEndChanged;
  final ValueChanged<DateTime> onRepeatUntilChanged;
  final ValueChanged<ResultStatus> onStatusChanged;
  final ValueChanged<String?> onMatterChanged;

  @override
  Widget build(BuildContext context) {
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (type == ResultType.event) ...[
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: allDay,
                title: const Text('全天'),
                onChanged: onAllDayChanged,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _QuickDateTimeField(
                    label: '开始',
                    value: start,
                    allDay: allDay,
                    onChanged: onStartChanged,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickDateTimeField(
                    label: '结束',
                    value: end,
                    allDay: allDay,
                    onChanged: onEndChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<_RepeatFrequency>(
              initialValue: repeatFrequency,
              decoration: const InputDecoration(
                labelText: '重复',
                prefixIcon: Icon(Icons.repeat),
              ),
              items: const [
                DropdownMenuItem(
                  value: _RepeatFrequency.none,
                  child: Text('不重复'),
                ),
                DropdownMenuItem(
                  value: _RepeatFrequency.daily,
                  child: Text('每天'),
                ),
                DropdownMenuItem(
                  value: _RepeatFrequency.weekly,
                  child: Text('每周'),
                ),
                DropdownMenuItem(
                  value: _RepeatFrequency.monthly,
                  child: Text('每月'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  onRepeatFrequencyChanged(value);
                }
              },
            ),
            if (repeatFrequency != _RepeatFrequency.none) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<_RepeatEnd>(
                initialValue: repeatEnd,
                decoration: const InputDecoration(
                  labelText: '重复结束',
                  prefixIcon: Icon(Icons.event_repeat),
                ),
                items: const [
                  DropdownMenuItem(
                    value: _RepeatEnd.until,
                    child: Text('在日期结束'),
                  ),
                  DropdownMenuItem(
                    value: _RepeatEnd.count,
                    child: Text('重复次数'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    onRepeatEndChanged(value);
                  }
                },
              ),
              const SizedBox(height: 12),
              if (repeatEnd == _RepeatEnd.until)
                _QuickDateTimeField(
                  label: '结束日期',
                  value: repeatUntil,
                  allDay: true,
                  onChanged: onRepeatUntilChanged,
                )
              else
                TextField(
                  controller: repeatCount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '重复次数',
                    prefixIcon: Icon(Icons.numbers),
                  ),
                ),
            ],
            const SizedBox(height: 12),
          ] else ...[
            _QuickDateTimeField(
              label: '截止',
              value: due,
              allDay: false,
              onChanged: onDueChanged,
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: tags,
            decoration: const InputDecoration(
              labelText: '标签',
              hintText: '用逗号或空格分隔',
              prefixIcon: Icon(Icons.tag),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: matterId,
            decoration: const InputDecoration(
              labelText: '所属事项',
              prefixIcon: Icon(Icons.account_tree_outlined),
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('无')),
              for (final matter in matters)
                DropdownMenuItem<String?>(
                  value: matter.id,
                  child: Text(matter.title),
                ),
            ],
            onChanged: onMatterChanged,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ResultStatus>(
            initialValue: status,
            decoration: const InputDecoration(
              labelText: '状态',
              prefixIcon: Icon(Icons.verified_outlined),
            ),
            items: [
              for (final value in ResultStatus.values)
                DropdownMenuItem(value: value, child: Text(value.label)),
            ],
            onChanged: (value) {
              if (value != null) {
                onStatusChanged(value);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('quick_create_body'),
            controller: body,
            minLines: 5,
            maxLines: 10,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: 'Markdown 正文',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickDateTimeField extends StatelessWidget {
  const _QuickDateTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.allDay,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final bool allDay;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final format = allDay ? DateFormat('MM月dd日') : DateFormat('MM月dd日 HH:mm');
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.schedule),
        ),
        child: Text(format.format(value)),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(value.year - 5),
      lastDate: DateTime(value.year + 10),
    );
    if (date == null || !context.mounted) {
      return;
    }
    if (allDay) {
      onChanged(DateTime(date.year, date.month, date.day));
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (time != null) {
      onChanged(
        DateTime(date.year, date.month, date.day, time.hour, time.minute),
      );
    }
  }
}
