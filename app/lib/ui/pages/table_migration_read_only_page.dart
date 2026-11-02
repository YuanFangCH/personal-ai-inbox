import 'package:flutter/material.dart';

import '../../modules/tables/table_migration_gate.dart';

class TableMigrationReadOnlyPage extends StatelessWidget {
  const TableMigrationReadOnlyPage({super.key, required this.gate});

  final TableMigrationGate gate;

  Future<void> _confirmAndApply(BuildContext context) async {
    final preview = gate.preview;
    if (preview == null || !preview.canApply || gate.migrationComplete) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认迁移旧资料'),
        content: Text(
          '将创建 ${preview.tables.length} 张表和 ${preview.entries.length} 条内容。应用会先备份 vault、数据库、会话和设置并校验空间；完成后清理已校验备份的旧格式源件，保留全局知识及迁移备份。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始迁移'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await gate.applyMigration();
    } on Object {
      // The gate keeps the failure visible and retains all source files.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('旧资料只读预检'),
        automaticallyImplyLeading: false,
      ),
      body: AnimatedBuilder(
        animation: gate,
        builder: (context, _) {
          final preview = gate.previewPresentation;
          return Column(
            children: [
              Material(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lock_outline,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '检测到旧格式资料。当前只读展示预检结果，原资料没有被改动。迁移和新表页面接通前，旧格式写入保持关闭。',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (gate.isChecking) const LinearProgressIndicator(),
              Expanded(
                child: gate.error != null
                    ? _ErrorState(message: gate.error!)
                    : preview == null
                    ? const Center(child: Text('正在检查旧资料…'))
                    : _PreviewContent(
                        preview: preview,
                        migrationComplete: gate.migrationComplete,
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if ((gate.preview?.canApply ?? false) &&
                          !gate.migrationComplete)
                        FilledButton.icon(
                          onPressed: gate.isChecking || gate.isApplying
                              ? null
                              : () => _confirmAndApply(context),
                          icon: gate.isApplying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.drive_file_move_outline),
                          label: Text(gate.isApplying ? '迁移中…' : '迁移到表格式'),
                        ),
                      if ((gate.preview?.canApply ?? false) &&
                          !gate.migrationComplete)
                        const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: gate.isChecking || gate.isApplying
                            ? null
                            : gate.refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重新检查'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PreviewContent extends StatelessWidget {
  const _PreviewContent({
    required this.preview,
    required this.migrationComplete,
  });

  final TableMigrationPreviewPresentation preview;
  final bool migrationComplete;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      children: [
        Text('迁移预检', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '发现 ${preview.legacyRecordCount} 条可读取旧资料；拟建立 ${preview.tablesCount} 张表和 ${preview.entryCount} 条内容。全局知识保留在原独立管理中。',
        ),
        if (migrationComplete) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: const ListTile(
              leading: Icon(Icons.task_alt),
              title: Text('迁移副本已生成'),
              subtitle: Text('旧 Markdown 源件仍保留；当前继续只读，直到新表页面接管。'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          '空间估算：备份 ${_formatBytes(preview.estimatedBackupBytes)}，新格式文件 ${_formatBytes(preview.estimatedOutputBytes)}，本次总计约 ${_formatBytes(preview.estimatedRequiredBytes)}。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (preview.availableBytes != null) ...[
          const SizedBox(height: 4),
          Text(
            '当前可用 ${_formatBytes(preview.availableBytes!)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (preview.issues.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('需要人工处理', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final issue in preview.issues)
            Card(
              child: ListTile(
                leading: const Icon(Icons.warning_amber_outlined),
                title: Text(issue.message),
                subtitle: Text(issue.path),
              ),
            ),
        ],
        const SizedBox(height: 24),
        Text('旧资料（只读）', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final record in preview.records)
          Card(
            child: ExpansionTile(
              leading: Icon(_typeIcon(record.type)),
              title: Text(record.title),
              subtitle: Text(
                '${record.type} · ${record.status}${record.deleted ? ' · 已删除' : ''}\n${record.sourcePath}',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    record.body.isEmpty ? '（无正文）' : record.body,
                  ),
                ),
              ],
            ),
          ),
        if (preview.records.isEmpty)
          const Card(child: ListTile(title: Text('没有可读取的旧资料'))),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 12),
          const Text('旧资料预检未完成，应用保持只读。'),
          const SizedBox(height: 8),
          SelectableText(message),
        ],
      ),
    ),
  );
}

IconData _typeIcon(String type) => switch (type) {
  'matter' => Icons.folder_outlined,
  'todo' => Icons.check_box_outlined,
  'event' => Icons.event_outlined,
  'knowledge' => Icons.notes_outlined,
  _ => Icons.notes_outlined,
};

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
