import 'package:flutter/material.dart';

import '../../../core/ai_policy.dart';

Future<AiPolicy?> showConversationPermissionSheet({
  required BuildContext context,
  required AiPolicy initialPolicy,
}) {
  return showModalBottomSheet<AiPolicy>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (context) =>
        ConversationPermissionSheet(initialPolicy: initialPolicy),
  );
}

class ConversationPermissionSheet extends StatefulWidget {
  const ConversationPermissionSheet({super.key, required this.initialPolicy});

  final AiPolicy initialPolicy;

  @override
  State<ConversationPermissionSheet> createState() =>
      _ConversationPermissionSheetState();
}

class _ConversationPermissionSheetState
    extends State<ConversationPermissionSheet> {
  late AiPolicy _policy = widget.initialPolicy;

  AiPolicyPreset get _preset => _policy.preset;

  void _selectPreset(AiPolicyPreset preset) {
    setState(() {
      _policy = preset == AiPolicyPreset.custom
          ? AiPolicy.custom(
              decisions: _policy.decisions,
              version: _policy.version + 1,
              tableScope: _policy.tableScope,
              knowledgeReadScope: _policy.knowledgeReadScope,
              conversationHistoryReadScope:
                  _policy.conversationHistoryReadScope,
            )
          : AiPolicy.forPreset(preset, version: _policy.version + 1);
    });
  }

  void _setDecisionGroup(
    Set<AiPermissionAction> actions,
    AiPolicyDecision decision,
  ) {
    final decisions = {..._policy.decisions};
    for (final action in actions) {
      decisions[action] = decision;
    }
    setState(() {
      _policy = AiPolicy.custom(
        decisions: decisions,
        version: _policy.version + 1,
        tableScope: _policy.tableScope,
        knowledgeReadScope: _policy.knowledgeReadScope,
        conversationHistoryReadScope: _policy.conversationHistoryReadScope,
      );
    });
  }

  Future<void> _apply() async {
    if (_preset == AiPolicyPreset.fullAccess) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('启用完全权限？'),
          content: const Text(
            '完全权限允许 AI 直接调整任意表和内容、删除预置表、修改字段，'
            '并让全局知识直接生效。每次操作仍会显示真实回执和可用的撤销入口。',
          ),
          actions: [
            TextButton(
              key: const Key('permission_full_access_cancel'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('permission_full_access_confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('启用完全权限'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    Navigator.pop(context, _policy);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('当前对话权限', style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    key: const Key('conversation_permissions_close'),
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '权限只影响当前对话。预设会整体替换策略；自定义可逐组选择允许、确认或禁止。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Text('权限模式', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in AiPolicyPreset.values)
                    ChoiceChip(
                      key: Key('permission_preset_${preset.wireName}'),
                      label: Text(_presetLabel(preset)),
                      selected: _preset == preset,
                      onSelected: (_) => _selectPreset(preset),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _PresetExplanation(preset: _preset),
              if (_preset == AiPolicyPreset.custom) ...[
                const SizedBox(height: 16),
                Text('自定义动作', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final group in _customGroups)
                  _DecisionGroupTile(
                    group: group,
                    decision: _groupDecision(_policy, group.actions),
                    onChanged: (decision) =>
                        _setDecisionGroup(group.actions, decision),
                  ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const Key('conversation_permissions_apply'),
                onPressed: _apply,
                icon: const Icon(Icons.check),
                label: const Text('应用到此对话'),
              ),
              const SizedBox(height: 8),
              Text(
                '完全权限不包含 API Key、系统文件、SQL、操作系统权限、'
                '历史消息修改或修改权限设置本身。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetExplanation extends StatelessWidget {
  const _PresetExplanation({required this.preset});

  final AiPolicyPreset preset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, description, tone) = switch (preset) {
      AiPolicyPreset.readOnly => (
        '只读',
        '允许按权限范围读取，所有新增、修改、删除和结构调整均禁止。',
        theme.colorScheme.secondaryContainer,
      ),
      AiPolicyPreset.standard => (
        '标准秘书',
        '表内内容和正文可直接增改删；表结构、收纳目标、恢复与全局知识写入逐项确认。',
        theme.colorScheme.surfaceContainerHighest,
      ),
      AiPolicyPreset.fullAccess => (
        '完全权限',
        '可直接管理任意表及内容、字段、收纳目标和全局知识，包括删除三个预置收纳表。',
        theme.colorScheme.errorContainer,
      ),
      AiPolicyPreset.custom => (
        '自定义',
        '每类动作可独立选择允许、每次确认或禁止；未配置动作按禁止处理。',
        theme.colorScheme.tertiaryContainer,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(description),
        ],
      ),
    );
  }
}

class _DecisionGroupTile extends StatelessWidget {
  const _DecisionGroupTile({
    required this.group,
    required this.decision,
    required this.onChanged,
  });

  final _CustomDecisionGroup group;
  final AiPolicyDecision decision;
  final ValueChanged<AiPolicyDecision> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.title),
                const SizedBox(height: 2),
                Text(
                  group.subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<AiPolicyDecision>(
            key: Key('permission_group_${group.id}'),
            value: decision,
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
            items: [
              for (final value in AiPolicyDecision.values)
                DropdownMenuItem(
                  value: value,
                  child: Text(_decisionLabel(value)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

AiPolicyDecision _groupDecision(
  AiPolicy policy,
  Set<AiPermissionAction> actions,
) {
  final decisions = {for (final action in actions) policy.decisionFor(action)};
  return decisions.length == 1 ? decisions.single : AiPolicyDecision.ask;
}

String _presetLabel(AiPolicyPreset preset) => switch (preset) {
  AiPolicyPreset.readOnly => '只读',
  AiPolicyPreset.standard => '标准秘书',
  AiPolicyPreset.fullAccess => '完全权限',
  AiPolicyPreset.custom => '自定义',
};

String _decisionLabel(AiPolicyDecision decision) => switch (decision) {
  AiPolicyDecision.allow => '允许',
  AiPolicyDecision.ask => '每次确认',
  AiPolicyDecision.deny => '禁止',
};

const _readActions = {
  AiPermissionAction.tableRead,
  AiPermissionAction.contentRead,
  AiPermissionAction.globalKnowledgeRead,
  AiPermissionAction.globalKnowledgeSearch,
  AiPermissionAction.conversationHistorySearch,
  AiPermissionAction.conversationHistoryRead,
};

const _customGroups = [
  _CustomDecisionGroup(
    id: 'read',
    title: '读取',
    subtitle: '表、内容、全局知识和历史会话',
    actions: _readActions,
  ),
  _CustomDecisionGroup(
    id: 'create',
    title: '新增内容',
    subtitle: '创建表内笔记、待办、日程和事件',
    actions: {AiPermissionAction.contentCreate},
  ),
  _CustomDecisionGroup(
    id: 'modify',
    title: '修改内容',
    subtitle: '更新、移动和删除表内内容及表正文',
    actions: {
      AiPermissionAction.contentUpdate,
      AiPermissionAction.contentDelete,
      AiPermissionAction.contentMove,
      AiPermissionAction.tableBodyUpdate,
    },
  ),
  _CustomDecisionGroup(
    id: 'structure',
    title: '表结构、收纳与恢复',
    subtitle: '建删表、调整字段、修改收纳目标和执行恢复',
    actions: {
      AiPermissionAction.tableCreate,
      AiPermissionAction.tableUpdate,
      AiPermissionAction.tableDelete,
      AiPermissionAction.fieldAdjust,
      AiPermissionAction.inboxTargetAdjust,
      AiPermissionAction.restore,
    },
  ),
  _CustomDecisionGroup(
    id: 'knowledge',
    title: '全局知识写入',
    subtitle: '新增、更新或删除全局事实',
    actions: {
      AiPermissionAction.globalKnowledgeCreate,
      AiPermissionAction.globalKnowledgeUpdate,
      AiPermissionAction.globalKnowledgeDelete,
    },
  ),
];

class _CustomDecisionGroup {
  const _CustomDecisionGroup({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final String id;
  final String title;
  final String subtitle;
  final Set<AiPermissionAction> actions;
}
