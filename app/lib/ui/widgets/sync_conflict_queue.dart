import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../modules/sync/sync_workspace.dart';
import 'common.dart';

class SyncConflictQueue extends StatelessWidget {
  const SyncConflictQueue({super.key, required this.workspace});

  final SyncWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: workspace,
      builder: (context, _) {
        final paths = workspace.conflictFiles;
        if (paths.isEmpty) return const SizedBox.shrink();
        return SurfacePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeading(
                title: '同步冲突',
                trailing: Text('${paths.length} 项'),
              ),
              const SizedBox(height: 8),
              for (var index = 0; index < paths.length; index++) ...[
                _ConflictTile(path: paths[index], workspace: workspace),
                if (index != paths.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ConflictTile extends StatelessWidget {
  const _ConflictTile({required this.path, required this.workspace});

  final String path;
  final SyncWorkspace workspace;

  @override
  Widget build(BuildContext context) => Padding(
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
          onSelected: (value) =>
              workspace.resolveConflict(path, useRemote: value == 'remote'),
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'local', child: Text('保留本地版本')),
            PopupMenuItem(value: 'remote', child: Text('使用远端版本')),
          ],
        ),
      ],
    ),
  );
}
