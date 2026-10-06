import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../app_scope.dart';

class DocumentEditorPage extends StatefulWidget {
  const DocumentEditorPage({super.key, required this.document})
    : initialType = null;

  const DocumentEditorPage.create({super.key, required ResultType type})
    : document = null,
      initialType = type;

  final ResultDocument? document;
  final ResultType? initialType;

  @override
  State<DocumentEditorPage> createState() => _DocumentEditorPageState();
}

class _DocumentEditorPageState extends State<DocumentEditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _tags;
  late final TextEditingController _recurrence;
  late ResultType _type;
  late ResultStatus _status;
  DateTime? _due;
  DateTime? _start;
  DateTime? _end;
  bool _allDay = false;
  String? _matterId;
  bool _saving = false;
  int _mode = 0;

  bool get isEditing => widget.document != null;

  @override
  void initState() {
    super.initState();
    final document = widget.document;
    _title = TextEditingController(text: document?.title ?? '');
    _body = TextEditingController(text: document?.body ?? '');
    _tags = TextEditingController(text: document?.tags.join(', ') ?? '');
    _recurrence = TextEditingController(text: document?.recurrence ?? '');
    _type = document?.type ?? widget.initialType ?? ResultType.knowledge;
    _status = document?.status ?? ResultStatus.canonical;
    _due = document?.due;
    _start = document?.start;
    _end = document?.end;
    _allDay = document?.allDay ?? false;
    _matterId = document?.matterId;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    _recurrence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '编辑${_type.label}' : '新建${_type.label}'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('保存'),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<ResultType>(
                          segments: [
                            for (final type in ResultType.values)
                              ButtonSegment(
                                value: type,
                                icon: Icon(type.icon),
                                label: Text(type.label),
                              ),
                          ],
                          selected: {_type},
                          onSelectionChanged: isEditing
                              ? null
                              : (value) => setState(() => _type = value.first),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(
                          value: 0,
                          icon: Icon(Icons.edit_outlined),
                          tooltip: '编辑',
                        ),
                        ButtonSegment(
                          value: 1,
                          icon: Icon(Icons.visibility_outlined),
                          tooltip: '预览',
                        ),
                      ],
                      selected: {_mode},
                      showSelectedIcon: false,
                      onSelectionChanged: (value) =>
                          setState(() => _mode = value.first),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 900;
                      if (_mode == 1) {
                        return _Preview(title: _title.text, body: _body.text);
                      }
                      if (!wide) {
                        return _EditorForm(
                          title: _title,
                          body: _body,
                          tags: _tags,
                          recurrence: _recurrence,
                          type: _type,
                          status: _status,
                          due: _due,
                          start: _start,
                          end: _end,
                          allDay: _allDay,
                          matterId: _matterId,
                          matters: app.matters,
                          onStatusChanged: (value) =>
                              setState(() => _status = value),
                          onDueChanged: (value) => setState(() => _due = value),
                          onStartChanged: (value) =>
                              setState(() => _start = value),
                          onEndChanged: (value) => setState(() => _end = value),
                          onAllDayChanged: (value) =>
                              setState(() => _allDay = value),
                          onMatterChanged: (value) =>
                              setState(() => _matterId = value),
                          onChanged: () => setState(() {}),
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _EditorForm(
                              title: _title,
                              body: _body,
                              tags: _tags,
                              recurrence: _recurrence,
                              type: _type,
                              status: _status,
                              due: _due,
                              start: _start,
                              end: _end,
                              allDay: _allDay,
                              matterId: _matterId,
                              matters: app.matters,
                              onStatusChanged: (value) =>
                                  setState(() => _status = value),
                              onDueChanged: (value) =>
                                  setState(() => _due = value),
                              onStartChanged: (value) =>
                                  setState(() => _start = value),
                              onEndChanged: (value) =>
                                  setState(() => _end = value),
                              onAllDayChanged: (value) =>
                                  setState(() => _allDay = value),
                              onMatterChanged: (value) =>
                                  setState(() => _matterId = value),
                              onChanged: () => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            flex: 2,
                            child: _Preview(
                              title: _title.text,
                              body: _body.text,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('标题不能为空')));
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
      final current = widget.document;
      if (current == null) {
        await app.createManual(
          type: _type,
          title: _title.text,
          body: _body.text,
          status: _status,
          due: _type == ResultType.todo ? _due : null,
          matterId: _type == ResultType.todo || _type == ResultType.event
              ? _matterId
              : null,
          start: _type == ResultType.event ? _start : null,
          end: _type == ResultType.event ? _end : null,
          allDay: _allDay,
          recurrence:
              _type == ResultType.event && _recurrence.text.trim().isNotEmpty
              ? _recurrence.text.trim()
              : null,
          tags: tags,
        );
      } else {
        await app.saveDocument(
          current.copyWith(
            title: _title.text.trim(),
            body: _body.text,
            tags: tags,
            status: _status,
            due: _type == ResultType.todo ? _due : null,
            matterId: _type == ResultType.todo || _type == ResultType.event
                ? _matterId
                : null,
            start: _type == ResultType.event ? _start : null,
            end: _type == ResultType.event ? _end : null,
            allDay: _allDay,
            recurrence:
                _type == ResultType.event && _recurrence.text.trim().isNotEmpty
                ? _recurrence.text.trim()
                : null,
          ),
        );
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _EditorForm extends StatelessWidget {
  const _EditorForm({
    required this.title,
    required this.body,
    required this.tags,
    required this.recurrence,
    required this.type,
    required this.status,
    required this.due,
    required this.start,
    required this.end,
    required this.allDay,
    required this.matterId,
    required this.matters,
    required this.onStatusChanged,
    required this.onDueChanged,
    required this.onStartChanged,
    required this.onEndChanged,
    required this.onAllDayChanged,
    required this.onMatterChanged,
    required this.onChanged,
  });

  final TextEditingController title;
  final TextEditingController body;
  final TextEditingController tags;
  final TextEditingController recurrence;
  final ResultType type;
  final ResultStatus status;
  final DateTime? due;
  final DateTime? start;
  final DateTime? end;
  final bool allDay;
  final String? matterId;
  final List<ResultDocument> matters;
  final ValueChanged<ResultStatus> onStatusChanged;
  final ValueChanged<DateTime?> onDueChanged;
  final ValueChanged<DateTime?> onStartChanged;
  final ValueChanged<DateTime?> onEndChanged;
  final ValueChanged<bool> onAllDayChanged;
  final ValueChanged<String?> onMatterChanged;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('document_title_field'),
            controller: title,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '标题',
              prefixIcon: Icon(Icons.title),
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: tags,
            decoration: const InputDecoration(
              labelText: '标签',
              hintText: '用逗号或空格分隔',
              prefixIcon: Icon(Icons.tag),
            ),
          ),
          const SizedBox(height: 12),
          if (type == ResultType.todo) ...[
            _DateTimeField(label: '截止时间', value: due, onChanged: onDueChanged),
            const SizedBox(height: 12),
          ],
          if (type == ResultType.event) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: allDay,
              onChanged: onAllDayChanged,
              title: const Text('全天'),
            ),
            Row(
              children: [
                Expanded(
                  child: _DateTimeField(
                    label: '开始',
                    value: start,
                    onChanged: onStartChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateTimeField(
                    label: '结束',
                    value: end,
                    onChanged: onEndChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: recurrence,
              decoration: const InputDecoration(
                labelText: '重复规则',
                hintText: '例如 FREQ=WEEKLY;BYDAY=WE',
                prefixIcon: Icon(Icons.repeat),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (type == ResultType.todo || type == ResultType.event) ...[
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
          ],
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
            key: const Key('document_body_field'),
            controller: body,
            minLines: 12,
            maxLines: 24,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: 'Markdown 正文',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.schedule),
          suffixIcon: value == null
              ? null
              : IconButton(
                  tooltip: '清除',
                  onPressed: () => onChanged(null),
                  icon: const Icon(Icons.close, size: 18),
                ),
        ),
        child: Text(
          value == null ? '未设置' : DateFormat('yyyy-MM-dd HH:mm').format(value!),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !context.mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value ?? now),
    );
    if (time == null) {
      return;
    }
    onChanged(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title.trim().isEmpty ? '未命名' : title,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            MarkdownBody(
              data: body.trim().isEmpty ? '开始写正文……' : body,
              selectable: true,
            ),
          ],
        ),
      ),
    );
  }
}
