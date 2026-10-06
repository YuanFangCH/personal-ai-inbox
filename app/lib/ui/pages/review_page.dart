import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/models.dart';
import '../../services/app_controller.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

class ReviewPage extends StatelessWidget {
  const ReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final reviews = app.reviewCaptures;
    final conflicts = app.conflictFiles;
    final total = reviews.length + conflicts.length;
    return PageFrame(
      title: '确认',
      subtitle: total == 0 ? '没有待确认内容' : '$total 项需要处理',
      child: total == 0
          ? const EmptyState(
              icon: Icons.verified_outlined,
              title: '没有待确认内容',
              message: '低置信度捕获和同步冲突会出现在这里。',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (reviews.isNotEmpty) ...[
                  SectionHeading(
                    title: '捕获确认',
                    trailing: Text('${reviews.length} 项'),
                  ),
                  const SizedBox(height: 8),
                  SurfacePanel(
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < reviews.length;
                          index++
                        ) ...[
                          _ReviewCaptureTile(capture: reviews[index], app: app),
                          if (index != reviews.length - 1)
                            const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                if (conflicts.isNotEmpty) ...[
                  SectionHeading(
                    title: '同步冲突',
                    trailing: Text('${conflicts.length} 项'),
                  ),
                  const SizedBox(height: 8),
                  SurfacePanel(
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < conflicts.length;
                          index++
                        ) ...[
                          _ConflictTile(path: conflicts[index], app: app),
                          if (index != conflicts.length - 1)
                            const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _ReviewCaptureTile extends StatelessWidget {
  const _ReviewCaptureTile({required this.capture, required this.app});

  final CaptureRecord capture;
  final AppController app;

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
              Icon(type.icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      capture.candidateTitle ?? '待整理',
                      style: const TextStyle(fontWeight: FontWeight.w800),
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
                onPressed: () => app.acceptCapture(capture),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('按建议生成'),
              ),
              OutlinedButton.icon(
                onPressed: () => _changeAndAccept(context),
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('调整'),
              ),
              TextButton.icon(
                onPressed: () => app.rejectCapture(capture),
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
      builder: (context) => _ReviewDialog(capture: capture),
    );
    if (decision != null) {
      await app.acceptCapture(
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
                    icon: Icon(type.icon),
                    label: Text(type.label),
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
  const _ConflictTile({required this.path, required this.app});

  final String path;
  final AppController app;

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
                  style: const TextStyle(fontWeight: FontWeight.w700),
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
            onSelected: (value) =>
                app.resolveConflict(path, useRemote: value == 'remote'),
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
