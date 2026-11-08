part of '../conversation_page.dart';

class _TableChatActionCard extends StatelessWidget {
  const _TableChatActionCard({required this.action, required this.app});

  final TableChatAction action;
  final ConversationWorkspace app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pending = action.status == TableChatActionStatus.pendingConfirmation;
    final retryPending = action.status == TableChatActionStatus.pendingRetry;
    final tone = pending || retryPending
        ? scheme.tertiary
        : action.status == TableChatActionStatus.applied ||
              action.status == TableChatActionStatus.undone
        ? scheme.primary
        : action.status == TableChatActionStatus.failed ||
              action.status == TableChatActionStatus.stale
        ? scheme.error
        : scheme.onSurfaceVariant;
    return Card(
      key: ValueKey('table_chat_action_${action.id}'),
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  pending
                      ? Icons.rule_outlined
                      : retryPending
                      ? Icons.hourglass_top
                      : Icons.table_chart_outlined,
                  color: tone,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _actionHeading(action),
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                StatusPill(
                  label: _statusLabel(action.status),
                  tone: pending || retryPending
                      ? StatusTone.warning
                      : StatusTone.neutral,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                if (action.tableTitle != null) action.tableTitle!,
                action.title,
              ].where((part) => part.isNotEmpty).join(' · '),
            ),
            if (pending) ...[
              const SizedBox(height: 8),
              Text(
                _proposalDescription(action),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  OutlinedButton(
                    key: Key('reject_table_action_${action.id}'),
                    onPressed: () => app.rejectTableStructureAction(action.id),
                    child: const Text('拒绝'),
                  ),
                  FilledButton(
                    key: Key('confirm_table_action_${action.id}'),
                    onPressed: () => app.confirmTableStructureAction(action.id),
                    child: const Text('确认执行'),
                  ),
                ],
              ),
            ] else ...[
              if (action.message != null) ...[
                const SizedBox(height: 4),
                Text(
                  action.message!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (action.reviewRequired) ...[
                const SizedBox(height: 4),
                Text(
                  action.reviewReason ?? '此内容未能证明为重复，已新建并标记待核对。',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.tertiary),
                ),
              ],
              if ((action.retryableIntake || retryPending) &&
                  action.intakeCoverageComplete == false) ...[
                const SizedBox(height: 6),
                Text(
                  '查重语义覆盖：已检查 '
                  '${action.intakeCoverageChecked ?? 0}/'
                  '${action.intakeCoverageTotal ?? 0} 个候选，'
                  '仍有 ${((action.intakeCoverageTotal ?? 0) - (action.intakeCoverageChecked ?? 0)).clamp(0, 1 << 30)} 个未检查。'
                  '原始内容和操作意图已保存，尚未确认写入。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else if (retryPending) ...[
                const SizedBox(height: 6),
                Text(
                  '查重覆盖已完整；授权检查阻止写入。操作编号仍待执行，授权恢复后可继续。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (action.retryableIntake || retryPending) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    key: Key('retry_intake_${action.id}'),
                    onPressed: app.isHandlingIntakeRetry
                        ? null
                        : () => app.retryIncompleteIntakeAction(action.id),
                    icon: const Icon(Icons.refresh),
                    label: Text(action.intakeRetryPending ? '继续扫描' : '重新扫描并继续'),
                  ),
                ),
              ],
              if (action.recoveryBatchId != null && action.canUndo)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: Key('undo_table_action_${action.id}'),
                    onPressed: () => app.undoTableAction(action.id),
                    child: const Text('撤销'),
                  ),
                )
              else if (action.entryId != null && action.tableId != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _openEntry(context),
                    icon: const Icon(Icons.open_in_new, size: 17),
                    label: const Text('查看内容'),
                  ),
                )
              else if (action.tableId != null &&
                  const {
                    'table.body.update',
                    'table.create',
                    'table.rename',
                    'table.upsert_field',
                  }.contains(action.operation))
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _openTable(context),
                    icon: const Icon(Icons.open_in_new, size: 17),
                    label: const Text('查看表'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openEntry(BuildContext context) async {
    final id = action.entryId;
    final tableId = action.tableId;
    if (id == null || tableId == null) return;
    final library = AppScope.tables(context);
    final entry = await library.readEntry(id);
    if (!context.mounted || entry == null || entry.deleted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TableEntryEditorPage(
          tableId: tableId,
          type: entry.type,
          entry: entry,
        ),
      ),
    );
  }

  void _openTable(BuildContext context) {
    final id = action.tableId;
    if (id == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => TableDetailPage(tableId: id)),
    );
  }
}

String _actionHeading(TableChatAction action) {
  if (action.status == TableChatActionStatus.pendingConfirmation) {
    return '需要确认的表结构变更';
  }
  if (action.retryableIntake ||
      action.status == TableChatActionStatus.pendingRetry) {
    return '待重新扫描的接收意图';
  }
  final verb = switch (action.operation) {
    'content.create' => '已添加内容',
    'table.body.update' => '已更新表正文',
    'content.update' => '已更新内容',
    'content.move' => '已移动内容',
    'content.delete' => '已删除内容',
    'schedule.change' => '已更新日程并保留通知',
    'recovery.restore' => '已恢复回收站内容',
    'table.create' => '已创建表',
    'table.rename' => '已重命名表',
    'table.delete' => '已删除表',
    'table.upsert_field' => '已更新字段',
    'table.delete_field' => '已删除字段',
    _ => '表操作',
  };
  return action.status == TableChatActionStatus.applied
      ? verb
      : action.status == TableChatActionStatus.rejected
      ? '已拒绝'
      : action.status == TableChatActionStatus.stale
      ? '候选已过期'
      : action.status == TableChatActionStatus.undone
      ? '已撤销'
      : '未执行';
}

String _statusLabel(TableChatActionStatus status) => switch (status) {
  TableChatActionStatus.applied => '已执行',
  TableChatActionStatus.pendingConfirmation => '待确认',
  TableChatActionStatus.pendingRetry => '待继续扫描',
  TableChatActionStatus.rejected => '已拒绝',
  TableChatActionStatus.stale => '需重新确认',
  TableChatActionStatus.failed => '失败',
  TableChatActionStatus.undone => '已撤销',
  TableChatActionStatus.expired => '已过期',
};

String _proposalDescription(TableChatAction action) {
  final operation = action.proposal['operation'];
  final payload = action.proposal['payload'];
  final fields = payload is Map ? payload : const <String, Object?>{};
  return switch (operation) {
    'create' => '将新建表“${action.title}”。',
    'rename' => '将表重命名为“${fields['name'] ?? action.title}”。',
    'delete' =>
      '将删除“${action.tableTitle ?? action.title}”及 ${fields['content_count'] ?? '其全部'} 条内容，30 天内可从回收站恢复。',
    'upsert_field' =>
      '将修改“${action.tableTitle}”中的字段“${action.title}”（${_proposalFieldDescription(fields['field'])}）。',
    'delete_field' =>
      '将删除字段“${action.title}”及 ${fields['value_count'] ?? '已有'} 条字段值，30 天内可撤销。',
    _ => '确认后才会修改表结构。',
  };
}

String _proposalFieldDescription(Object? raw) {
  if (raw is! Map) return '字段定义';
  final type = raw['type']?.toString() ?? '字段';
  final options = raw['options'];
  if (options is! List || options.isEmpty) return type;
  final labels = options
      .whereType<Map>()
      .map((option) => option['label']?.toString() ?? '')
      .where((label) => label.isNotEmpty)
      .join('、');
  return labels.isEmpty ? type : '$type：$labels';
}
