import 'package:flutter/material.dart';

import '../../../modules/conversation/conversation_workspace.dart';

class AgentTaskStatusCard extends StatefulWidget {
  const AgentTaskStatusCard({super.key, required this.workspace});

  final ConversationWorkspace workspace;

  @override
  State<AgentTaskStatusCard> createState() => _AgentTaskStatusCardState();
}

class _AgentTaskStatusCardState extends State<AgentTaskStatusCard> {
  final Set<String> _busyRunIds = {};

  Future<void> _resume(AgentTaskSummary task) async {
    if (_busyRunIds.contains(task.runId)) return;
    final workspace = widget.workspace;
    if (task.needsReview) {
      final reviewed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('核对中断操作'),
          content: const Text('部分操作在中断时未取得完整回执。请先查看操作卡及表内实际内容，核对后再继续，以免重复修改。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('稍后核对'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('已核对，继续'),
            ),
          ],
        ),
      );
      if (reviewed != true || !mounted) return;
    }
    setState(() => _busyRunIds.add(task.runId));
    try {
      await workspace.resumeTasks(
        taskId: task.taskIds.first,
        approveUncertainEffects: task.needsReview,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('任务未能继续：$error')));
      }
    } finally {
      if (mounted) setState(() => _busyRunIds.remove(task.runId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = widget.workspace;
    final tasks = workspace.tasksNeedingAction;
    if (tasks.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      key: const Key('agent_task_status_card'),
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (workspace.fullAgentMode) ...[
              const Text('完全体模式运行中', key: Key('agent_full_agent_mode_status')),
              const SizedBox(height: 6),
            ],
            for (var index = 0; index < tasks.length; index++) ...[
              if (index > 0) const Divider(),
              _taskSection(tasks[index], index),
            ],
          ],
        ),
      ),
    );
  }

  Widget _taskSection(AgentTaskSummary task, int index) {
    final usage = task.usage;
    final busy = _busyRunIds.contains(task.runId);
    final conversation = widget.workspace.findConversation(task.conversationId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          task.needsReview
              ? '任务中断，等待核对'
              : task.awaitingInput
              ? '任务等待确认或补充'
              : '任务已暂停',
        ),
        if (conversation != null) Text(conversation.title),
        Text(
          '已使用 ${usage.usedRequests} 次模型请求、'
          '${usage.usedToolCalls} 次工具调用，待继续 ${task.taskIds.length} 项。',
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: index == 0
              ? const Key('resume_agent_tasks')
              : Key('resume_agent_tasks_${task.runId}'),
          onPressed: busy ? null : () => _resume(task),
          child: Text(task.awaitingInput ? '已确认或补充，继续任务' : '继续任务'),
        ),
      ],
    );
  }
}
