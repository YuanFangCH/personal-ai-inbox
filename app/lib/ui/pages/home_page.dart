import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/calendar.dart';
import '../../core/models.dart';
import '../../core/table_models.dart';
import '../../modules/tables/table_library.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import 'calendar_page.dart';
import 'table_detail_page.dart';
import 'tables_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppScope.results(context),
        AppScope.tables(context),
        AppScope.preferences(context),
      ]),
      builder: (context, _) => _buildHome(context),
    );
  }

  Widget _buildHome(BuildContext context) {
    final tableLibrary = AppScope.tables(context);
    final now = DateTime.now();
    final projected = projectTableCalendarDocuments(
      tables: tableLibrary.tables,
      entries: tableLibrary.entries,
      visibleTableIds: const ['*'],
    );
    final events =
        projected
            .where(
              (event) => event.start != null && isSameDay(event.start!, now),
            )
            .toList()
          ..sort((a, b) => a.start!.compareTo(b.start!));
    final openTodos =
        tableLibrary.entries
            .where(
              (entry) => entry.type == TableContentType.todo && !entry.done,
            )
            .map((entry) => _asTodoDocument(entry, tableLibrary))
            .toList()
          ..sort(_compareTodo);
    final recentKnowledge =
        tableLibrary.entries
            .where((entry) => entry.type == TableContentType.note)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return PageFrame(
      title: '首页',
      subtitle: fullDateHeader(now),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final agenda = _AgendaSection(
            events: events.take(wide ? 4 : 3).toList(growable: false),
          );
          final todos = _TodoSection(
            todos: openTodos.take(wide ? 6 : 4).toList(growable: false),
            onOpen: (document) => _openTableDocument(context, document),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: agenda),
                    const SizedBox(width: 40),
                    Expanded(flex: 2, child: todos),
                  ],
                )
              else ...[
                agenda,
                const SizedBox(height: 28),
                todos,
              ],
              const SizedBox(height: 32),
              _KnowledgeSection(
                documents: recentKnowledge
                    .take(wide ? 4 : 3)
                    .map((entry) => _asNoteDocument(entry, tableLibrary))
                    .toList(growable: false),
              ),
              const SizedBox(height: 28),
              const _HomeTableModules(),
            ],
          );
        },
      ),
    );
  }

  static int _compareTodo(ResultDocument a, ResultDocument b) {
    if (a.due == null && b.due == null) {
      return b.updatedAt.compareTo(a.updatedAt);
    }
    if (a.due == null) return 1;
    if (b.due == null) return -1;
    return a.due!.compareTo(b.due!);
  }

  static ResultDocument _asTodoDocument(
    TableEntryDocument entry,
    TableLibrary library,
  ) => _asTableDocument(entry, library, ResultType.todo);

  static ResultDocument _asNoteDocument(
    TableEntryDocument entry,
    TableLibrary library,
  ) => _asTableDocument(entry, library, ResultType.knowledge);

  static ResultDocument _asTableDocument(
    TableEntryDocument entry,
    TableLibrary library,
    ResultType type,
  ) {
    final table = library.findTable(entry.tableId);
    return ResultDocument(
      id: entry.id,
      type: type,
      title: entry.title,
      status: ResultStatus.canonical,
      originDevice: 'table',
      revision: entry.revision,
      createdAt: entry.createdAt,
      updatedAt: entry.updatedAt,
      body: entry.body,
      tags: entry.tags,
      due: entry.due,
      done: entry.done,
      extensionFields: {
        'table_id': entry.tableId,
        'table_title': table?.title ?? entry.tableId,
      },
    );
  }
}

void _openTableDocument(BuildContext context, ResultDocument document) {
  final library = AppScope.tables(context);
  TableEntryDocument? entry;
  for (final candidate in library.entries) {
    if (candidate.id == document.id) entry = candidate;
  }
  final tableId = document.extensionFields['table_id'];
  if (entry == null || tableId is! String) return;
  final selected = entry;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TableEntryEditorPage(
        tableId: tableId,
        type: selected.type,
        entry: selected,
      ),
    ),
  );
}

class _AgendaSection extends StatelessWidget {
  const _AgendaSection({required this.events});

  final List<ResultDocument> events;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(
          title: '今日安排',
          trailing: _SectionAction(
            label: '查看全部',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CalendarPage()),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (events.isEmpty)
          const _EmptySection(label: '今天暂无安排')
        else
          for (var index = 0; index < events.length; index++) ...[
            _AgendaRow(document: events[index]),
            if (index != events.length - 1) const Divider(height: 1),
          ],
      ],
    );
  }
}

class _AgendaRow extends StatelessWidget {
  const _AgendaRow({required this.document});

  final ResultDocument document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _openTableDocument(context, document),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                DateFormat('HH:mm').format(document.start!),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              width: 2,
              height: 32,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (document.body.trim().isNotEmpty)
                    Text(
                      document.body.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

class _TodoSection extends StatelessWidget {
  const _TodoSection({required this.todos, required this.onOpen});

  final List<ResultDocument> todos;
  final ValueChanged<ResultDocument> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(
          title: '要做的',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SectionAction(
                label: '查看全部',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CalendarPage(
                      initialSection: CalendarSection.todos,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              FilledButton.tonalIcon(
                onPressed: () {
                  final library = AppScope.tables(context);
                  final table = library.tableForInboxAssignment(
                    InboxAssignmentKind.todo,
                  );
                  if (table == null) {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(
                          body: SafeArea(
                            child: Column(
                              children: [
                                Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text('请先选择待办收纳目标，或在表中直接新建。'),
                                ),
                                Expanded(child: TablesPage()),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => TableEntryEditorPage(
                        tableId: table.id,
                        type: TableContentType.todo,
                        initialDate: DateTime.now(),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _TodoList(todos: todos, onOpen: onOpen),
      ],
    );
  }
}

class _TodoList extends StatefulWidget {
  const _TodoList({required this.todos, required this.onOpen});

  final List<ResultDocument> todos;
  final ValueChanged<ResultDocument> onOpen;

  @override
  State<_TodoList> createState() => _TodoListState();
}

class _TodoListState extends State<_TodoList> {
  static const _duration = Duration(milliseconds: 180);
  final _listKey = GlobalKey<AnimatedListState>();
  late final List<ResultDocument> _items = List.of(widget.todos);
  bool _removingLastItem = false;

  @override
  void didUpdateWidget(covariant _TodoList oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = widget.todos;
      final library = AppScope.tables(context);
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      final duration = reduceMotion ? Duration.zero : _duration;
      final targetIds = target.map((todo) => todo.id).toSet();
      var changed = false;

      for (var index = _items.length - 1; index >= 0; index--) {
        if (targetIds.contains(_items[index].id)) continue;
        final removed = _items.removeAt(index);
        changed = true;
        final current = _findEntry(library, removed.id);
        final completed = current?.done == true;
        _listKey.currentState?.removeItem(
          index,
          (context, animation) => _buildItem(
            context,
            removed,
            animation,
            library,
            completed: completed,
          ),
          duration: duration,
        );
      }

      for (var index = 0; index < target.length; index++) {
        final todo = target[index];
        final existingIndex = _items.indexWhere((item) => item.id == todo.id);
        if (existingIndex < 0) {
          _items.insert(index, todo);
          _listKey.currentState?.insertItem(index, duration: duration);
          changed = true;
        } else if (existingIndex != index) {
          final moved = _items.removeAt(existingIndex);
          final completed = _findEntry(library, moved.id)?.done == true;
          _listKey.currentState?.removeItem(
            existingIndex,
            (context, animation) => _buildItem(
              context,
              moved,
              animation,
              library,
              completed: completed,
            ),
            duration: duration,
          );
          _items.insert(index, todo);
          _listKey.currentState?.insertItem(index, duration: duration);
          changed = true;
        } else if (!identical(_items[index], todo)) {
          _items[index] = todo;
          changed = true;
        }
      }

      if (!changed) return;
      if (_items.isEmpty && target.isEmpty) {
        _removingLastItem = true;
        Future<void>.delayed(duration, () {
          if (!mounted || _items.isNotEmpty) return;
          setState(() => _removingLastItem = false);
        });
      } else {
        _removingLastItem = false;
      }
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final library = AppScope.tables(context);
    final empty = _items.isEmpty && widget.todos.isEmpty && !_removingLastItem;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (empty) const _EmptySection(label: '没有未完成待办'),
        AnimatedList(
          key: _listKey,
          initialItemCount: _items.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (context, index, animation) =>
              _buildItem(context, _items[index], animation, library),
        ),
      ],
    );
  }

  Widget _buildItem(
    BuildContext context,
    ResultDocument todo,
    Animation<double> animation,
    TableLibrary library, {
    bool completed = false,
  }) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return SizeTransition(
      sizeFactor: curved,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: curved,
        child: _TodoRow(
          key: ValueKey('home_todo_${todo.id}'),
          document: todo,
          library: library,
          onOpen: widget.onOpen,
          completedFeedback: completed,
        ),
      ),
    );
  }
}

class _TodoRow extends StatefulWidget {
  const _TodoRow({
    super.key,
    required this.document,
    required this.library,
    required this.onOpen,
    this.completedFeedback = false,
  });

  final ResultDocument document;
  final TableLibrary library;
  final ValueChanged<ResultDocument> onOpen;
  final bool completedFeedback;

  @override
  State<_TodoRow> createState() => _TodoRowState();
}

class _TodoRowState extends State<_TodoRow> {
  bool _saving = false;

  Future<void> _toggle(bool? value) async {
    if (value == null || _saving) return;
    setState(() => _saving = true);
    try {
      final entry = _findEntry(widget.library, widget.document.id);
      if (entry == null) throw StateError('待办已不存在');
      await widget.library.updateEntry(
        entry.copyWith(done: value),
        expectedRevision: entry.revision,
      );
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('待办未能更新，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      key: ValueKey(widget.document.id),
      children: [
        if (_saving)
          const SizedBox.square(
            dimension: 48,
            child: Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          Checkbox(
            key: Key('home_todo_checkbox_${widget.document.id}'),
            value: widget.completedFeedback || widget.document.done,
            onChanged: _toggle,
          ),
        Expanded(
          child: InkWell(
            onTap: _saving ? null : () => widget.onOpen(widget.document),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: widget.completedFeedback
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  if (widget.document.due != null)
                    Text(
                      widget.completedFeedback
                          ? '已完成'
                          : _dueText(widget.document.due!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            !widget.completedFeedback &&
                                widget.document.due!.isBefore(DateTime.now())
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _dueText(DateTime due) {
    final prefix = due.isBefore(DateTime.now()) ? '已逾期 · ' : '';
    return '$prefix${friendlyDate(due)} ${DateFormat('HH:mm').format(due)}';
  }
}

class _KnowledgeSection extends StatelessWidget {
  const _KnowledgeSection({required this.documents});

  final List<ResultDocument> documents;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(
          title: '最近知识',
          trailing: _SectionAction(
            label: '查看各表',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const TablesPage())),
          ),
        ),
        const SizedBox(height: 4),
        if (documents.isEmpty)
          const _EmptySection(label: '还没有知识条目')
        else
          for (var index = 0; index < documents.length; index++) ...[
            DocumentListTile(
              document: documents[index],
              onTap: () => _openTableDocument(context, documents[index]),
            ),
            if (index != documents.length - 1) const Divider(height: 1),
          ],
      ],
    );
  }
}

class _HomeTableModules extends StatefulWidget {
  const _HomeTableModules();

  @override
  State<_HomeTableModules> createState() => _HomeTableModulesState();
}

class _HomeTableModulesState extends State<_HomeTableModules> {
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final library = AppScope.tables(context);
    final preferences = AppScope.preferences(context);
    return AnimatedBuilder(
      animation: Listenable.merge([library, preferences]),
      builder: (context, _) {
        final order = preferences.settings.homeTableOrder
            .where((id) => library.findTable(id) != null)
            .toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeading(
              title: '我的表',
              trailing: FilledButton.tonalIcon(
                key: const Key('home_add_table_module'),
                onPressed: () => _addTable(context, order),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加表'),
              ),
            ),
            const SizedBox(height: 8),
            if (order.isEmpty)
              const _EmptySection(label: '添加常用表，在首页查看内容摘要。')
            else
              for (var index = 0; index < order.length; index++)
                _HomeTableCard(
                  key: ValueKey('home_table_${order[index]}'),
                  table: library.findTable(order[index])!,
                  entries:
                      library.entries
                          .where((entry) => entry.tableId == order[index])
                          .toList()
                        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
                  expanded: _expanded.contains(order[index]),
                  onToggleExpanded: () => setState(() {
                    if (!_expanded.add(order[index])) {
                      _expanded.remove(order[index]);
                    }
                  }),
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TableDetailPage(tableId: order[index]),
                    ),
                  ),
                  onMove: (offset) => _moveTable(order, index, offset),
                  onRemove: () => preferences.update(
                    homeTableOrder: order
                        .where((id) => id != order[index])
                        .toList(growable: false),
                  ),
                ),
          ],
        );
      },
    );
  }

  Future<void> _addTable(BuildContext context, List<String> order) async {
    final library = AppScope.tables(context);
    final preferences = AppScope.preferences(context);
    final candidates = library.tables
        .where((table) => !order.contains(table.id))
        .toList(growable: false);
    if (candidates.isEmpty) return;
    final selected = await showModalBottomSheet<TableDocument>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('添加到首页')),
            for (final table in candidates)
              ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: Text(table.title),
                subtitle: Text(
                  '${library.entries.where((entry) => entry.tableId == table.id).length} 条内容',
                ),
                onTap: () => Navigator.pop(context, table),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    await preferences.update(homeTableOrder: [...order, selected.id]);
  }

  Future<void> _moveTable(List<String> order, int index, int offset) async {
    final destination = index + offset;
    if (destination < 0 || destination >= order.length) return;
    final updated = List<String>.of(order);
    final moved = updated.removeAt(index);
    updated.insert(destination, moved);
    await AppScope.preferences(context).update(homeTableOrder: updated);
  }
}

class _HomeTableCard extends StatelessWidget {
  const _HomeTableCard({
    super.key,
    required this.table,
    required this.entries,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onOpen,
    required this.onMove,
    required this.onRemove,
  });

  final TableDocument table;
  final List<TableEntryDocument> entries;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onOpen;
  final ValueChanged<int> onMove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final visible = expanded ? entries : entries.take(5).toList();
    return Card(
      key: ValueKey('home_table_card_${table.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onOpen,
                    child: Text(
                      table.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '上移',
                  onPressed: () => onMove(-1),
                  icon: const Icon(Icons.arrow_upward, size: 18),
                ),
                IconButton(
                  tooltip: '下移',
                  onPressed: () => onMove(1),
                  icon: const Icon(Icons.arrow_downward, size: 18),
                ),
                IconButton(
                  tooltip: '从首页移除',
                  onPressed: onRemove,
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                ),
              ],
            ),
            if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('这张表还没有内容。'),
              )
            else
              for (final entry in visible)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(_tableEntrySummary(entry)),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TableEntryEditorPage(
                        tableId: table.id,
                        type: entry.type,
                        entry: entry,
                      ),
                    ),
                  ),
                ),
            if (entries.length > 5)
              TextButton(
                onPressed: onToggleExpanded,
                child: Text(expanded ? '收起' : '展开全部 ${entries.length} 条'),
              ),
          ],
        ),
      ),
    );
  }
}

String _tableEntrySummary(TableEntryDocument entry) {
  final type = switch (entry.type) {
    TableContentType.note => '笔记',
    TableContentType.todo => '待办',
    TableContentType.schedule => '日程',
    TableContentType.event => '事件',
  };
  final time = switch (entry.type) {
    TableContentType.todo => entry.due,
    TableContentType.schedule => entry.start,
    TableContentType.event => entry.occurredAt,
    TableContentType.note => null,
  };
  return time == null ? type : '$type · ${friendlyDate(time)}';
}

TableEntryDocument? _findEntry(TableLibrary library, String id) {
  for (final entry in library.entries) {
    if (entry.id == id) return entry;
  }
  return null;
}

class _SectionAction extends StatelessWidget {
  const _SectionAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 40),
      visualDensity: VisualDensity.compact,
    ),
    child: Text(label),
  );
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      label,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}
