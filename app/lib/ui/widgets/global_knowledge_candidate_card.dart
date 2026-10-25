import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../modules/results/result_library.dart';
import 'common.dart';

class GlobalKnowledgeCandidateCard extends StatelessWidget {
  const GlobalKnowledgeCandidateCard({
    super.key,
    required this.candidate,
    required this.results,
    this.showActions = false,
  });

  final GlobalKnowledgeCandidate candidate;
  final ResultLibrary results;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPending =
        candidate.status == GlobalKnowledgeCandidateStatus.pending;
    final currentTarget = candidate.targetId == null
        ? null
        : results.findDocument(candidate.targetId!);
    final showUpdateDiff =
        candidate.operation == GlobalKnowledgeOperation.update &&
        currentTarget != null &&
        candidate.status != GlobalKnowledgeCandidateStatus.applied;
    final showAppliedUpdate =
        candidate.operation == GlobalKnowledgeOperation.update &&
        currentTarget != null &&
        candidate.status == GlobalKnowledgeCandidateStatus.applied;
    final title =
        candidate.proposal['title']?.toString() ??
        currentTarget?.title ??
        candidate.targetId ??
        '全局知识';
    final operation = switch (candidate.operation) {
      GlobalKnowledgeOperation.create => '新增',
      GlobalKnowledgeOperation.update => '修改',
      GlobalKnowledgeOperation.delete => '删除',
    };
    final status = switch (candidate.status) {
      GlobalKnowledgeCandidateStatus.pending => '等待确认',
      GlobalKnowledgeCandidateStatus.approved => '已确认，等待提交',
      GlobalKnowledgeCandidateStatus.applied => '已完成',
      GlobalKnowledgeCandidateStatus.rejected => '已拒绝',
      GlobalKnowledgeCandidateStatus.stale => '内容已变化，需重新确认',
      GlobalKnowledgeCandidateStatus.failed => '提交失败',
    };
    return SurfacePanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$operation全局知识 · $title',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(
                label: status,
                tone: isPending ? StatusTone.warning : StatusTone.neutral,
              ),
              if (candidate.targetId != null)
                Text(
                  '目标版本 ${candidate.expectedRevision ?? '-'}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
          if (candidate.targetId != null) ...[
            const SizedBox(height: 8),
            Text(
              '目标 ID · ${candidate.targetId}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (showUpdateDiff) ...[
            const SizedBox(height: 10),
            Text(
              candidate.status == GlobalKnowledgeCandidateStatus.stale
                  ? '当前内容 · 原版本已变化'
                  : '当前内容',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            SelectableText(
              '${currentTarget.title}\n${currentTarget.body}',
              style: theme.textTheme.bodyMedium,
            ),
            const Divider(height: 20),
            Text('修改后内容', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            SelectableText(
              '${candidate.proposal['title'] ?? currentTarget.title}\n${candidate.proposal['body'] ?? ''}',
              style: theme.textTheme.bodyMedium,
            ),
          ] else if (showAppliedUpdate) ...[
            const SizedBox(height: 10),
            Text('已写入当前版本', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            SelectableText(
              '${currentTarget.title}\n${currentTarget.body}',
              style: theme.textTheme.bodyMedium,
            ),
          ] else if (candidate.operation == GlobalKnowledgeOperation.delete &&
              currentTarget != null) ...[
            const SizedBox(height: 10),
            Text('确认后将删除以下全局知识：', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(currentTarget.title, style: theme.textTheme.labelLarge),
          ],
          if (!showUpdateDiff && !showAppliedUpdate)
            if (candidate.proposal['body'] case final String body)
              if (body.isNotEmpty) ...[
                const SizedBox(height: 8),
                SelectableText(body),
              ],
          if (candidate.proposal['facts'] != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              jsonEncode(candidate.proposal['facts']),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (candidate.error != null) ...[
            const SizedBox(height: 6),
            Text(
              candidate.error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (showActions && isPending) ...[
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => _reject(context),
                  child: const Text('拒绝'),
                ),
                FilledButton(
                  onPressed: () => _confirm(context),
                  child: Text('确认$operation'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    try {
      await results.confirmGlobalKnowledgeChange(
        candidate.id,
        displayedDigest: candidate.digest,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('全局知识$operationLabel')));
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('未执行：$error')));
      }
    }
  }

  Future<void> _reject(BuildContext context) async {
    try {
      await results.rejectGlobalKnowledgeChange(
        candidate.id,
        displayedDigest: candidate.digest,
      );
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法拒绝：$error')));
      }
    }
  }

  String get operationLabel => switch (candidate.operation) {
    GlobalKnowledgeOperation.create => '已新增',
    GlobalKnowledgeOperation.update => '已修改',
    GlobalKnowledgeOperation.delete => '已删除',
  };
}
