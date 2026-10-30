import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/table_models.dart';
import '../../modules/tables/table_library.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import 'table_fields_page.dart';

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
                const SizedBox(height: 14),
                _TableFieldsPanel(
                  fields: table.fields,
                  onManage: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => TableFieldsPage(tableId: table.id),
                    ),
                  ),
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
    final movedTo = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => TableEntryEditorPage(
          tableId: ownerTableId,
          type: entry?.type ?? type,
          entry: entry,
        ),
      ),
    );
    if (!context.mounted || movedTo == null || movedTo == ownerTableId) return;
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => TableDetailPage(tableId: movedTo),
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

class _TableFieldsPanel extends StatelessWidget {
  const _TableFieldsPanel({required this.fields, required this.onManage});

  final List<TableFieldDefinition> fields;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfacePanel(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          Icon(Icons.tune_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fields.isEmpty
                  ? '自定义字段 · 尚未设置'
                  : '自定义字段 · ${fields.map((field) => field.name).join('、')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            key: const Key('manage_table_fields'),
            onPressed: onManage,
            child: const Text('管理'),
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

class _FieldMappingDialog extends StatefulWidget {
  const _FieldMappingDialog({
    required this.sourceFields,
    required this.targetFields,
  });

  final List<TableFieldDefinition> sourceFields;
  final List<TableFieldDefinition> targetFields;

  @override
  State<_FieldMappingDialog> createState() => _FieldMappingDialogState();
}

class _FieldMappingDialogState extends State<_FieldMappingDialog> {
  late final Map<String, String?> _mapping;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mapping = {
      for (final source in widget.sourceFields)
        source.id: _defaultTarget(source)?.id,
    };
  }

  TableFieldDefinition? _defaultTarget(TableFieldDefinition source) {
    final sameId = widget.targetFields.where(
      (target) => target.id == source.id && target.type == source.type,
    );
    if (sameId.length == 1) return sameId.single;
    final sameName = widget.targetFields.where(
      (target) => target.name == source.name && target.type == source.type,
    );
    return sameName.length == 1 ? sameName.single : null;
  }

  void _confirm() {
    if (_mapping.values.any((targetId) => targetId == null)) {
      setState(() => _error = '请为每个有值字段选择目标字段。');
      return;
    }
    final selectedIds = _mapping.values.cast<String>().toList();
    if (selectedIds.toSet().length != selectedIds.length) {
      setState(() => _error = '每个源字段需要映射到不同的目标字段。');
      return;
    }
    Navigator.pop(context, {
      for (final entry in _mapping.entries) entry.key: entry.value!,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('映射自定义字段'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('移动时会保留内容 ID，并按下列映射转换字段归属。选项值按相同标签匹配。'),
            const SizedBox(height: 12),
            for (final source in widget.sourceFields) ...[
              DropdownButtonFormField<String>(
                key: ValueKey('map_field_${source.id}'),
                initialValue: _mapping[source.id],
                decoration: InputDecoration(
                  labelText: '${source.name}（${_customTypeLabel(source.type)}）',
                ),
                items: [
                  for (final target in widget.targetFields.where(
                    (target) => target.type == source.type,
                  ))
                    DropdownMenuItem(
                      value: target.id,
                      child: Text(target.name),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _mapping[source.id] = value),
              ),
              const SizedBox(height: 8),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消移动'),
      ),
      FilledButton(
        key: const Key('confirm_field_mapping'),
        onPressed: _confirm,
        child: const Text('确认映射并移动'),
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
    this.initialDate,
  });

  final String tableId;
  final TableContentType type;
  final TableEntryDocument? entry;
  final DateTime? initialDate;

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
  late final Map<String, Object?> _customValues;
  final Map<String, TextEditingController> _customTextControllers = {};
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
    _due =
        entry?.due ??
        (entry == null && widget.type == TableContentType.todo
            ? widget.initialDate
            : null);
    _start =
        entry?.start ??
        (entry == null && widget.type == TableContentType.schedule
            ? widget.initialDate
            : null);
    _end = entry?.end;
    _occurredAt =
        entry?.occurredAt ??
        (entry == null && widget.type == TableContentType.event
            ? widget.initialDate
            : null);
    _done = entry?.done ?? false;
    _customValues = Map<String, Object?>.of(entry?.customValues ?? const {});
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    for (final controller in _customTextControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<TableFieldDefinition> get _fields =>
      AppScope.tables(context).findTable(widget.tableId)?.fields ?? const [];

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
          if (_editing && AppScope.tables(context).tables.length > 1)
            IconButton(
              key: const Key('move_table_entry'),
              tooltip: '移动到其他表',
              onPressed: _saving ? null : _moveToAnotherTable,
              icon: const Icon(Icons.drive_file_move_outlined),
            ),
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
          if (_fields.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionHeading(title: '自定义字段'),
            const SizedBox(height: 8),
            for (final field in _fields) ...[
              _customFieldInput(field),
              const SizedBox(height: 10),
            ],
          ],
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

  Widget _customFieldInput(TableFieldDefinition field) {
    final storedValue = _customValues[field.id] ?? field.defaultValue;
    final label = field.required ? '${field.name}（必填）' : field.name;
    switch (field.type) {
      case CustomFieldType.text:
        final controller = _customTextControllers.putIfAbsent(
          field.id,
          () => TextEditingController(text: storedValue?.toString() ?? ''),
        );
        return TextField(
          key: ValueKey('custom_field_${field.id}'),
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        );
      case CustomFieldType.number:
        final controller = _customTextControllers.putIfAbsent(
          field.id,
          () => TextEditingController(text: storedValue?.toString() ?? ''),
        );
        return TextField(
          key: ValueKey('custom_field_${field.id}'),
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        );
      case CustomFieldType.date:
        final date = storedValue is String
            ? DateTime.tryParse(storedValue)
            : null;
        return _DateTimeField(
          key: ValueKey('custom_field_${field.id}'),
          label: label,
          value: date,
          onPick: (value) => setState(() {
            if (value == null) {
              _customValues.remove(field.id);
            } else {
              _customValues[field.id] = value.toIso8601String();
            }
          }),
        );
      case CustomFieldType.singleSelect:
        final selected =
            storedValue is String &&
                field.options.any((option) => option.id == storedValue)
            ? storedValue
            : null;
        return Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('custom_field_${field.id}'),
                initialValue: selected,
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final option in field.options)
                    DropdownMenuItem(
                      value: option.id,
                      child: Text(option.label),
                    ),
                ],
                onChanged: (value) => setState(() {
                  if (value == null) {
                    _customValues.remove(field.id);
                  } else {
                    _customValues[field.id] = value;
                  }
                }),
              ),
            ),
            if (selected != null)
              IconButton(
                tooltip: '清除字段值',
                onPressed: () => setState(() => _customValues.remove(field.id)),
                icon: const Icon(Icons.close),
              ),
          ],
        );
      case CustomFieldType.multiSelect:
        final selected = storedValue is List
            ? storedValue.whereType<String>().toSet()
            : <String>{};
        return InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final option in field.options)
                FilterChip(
                  label: Text(option.label),
                  selected: selected.contains(option.id),
                  onSelected: (enabled) => setState(() {
                    final values = {...selected};
                    if (enabled) {
                      values.add(option.id);
                    } else {
                      values.remove(option.id);
                    }
                    if (values.isEmpty) {
                      _customValues.remove(field.id);
                    } else {
                      _customValues[field.id] = values.toList(growable: false);
                    }
                  }),
                ),
            ],
          ),
        );
      case CustomFieldType.checkbox:
        return Row(
          children: [
            Expanded(
              child: SwitchListTile(
                key: ValueKey('custom_field_${field.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(label),
                value: storedValue is bool ? storedValue : false,
                onChanged: (value) =>
                    setState(() => _customValues[field.id] = value),
              ),
            ),
            if (_customValues.containsKey(field.id))
              IconButton(
                tooltip: '清除字段值',
                onPressed: () => setState(() => _customValues.remove(field.id)),
                icon: const Icon(Icons.close),
              ),
          ],
        );
    }
  }

  Map<String, Object?> _readCustomValues() {
    final values = Map<String, Object?>.of(_customValues);
    for (final field in _fields) {
      if (field.type == CustomFieldType.text ||
          field.type == CustomFieldType.number) {
        final text = _customTextControllers[field.id]?.text ?? '';
        if (text.isEmpty) {
          values.remove(field.id);
        } else if (field.type == CustomFieldType.text) {
          values[field.id] = text;
        } else {
          final number = num.tryParse(text);
          if (number == null || !number.isFinite) {
            throw FormatException('“${field.name}”必须填写有效数字。');
          }
          values[field.id] = number;
        }
      }
      final value = values[field.id] ?? field.defaultValue;
      if (field.required &&
          (value == null || value == '' || (value is List && value.isEmpty))) {
        throw FormatException('请填写必填字段“${field.name}”。');
      }
    }
    return values;
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
    final Map<String, Object?> customValues;
    try {
      customValues = _readCustomValues();
    } on FormatException catch (error) {
      setState(() => _error = error.message);
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
            customValues: customValues,
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
            customValues: customValues,
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

  Future<void> _moveToAnotherTable() async {
    final entry = widget.entry;
    if (entry == null) return;
    final library = AppScope.tables(context);
    final targets = library.tables
        .where((table) => table.id != entry.tableId && !table.deleted)
        .toList(growable: false);
    final target = await showModalBottomSheet<TableDocument>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('移动到哪张表？')),
            for (final table in targets)
              ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: Text(table.title),
                subtitle: Text(_roleLabel(table.role)),
                onTap: () => Navigator.pop(context, table),
              ),
          ],
        ),
      ),
    );
    if (!mounted || target == null) return;
    final source = library.findTable(entry.tableId);
    if (source == null) {
      setState(() => _error = '原表不存在，无法移动。');
      return;
    }
    final sourceFields = {for (final field in source.fields) field.id: field};
    final populatedFields = entry.customValues.entries
        .where((value) => value.value != null)
        .map((value) => sourceFields[value.key])
        .whereType<TableFieldDefinition>()
        .toList(growable: false);
    if (populatedFields.length !=
        entry.customValues.values.where((value) => value != null).length) {
      setState(() => _error = '内容中的字段值与源表定义不一致，已停止移动。');
      return;
    }
    final unrepresentableFields = populatedFields
        .where(
          (field) =>
              !target.fields.any((candidate) => candidate.type == field.type),
        )
        .map((field) => field.name)
        .toList(growable: false);
    if (unrepresentableFields.isNotEmpty) {
      await _showFieldMoveError(
        '目标表没有同类型字段：${unrepresentableFields.join('、')}。源表内容未改变。',
      );
      return;
    }
    var fieldMapping = <String, String>{};
    if (populatedFields.isNotEmpty) {
      final selectedMapping = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => _FieldMappingDialog(
          sourceFields: populatedFields,
          targetFields: target.fields,
        ),
      );
      if (!mounted || selectedMapping == null) return;
      fieldMapping = selectedMapping;
    }
    final optionMapping = <String, Map<String, String>>{};
    final incompatible = <String>[];
    final targetFields = {for (final field in target.fields) field.id: field};
    for (final value in entry.customValues.entries.where(
      (value) => value.value != null,
    )) {
      final oldField = sourceFields[value.key]!;
      final targetFieldId = fieldMapping[value.key] ?? value.key;
      final newField = targetFields[targetFieldId];
      if (newField == null || oldField.type != newField.type) {
        incompatible.add(oldField.name);
        continue;
      }
      if (oldField.type == CustomFieldType.singleSelect ||
          oldField.type == CustomFieldType.multiSelect) {
        final selectedOptionIds = oldField.type == CustomFieldType.singleSelect
            ? [value.value as String]
            : (value.value as List<Object?>).cast<String>();
        final mapping = <String, String>{};
        for (final sourceOptionId in selectedOptionIds) {
          TableFieldOption? sourceOption;
          for (final option in oldField.options) {
            if (option.id == sourceOptionId) sourceOption = option;
          }
          final selectedSourceOption = sourceOption;
          final matches = selectedSourceOption == null
              ? const <TableFieldOption>[]
              : newField.options
                    .where(
                      (option) => option.label == selectedSourceOption.label,
                    )
                    .toList(growable: false);
          if (matches.length != 1) {
            incompatible.add(
              '${oldField.name} / ${sourceOption?.label ?? sourceOptionId}',
            );
          } else {
            mapping[sourceOptionId] = matches.single.id;
          }
        }
        optionMapping[value.key] = mapping;
      } else if (!_fitsField(value.value, newField)) {
        incompatible.add(oldField.name);
      }
    }
    if (incompatible.isNotEmpty) {
      await _showFieldMoveError(
        '目标表中没有兼容定义/选项：${incompatible.toSet().join('、')}。源表内容未改变。',
        title: '有字段值无法映射',
      );
      return;
    }
    try {
      await library.moveEntry(
        id: entry.id,
        tableId: target.id,
        expectedRevision: entry.revision,
        fieldMapping: fieldMapping,
        optionMapping: optionMapping,
      );
      if (mounted) Navigator.pop(context, target.id);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '移动失败：$error');
    }
  }

  Future<void> _showFieldMoveError(
    String message, {
    String title = '目标表字段不兼容',
  }) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回'),
        ),
      ],
    ),
  );

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
    super.key,
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

bool _fitsField(Object? value, TableFieldDefinition field) {
  if (value == null) return true;
  switch (field.type) {
    case CustomFieldType.text:
      return value is String;
    case CustomFieldType.number:
      return value is num && value.isFinite;
    case CustomFieldType.date:
      return value is String && DateTime.tryParse(value) != null;
    case CustomFieldType.singleSelect:
      return value is String &&
          field.options.any((option) => option.id == value);
    case CustomFieldType.multiSelect:
      return value is List &&
          value.every(
            (item) =>
                item is String &&
                field.options.any((option) => option.id == item),
          );
    case CustomFieldType.checkbox:
      return value is bool;
  }
}

String _customTypeLabel(CustomFieldType type) => switch (type) {
  CustomFieldType.text => '文本',
  CustomFieldType.number => '数字',
  CustomFieldType.date => '日期时间',
  CustomFieldType.singleSelect => '单选',
  CustomFieldType.multiSelect => '多选',
  CustomFieldType.checkbox => '勾选',
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
