import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import 'document_detail_page.dart';
import 'document_editor_page.dart';

class MattersPage extends StatelessWidget {
  const MattersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final matters = app.matters;
    return PageFrame(
      title: '事项',
      subtitle: '${matters.length} 件事',
      actions: [
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const DocumentEditorPage.create(type: ResultType.matter),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text('新建事项'),
        ),
      ],
      child: matters.isEmpty
          ? const EmptyState(
              icon: Icons.account_tree_outlined,
              title: '还没有事项',
              message: '把需要多个行动或资料的内容建成事项。',
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1100
                    ? 3
                    : constraints.maxWidth >= 680
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 14) / columns;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final matter in matters)
                      SizedBox(
                        width: width,
                        child: _MatterTile(
                          matter: matter,
                          childCount: app.documents
                              .where((item) => item.matterId == matter.id)
                              .length,
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _MatterTile extends StatelessWidget {
  const _MatterTile({required this.matter, required this.childCount});

  final ResultDocument matter;
  final int childCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DocumentDetailPage(documentId: matter.id),
        ),
      ),
      borderRadius: BorderRadius.circular(8),
      child: SurfacePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    matter.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              matter.body.trim().isEmpty ? '暂无正文' : matter.body.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                StatusPill(
                  label: '$childCount 个行动',
                  icon: Icons.checklist_outlined,
                ),
                const Spacer(),
                if (matter.tags.isNotEmpty)
                  Text(
                    matter.tags.take(2).map((tag) => '#$tag').join(' '),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
