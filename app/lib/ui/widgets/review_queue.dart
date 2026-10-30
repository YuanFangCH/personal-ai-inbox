import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/table_models.dart';
import '../../modules/capture/capture_workflow.dart';
import '../app_scope.dart';
import 'common.dart';

class CaptureReviewQueue extends StatelessWidget {
  const CaptureReviewQueue({super.key});

  @override
  Widget build(BuildContext context) {
    final captureWorkflow = AppScope.capture(context);
    final reviews = captureWorkflow.reviewCaptures;
    if (reviews.isEmpty) {
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
            SectionHeading(
              title: '待整理捕获',
              trailing: Text('${reviews.length} 项'),
            ),
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
    final type = _captureTableType(capture);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _captureTypeIcon(type),
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
                onPressed: () =>
                    _accept(captureWorkflow, capture, context: context),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('按建议保存'),
              ),
              OutlinedButton.icon(
                onPressed: () => _accept(
                  captureWorkflow,
                  capture,
                  type: TableContentType.note,
                  title: capture.candidateTitle ?? '待整理笔记',
                  context: context,
                ),
                icon: const Icon(Icons.notes_outlined, size: 18),
                label: const Text('保存为笔记'),
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
    if (!context.mounted) return;
    if (decision != null) {
      await _accept(
        captureWorkflow,
        capture,
        type: decision.type,
        title: decision.title,
        context: context,
      );
    }
  }

  Future<void> _accept(
    CaptureWorkflow workflow,
    CaptureRecord capture, {
    TableContentType? type,
    String? title,
    BuildContext? context,
  }) async {
    try {
      await workflow.acceptCaptureToTable(capture, type: type, title: title);
    } on Object catch (error) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '保存捕获失败：${error is StateError ? error.message : error}',
            ),
          ),
        );
      }
    }
  }
}

class _ReviewDecision {
  const _ReviewDecision(this.type, this.title);

  final TableContentType type;
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
  late TableContentType _type;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(
      text: widget.capture.candidateTitle ?? '待整理',
    );
    _type = _captureTableType(widget.capture);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('调整捕获归类'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<TableContentType>(
              segments: [
                for (final type in _availableCaptureTypes(widget.capture))
                  ButtonSegment(
                    value: type,
                    icon: Icon(_captureTypeIcon(type)),
                    label: Text(_captureTypeLabel(type)),
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
          child: const Text('保存到表'),
        ),
      ],
    );
  }
}

TableContentType _captureTableType(CaptureRecord capture) =>
    switch (capture.candidateType) {
      ResultType.todo => TableContentType.todo,
      ResultType.event =>
        capture.candidateAt?.isAfter(DateTime.now()) == true
            ? TableContentType.schedule
            : TableContentType.event,
      ResultType.matter ||
      ResultType.knowledge ||
      null => TableContentType.note,
    };

List<TableContentType> _availableCaptureTypes(CaptureRecord capture) => [
  TableContentType.note,
  TableContentType.todo,
  TableContentType.event,
  if (capture.candidateType == ResultType.event &&
      capture.candidateAt?.isAfter(DateTime.now()) == true)
    TableContentType.schedule,
];

String _captureTypeLabel(TableContentType type) => switch (type) {
  TableContentType.note => '笔记',
  TableContentType.todo => '待办',
  TableContentType.schedule => '日程',
  TableContentType.event => '事件',
};

IconData _captureTypeIcon(TableContentType type) => switch (type) {
  TableContentType.note => Icons.notes_outlined,
  TableContentType.todo => Icons.check_circle_outline,
  TableContentType.schedule => Icons.event_outlined,
  TableContentType.event => Icons.history,
};
