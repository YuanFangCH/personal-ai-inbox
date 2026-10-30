import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/table_models.dart';
import '../../modules/tables/table_library.dart';
import '../app_scope.dart';
import '../theme/app_design_tokens.dart';
import '../widgets/common.dart';
import '../widgets/review_queue.dart';
import '../widgets/legacy_draft_queue.dart';
import 'table_detail_page.dart';

class TablesPage extends StatefulWidget {
  const TablesPage({super.key});

  @override
  State<TablesPage> createState() => _TablesPageState();
}

class _TablesPageState extends State<TablesPage> {
  final _query = TextEditingController();
  String _normalizedQuery = '';
  bool _showTables = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppScope.tables(context),
        AppScope.capture(context),
        AppScope.results(context),
      ]),
      builder: (context, _) {
        final library = AppScope.tables(context);
        final matchingEntries = _normalizedQuery.isEmpty
            ? const <TableEntryDocument>[]
            : library.entries
                  .where(
                    (entry) =>
                        entry.title.toLowerCase().contains(_normalizedQuery) ||
                        entry.body.toLowerCase().contains(_normalizedQuery),
                  )
                  .toList(growable: false);
        final matchingTableIds = matchingEntries
            .map((entry) => entry.tableId)
            .toSet();
        final tables = library.tables
            .where((table) {
              if (_normalizedQuery.isEmpty) return true;
              final query = _normalizedQuery;
              return table.title.toLowerCase().contains(query) ||
                  table.body.toLowerCase().contains(query) ||
                  matchingTableIds.contains(table.id);
            })
            .toList(growable: false);
        final defaults = tables
            .where((table) => table.role != TableRole.custom)
            .toList(growable: false);
        final custom = tables
            .where((table) => table.role == TableRole.custom)
            .toList(growable: false);
        final notes =
            library.entries
                .where((entry) => entry.type == TableContentType.note)
                .where(
                  (entry) =>
                      _normalizedQuery.isEmpty ||
                      entry.title.toLowerCase().contains(_normalizedQuery) ||
                      entry.body.toLowerCase().contains(_normalizedQuery),
                )
                .toList(growable: false)
              ..sort(
                (left, right) => right.updatedAt.compareTo(left.updatedAt),
              );

        return PageFrame(
          title: _showTables ? '表与笔记' : '全部笔记',
          subtitle: _showTables
              ? '${library.tables.length} 张表 · ${library.entries.length} 条内容'
              : '${notes.length} 条笔记',
          actions: [
            OutlinedButton.icon(
              key: Key(
                _showTables ? 'notebook_show_notes' : 'notebook_show_tables',
              ),
              onPressed: () => setState(() => _showTables = !_showTables),
              icon: Icon(
                _showTables ? Icons.notes_outlined : Icons.table_chart_outlined,
              ),
              label: Text(_showTables ? '全部笔记' : '查看表'),
            ),
            OutlinedButton.icon(
              key: const Key('notebook_recycle_bin'),
              onPressed: () => _openRecovery(context, library),
              icon: const Icon(Icons.restore_outlined),
              label: const Text('回收站'),
            ),
            FilledButton.icon(
              key: const Key('create_table_button'),
              onPressed: () => _createTable(context, library),
              icon: const Icon(Icons.add),
              label: const Text('新建表'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('notebook_search_field'),
                controller: _query,
                onChanged: (value) => setState(
                  () => _normalizedQuery = value.trim().toLowerCase(),
                ),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: _showTables ? '搜索表名或内容' : '搜索笔记标题或正文',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              if (matchingEntries.isNotEmpty) ...[
                const SectionHeading(title: '匹配内容'),
                const SizedBox(height: 8),
                for (final entry in matchingEntries) ...[
                  ListTile(
                    key: ValueKey('table_search_entry_${entry.id}'),
                    leading: const Icon(Icons.notes_outlined),
                    title: Text(entry.title),
                    subtitle: Text(
                      '${library.findTable(entry.tableId)?.title ?? entry.tableId} · ${_entryTypeLabel(entry.type)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TableEntryEditorPage(
                          tableId: entry.tableId,
                          type: entry.type,
                          entry: entry,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                ],
                const SizedBox(height: 12),
              ],
              if (AppScope.capture(context).reviewCaptures.isNotEmpty) ...[
                const CaptureReviewQueue(),
                const SizedBox(height: 16),
              ],
              if (AppScope.results(context).draftDocuments.isNotEmpty) ...[
                LegacyDraftQueue(
                  documents: AppScope.results(context).draftDocuments,
                ),
                const SizedBox(height: 16),
              ],
              if (!_showTables) ...[
                if (notes.isEmpty && matchingEntries.isEmpty)
                  EmptyState(
                    icon: Icons.menu_book_outlined,
                    title: _normalizedQuery.isEmpty ? '还没有笔记' : '没有匹配的笔记',
                    message: _normalizedQuery.isEmpty
                        ? '点“收下”记一段文字，或切到表视图管理待办和日程。'
                        : '试试其他关键词，或在表视图中搜索全部内容。',
                  )
                else ...[
                  ..._buildNoteGroups(context, library, notes),
                ],
              ] else if (tables.isEmpty)
                EmptyState(
                  icon: Icons.menu_book_outlined,
                  title: _normalizedQuery.isEmpty ? '还没有表' : '没有匹配的表',
                  message: _normalizedQuery.isEmpty
                      ? '可以先写一段正文，或创建作业、考试等主题表。'
                      : '试试其他关键词。',
                  action: _normalizedQuery.isEmpty
                      ? FilledButton.icon(
                          onPressed: () => _createTable(context, library),
                          icon: const Icon(Icons.add),
                          label: const Text('新建表'),
                        )
                      : null,
                )
              else ...[
                if (defaults.isNotEmpty) ...[
                  const SectionHeading(title: '默认收纳表'),
                  const SizedBox(height: 8),
                  for (final table in defaults) ...[
                    _TableCard(
                      table: table,
                      entryCount: _entryCount(library, table.id),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
                if (custom.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const SectionHeading(title: '我的表'),
                  const SizedBox(height: 8),
                  for (final table in custom) ...[
                    _TableCard(
                      table: table,
                      entryCount: _entryCount(library, table.id),
                      onRename: () => _renameTable(context, library, table),
                      onDelete: () => _deleteTable(context, library, table),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  int _entryCount(TableLibrary library, String tableId) =>
      library.entries.where((entry) => entry.tableId == tableId).length;

  List<Widget> _buildNoteGroups(
    BuildContext context,
    TableLibrary library,
    List<TableEntryDocument> notes,
  ) {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 7));
    final recent = notes
        .where((entry) => !entry.updatedAt.isBefore(cutoff))
        .toList(growable: false);
    final older = notes
        .where((entry) => entry.updatedAt.isBefore(cutoff))
        .toList(growable: false);
    final groups = <String, List<TableEntryDocument>>{};
    for (final entry in older) {
      groups
          .putIfAbsent(DateFormat('M月').format(entry.updatedAt), () => [])
          .add(entry);
    }
    return [
      if (recent.isNotEmpty) ...[
        const SectionHeading(title: '最近 7 天'),
        const SizedBox(height: 10),
        for (final entry in recent) ...[
          _NotebookNoteCard(
            entry: entry,
            tableTitle:
                library.findTable(entry.tableId)?.title ?? entry.tableId,
            onTap: () => _openNote(context, entry),
          ),
          const SizedBox(height: 12),
        ],
      ],
      for (final group in groups.entries) ...[
        const SizedBox(height: 8),
        SectionHeading(title: group.key),
        const SizedBox(height: 10),
        for (final entry in group.value) ...[
          _NotebookNoteCard(
            entry: entry,
            tableTitle:
                library.findTable(entry.tableId)?.title ?? entry.tableId,
            onTap: () => _openNote(context, entry),
          ),
          const SizedBox(height: 12),
        ],
      ],
    ];
  }

  Future<void> _openNote(BuildContext context, TableEntryDocument entry) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TableEntryEditorPage(
            tableId: entry.tableId,
            type: TableContentType.note,
            entry: entry,
          ),
        ),
      );

  Future<void> _createTable(BuildContext context, TableLibrary library) async {
    final title = await _askForTitle(context, dialogTitle: '新建表');
    if (!context.mounted || title == null) return;
    try {
      final table = await library.createTable(title: title);
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TableDetailPage(tableId: table.id),
        ),
      );
    } on Object catch (error) {
      if (context.mounted) _showMessage(context, '创建失败：$error');
    }
  }

  Future<void> _renameTable(
    BuildContext context,
    TableLibrary library,
    TableDocument table,
  ) async {
    final title = await _askForTitle(
      context,
      dialogTitle: '重命名表',
      initialValue: table.title,
    );
    if (!context.mounted || title == null || title == table.title) return;
    try {
      await library.updateTable(
        table.copyWith(title: title),
        expectedRevision: table.revision,
      );
    } on Object catch (error) {
      if (context.mounted) _showMessage(context, '重命名失败：$error');
    }
  }

  Future<void> _deleteTable(
    BuildContext context,
    TableLibrary library,
    TableDocument table,
  ) async {
    final count = _entryCount(library, table.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这张表？'),
        content: Text('“${table.title}”及其中 $count 条内容会一起移入回收站，30 天内可整表恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除表和内容'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;
    try {
      await library.deleteTable(id: table.id, expectedRevision: table.revision);
      if (context.mounted) _showMessage(context, '已移入回收站，可在 30 天内恢复。');
    } on Object catch (error) {
      if (context.mounted) _showMessage(context, '删除失败：$error');
    }
  }

  Future<void> _openRecovery(BuildContext context, TableLibrary library) async {
    final batches = await library.recoveryBatches();
    final previews = <String, TableRecoveryPreview>{};
    for (final batch in batches.where(
      (batch) => batch.scope == TableRecoveryScope.table,
    )) {
      final preview = await library.previewDeletedTable(batch.id);
      if (preview != null) previews[batch.id] = preview;
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: batches.isEmpty
              ? const EmptyState(
                  icon: Icons.delete_outline,
                  title: '回收站为空',
                  message: '删除的自定义表会在这里保留 30 天。',
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    Text('回收站', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    for (final batch in batches)
                      _RecoveryTableTile(
                        batch: batch,
                        preview: previews[batch.id],
                        onRestore: () async {
                          try {
                            await library.restoreRecoveryBatch(batch.id);
                            if (context.mounted) Navigator.pop(context);
                          } on Object catch (error) {
                            if (context.mounted) {
                              _showMessage(context, '恢复失败：$error');
                            }
                          }
                        },
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<String?> _askForTitle(
    BuildContext context, {
    required String dialogTitle,
    String initialValue = '',
  }) => showDialog<String>(
    context: context,
    builder: (context) =>
        _TableTitleDialog(dialogTitle: dialogTitle, initialValue: initialValue),
  );

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _NotebookNoteCard extends StatelessWidget {
  const _NotebookNoteCard({
    required this.entry,
    required this.tableTitle,
    required this.onTap,
  });

  final TableEntryDocument entry;
  final String tableTitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = entry.body.trim();
    return Material(
      key: ValueKey('notebook_note_${entry.id}'),
      color: theme.brightness == Brightness.dark
          ? const Color(0xff202123)
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 34,
                margin: const EdgeInsets.only(right: 12, top: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          DateFormat('M月d日').format(entry.updatedAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            tableTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
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
}

class _RecoveryTableTile extends StatelessWidget {
  const _RecoveryTableTile({
    required this.batch,
    required this.preview,
    required this.onRestore,
  });

  final TableRecoveryBatch batch;
  final TableRecoveryPreview? preview;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final remaining = batch.expiresAt.difference(DateTime.now());
    final days = remaining.inDays;
    final hours = remaining.inHours.remainder(24);
    final remainingLabel = remaining.isNegative
        ? '已超过恢复期限，正在清理'
        : days > 0
        ? '剩余 $days 天 $hours 小时'
        : '剩余 ${remaining.inHours} 小时';
    final title = preview?.table.title ?? batch.tableId;
    final entries = preview?.entries ?? const <TableEntryDocument>[];
    return ExpansionTile(
      leading: const Icon(Icons.table_chart_outlined),
      title: Text(title),
      subtitle: Text('${entries.length} 条内容 · $remainingLabel'),
      children: [
        for (final entry in entries.take(5))
          ListTile(
            dense: true,
            title: Text(entry.title),
            subtitle: Text(_contentTypeLabel(entry.type)),
          ),
        if (entries.length > 5)
          ListTile(dense: true, title: Text('另有 ${entries.length - 5} 条内容')),
        if (preview == null)
          const ListTile(dense: true, title: Text('暂时无法读取预览，恢复账本仍保留原内容。')),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 8),
            child: FilledButton.tonal(
              onPressed: remaining.isNegative ? null : onRestore,
              child: const Text('恢复整表'),
            ),
          ),
        ),
      ],
    );
  }
}

String _contentTypeLabel(TableContentType type) => switch (type) {
  TableContentType.note => '笔记',
  TableContentType.todo => '待办',
  TableContentType.schedule => '日程',
  TableContentType.event => '事件',
};

class _TableTitleDialog extends StatefulWidget {
  const _TableTitleDialog({
    required this.dialogTitle,
    required this.initialValue,
  });

  final String dialogTitle;
  final String initialValue;

  @override
  State<_TableTitleDialog> createState() => _TableTitleDialogState();
}

class _TableTitleDialogState extends State<_TableTitleDialog> {
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

  void _save() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.dialogTitle),
    content: TextField(
      key: const Key('table_name_input'),
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(labelText: '表名'),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('table_name_save'),
        onPressed: _save,
        child: const Text('保存'),
      ),
    ],
  );
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.entryCount,
    this.onRename,
    this.onDelete,
  });

  final TableDocument table;
  final int entryCount;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDefault = table.role != TableRole.custom;
    return Material(
      key: ValueKey('table_${table.id}'),
      color: theme.brightness == Brightness.dark
          ? const Color(0xff202123)
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppDesignTokens.panelRadius),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TableDetailPage(tableId: table.id),
          ),
        ),
        borderRadius: BorderRadius.circular(AppDesignTokens.panelRadius),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 42,
                margin: const EdgeInsets.only(right: 12, top: 1),
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
                        Expanded(
                          child: Text(
                            table.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (isDefault) const Icon(Icons.lock_outline, size: 16),
                        if (onRename != null || onDelete != null)
                          PopupMenuButton<String>(
                            tooltip: '表选项',
                            onSelected: (value) {
                              if (value == 'rename') onRename?.call();
                              if (value == 'delete') onDelete?.call();
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('重命名'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('删除表'),
                              ),
                            ],
                          ),
                      ],
                    ),
                    if (table.body.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        table.body.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          '$entryCount 条内容',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatDate(table.updatedAt),
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
}

String _formatDate(DateTime value) => '${value.month}月${value.day}日';

String _entryTypeLabel(TableContentType type) => switch (type) {
  TableContentType.note => '笔记',
  TableContentType.todo => '待办',
  TableContentType.schedule => '日程',
  TableContentType.event => '事件',
};
