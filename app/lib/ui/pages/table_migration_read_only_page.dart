import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../data/table_migration_service.dart';
import '../../modules/tables/table_migration_gate.dart';

class TableMigrationReadOnlyPage extends StatelessWidget {
  const TableMigrationReadOnlyPage({super.key, required this.gate});

  final TableMigrationGate gate;

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
          final preview = gate.preview;
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
                    : _PreviewContent(preview: preview),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: gate.isChecking ? null : gate.refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新检查'),
                    ),
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
  const _PreviewContent({required this.preview});

  final TableMigrationPreview preview;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      children: [
        Text('迁移预检', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '发现 ${preview.legacyRecords.length} 条可读取旧资料；拟建立 ${preview.tables.length} 张表和 ${preview.entries.length} 条内容。全局知识保留在原独立管理中。',
        ),
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
        for (final record in preview.legacyRecords)
          Card(
            child: ExpansionTile(
              leading: Icon(_typeIcon(record.type)),
              title: Text(record.title),
              subtitle: Text(
                '${record.type.wireName} · ${record.status.wireName}${record.deleted ? ' · 已删除' : ''}\n${record.sourcePath}',
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
        if (preview.legacyRecords.isEmpty)
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

IconData _typeIcon(ResultType type) => switch (type) {
  ResultType.matter => Icons.folder_outlined,
  ResultType.todo => Icons.check_box_outlined,
  ResultType.event => Icons.event_outlined,
  ResultType.knowledge => Icons.notes_outlined,
};

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
