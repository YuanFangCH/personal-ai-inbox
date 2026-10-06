import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../../services/app_controller.dart';
import '../app_scope.dart';
import '../widgets/capture_sheet.dart';
import '../widgets/common.dart';
import 'document_detail_page.dart';
import 'document_editor_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
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
    final recentKnowledge = app.knowledge.take(4).toList(growable: false);

    return PageFrame(
      title: _greeting(now),
      subtitle: fullDateHeader(now),
      actions: [
        FilledButton.icon(
          onPressed: () => showCaptureSheet(context),
          icon: const Icon(Icons.add),
          label: const Text('收下内容'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Metrics(
            eventCount: events.length,
            todoCount: openTodos.length,
            reviewCount: app.reviewCaptures.length + app.conflictFiles.length,
            knowledgeCount: app.knowledge.length,
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final agenda = _AgendaSection(events: events);
              final todos = _TodoSection(todos: openTodos.take(6).toList());
              if (!wide) {
                return Column(
                  children: [agenda, const SizedBox(height: 16), todos],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: agenda),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: todos),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _KnowledgeSection(documents: recentKnowledge),
        ],
      ),
    );
  }

  String _greeting(DateTime now) {
    return switch (now.hour) {
      < 6 => '夜深了',
      < 12 => '早上好',
      < 18 => '下午好',
      _ => '晚上好',
    };
  }

  static int _compareTodo(ResultDocument a, ResultDocument b) {
    if (a.due == null && b.due == null) {
      return b.updatedAt.compareTo(a.updatedAt);
    }
    if (a.due == null) {
      return 1;
    }
    if (b.due == null) {
      return -1;
    }
    return a.due!.compareTo(b.due!);
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.eventCount,
    required this.todoCount,
    required this.reviewCount,
    required this.knowledgeCount,
  });

  final int eventCount;
  final int todoCount;
  final int reviewCount;
  final int knowledgeCount;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('今日日程', eventCount.toString(), Icons.event_available_outlined),
      ('未完成', todoCount.toString(), Icons.checklist_rtl_outlined),
      ('待确认', reviewCount.toString(), Icons.rule_folder_outlined),
      ('知识', knowledgeCount.toString(), Icons.menu_book_outlined),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 2;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: _MetricTile(
                  label: metric.$1,
                  value: metric.$2,
                  icon: metric.$3,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfacePanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgendaSection extends StatelessWidget {
  const _AgendaSection({required this.events});

  final List<ResultDocument> events;

  @override
  Widget build(BuildContext context) {
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            title: '接下来的安排',
            trailing: Text(
              '${events.length} 项',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: Text('今天没有安排')),
            )
          else
            for (var index = 0; index < events.length; index++) ...[
              _AgendaRow(document: events[index]),
              if (index != events.length - 1) const Divider(height: 1),
            ],
        ],
      ),
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
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              width: 3,
              height: 34,
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
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
    final app = AppScope.of(context);
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            title: '要做的',
            trailing: FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const DocumentEditorPage.create(type: ResultType.todo),
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新建'),
            ),
          ),
          const SizedBox(height: 8),
          if (todos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: Text('没有未完成待办')),
            )
          else
            for (var index = 0; index < todos.length; index++) ...[
              _TodoRow(document: todos[index], app: app),
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
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Checkbox(
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
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading(title: '最近知识'),
          const SizedBox(height: 4),
          if (documents.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('还没有知识条目')),
            )
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
      ),
    );
  }
}
