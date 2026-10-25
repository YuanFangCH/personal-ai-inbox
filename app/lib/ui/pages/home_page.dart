import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/calendar.dart';
import '../../core/models.dart';
import '../../modules/results/result_library.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import '../widgets/quick_create_sheet.dart';
import 'calendar_page.dart';
import 'document_detail_page.dart';
import 'knowledge_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppScope.results(context),
      builder: (context, _) => _buildHome(context),
    );
  }

  Widget _buildHome(BuildContext context) {
    final app = AppScope.results(context);
    final now = DateTime.now();
    final events =
        app.events
            .where(
              (event) => event.start != null && isSameDay(event.start!, now),
            )
            .toList()
          ..sort((a, b) => a.start!.compareTo(b.start!));
    final openTodos = app.todos.where((todo) => !todo.done).toList()
      ..sort(_compareTodo);
    final recentKnowledge = app.knowledge.toList(growable: false);

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
                    .toList(growable: false),
              ),
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
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DocumentDetailPage(documentId: document.id),
        ),
      ),
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
  const _TodoSection({required this.todos});

  final List<ResultDocument> todos;

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
                onPressed: () => showQuickCreateSheet(
                  context,
                  initialDate: DateTime.now(),
                  type: ResultType.todo,
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _TodoList(todos: todos),
      ],
    );
  }
}

class _TodoList extends StatefulWidget {
  const _TodoList({required this.todos});

  final List<ResultDocument> todos;

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
      final library = AppScope.results(context);
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      final duration = reduceMotion ? Duration.zero : _duration;
      final targetIds = target.map((todo) => todo.id).toSet();
      var changed = false;

      for (var index = _items.length - 1; index >= 0; index--) {
        if (targetIds.contains(_items[index].id)) continue;
        final removed = _items.removeAt(index);
        changed = true;
        final current = library.findDocument(removed.id);
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
          final completed = library.findDocument(moved.id)?.done == true;
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
    final library = AppScope.results(context);
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
    ResultLibrary library, {
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
          app: library,
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
    required this.app,
    this.completedFeedback = false,
  });

  final ResultDocument document;
  final ResultLibrary app;
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
      await widget.app.toggleTodo(widget.document, value);
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
        Checkbox(
          key: Key('home_todo_checkbox_${widget.document.id}'),
          value: widget.completedFeedback || widget.document.done,
          onChanged: _saving ? null : _toggle,
        ),
        Expanded(
          child: InkWell(
            onTap: _saving
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          DocumentDetailPage(documentId: widget.document.id),
                    ),
                  ),
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
            label: '查看全部',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const KnowledgePage()),
            ),
          ),
        ),
        const SizedBox(height: 4),
        if (documents.isEmpty)
          const _EmptySection(label: '还没有知识条目')
        else
          for (var index = 0; index < documents.length; index++) ...[
            DocumentListTile(
              document: documents[index],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      DocumentDetailPage(documentId: documents[index].id),
                ),
              ),
            ),
            if (index != documents.length - 1) const Divider(height: 1),
          ],
      ],
    );
  }
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
