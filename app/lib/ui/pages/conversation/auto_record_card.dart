part of '../conversation_page.dart';

class _AutoRecordCard extends StatefulWidget {
  const _AutoRecordCard({required this.action, required this.app});

  final AutoRecordAction action;
  final ConversationWorkspace app;

  @override
  State<_AutoRecordCard> createState() => _AutoRecordCardState();
}

class _AutoRecordCardState extends State<_AutoRecordCard> {
  bool _undoing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = widget.action;
    final tone = switch (action.status) {
      AutoRecordStatus.created => StatusTone.positive,
      AutoRecordStatus.undone => StatusTone.neutral,
      AutoRecordStatus.review => StatusTone.warning,
      AutoRecordStatus.skipped ||
      AutoRecordStatus.undoFailed => StatusTone.danger,
      AutoRecordStatus.expired => StatusTone.neutral,
    };
    final label = switch (action.status) {
      AutoRecordStatus.created =>
        action.undoUntil != null && !action.canUndo
            ? '已执行 · 撤销已过期'
            : switch (action.operation) {
                AutoRecordOperation.create => '已新增成果',
                AutoRecordOperation.update => '已修改成果',
                AutoRecordOperation.delete => '已删除成果',
              },
      AutoRecordStatus.undone => '已撤销',
      AutoRecordStatus.review => '待人工确认',
      AutoRecordStatus.skipped => '未执行',
      AutoRecordStatus.undoFailed => '撤销失败',
      AutoRecordStatus.expired => '撤销已过期',
    };
    final icon = switch (action.status) {
      AutoRecordStatus.created => Icons.check_circle_outline,
      AutoRecordStatus.undone => Icons.undo,
      AutoRecordStatus.review => Icons.pending_outlined,
      AutoRecordStatus.skipped ||
      AutoRecordStatus.undoFailed => Icons.error_outline,
      AutoRecordStatus.expired => Icons.schedule_outlined,
    };
    final toneColor = switch (tone) {
      StatusTone.positive => theme.colorScheme.primary,
      StatusTone.warning => theme.colorScheme.tertiary,
      StatusTone.danger => theme.colorScheme.error,
      StatusTone.neutral => theme.colorScheme.onSurfaceVariant,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppDesignTokens.controlRadius),
        border: Border(left: BorderSide(color: toneColor, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            Icon(icon, color: toneColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${resultTypeLabel(action.type)} · ${action.title}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 7,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusPill(label: _undoing ? '正在撤销' : label, tone: tone),
                      Text(
                        DateFormat('MM-dd HH:mm').format(action.createdAt),
                        style: theme.textTheme.bodySmall,
                      ),
                      if (action.canUndo && action.undoUntil != null)
                        Text(
                          '可撤销至 ${DateFormat('HH:mm').format(action.undoUntil!)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      if (action.reason != null)
                        Text(action.reason!, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
            if (action.status == AutoRecordStatus.created &&
                action.operation != AutoRecordOperation.delete &&
                action.resultId != null)
              IconButton(
                tooltip: '打开成果',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        DocumentDetailPage(documentId: action.resultId!),
                  ),
                ),
                icon: const Icon(Icons.open_in_new),
              ),
            if (_undoing)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (action.canUndo)
              TextButton(onPressed: _undo, child: const Text('撤销')),
          ],
        ),
      ),
    );
  }

  Future<void> _undo() async {
    if (_undoing) return;
    setState(() => _undoing = true);
    try {
      await widget.app.undoAutoRecord(widget.action.id);
    } finally {
      if (mounted) setState(() => _undoing = false);
    }
  }
}
