import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/table_models.dart';
import '../../modules/home_widgets/home_widgets.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

class WidgetSettingsPage extends StatefulWidget {
  const WidgetSettingsPage({super.key});

  @override
  State<WidgetSettingsPage> createState() => _WidgetSettingsPageState();
}

class _WidgetSettingsPageState extends State<WidgetSettingsPage> {
  WidgetWorkspace? _workspace;
  List<CardSummary> _cards = const [];
  bool _scheduledInitialLoad = false;
  bool _loading = true;
  bool _mutating = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _workspace = AppScope.of(context).homeWidgets;
    if (_scheduledInitialLoad) return;
    _scheduledInitialLoad = true;
    unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    final workspace = _workspace;
    final bridge = AppScope.of(context).homeWidgetBridge;
    return Scaffold(
      appBar: AppBar(title: const Text('桌面卡片')),
      body: PageFrame(
        title: '桌面卡片',
        subtitle: '管理只读内容卡片与本机桌面入口',
        actions: [
          FilledButton.icon(
            key: const Key('widget_card_create'),
            onPressed: workspace == null || _mutating
                ? null
                : () => _openEditor(workspace),
            icon: const Icon(Icons.add),
            label: const Text('新建卡片'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SurfacePanel(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_outline),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '卡片只保存显示用短文本和对象 ID。默认仅显示标题，'
                      '字段内容需在每张卡片中单独开启。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            if (workspace == null) ...[
              const SizedBox(height: 16),
              const EmptyState(
                icon: Icons.phonelink_erase_outlined,
                title: '此设备不支持桌面卡片',
                message: '桌面卡片目前仅在已接入 Android 小组件桥的设备上可用。',
              ),
            ] else if (_loading) ...[
              const SizedBox(height: 28),
              const Center(child: CircularProgressIndicator()),
            ] else if (_cards.isEmpty) ...[
              const SizedBox(height: 16),
              EmptyState(
                icon: Icons.dashboard_customize_outlined,
                title: '还没有桌面卡片',
                message: '新建卡片，选择要显示的表、条目类型和隐私级别。',
                action: FilledButton.icon(
                  onPressed: () => _openEditor(workspace),
                  icon: const Icon(Icons.add),
                  label: const Text('新建卡片'),
                ),
              ),
            ] else ...[
              const SizedBox(height: 18),
              for (final card in _cards) ...[
                _CardPanel(
                  card: card,
                  bridgeAvailable: bridge != null,
                  busy: _mutating,
                  onEdit: () => _openEditor(workspace, cardId: card.cardId),
                  onVisibilityChanged: (visibility) =>
                      _setVisibility(workspace, card, visibility),
                  onPin: bridge == null
                      ? null
                      : () => _pinCard(bridge.requestPin, card),
                  onArchive: () => _archiveCard(workspace, card),
                  onRestore: () => _restoreCard(workspace, card),
                ),
                const SizedBox(height: 10),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _reload() async {
    final workspace = _workspace;
    if (workspace == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _cards = const [];
        });
      }
      return;
    }
    try {
      final cards = await workspace.listCards(includeArchived: true);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取桌面卡片失败：$error';
      });
    }
  }

  Future<void> _openEditor(WidgetWorkspace workspace, {String? cardId}) async {
    CardDefinition? card;
    try {
      if (cardId != null) {
        card = await workspace.getCard(cardId);
        if (card == null) {
          throw StateError('卡片不存在或已被移除');
        }
      }
      if (!mounted) return;
      final receipt = await Navigator.of(context).push<CardWriteReceipt>(
        MaterialPageRoute<CardWriteReceipt>(
          builder: (_) => WidgetCardEditorPage(card: card),
        ),
      );
      if (!mounted || receipt == null) return;
      await _reload();
      if (!mounted) return;
      _showReceipt(workspace, receipt);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '打开卡片编辑器失败：$error');
    }
  }

  Future<void> _setVisibility(
    WidgetWorkspace workspace,
    CardSummary card,
    WidgetVisibility visibility,
  ) => _runCommand(
    workspace,
    CardCommand.setVisibility(
      cardId: card.cardId,
      expectedRevision: card.revision,
      visibility: visibility,
    ),
  );

  Future<void> _archiveCard(WidgetWorkspace workspace, CardSummary card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: reducedMotionAnimationStyle(context),
      builder: (context) => AlertDialog(
        title: const Text('归档这张卡片？'),
        content: const Text('已放置到桌面的实例会显示归档占位；卡片配置仍保留，可随时恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('归档'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runCommand(
      workspace,
      CardCommand.archive(cardId: card.cardId, expectedRevision: card.revision),
    );
  }

  Future<void> _restoreCard(WidgetWorkspace workspace, CardSummary card) =>
      _runCommand(
        workspace,
        CardCommand.restore(
          cardId: card.cardId,
          expectedRevision: card.revision,
        ),
      );

  Future<void> _runCommand(
    WidgetWorkspace workspace,
    CardCommand command,
  ) async {
    if (_mutating) return;
    setState(() {
      _mutating = true;
      _error = null;
    });
    try {
      final receipt = await workspace.applyCardCommand(
        command,
        operationId: _newOperationId(),
        authorize: () async => true,
      );
      if (!receipt.succeeded) {
        throw StateError(_receiptError(receipt));
      }
      await _reload();
      if (!mounted) return;
      _showReceipt(workspace, receipt);
    } catch (error) {
      if (mounted) {
        setState(() => _error = '保存桌面卡片失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _mutating = false);
      }
    }
  }

  Future<void> _pinCard(
    Future<String> Function(String cardId) requestPin,
    CardSummary card,
  ) async {
    try {
      final result = await requestPin(card.cardId);
      if (!mounted) return;
      final message = switch (result) {
        'requested' => '已请求添加“${card.spec.title}”到桌面',
        'unsupported' => '当前启动器不支持固定请求，请从桌面小组件列表手动添加',
        _ => '添加桌面卡片失败',
      };
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '请求添加桌面卡片失败：$error');
    }
  }

  void _showReceipt(WidgetWorkspace workspace, CardWriteReceipt receipt) {
    final pending =
        receipt.publishStatus == WidgetPublishStatus.pending ||
        receipt.publishStatus == WidgetPublishStatus.failed;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(pending ? '卡片已保存，桌面刷新待完成' : '卡片已保存并刷新'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => unawaited(_undo(workspace, receipt)),
          ),
        ),
      );
  }

  Future<void> _undo(
    WidgetWorkspace workspace,
    CardWriteReceipt receipt,
  ) async {
    try {
      final undoReceipt = await workspace.applyCardCommand(
        CardCommand.undo(
          cardId: receipt.cardId,
          expectedRevision: receipt.revision,
          targetOperationId: receipt.operationId,
        ),
        operationId: _newOperationId(),
        authorize: () async => true,
      );
      if (!undoReceipt.succeeded) {
        throw StateError(_receiptError(undoReceipt));
      }
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已撤销上次卡片修改')));
    } catch (error) {
      if (mounted) {
        setState(() => _error = '撤销失败：$error');
      }
    }
  }
}

class _CardPanel extends StatelessWidget {
  const _CardPanel({
    required this.card,
    required this.bridgeAvailable,
    required this.busy,
    required this.onEdit,
    required this.onVisibilityChanged,
    required this.onPin,
    required this.onArchive,
    required this.onRestore,
  });

  final CardSummary card;
  final bool bridgeAvailable;
  final bool busy;
  final VoidCallback onEdit;
  final ValueChanged<WidgetVisibility> onVisibilityChanged;
  final VoidCallback? onPin;
  final VoidCallback onArchive;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spec = card.spec;
    final source = spec.sourceMode == WidgetSourceMode.selectedTables
        ? '${spec.sections.length} 张指定表'
        : '全部表';
    return Opacity(
      opacity: card.archived ? 0.68 : 1,
      child: SurfacePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  card.archived
                      ? Icons.inventory_2_outlined
                      : Icons.dashboard_customize_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spec.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          source,
                          '版本 ${card.revision}',
                          if (card.archived) '已归档',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: Key('widget_card_edit_${card.cardId}'),
                  onPressed: busy ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: '编辑',
                ),
                IconButton(
                  key: Key('widget_card_pin_${card.cardId}'),
                  onPressed: busy || card.archived || !bridgeAvailable
                      ? null
                      : onPin,
                  icon: const Icon(Icons.add_to_home_screen_outlined),
                  tooltip: bridgeAvailable ? '添加到桌面' : '当前设备不支持固定请求',
                ),
                PopupMenuButton<_CardMenuAction>(
                  enabled: !busy,
                  onSelected: (action) {
                    switch (action) {
                      case _CardMenuAction.archive:
                        onArchive();
                        break;
                      case _CardMenuAction.restore:
                        onRestore();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (card.archived)
                      const PopupMenuItem(
                        value: _CardMenuAction.restore,
                        child: Text('恢复'),
                      )
                    else
                      const PopupMenuItem(
                        value: _CardMenuAction.archive,
                        child: Text('归档'),
                      ),
                  ],
                ),
              ],
            ),
            if (!card.archived) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.visibility_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<WidgetVisibility>(
                      key: Key(
                        'widget_card_visibility_${card.cardId}_${card.revision}',
                      ),
                      initialValue: card.visibility,
                      decoration: const InputDecoration(
                        labelText: '桌面隐私',
                        isDense: true,
                      ),
                      items: [
                        for (final visibility in WidgetVisibility.values)
                          DropdownMenuItem(
                            value: visibility,
                            child: Text(_visibilityLabel(visibility)),
                          ),
                      ],
                      onChanged: busy
                          ? null
                          : (visibility) {
                              if (visibility != null &&
                                  visibility != card.visibility) {
                                onVisibilityChanged(visibility);
                              }
                            },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _CardMenuAction { archive, restore }

class WidgetCardEditorPage extends StatefulWidget {
  const WidgetCardEditorPage({super.key, this.card});

  final CardDefinition? card;

  @override
  State<WidgetCardEditorPage> createState() => _WidgetCardEditorPageState();
}

class _WidgetCardEditorPageState extends State<WidgetCardEditorPage> {
  final _title = TextEditingController();
  late _CardDraft _draft;
  bool _initialized = false;
  bool _saving = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final tables = AppScope.of(context).tables.tables;
    if (widget.card != null) {
      _draft = _CardDraft.fromSpec(widget.card!.spec);
    } else {
      _draft = _CardDraft.blank();
      if (tables.isNotEmpty) {
        _draft.sections.add(_SectionDraft(tableId: tables.first.id));
      }
    }
    _title.text = _draft.title;
  }

  @override
  void dispose() {
    _title.dispose();
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tables = AppScope.of(context).tables.tables;
    final configuredIds = _draft.sections.map((item) => item.tableId).toSet();
    return Scaffold(
      appBar: AppBar(title: Text(widget.card == null ? '新建桌面卡片' : '编辑桌面卡片')),
      body: PageFrame(
        title: widget.card == null ? '新建卡片' : '编辑卡片',
        subtitle: '预览后会保存配置，再交给 Android 刷新桌面实例',
        actions: [
          FilledButton.icon(
            key: const Key('widget_card_save'),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.preview_outlined),
            label: const Text('预览并保存'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SurfacePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('widget_card_title'),
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: '卡片标题',
                      prefixIcon: Icon(Icons.title),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('内容来源', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<WidgetSourceMode>(
                    segments: const [
                      ButtonSegment(
                        value: WidgetSourceMode.selectedTables,
                        icon: Icon(Icons.table_chart_outlined),
                        label: Text('指定表'),
                      ),
                      ButtonSegment(
                        value: WidgetSourceMode.allTables,
                        icon: Icon(Icons.view_list_outlined),
                        label: Text('全部表'),
                      ),
                    ],
                    selected: {_draft.sourceMode},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _draft.sourceMode = selection.single;
                        if (_draft.sourceMode ==
                            WidgetSourceMode.selectedTables) {
                          _draft.excludedTableIds.clear();
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  Text('主题', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<WidgetTheme>(
                    segments: const [
                      ButtonSegment(
                        value: WidgetTheme.system,
                        icon: Icon(Icons.brightness_auto_outlined),
                        label: Text('系统'),
                      ),
                      ButtonSegment(
                        value: WidgetTheme.light,
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('浅色'),
                      ),
                      ButtonSegment(
                        value: WidgetTheme.dark,
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('深色'),
                      ),
                    ],
                    selected: {_draft.theme},
                    onSelectionChanged: (selection) {
                      setState(() => _draft.theme = selection.single);
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _draft.hideEmptySections,
                    onChanged: (value) {
                      setState(() => _draft.hideEmptySections = value);
                    },
                    title: const Text('隐藏空分区'),
                    subtitle: const Text('关闭时仍显示表名和 0 条内容'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SurfacePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SectionHeading(
                          title:
                              _draft.sourceMode ==
                                  WidgetSourceMode.selectedTables
                              ? '显示的表'
                              : '优先显示的表',
                        ),
                      ),
                      TextButton.icon(
                        key: const Key('widget_card_add_section'),
                        onPressed:
                            tables.isEmpty ||
                                tables.every(
                                  (table) => _draft.sections.any(
                                    (section) => section.tableId == table.id,
                                  ),
                                )
                            ? null
                            : () => _addSection(tables),
                        icon: const Icon(Icons.add),
                        label: const Text('添加'),
                      ),
                    ],
                  ),
                  Text(
                    _draft.sourceMode == WidgetSourceMode.selectedTables
                        ? '按这里的顺序显示，每张表只能出现一次。'
                        : '这里的表先显示，其余未排除的表随后按名称和 ID 排列。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  if (_draft.sections.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('尚未选择表。'),
                    )
                  else
                    for (
                      var index = 0;
                      index < _draft.sections.length;
                      index++
                    ) ...[
                      _SectionEditor(
                        key: ValueKey(_draft.sections[index]),
                        draft: _draft.sections[index],
                        tables: tables,
                        allowRemove:
                            _draft.sections.length > 1 ||
                            _draft.sourceMode == WidgetSourceMode.allTables,
                        onChanged: () => setState(() {}),
                        onMoveUp: index == 0
                            ? null
                            : () => _moveSection(index, index - 1),
                        onMoveDown: index == _draft.sections.length - 1
                            ? null
                            : () => _moveSection(index, index + 1),
                        onRemove: () => _removeSection(index),
                      ),
                      if (index != _draft.sections.length - 1)
                        const Divider(height: 28),
                    ],
                ],
              ),
            ),
            if (_draft.sourceMode == WidgetSourceMode.allTables) ...[
              const SizedBox(height: 16),
              SurfacePanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeading(title: '排除的表'),
                    const SizedBox(height: 4),
                    Text(
                      '优先显示的表不会被排除。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    if (tables.isEmpty)
                      const Text('当前没有可显示的表。')
                    else
                      for (final table in tables)
                        CheckboxListTile(
                          key: Key('widget_card_exclude_${table.id}'),
                          contentPadding: EdgeInsets.zero,
                          value: _draft.excludedTableIds.contains(table.id),
                          onChanged: configuredIds.contains(table.id)
                              ? null
                              : (selected) {
                                  setState(() {
                                    if (selected == true) {
                                      _draft.excludedTableIds.add(table.id);
                                    } else {
                                      _draft.excludedTableIds.remove(table.id);
                                    }
                                  });
                                },
                          title: Text(table.title),
                        ),
                  ],
                ),
              ),
            ],
            if (_draft.sections.any(
              (section) => !tables.any((table) => table.id == section.tableId),
            )) ...[
              const SizedBox(height: 12),
              const StatusPill(
                label: '失效表引用会省略显示；可更换或移除',
                icon: Icons.warning_amber_rounded,
                tone: StatusTone.warning,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _addSection(List<TableDocument> tables) {
    final used = _draft.sections.map((item) => item.tableId).toSet();
    final table =
        tables.where((item) => !used.contains(item.id)).firstOrNull ??
        tables.first;
    setState(() {
      _draft.sections.add(_SectionDraft(tableId: table.id));
    });
  }

  void _removeSection(int index) {
    final section = _draft.sections.removeAt(index);
    section.dispose();
    setState(() {});
  }

  void _moveSection(int from, int to) {
    final section = _draft.sections.removeAt(from);
    _draft.sections.insert(to, section);
    setState(() {});
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final spec = _buildSpec();
      final workspace = AppScope.of(context).homeWidgets;
      if (workspace == null) {
        throw StateError('此设备未接入桌面卡片');
      }
      final preview = await workspace.previewCard(
        spec,
        cardId: widget.card?.cardId,
      );
      if (!mounted) return;
      final confirmed = await _confirmPreview(preview);
      if (confirmed != true || !mounted) return;
      final command = widget.card == null
          ? CardCommand.create(spec)
          : CardCommand.replace(
              cardId: widget.card!.cardId,
              expectedRevision: widget.card!.revision,
              spec: spec,
            );
      final receipt = await workspace.applyCardCommand(
        command,
        operationId: _newOperationId(),
        authorize: () async => true,
      );
      if (!receipt.succeeded) {
        throw StateError(_receiptError(receipt));
      }
      if (mounted) Navigator.of(context).pop(receipt);
    } catch (error) {
      if (mounted) {
        setState(() => _error = '保存失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  CardSpec _buildSpec() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      throw const FormatException('请填写卡片标题');
    }
    final tables = AppScope.of(context).tables.tables;
    if (_draft.sourceMode == WidgetSourceMode.selectedTables &&
        _draft.sections.isEmpty) {
      throw const FormatException('指定表模式至少需要一张表');
    }
    final sectionIds = <String>{};
    final sections = <SectionSpec>[];
    for (final draft in _draft.sections) {
      if (!sectionIds.add(draft.tableId)) {
        throw FormatException('同一张表不能重复添加：${draft.tableId}');
      }
      sections.add(draft.toSpec());
    }
    final excluded = _draft.sourceMode == WidgetSourceMode.allTables
        ? _draft.excludedTableIds
              .where((id) => !sectionIds.contains(id))
              .toList(growable: false)
        : const <String>[];
    if (_draft.sourceMode == WidgetSourceMode.allTables &&
        sections.isEmpty &&
        tables.every((table) => excluded.contains(table.id))) {
      throw const FormatException('至少保留一张可显示的表');
    }
    return CardSpec(
      title: title,
      sourceMode: _draft.sourceMode,
      sections: sections,
      excludedTableIds: excluded,
      hideEmptySections: _draft.hideEmptySections,
      theme: _draft.theme,
    );
  }

  Future<bool?> _confirmPreview(CardPreview preview) {
    final rows = preview.snapshot.rows.take(6).toList(growable: false);
    return showDialog<bool>(
      context: context,
      animationStyle: reducedMotionAnimationStyle(context),
      builder: (context) => AlertDialog(
        title: const Text('预览桌面卡片'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('匹配 ${preview.matchingCount} 条内容，样本如下：'),
                const SizedBox(height: 10),
                if (rows.isEmpty)
                  const Text('当前没有匹配内容。')
                else
                  for (final row in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Text(
                        row.kind == WidgetRowKind.section
                            ? '${row.title} · ${row.count} 条'
                            : [
                                row.title,
                                if (row.detail != null) row.detail!,
                              ].join(' · '),
                      ),
                    ),
                if (preview.warnings.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final warning in preview.warnings)
                    Text(
                      warning,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回修改'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

class _SectionEditor extends StatelessWidget {
  const _SectionEditor({
    super.key,
    required this.draft,
    required this.tables,
    required this.allowRemove,
    required this.onChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  final _SectionDraft draft;
  final List<TableDocument> tables;
  final bool allowRemove;
  final VoidCallback onChanged;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final table = tables.where((item) => item.id == draft.tableId).firstOrNull;
    final tableIds = {for (final item in tables) item.id};
    final fields = [
      for (final field in WidgetBuiltinField.values)
        (wireName: field.wireName, label: _builtinFieldLabel(field)),
      if (table != null)
        for (final field in table.fields)
          (wireName: 'custom:${field.id}', label: field.name),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: Key('widget_section_table_${draft.tableId}'),
                initialValue: tableIds.contains(draft.tableId)
                    ? draft.tableId
                    : null,
                decoration: const InputDecoration(
                  labelText: '表',
                  isDense: true,
                ),
                hint: const Text('选择表'),
                items: [
                  for (final item in tables)
                    DropdownMenuItem(
                      value: item.id,
                      child: Text(item.title, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (tableId) {
                  if (tableId == null) return;
                  draft.tableId = tableId;
                  draft.fields.clear();
                  onChanged();
                },
              ),
            ),
            IconButton(
              onPressed: onMoveUp,
              icon: const Icon(Icons.arrow_upward),
              tooltip: '上移',
            ),
            IconButton(
              onPressed: onMoveDown,
              icon: const Icon(Icons.arrow_downward),
              tooltip: '下移',
            ),
            IconButton(
              onPressed: allowRemove ? onRemove : null,
              icon: const Icon(Icons.delete_outline),
              tooltip: '移除',
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: draft.label,
          decoration: const InputDecoration(
            labelText: '分区标题（可选）',
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Text('内容类型', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final type in TableContentType.values)
              FilterChip(
                label: Text(_typeLabel(type)),
                selected: draft.types.contains(type),
                onSelected: (selected) {
                  if (selected) {
                    draft.types.add(type);
                  } else if (draft.types.length > 1) {
                    draft.types.remove(type);
                  }
                  onChanged();
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 178,
              child: DropdownButtonFormField<WidgetTodoState>(
                initialValue: draft.todoState,
                decoration: const InputDecoration(
                  labelText: '待办状态',
                  isDense: true,
                ),
                items: [
                  for (final state in WidgetTodoState.values)
                    DropdownMenuItem(
                      value: state,
                      child: Text(_todoStateLabel(state)),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  draft.todoState = value;
                  onChanged();
                },
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<int?>(
                initialValue: draft.daysAhead,
                decoration: const InputDecoration(
                  labelText: '未来范围',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('不限')),
                  DropdownMenuItem(value: 1, child: Text('今天')),
                  DropdownMenuItem(value: 7, child: Text('未来 7 天')),
                  DropdownMenuItem(value: 30, child: Text('未来 30 天')),
                  DropdownMenuItem(value: 90, child: Text('未来 90 天')),
                ],
                onChanged: (value) {
                  draft.daysAhead = value;
                  onChanged();
                },
              ),
            ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<int>(
                initialValue: draft.limit,
                decoration: const InputDecoration(
                  labelText: '条目上限',
                  isDense: true,
                ),
                items: [
                  for (var limit = 1; limit <= 10; limit++)
                    DropdownMenuItem(value: limit, child: Text('$limit 条')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  draft.limit = value;
                  onChanged();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<WidgetSortKey>(
                initialValue: draft.sortKey,
                decoration: const InputDecoration(
                  labelText: '排序',
                  isDense: true,
                ),
                items: [
                  for (final key in WidgetSortKey.values)
                    DropdownMenuItem(
                      value: key,
                      child: Text(_sortKeyLabel(key)),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  draft.sortKey = value;
                  onChanged();
                },
              ),
            ),
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<WidgetSortDirection>(
                initialValue: draft.sortDirection,
                decoration: const InputDecoration(
                  labelText: '方向',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: WidgetSortDirection.desc,
                    child: Text('降序'),
                  ),
                  DropdownMenuItem(
                    value: WidgetSortDirection.asc,
                    child: Text('升序'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  draft.sortDirection = value;
                  onChanged();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('显示字段（最多 3 项）', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final field in fields)
              FilterChip(
                label: Text(field.label),
                selected: draft.fields.contains(field.wireName),
                onSelected: (selected) {
                  if (selected) {
                    if (draft.fields.length < 3) {
                      draft.fields.add(field.wireName);
                    }
                  } else {
                    draft.fields.remove(field.wireName);
                  }
                  onChanged();
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _CardDraft {
  _CardDraft({
    required this.title,
    required this.sourceMode,
    required this.theme,
    required this.hideEmptySections,
    required this.sections,
    required this.excludedTableIds,
  });

  factory _CardDraft.blank() => _CardDraft(
    title: '',
    sourceMode: WidgetSourceMode.selectedTables,
    theme: WidgetTheme.system,
    hideEmptySections: false,
    sections: [],
    excludedTableIds: {},
  );

  factory _CardDraft.fromSpec(CardSpec spec) => _CardDraft(
    title: spec.title,
    sourceMode: spec.sourceMode,
    theme: spec.theme,
    hideEmptySections: spec.hideEmptySections,
    sections: spec.sections.map(_SectionDraft.fromSpec).toList(),
    excludedTableIds: spec.excludedTableIds.toSet(),
  );

  String title;
  WidgetSourceMode sourceMode;
  WidgetTheme theme;
  bool hideEmptySections;
  final List<_SectionDraft> sections;
  final Set<String> excludedTableIds;

  void dispose() {
    for (final section in sections) {
      section.dispose();
    }
  }
}

class _SectionDraft {
  _SectionDraft({
    required this.tableId,
    String label = '',
    Set<TableContentType>? types,
    this.todoState = WidgetTodoState.any,
    this.daysAhead,
    this.sortKey = WidgetSortKey.updatedAt,
    this.sortDirection = WidgetSortDirection.desc,
    this.limit = 4,
    Set<String>? fields,
  }) : label = TextEditingController(text: label),
       types = types ?? TableContentType.values.toSet(),
       fields = fields ?? {};

  factory _SectionDraft.fromSpec(SectionSpec spec) => _SectionDraft(
    tableId: spec.tableId,
    label: spec.label ?? '',
    types: spec.types.toSet(),
    todoState: spec.todoState,
    daysAhead: spec.daysAhead,
    sortKey: spec.sort.key,
    sortDirection: spec.sort.direction,
    limit: spec.limit,
    fields: spec.fields.map((field) => field.wireName).toSet(),
  );

  String tableId;
  final TextEditingController label;
  final Set<TableContentType> types;
  WidgetTodoState todoState;
  int? daysAhead;
  WidgetSortKey sortKey;
  WidgetSortDirection sortDirection;
  int limit;
  final Set<String> fields;

  SectionSpec toSpec() {
    final labelText = label.text.trim();
    return SectionSpec(
      tableId: tableId,
      label: labelText.isEmpty ? null : labelText,
      types: [
        for (final type in TableContentType.values)
          if (types.contains(type)) type,
      ],
      todoState: todoState,
      daysAhead: daysAhead,
      sort: WidgetSort(key: sortKey, direction: sortDirection),
      limit: limit,
      fields: fields.map(WidgetField.parse).toList(growable: false),
    );
  }

  void dispose() {
    label.dispose();
  }
}

String _newOperationId() => 'home_widget_ui_${const Uuid().v4()}';

String _receiptError(CardWriteReceipt receipt) =>
    receipt.message ?? receipt.error?.wireName ?? '卡片命令未执行';

String _visibilityLabel(WidgetVisibility visibility) => switch (visibility) {
  WidgetVisibility.hidden => '全部隐藏',
  WidgetVisibility.titles => '仅标题',
  WidgetVisibility.fields => '标题和字段',
};

String _todoStateLabel(WidgetTodoState state) => switch (state) {
  WidgetTodoState.any => '全部',
  WidgetTodoState.open => '未完成',
  WidgetTodoState.done => '已完成',
};

String _sortKeyLabel(WidgetSortKey key) => switch (key) {
  WidgetSortKey.updatedAt => '更新时间',
  WidgetSortKey.businessTime => '业务时间',
  WidgetSortKey.title => '标题',
};

String _typeLabel(TableContentType type) => switch (type) {
  TableContentType.note => '笔记',
  TableContentType.todo => '待办',
  TableContentType.schedule => '日程',
  TableContentType.event => '事件',
};

String _builtinFieldLabel(WidgetBuiltinField field) => switch (field) {
  WidgetBuiltinField.time => '时间',
  WidgetBuiltinField.type => '类型',
  WidgetBuiltinField.status => '状态',
};
