part of '../conversation_page.dart';

class _ChatActivityPanel extends StatefulWidget {
  const _ChatActivityPanel({required this.message, required this.live});

  final ChatMessage message;
  final ChatLiveActivity? live;

  @override
  State<_ChatActivityPanel> createState() => _ChatActivityPanelState();
}

class _ChatActivityPanelState extends State<_ChatActivityPanel> {
  static const _liveLimit = 6;
  static const _pageSize = 20;
  var _expanded = false;
  var _visibleHistoryCount = _pageSize;

  @override
  Widget build(BuildContext context) {
    final completed = completedChatActivityTools(widget.message.toolTranscript);
    final live = widget.live;
    if (live != null) {
      final completedKeys = completed.map((tool) => tool.key).toSet();
      final rows = <(ChatActivityTool, bool)>[
        for (final tool in completed) (tool, false),
        for (final tool in live.runningTools)
          if (!completedKeys.contains(tool.key)) (tool, true),
      ];
      final visible = rows.length <= _liveLimit
          ? rows
          : rows.sublist(rows.length - _liveLimit);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              child: _phaseLabel(context, live.phase),
            ),
            if (rows.length > visible.length)
              Padding(
                padding: const EdgeInsets.only(left: 28, bottom: 4),
                child: Text(
                  '还有 ${rows.length - visible.length} 条工具记录',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            for (final (tool, running) in visible)
              _toolRow(context, tool, running: running),
          ],
        ),
      );
    }
    if (completed.isEmpty || widget.message.isUser) {
      return const SizedBox.shrink();
    }

    final start = (completed.length - _visibleHistoryCount).clamp(
      0,
      completed.length,
    );
    final history = completed.sublist(start);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        key: ValueKey('chat_activity_${widget.message.id}'),
        initiallyExpanded: _expanded,
        onExpansionChanged: (value) => setState(() => _expanded = value),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        dense: true,
        leading: const Icon(Icons.auto_awesome_outlined, size: 18),
        title: Text(
          '运行过程 · ${completed.length} 个工具调用',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        children: [
          for (final tool in history) _toolRow(context, tool),
          if (start > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    setState(() => _visibleHistoryCount += _pageSize),
                child: Text('查看更早步骤（还有 $start 条）'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _phaseLabel(BuildContext context, ChatActivityPhase phase) {
    final (icon, label) = switch (phase) {
      ChatActivityPhase.preparing => (Icons.hourglass_top, '正在准备'),
      ChatActivityPhase.waitingForModel => (Icons.hourglass_empty, '等待模型响应'),
      ChatActivityPhase.thinking => (Icons.auto_awesome_outlined, '正在思考'),
      ChatActivityPhase.runningTools => (Icons.build_outlined, '正在调用工具'),
      ChatActivityPhase.writingReply => (Icons.edit_note, '正在生成回复'),
      ChatActivityPhase.waitingToRetry => (Icons.refresh, '等待重试'),
    };
    return _activityLabel(context, icon, label);
  }

  Widget _toolRow(
    BuildContext context,
    ChatActivityTool tool, {
    bool running = false,
  }) => _activityLabel(
    context,
    running ? Icons.play_arrow : Icons.check,
    '${running ? '调用工具' : '工具已返回'} · ${_toolActivityLabel(tool.wireName)}',
  );

  Widget _activityLabel(BuildContext context, IconData icon, String label) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Icon(
              icon,
              size: 17,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _toolActivityLabel(String wireName) => switch (wireName) {
  'table_list' => '查看表列表',
  'table_search' => '搜索表',
  'table_read' => '读取表',
  'content_search' => '搜索内容',
  'content_read' => '读取内容',
  'content_verify' => '核对内容',
  'content_create' => '新增内容',
  'content_update' => '修改内容',
  'content_move' => '移动内容',
  'content_delete' => '删除内容',
  'table_body_update' => '修改表正文',
  'table_propose' => '申请修改表结构',
  'schedule_change' => '调整日程',
  'recovery_list' => '查看回收站',
  'recovery_preview' => '预览回收内容',
  'recovery_restore' => '恢复内容',
  'inbox_targets_read' => '查看收纳目标',
  'search_global_knowledge' => '搜索全局知识',
  'read_global_knowledge' => '读取全局知识',
  'conversation_list' => '查看会话',
  'attachment_search' => '搜索附件',
  'attachment_read' => '读取附件',
  'app_settings_read' => '查看应用设置',
  'app_settings_update' => '修改应用设置',
  'widget_list' => '查看桌面小组件',
  'widget_get' => '读取桌面小组件',
  'widget_manage' => '管理桌面小组件',
  'conversation_manage' => '管理会话',
  'attachment_manage' => '管理附件',
  'propose_global_knowledge_change' => '申请修改全局知识',
  'search_results' => '搜索成果',
  'read_result' => '读取成果',
  'create_result' => '新增成果',
  'update_result' => '修改成果',
  'delete_result' => '删除成果',
  _ => '应用工具',
};
