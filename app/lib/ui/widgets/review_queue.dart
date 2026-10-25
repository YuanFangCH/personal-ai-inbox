import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/models.dart';
import '../../modules/capture/capture_workflow.dart';
import '../../modules/sync/sync_workspace.dart';
import '../presentation/domain_presentation.dart';
import '../app_scope.dart';
import 'common.dart';

class ReviewQueue extends StatelessWidget {
  const ReviewQueue({super.key});

  @override
  Widget build(BuildContext context) {
    final captureWorkflow = AppScope.capture(context);
    final syncWorkspace = AppScope.sync(context);
    final reviews = captureWorkflow.reviewCaptures;
    final conflicts = syncWorkspace.conflictFiles;
    if (reviews.isEmpty && conflicts.isEmpty) {
      return const SizedBox.shrink();
    }
    return AnimatedSize(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (reviews.isNotEmpty) ...[
            SectionHeading(title: '待确认', trailing: Text('${reviews.length} 项')),
            const SizedBox(height: 8),
            Column(
              children: [
                for (var index = 0; index < reviews.length; index++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _ReviewCaptureTile(
                      capture: reviews[index],
                      captureWorkflow: captureWorkflow,
                    ),
                  ),
                  if (index != reviews.length - 1) const Divider(height: 1),
                ],
              ],
            ),
            const SizedBox(height: 18),
          ],
          if (conflicts.isNotEmpty) ...[
            SectionHeading(
              title: '同步冲突',
              trailing: Text('${conflicts.length} 项'),
            ),
            const SizedBox(height: 8),
            Column(
              children: [
                for (var index = 0; index < conflicts.length; index++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _ConflictTile(
                      path: conflicts[index],
                      syncWorkspace: syncWorkspace,
                    ),
                  ),
                  if (index != conflicts.length - 1) const Divider(height: 1),
                ],
              ],
            ),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }
}

class _ReviewCaptureTile extends StatelessWidget {
  const _ReviewCaptureTile({
    required this.capture,
    required this.captureWorkflow,
  });

  final CaptureRecord capture;
  final CaptureWorkflow captureWorkflow;

  @override
  Widget build(BuildContext context) {
    final type = capture.candidateType ?? ResultType.knowledge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                resultTypeIcon(type),
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      capture.candidateTitle ?? '待整理',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 5),
                    Text(capture.text, maxLines: 3),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (capture.reviewReason != null)
                StatusPill(
                  label: capture.reviewReason!,
                  icon: Icons.info_outline,
                  tone: StatusTone.warning,
                ),
              FilledButton.tonalIcon(
                onPressed: () => captureWorkflow.acceptCapture(capture),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('按建议生成'),
              ),
              OutlinedButton.icon(
                onPressed: () => _changeAndAccept(context),
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('调整'),
              ),
              TextButton.icon(
                onPressed: () => captureWorkflow.rejectCapture(capture),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('忽略'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _changeAndAccept(BuildContext context) async {
    final decision = await showDialog<_ReviewDecision>(
      context: context,
      animationStyle: reducedMotionAnimationStyle(context),
      builder: (context) => _ReviewDialog(capture: capture),
    );
    if (decision != null) {
      await captureWorkflow.acceptCapture(
        capture,
        type: decision.type,
        title: decision.title,
      );
    }
  }
}

class _ReviewDecision {
  const _ReviewDecision(this.type, this.title);

  final ResultType type;
  final String title;
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({required this.capture});

  final CaptureRecord capture;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late final TextEditingController _title;
  late ResultType _type;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(
      text: widget.capture.candidateTitle ?? '待整理',
    );
    _type = widget.capture.candidateType ?? ResultType.knowledge;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('调整成果'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<ResultType>(
              segments: [
                for (final type in ResultType.values)
                  ButtonSegment(
                    value: type,
                    icon: Icon(resultTypeIcon(type)),
                    label: Text(resultTypeLabel(type)),
                  ),
              ],
              selected: {_type},
              onSelectionChanged: (value) =>
                  setState(() => _type = value.first),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: '标题'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _ReviewDecision(_type, _title.text.trim()),
          ),
          child: const Text('生成'),
        ),
      ],
    );
  }
}

class _ConflictTile extends StatelessWidget {
  const _ConflictTile({required this.path, required this.syncWorkspace});

  final String path;
  final SyncWorkspace syncWorkspace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.call_split),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.basename(path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '远端版本已保留为冲突副本',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '裁决冲突',
            onSelected: (value) => syncWorkspace.resolveConflict(
              path,
              useRemote: value == 'remote',
            ),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'local', child: Text('保留本地版本')),
              PopupMenuItem(value: 'remote', child: Text('使用远端版本')),
            ],
          ),
        ],
      ),
    );
  }
}
