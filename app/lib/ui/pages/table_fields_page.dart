import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/table_models.dart';
import '../../modules/tables/table_library.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

class TableFieldsPage extends StatelessWidget {
  const TableFieldsPage({super.key, required this.tableId});

  final String tableId;

  @override
  Widget build(BuildContext context) {
    final library = AppScope.tables(context);
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final table = library.findTable(tableId);
        final readOnly = library.inboxAssignmentNeedsReview;
        if (table == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('管理字段')),
            body: const EmptyState(
              icon: Icons.error_outline,
              title: '找不到这张表',
              message: '返回表列表后重新打开。',
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text('${table.title} · 字段'),
            actions: [
              IconButton(
                key: const Key('add_table_field'),
                tooltip: '新增字段',
                onPressed: readOnly
                    ? null
                    : () => _addField(context, library, table),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (readOnly) ...[
                const MaterialBanner(
                  content: Text('收纳映射状态待核对。字段与恢复操作已暂停。'),
                  leading: Icon(Icons.warning_amber_rounded),
                  actions: [SizedBox.shrink()],
                ),
                const SizedBox(height: 12),
              ],
              const Text(
                '字段定义属于表结构，每条内容可单独填写字段值。字段类型暂不支持直接转换；删除字段和值会保留 30 天，可在本页撤销。',
              ),
              const SizedBox(height: 12),
              _FieldRecoverySection(
                tableId: table.id,
                library: library,
                readOnly: readOnly,
              ),
              const SizedBox(height: 16),
              if (table.fields.isEmpty)
                EmptyState(
                  icon: Icons.tune_outlined,
                  title: '还没有自定义字段',
                  message: '例如课程、章节、提交方式等信息可以定义成字段。',
                  action: FilledButton.icon(
                    onPressed: readOnly
                        ? null
                        : () => _addField(context, library, table),
                    icon: const Icon(Icons.add),
                    label: const Text('新增字段'),
                  ),
                )
              else
                for (final field in table.fields)
                  Card(
                    child: ListTile(
                      leading: Icon(_fieldIcon(field.type)),
                      title: Text(field.name),
                      subtitle: Text(_fieldDescription(field)),
                      trailing: PopupMenuButton<String>(
                        enabled: !readOnly,
                        onSelected: (action) {
                          if (action == 'rename') {
                            _renameField(context, library, table, field);
                          } else if (action == 'options') {
                            _editField(context, library, table, field);
                          } else if (action == 'delete') {
                            _deleteField(context, library, table, field);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'rename',
                            child: Text('重命名'),
                          ),
                          if (field.type == CustomFieldType.singleSelect ||
                              field.type == CustomFieldType.multiSelect)
                            const PopupMenuItem(
                              value: 'options',
                              child: Text('编辑选项'),
                            ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('删除字段'),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addField(
    BuildContext context,
    TableLibrary library,
    TableDocument table,
  ) async {
    final definition = await showDialog<TableFieldDefinition>(
      context: context,
      builder: (context) => const _FieldDefinitionDialog(),
    );
    if (!context.mounted || definition == null) return;
    try {
      await library.updateTable(
        table.copyWith(fields: [...table.fields, definition]),
        expectedRevision: table.revision,
      );
    } on Object catch (error) {
      if (context.mounted) _showMessage(context, '新增字段失败：$error');
    }
  }

  Future<void> _renameField(
    BuildContext context,
    TableLibrary library,
    TableDocument table,
    TableFieldDefinition field,
  ) async {
    final name = await _askForFieldName(context, field.name);
    if (!context.mounted || name == null || name == field.name) return;
    try {
      final fields = table.fields
          .map(
            (candidate) => candidate.id == field.id
                ? TableFieldDefinition(
                    id: candidate.id,
                    name: name,
                    type: candidate.type,
                    options: candidate.options,
                    required: candidate.required,
                    defaultValue: candidate.defaultValue,
                  )
                : candidate,
          )
          .toList(growable: false);
      await library.updateTable(
        table.copyWith(fields: fields),
        expectedRevision: table.revision,
      );
    } on Object catch (error) {
      if (context.mounted) _showMessage(context, '重命名失败：$error');
    }
  }

  Future<void> _editField(
    BuildContext context,
    TableLibrary library,
    TableDocument table,
    TableFieldDefinition field,
  ) async {
    final edited = await showDialog<TableFieldDefinition>(
      context: context,
      builder: (context) => _FieldDefinitionDialog(existing: field),
    );
    if (!context.mounted || edited == null) return;
    final retainedOptionIds = edited.options.map((option) => option.id).toSet();
    final removedOptions = field.options
        .where((option) => !retainedOptionIds.contains(option.id))
        .toList(growable: false);
    final usedCounts = <String, int>{};
    for (final entry in library.entries.where(
      (entry) => entry.tableId == table.id && !entry.deleted,
    )) {
      final value = entry.customValues[field.id];
      for (final removed in removedOptions) {
        final used = field.type == CustomFieldType.singleSelect
            ? value == removed.id
            : value is List && value.contains(removed.id);
        if (used) {
          usedCounts.update(
            removed.id,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
      }
    }
    if (usedCounts.isNotEmpty) {
      final count = usedCounts.values.fold<int>(0, (sum, value) => sum + value);
      _showMessage(context, '有 $count 条内容正在使用被移除的选项。请先清空这些值，再删除选项。');
      return;
    }
    try {
      await library.updateTable(
        table.copyWith(
          fields: table.fields
              .map((candidate) => candidate.id == field.id ? edited : candidate)
              .toList(growable: false),
        ),
        expectedRevision: table.revision,
      );
    } on Object catch (error) {
      if (context.mounted) _showMessage(context, '保存字段选项失败：$error');
    }
  }

  Future<void> _deleteField(
    BuildContext context,
    TableLibrary library,
    TableDocument table,
    TableFieldDefinition field,
  ) async {
    final used = library.entries
        .where(
          (entry) =>
              entry.tableId == table.id &&
              entry.customValues.containsKey(field.id),
        )
        .toList(growable: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除字段？'),
        content: Text(
          used.isEmpty
              ? '删除“${field.name}”字段定义。'
              : '删除“${field.name}”字段，并移除 ${used.length} 条内容中的字段值。字段定义和原值将保留 30 天，可在此页撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除字段和值'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;
    try {
      final batch = await library.removeTableField(
        tableId: table.id,
        fieldId: field.id,
        expectedRevision: table.revision,
      );
      if (context.mounted) {
        _showMessage(context, '字段已删除，可在 30 天内撤销（${batch.id}）。');
      }
    } on Object catch (error) {
      if (context.mounted) _showMessage(context, '删除字段失败：$error');
    }
  }

  Future<String?> _askForFieldName(BuildContext context, String initial) =>
      showDialog<String>(
        context: context,
        builder: (context) => _FieldNameDialog(initialValue: initial),
      );

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FieldRecoverySection extends StatelessWidget {
  const _FieldRecoverySection({
    required this.tableId,
    required this.library,
    required this.readOnly,
  });

  final String tableId;
  final TableLibrary library;
  final bool readOnly;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: library.fieldChangeRecoveryBatches(tableId: tableId),
    builder: (context, snapshot) {
      final batches = snapshot.data ?? const <TableRecoveryBatch>[];
      if (batches.isEmpty) return const SizedBox.shrink();
      return Card(
        child: Column(
          children: [
            for (final batch in batches)
              ListTile(
                leading: const Icon(Icons.restore_outlined),
                title: const Text('可撤销的字段删除'),
                subtitle: Text(
                  '字段定义与原有字段值保留至 ${batch.expiresAt.month}月${batch.expiresAt.day}日',
                ),
                trailing: TextButton(
                  onPressed: readOnly
                      ? null
                      : () async {
                          try {
                            await library.restoreRecoveryBatch(batch.id);
                          } on Object catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('字段恢复失败：$error')),
                              );
                            }
                          }
                        },
                  child: Text(readOnly ? '核对后可撤销' : '撤销'),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _FieldDefinitionDialog extends StatefulWidget {
  const _FieldDefinitionDialog({this.existing});

  final TableFieldDefinition? existing;

  @override
  State<_FieldDefinitionDialog> createState() => _FieldDefinitionDialogState();
}

class _FieldDefinitionDialogState extends State<_FieldDefinitionDialog> {
  final _name = TextEditingController();
  final _optionControllers = <TextEditingController>[];
  final _optionIds = <String?>[];
  CustomFieldType _type = CustomFieldType.text;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _name.text = existing.name;
      _type = existing.type;
      for (final option in existing.options) {
        _optionIds.add(option.id);
        _optionControllers.add(TextEditingController(text: option.label));
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请填写字段名称。');
      return;
    }
    final optionLabels = _optionControllers
        .map((controller) => controller.text.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final select =
        _type == CustomFieldType.singleSelect ||
        _type == CustomFieldType.multiSelect;
    if (select && optionLabels.isEmpty) {
      setState(() => _error = '单选和多选字段至少需要一个选项。');
      return;
    }
    if (optionLabels.toSet().length != optionLabels.length) {
      setState(() => _error = '选项名称不能重复。');
      return;
    }
    final options = <TableFieldOption>[];
    if (select) {
      for (var index = 0; index < _optionControllers.length; index++) {
        final label = _optionControllers[index].text.trim();
        if (label.isEmpty) continue;
        options.add(
          TableFieldOption(
            id:
                _optionIds[index] ??
                'opt_${const Uuid().v4().replaceAll('-', '')}',
            label: label,
          ),
        );
      }
    }
    Navigator.pop(
      context,
      TableFieldDefinition(
        id:
            widget.existing?.id ??
            'fld_${const Uuid().v4().replaceAll('-', '')}',
        name: name,
        type: widget.existing?.type ?? _type,
        options: options,
        required: widget.existing?.required ?? false,
        defaultValue: widget.existing?.defaultValue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? '新增自定义字段' : '编辑字段选项'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('table_field_name'),
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: '字段名称'),
          ),
          const SizedBox(height: 12),
          if (widget.existing == null)
            DropdownButtonFormField<CustomFieldType>(
              key: const Key('table_field_type'),
              initialValue: _type,
              decoration: const InputDecoration(labelText: '字段类型'),
              items: [
                for (final type in CustomFieldType.values)
                  DropdownMenuItem(
                    value: type,
                    child: Text(_fieldTypeLabel(type)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _type = value);
              },
            ),
          if (_type == CustomFieldType.singleSelect ||
              _type == CustomFieldType.multiSelect) ...[
            const SizedBox(height: 12),
            for (var index = 0; index < _optionControllers.length; index++)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: Key('table_field_option_$index'),
                      controller: _optionControllers[index],
                      decoration: InputDecoration(labelText: '选项 ${index + 1}'),
                    ),
                  ),
                  IconButton(
                    key: Key('remove_table_field_option_$index'),
                    tooltip: '移除选项',
                    onPressed: () => setState(() {
                      _optionControllers.removeAt(index).dispose();
                      _optionIds.removeAt(index);
                    }),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('add_table_field_option'),
                onPressed: () => setState(() {
                  _optionIds.add(null);
                  _optionControllers.add(TextEditingController());
                }),
                icon: const Icon(Icons.add),
                label: const Text('添加选项'),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('table_field_save'),
        onPressed: _save,
        child: Text(widget.existing == null ? '保存字段' : '保存选项'),
      ),
    ],
  );
}

class _FieldNameDialog extends StatefulWidget {
  const _FieldNameDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_FieldNameDialog> createState() => _FieldNameDialogState();
}

class _FieldNameDialogState extends State<_FieldNameDialog> {
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
    title: const Text('重命名字段'),
    content: TextField(
      key: const Key('table_field_rename_name'),
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(labelText: '字段名称'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('table_field_rename_save'),
        onPressed: () {
          final value = _controller.text.trim();
          if (value.isNotEmpty) Navigator.pop(context, value);
        },
        child: const Text('保存'),
      ),
    ],
  );
}

String _fieldDescription(TableFieldDefinition field) {
  final options = field.options.map((option) => option.label).join('、');
  return options.isEmpty
      ? _fieldTypeLabel(field.type)
      : '${_fieldTypeLabel(field.type)} · $options';
}

String _fieldTypeLabel(CustomFieldType type) => switch (type) {
  CustomFieldType.text => '文本',
  CustomFieldType.number => '数字',
  CustomFieldType.date => '日期时间',
  CustomFieldType.singleSelect => '单选',
  CustomFieldType.multiSelect => '多选',
  CustomFieldType.checkbox => '勾选',
};

IconData _fieldIcon(CustomFieldType type) => switch (type) {
  CustomFieldType.text => Icons.text_fields,
  CustomFieldType.number => Icons.numbers,
  CustomFieldType.date => Icons.calendar_month_outlined,
  CustomFieldType.singleSelect => Icons.radio_button_checked,
  CustomFieldType.multiSelect => Icons.checklist,
  CustomFieldType.checkbox => Icons.check_box_outlined,
};
