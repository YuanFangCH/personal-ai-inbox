import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/table_models.dart';
import '../../modules/tables/table_library.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

class TableDetailPage extends StatelessWidget {
  const TableDetailPage({super.key, required this.tableId});

  final String tableId;

  @override
  Widget build(BuildContext context) {
    final library = AppScope.tables(context);
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final table = library.findTable(tableId);
        if (table == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.error_outline,
              title: '找不到这张表',
              message: '它可能已被删除或尚未同步到本端。',
            ),
          );
        }
        final entries =
            library.entries
                .where((entry) => entry.tableId == tableId && !entry.deleted)
                .toList(growable: false)
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return Scaffold(
          appBar: AppBar(title: Text(table.title)),
          body: PageFrame(
            title: table.title,
            subtitle: '${_roleLabel(table.role)} · ${entries.length} 条内容',
            actions: [
              FilledButton.icon(
                key: const Key('table_add_content'),
                onPressed: () => _showCreateMenu(context, tableId),
                icon: const Icon(Icons.add),
                label: const Text('添加内容'),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TableBodyPanel(
                  table: table,
                  onEdit: () => _editTableBody(context, library, table),
                ),
                const SizedBox(height: 22),
                SectionHeading(
                  title: '表内内容',
                  trailing: Text('${entries.length} 条'),
                ),
                const SizedBox(height: 8),
                if (entries.isEmpty)
                  EmptyState(
                    icon: Icons.note_add_outlined,
                    title: '这张表还没有条目',
                    message: '可以只写上方正文，也可以添加笔记、待办、日程或事件。',
                    action: FilledButton.icon(
                      onPressed: () => _showCreateMenu(context, tableId),
                      icon: const Icon(Icons.add),
                      label: const Text('添加内容'),
                    ),
                  )
                else
                  for (final entry in entries) ...[
                    _EntryCard(
                      entry: entry,
                      onTap: () => _openEditor(context, tableId, entry: entry),
                    ),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _editTableBody(
    BuildContext context,
    TableLibrary library,
    TableDocument table,
  ) async {
    final body = await showDialog<String>(
      context: context,
      builder: (context) => _TableBodyDialog(initialValue: table.body),
    );
    if (!context.mounted || body == null) return;
    try {
      await library.updateTable(
        table.copyWith(body: body),
        expectedRevision: table.revision,
      );
    } on Object catch (error) {
      if (context.mounted) _showMessage(context, '保存失败：$error');
    }
  }

  Future<void> _showCreateMenu(
    BuildContext context,
    String ownerTableId,
  ) async {
    final selected = await showModalBottomSheet<TableContentType>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('添加到这张表')),
            for (final type in TableContentType.values)
              ListTile(
                leading: Icon(_typeIcon(type)),
                title: Text(_typeLabel(type)),
                onTap: () => Navigator.pop(context, type),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted || selected == null) return;
    await _openEditor(context, ownerTableId, type: selected);
  }

  Future<void> _openEditor(
    BuildContext context,
    String ownerTableId, {
    TableContentType type = TableContentType.note,
    TableEntryDocument? entry,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TableEntryEditorPage(
          tableId: ownerTableId,
          type: entry?.type ?? type,
          entry: entry,
        ),
      ),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TableBodyPanel extends StatelessWidget {
  const _TableBodyPanel({required this.table, required this.onEdit});

  final TableDocument table;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = table.body.trim();
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.notes_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '表正文',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                key: const Key('table_body_edit'),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(body.isEmpty ? '写正文' : '编辑'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body.isEmpty ? '这张表可以先作为记事簿，直接记录文本。' : body,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: body.isEmpty ? theme.colorScheme.onSurfaceVariant : null,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _TableBodyDialog extends StatefulWidget {
  const _TableBodyDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_TableBodyDialog> createState() => _TableBodyDialogState();
}

class _TableBodyDialogState extends State<_TableBodyDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('编辑表正文'),
    content: SizedBox(
      width: 560,
      child: TextField(
        key: const Key('table_body_dialog_input'),
        controller: _controller,
        autofocus: true,
        minLines: 8,
        maxLines: 16,
        decoration: const InputDecoration(
          hintText: '像笔记一样记录这张表的背景、说明或想法…',
          border: OutlineInputBorder(),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('table_body_dialog_save'),
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('保存正文'),
      ),
    ],
  );
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.onTap});

  final TableEntryDocument entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = entry.body.trim();
    final businessTime = _businessTime(entry);
    return Material(
      color: theme.brightness == Brightness.dark
          ? const Color(0xff202123)
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 32,
                margin: const EdgeInsets.only(right: 11, top: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_typeIcon(entry.type), size: 18),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (entry.type == TableContentType.todo)
                          Checkbox(
                            value: entry.done,
                            onChanged: (value) => _setDone(context, value),
                          ),
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          _typeLabel(entry.type),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        if (businessTime != null)
                          Text(
                            _formatDateTime(businessTime),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setDone(BuildContext context, bool? value) async {
    if (value == null) return;
    final library = AppScope.tables(context);
    try {
      await library.updateEntry(
        entry.copyWith(done: value),
        expectedRevision: entry.revision,
      );
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('更新待办失败：$error')));
      }
    }
  }
}

class TableEntryEditorPage extends StatefulWidget {
  const TableEntryEditorPage({
    super.key,
    required this.tableId,
    required this.type,
    this.entry,
  });

  final String tableId;
  final TableContentType type;
  final TableEntryDocument? entry;

  @override
  State<TableEntryEditorPage> createState() => _TableEntryEditorPageState();
}

class _TableEntryEditorPageState extends State<TableEntryEditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _tags;
  DateTime? _due;
  DateTime? _start;
  DateTime? _end;
  DateTime? _occurredAt;
  bool _done = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _title = TextEditingController(text: entry?.title ?? '');
    _body = TextEditingController(text: entry?.body ?? '');
    _tags = TextEditingController(text: entry?.tags.join(', ') ?? '');
    _due = entry?.due;
    _start = entry?.start;
    _end = entry?.end;
    _occurredAt = entry?.occurredAt;
    _done = entry?.done ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing
              ? '编辑${_typeLabel(widget.type)}'
              : '新建${_typeLabel(widget.type)}',
        ),
        actions: [
          if (_editing)
            IconButton(
              tooltip: '删除',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          TextButton(
            key: const Key('table_entry_save'),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            key: const Key('table_entry_title'),
            controller: _title,
            autofocus: !_editing,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: '标题',
              hintText: _typeLabel(widget.type),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('table_entry_body'),
            controller: _body,
            minLines: 6,
            maxLines: 18,
            decoration: const InputDecoration(
              labelText: '正文',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(
              labelText: '标签（逗号分隔）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          ..._timeFields(context),
          if (widget.type == TableContentType.todo)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('已完成'),
              value: _done,
              onChanged: (value) => setState(() => _done = value),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }

  List<Widget> _timeFields(BuildContext context) {
    switch (widget.type) {
      case TableContentType.note:
        return const [];
      case TableContentType.todo:
        return [
          _DateTimeField(
            label: '截止时间（可选）',
            value: _due,
            onPick: (value) => setState(() => _due = value),
          ),
        ];
      case TableContentType.schedule:
        return [
          _DateTimeField(
            label: '开始时间（必填）',
            value: _start,
            onPick: (value) => setState(() => _start = value),
          ),
          const SizedBox(height: 12),
          _DateTimeField(
            label: '结束时间（可选）',
            value: _end,
            onPick: (value) => setState(() => _end = value),
          ),
        ];
      case TableContentType.event:
        return [
          _DateTimeField(
            label: '发生时间（可选）',
            value: _occurredAt,
            onPick: (value) => setState(() => _occurredAt = value),
          ),
        ];
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请填写标题。');
      return;
    }
    if (widget.type == TableContentType.schedule && _start == null) {
      setState(() => _error = '日程必须设置开始时间。');
      return;
    }
    if (_start != null && _end != null && !_end!.isAfter(_start!)) {
      setState(() => _error = '结束时间必须晚于开始时间。');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final now = DateTime.now();
    final existing = widget.entry;
    final tags = _tags.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList(growable: false);
    try {
      final library = AppScope.tables(context);
      if (existing == null) {
        await library.createEntry(
          TableEntryDocument(
            id: 'nt_${const Uuid().v4().replaceAll('-', '')}',
            type: widget.type,
            tableId: widget.tableId,
            title: title,
            revision: 1,
            createdAt: now,
            updatedAt: now,
            body: _body.text,
            tags: tags,
            due: _due,
            done: _done,
            start: _start,
            end: _end,
            occurredAt: _occurredAt,
          ),
        );
      } else {
        await library.updateEntry(
          existing.copyWith(
            title: title,
            updatedAt: now,
            body: _body.text,
            tags: tags,
            due: _due,
            done: _done,
            start: _start,
            end: _end,
            occurredAt: _occurredAt,
          ),
          expectedRevision: existing.revision,
        );
      }
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final existing = widget.entry;
    if (existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条内容？'),
        content: const Text('删除后可在 10 分钟内撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      await AppScope.tables(context)
          .deleteEntry(id: existing.id, expectedRevision: existing.revision);
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '删除失败：$error');
    }
  }
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onPick;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          child: Text(value == null ? '未设置' : _formatDateTime(value!)),
        ),
      ),
      IconButton(
        tooltip: '选择时间',
        onPressed: () async =>
            onPick(await _pickDateTime(context, value ?? DateTime.now())),
        icon: const Icon(Icons.schedule_outlined),
      ),
      if (value != null)
        IconButton(
          tooltip: '清除时间',
          onPressed: () => onPick(null),
          icon: const Icon(Icons.close),
        ),
    ],
  );
}

Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

DateTime? _businessTime(TableEntryDocument entry) => switch (entry.type) {
  TableContentType.note => null,
  TableContentType.todo => entry.due,
  TableContentType.schedule => entry.start,
  TableContentType.event => entry.occurredAt,
};

String _formatDateTime(DateTime value) =>
    '${value.month}月${value.day}日 ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _roleLabel(TableRole role) => switch (role) {
  TableRole.inboxTodo => '默认待办表',
  TableRole.inboxSchedule => '默认日程表',
  TableRole.inboxEvent => '默认事件表',
  TableRole.custom => '自定义表',
};

String _typeLabel(TableContentType type) => switch (type) {
  TableContentType.note => '笔记',
  TableContentType.todo => '待办',
  TableContentType.schedule => '日程',
  TableContentType.event => '事件',
};

IconData _typeIcon(TableContentType type) => switch (type) {
  TableContentType.note => Icons.notes_outlined,
  TableContentType.todo => Icons.check_box_outlined,
  TableContentType.schedule => Icons.event_outlined,
  TableContentType.event => Icons.history_edu_outlined,
};
