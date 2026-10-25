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

class _TodoList extends StatelessWidget {
  const _TodoList({required this.todos});

  final List<ResultDocument> todos;

  @override
  Widget build(BuildContext context) {
    final library = AppScope.results(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSize(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: todos.isEmpty
          ? const _EmptySection(label: '没有未完成待办')
          : Column(
              key: ValueKey(todos.map((todo) => todo.id).join('|')),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < todos.length; index++) ...[
                  _TodoRow(document: todos[index], app: library),
                  if (index != todos.length - 1) const Divider(height: 1),
                ],
              ],
            ),
    );
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({required this.document, required this.app});

  final ResultDocument document;
  final ResultLibrary app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      key: ValueKey(document.id),
      children: [
        Checkbox(
          key: Key('home_todo_checkbox_${document.id}'),
          value: document.done,
          onChanged: (value) => app.toggleTodo(document, value ?? false),
        ),
        Expanded(
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DocumentDetailPage(documentId: document.id),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (document.due != null)
                    Text(
                      _dueText(document.due!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: document.due!.isBefore(DateTime.now())
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
