import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../app_scope.dart';
import '../widgets/common.dart';
import '../widgets/global_knowledge_candidate_card.dart';
import '../widgets/review_queue.dart';
import 'document_detail_page.dart';

class PendingPage extends StatelessWidget {
  const PendingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final capture = AppScope.capture(context);
    final sync = AppScope.sync(context);
    final results = AppScope.results(context);
    return AnimatedBuilder(
      animation: Listenable.merge([capture, sync, results]),
      builder: (context, _) {
        final candidates = results.globalKnowledgeCandidates
            .where(
              (candidate) =>
                  candidate.status == GlobalKnowledgeCandidateStatus.pending ||
                  candidate.status == GlobalKnowledgeCandidateStatus.approved ||
                  candidate.status == GlobalKnowledgeCandidateStatus.stale ||
                  candidate.status == GlobalKnowledgeCandidateStatus.failed,
            )
            .toList(growable: false);
        final count =
            capture.reviewCaptures.length +
            sync.conflictFiles.length +
            candidates.length +
            results.draftDocuments.length;
        return PageFrame(
          title: '待处理',
          subtitle: '$count 项需要查看或确认',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ReviewQueue(),
              if (results.draftDocuments.isNotEmpty) ...[
                SectionHeading(
                  title: '草稿',
                  trailing: Text('${results.draftDocuments.length} 项'),
                ),
                const SizedBox(height: 8),
                SurfacePanel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < results.draftDocuments.length;
                        index++
                      ) ...[
                        DocumentListTile(
                          document: results.draftDocuments[index],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => DocumentDetailPage(
                                documentId: results.draftDocuments[index].id,
                              ),
                            ),
                          ),
                        ),
                        if (index != results.draftDocuments.length - 1)
                          const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (candidates.isNotEmpty) ...[
                const SectionHeading(title: '全局知识候选'),
                const SizedBox(height: 8),
                for (final candidate in candidates) ...[
                  GlobalKnowledgeCandidateCard(
                    candidate: candidate,
                    results: results,
                    showActions: true,
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              if (count == 0)
                const EmptyState(
                  icon: Icons.task_alt_outlined,
                  title: '没有待处理内容',
                  message: '草稿、同步冲突和全局知识候选会显示在这里。',
                ),
            ],
          ),
        );
      },
    );
  }
}
