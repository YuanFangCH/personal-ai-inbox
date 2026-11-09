enum AgentToolAccess { read, write }

class AgentToolSpec {
  const AgentToolSpec({
    required this.operationName,
    required this.wireName,
    required this.access,
    required this.parallelSafe,
  });

  final String operationName;
  final String wireName;
  final AgentToolAccess access;
  final bool parallelSafe;
}

/// Central tool identity and execution classification.
///
/// Schemas remain policy-specific in ChatService; this registry is the single
/// place that decides whether a wire tool is a read or an exclusive write.
class AgentToolRegistry {
  const AgentToolRegistry();

  static const List<AgentToolSpec> specs = [
    AgentToolSpec(
      operationName: 'table.list',
      wireName: 'table_list',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'table.search',
      wireName: 'table_search',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'table.read',
      wireName: 'table_read',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'content.search',
      wireName: 'content_search',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'content.read',
      wireName: 'content_read',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'content.verify',
      wireName: 'content_verify',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'recovery.list',
      wireName: 'recovery_list',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'recovery.preview',
      wireName: 'recovery_preview',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'inbox.targets.read',
      wireName: 'inbox_targets_read',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'search_global_knowledge',
      wireName: 'search_global_knowledge',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'read_global_knowledge',
      wireName: 'read_global_knowledge',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'search_results',
      wireName: 'search_results',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'search_other_conversations',
      wireName: 'search_other_conversations',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'read_result',
      wireName: 'read_result',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'read_other_conversation_message',
      wireName: 'read_other_conversation_message',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'conversation.list',
      wireName: 'conversation_list',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'attachment.search',
      wireName: 'attachment_search',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'attachment.read',
      wireName: 'attachment_read',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'app.settings.read',
      wireName: 'app_settings_read',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'widget.list',
      wireName: 'widget_list',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'widget.get',
      wireName: 'widget_get',
      access: AgentToolAccess.read,
      parallelSafe: true,
    ),
    AgentToolSpec(
      operationName: 'content.create',
      wireName: 'content_create',
      access: AgentToolAccess.write,
      parallelSafe: false,
    ),
    AgentToolSpec(
      operationName: 'table.body.update',
      wireName: 'table_body_update',
      access: AgentToolAccess.write,
      parallelSafe: false,
    ),
    AgentToolSpec(
      operationName: 'content.update',
      wireName: 'content_update',
      access: AgentToolAccess.write,
      parallelSafe: false,
    ),
    AgentToolSpec(
      operationName: 'content.move',
      wireName: 'content_move',
      access: AgentToolAccess.write,
      parallelSafe: false,
    ),
    AgentToolSpec(
      operationName: 'content.delete',
      wireName: 'content_delete',
      access: AgentToolAccess.write,
      parallelSafe: false,
    ),
    AgentToolSpec(
      operationName: 'schedule.change',
      wireName: 'schedule_change',
      access: AgentToolAccess.write,
      parallelSafe: false,
    ),
    AgentToolSpec(
      operationName: 'table.propose',
      wireName: 'table_propose',
      access: AgentToolAccess.write,
      parallelSafe: false,
    ),
    AgentToolSpec(
      operationName: 'recovery.restore',
      wireName: 'recovery_restore',
      access: AgentToolAccess.write,
      parallelSafe: false,
    ),
    AgentToolSpec(
      operationName: 'propose_global_knowledge_change',
      wireName: 'propose_global_knowledge_change',
      access: AgentToolAccess.write,
      parallelSafe: false,
    ),
    AgentToolSpec(
      operationName: 'create_result',
      wireName: 'create_result',
      access: AgentToolAccess.write,
      parallelSafe: false,
    ),
    AgentToolSpec(
      operationName: 'update_result',
      wireName: 'update_result',
      access: AgentToolAccess.write,
      parallelSafe: false,
    ),
    AgentToolSpec(
      operationName: 'delete_result',
      wireName: 'delete_result',
      access: AgentToolAccess.write,
      parallelSafe: false,
    ),
    AgentToolSpec(
      operationName: 'conversation.manage',
      wireName: 'conversation_manage',
      access: AgentToolAccess.write,
      parallelSafe: false,
    ),
    AgentToolSpec(
      operationName: 'attachment.manage',
      wireName: 'attachment_manage',
      access: AgentToolAccess.write,
      parallelSafe: false,
    ),
    AgentToolSpec(
      operationName: 'app.settings.update',
      wireName: 'app_settings_update',
      access: AgentToolAccess.write,
      parallelSafe: false,
    ),
    AgentToolSpec(
      operationName: 'widget.manage',
      wireName: 'widget_manage',
      access: AgentToolAccess.write,
      parallelSafe: false,
    ),
  ];

  static final Map<String, AgentToolSpec> _byWire = {
    for (final spec in specs) spec.wireName: spec,
  };
  static final Map<String, AgentToolSpec> _byOperation = {
    for (final spec in specs) spec.operationName: spec,
  };

  AgentToolSpec? byWireName(String wireName) => _byWire[wireName];

  AgentToolSpec? byOperationName(String operationName) =>
      _byOperation[operationName];

  String operationName(String wireName) =>
      byWireName(wireName)?.operationName ?? wireName;

  String wireName(String operationName) =>
      byOperationName(operationName)?.wireName ?? operationName;

  bool isRead(String operationName) =>
      byOperationName(operationName)?.access == AgentToolAccess.read;

  bool isWrite(String operationName) =>
      byOperationName(operationName)?.access == AgentToolAccess.write;

  bool isParallelSafe(String operationName) =>
      byOperationName(operationName)?.parallelSafe == true;
}
