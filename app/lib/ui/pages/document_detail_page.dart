import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../../services/app_controller.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import 'document_editor_page.dart';

class DocumentDetailPage extends StatelessWidget {
  const DocumentDetailPage({super.key, required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final document = app.findDocument(documentId);
    if (document == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('成果不存在或已删除')),
      );
    }

    final children = document.type == ResultType.matter
        ? app.documents
              .where((item) => item.matterId == document.id)
              .toList(growable: false)
        : <ResultDocument>[];
    final backlinks = app.documents
        .where((item) => item.links.contains(document.id))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(document.type.label),
        actions: [
          IconButton(
            tooltip: '编辑',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DocumentEditorPage(document: document),
              ),
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) async {
              if (value == 'delete') {
                await _confirmDelete(context, document);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'delete', child: Text('删除并保留墓碑')),
            ],
          ),
        ],
      ),
      body: PageFrame(
        title: document.title,
        subtitle:
            '${document.type.label} · ${DateFormat('yyyy-MM-dd HH:mm').format(document.updatedAt)}',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final details = _DetailsPanel(document: document, app: app);
            final content = _ContentPanel(document: document, app: app);
            if (constraints.maxWidth < 900) {
              return Column(
                children: [
                  details,
                  const SizedBox(height: 16),
                  content,
                  if (children.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _ChildrenPanel(children: children),
                  ],
                  if (backlinks.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _BacklinksPanel(backlinks: backlinks),
                  ],
                ],
              );
            }
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: content),
                    const SizedBox(width: 16),
                    SizedBox(width: 320, child: details),
                  ],
                ),
                if (children.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _ChildrenPanel(children: children),
                ],
                if (backlinks.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _BacklinksPanel(backlinks: backlinks),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ResultDocument document,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除成果'),
        content: Text('“${document.title}”会保留为 30 天墓碑。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await AppScope.of(context).deleteDocument(document.id);
    if (context.mounted) {
      Navigator.pop(context);
    }
  }
}

class _ContentPanel extends StatelessWidget {
  const _ContentPanel({required this.document, required this.app});

  final ResultDocument document;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    return SurfacePanel(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (document.type == ResultType.todo)
            CheckboxListTile(
              value: document.done,
              contentPadding: EdgeInsets.zero,
              title: Text(document.done ? '已完成' : '未完成'),
              onChanged: (value) => app.toggleTodo(document, value ?? false),
            ),
          if (document.body.trim().isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: Text('正文为空')),
            )
          else
            MarkdownBody(data: document.body, selectable: true),
        ],
      ),
    );
  }
}

class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({required this.document, required this.app});

  final ResultDocument document;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final details = <(String, String)>[
      ('状态', document.status.label),
      ('版本', 'r${document.revision}'),
      ('来源端', document.originDevice),
      if (document.due != null)
        ('截止', DateFormat('yyyy-MM-dd HH:mm').format(document.due!)),
      if (document.start != null)
        ('开始', DateFormat('yyyy-MM-dd HH:mm').format(document.start!)),
      if (document.end != null)
        ('结束', DateFormat('yyyy-MM-dd HH:mm').format(document.end!)),
      if (document.recurrence != null) ('重复', document.recurrence!),
    ];
    final matter = document.matterId == null
        ? null
        : app.findDocument(document.matterId!);
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading(title: '属性'),
          const SizedBox(height: 10),
          for (final detail in details)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 68,
                    child: Text(
                      detail.$1,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      detail.$2,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          if (document.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final tag in document.tags)
                  Chip(
                    label: Text(tag),
                    avatar: const Icon(Icons.tag, size: 14),
                  ),
              ],
            ),
          ],
          if (matter != null) ...[
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_tree_outlined),
              title: const Text('所属事项'),
              subtitle: Text(matter.title),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DocumentDetailPage(documentId: matter.id),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChildrenPanel extends StatelessWidget {
  const _ChildrenPanel({required this.children});

  final List<ResultDocument> children;

  @override
  Widget build(BuildContext context) {
    return SurfacePanel(
      child: Column(
        children: [
          SectionHeading(title: '关联行动', trailing: Text('${children.length} 项')),
          const SizedBox(height: 6),
          for (var index = 0; index < children.length; index++) ...[
            DocumentListTile(
              document: children[index],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      DocumentDetailPage(documentId: children[index].id),
                ),
              ),
            ),
            if (index != children.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _BacklinksPanel extends StatelessWidget {
  const _BacklinksPanel({required this.backlinks});

  final List<ResultDocument> backlinks;

  @override
  Widget build(BuildContext context) {
    return SurfacePanel(
      child: Column(
        children: [
          SectionHeading(
            title: '反向引用',
            trailing: Text('${backlinks.length} 项'),
          ),
          const SizedBox(height: 6),
          for (var index = 0; index < backlinks.length; index++) ...[
            DocumentListTile(
              document: backlinks[index],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      DocumentDetailPage(documentId: backlinks[index].id),
                ),
              ),
            ),
            if (index != backlinks.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}
