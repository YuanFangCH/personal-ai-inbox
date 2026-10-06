import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_scope.dart';
import '../widgets/common.dart';

class SyncPage extends StatelessWidget {
  const SyncPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final report = app.lastSyncReport;
    return PageFrame(
      title: '同步',
      subtitle: app.syncProviderName,
      actions: [
        FilledButton.icon(
          onPressed: app.isBusy ? null : app.syncNow,
          icon: const Icon(Icons.sync),
          label: const Text('立即同步'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SurfacePanel(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final status = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.cloud_sync_outlined,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                report == null ? '尚未同步' : '最近同步完成',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                report == null
                                    ? '等待第一次同步'
                                    : DateFormat('yyyy-MM-dd HH:mm')
                                          .format(report.finishedAt),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '当前通道是端内沙箱，用于验证上传、下载和冲突判定；OneDrive Provider 仍需完成 Microsoft 应用登记。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                );
                final metrics = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StatusPill(
                      label: '上传 ${report?.uploaded ?? 0}',
                      icon: Icons.upload,
                      tone: StatusTone.positive,
                    ),
                    StatusPill(
                      label: '下载 ${report?.downloaded ?? 0}',
                      icon: Icons.download,
                    ),
                    StatusPill(
                      label:
                          '冲突 ${report?.conflicts ?? app.conflictFiles.length}',
                      icon: Icons.call_split,
                      tone: (report?.conflicts ?? 0) > 0
                          ? StatusTone.danger
                          : StatusTone.neutral,
                    ),
                    StatusPill(
                      label: '失败 ${report?.failed ?? 0}',
                      icon: Icons.error_outline,
                      tone: (report?.failed ?? 0) > 0
                          ? StatusTone.danger
                          : StatusTone.neutral,
                    ),
                  ],
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [status, const SizedBox(height: 16), metrics],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: status),
                    const SizedBox(width: 24),
                    Flexible(child: metrics),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeading(title: '本地状态'),
                const SizedBox(height: 10),
                _StatusRow(label: '成果对象', value: '${app.documents.length}'),
                _StatusRow(
                  label: '待上传',
                  value:
                      '${app.documents.where((document) => document.status.wireName == 'canonical').length}',
                ),
                _StatusRow(label: '冲突副本', value: '${app.conflictFiles.length}'),
                _StatusRow(label: 'Markdown 主库', value: app.vaultRoot),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
