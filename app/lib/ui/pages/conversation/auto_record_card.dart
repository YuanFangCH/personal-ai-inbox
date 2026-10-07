part of '../conversation_page.dart';

class _AutoRecordCard extends StatelessWidget {
  const _AutoRecordCard({required this.action, required this.app});

  final AutoRecordAction action;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = switch (action.status) {
      AutoRecordStatus.created => StatusTone.positive,
      AutoRecordStatus.undone => StatusTone.neutral,
      AutoRecordStatus.review => StatusTone.warning,
      AutoRecordStatus.skipped => StatusTone.danger,
    };
    final label = switch (action.status) {
      AutoRecordStatus.created => '已自动创建',
      AutoRecordStatus.undone => '已撤销',
      AutoRecordStatus.review => '待人工确认',
      AutoRecordStatus.skipped => '未创建',
    };
    return SurfacePanel(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Icon(action.type.icon, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    StatusPill(label: label, tone: tone),
                    if (action.reason != null)
                      Text(action.reason!, style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
          if (action.status == AutoRecordStatus.created &&
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
          if (action.canUndo)
            TextButton(
              onPressed: () => app.undoAutoRecord(action.id),
              child: const Text('撤销'),
            ),
        ],
      ),
    );
  }
}
