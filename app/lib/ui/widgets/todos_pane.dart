import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../../services/app_controller.dart';
import '../app_scope.dart';
import '../pages/document_detail_page.dart';
import 'common.dart';

enum _TodoFilter { all, today, upcoming, completed }

class TodosPane extends StatefulWidget {
  const TodosPane({super.key});

  @override
  State<TodosPane> createState() => _TodosPaneState();
}

class _TodosPaneState extends State<TodosPane> {
  _TodoFilter _filter = _TodoFilter.all;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final now = DateTime.now();
    final all = app.todos.toList()..sort(_compareTodo);
    final filtered = all
        .where((todo) {
          return switch (_filter) {
            _TodoFilter.all => !todo.done,
            _TodoFilter.today =>
              !todo.done && todo.due != null && isSameDay(todo.due!, now),
            _TodoFilter.upcoming =>
              !todo.done && todo.due != null && todo.due!.isAfter(now),
            _TodoFilter.completed => todo.done,
          };
        })
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_TodoFilter>(
            segments: const [
              ButtonSegment(value: _TodoFilter.all, label: Text('全部')),
              ButtonSegment(value: _TodoFilter.today, label: Text('今天')),
              ButtonSegment(value: _TodoFilter.upcoming, label: Text('即将到期')),
              ButtonSegment(value: _TodoFilter.completed, label: Text('已完成')),
            ],
            selected: {_filter},
            onSelectionChanged: (value) =>
                setState(() => _filter = value.first),
          ),
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          const EmptyState(
            icon: Icons.task_alt,
            title: '这里没有待办',
            message: '切换筛选条件，或通过下方加号新建一条待办。',
          )
        else
          SurfacePanel(
            child: Column(
              children: [
                for (var index = 0; index < filtered.length; index++) ...[
                  _TodoTile(todo: filtered[index], app: app),
                  if (index != filtered.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
      ],
    );
  }

  static int _compareTodo(ResultDocument a, ResultDocument b) {
    if (a.done != b.done) {
      return a.done ? 1 : -1;
    }
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

class _TodoTile extends StatelessWidget {
  const _TodoTile({required this.todo, required this.app});

  final ResultDocument todo;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final overdue =
        todo.due != null && !todo.done && todo.due!.isBefore(DateTime.now());
    final matter = todo.matterId == null
        ? null
        : app.findDocument(todo.matterId!);
    return Row(
      children: [
        Checkbox(
          value: todo.done,
          onChanged: (value) => app.toggleTodo(todo, value ?? false),
        ),
        Expanded(
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DocumentDetailPage(documentId: todo.id),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    todo.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      decoration: todo.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 7,
                    runSpacing: 5,
                    children: [
                      if (todo.due != null)
                        StatusPill(
                          label:
                              '${friendlyDate(todo.due!)} ${DateFormat('HH:mm').format(todo.due!)}',
                          icon: Icons.schedule,
                          tone: overdue
                              ? StatusTone.danger
                              : StatusTone.neutral,
                        ),
                      if (matter != null)
                        StatusPill(
                          label: matter.title,
                          icon: Icons.account_tree_outlined,
                        ),
                      for (final tag in todo.tags.take(2))
                        StatusPill(label: '#$tag'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
