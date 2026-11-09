import 'dart:typed_data';

import 'models.dart';

enum ChatRole {
  user('user'),
  assistant('assistant');

  const ChatRole(this.wireName);

  final String wireName;

  static ChatRole parse(String value) {
    return ChatRole.values.firstWhere(
      (role) => role.wireName == value,
      orElse: () => ChatRole.assistant,
    );
  }
}

enum ChatMessageStatus {
  complete('complete'),
  streaming('streaming'),
  interrupted('interrupted'),
  failed('failed');

  const ChatMessageStatus(this.wireName);

  final String wireName;

  static ChatMessageStatus parse(String value) {
    return ChatMessageStatus.values.firstWhere(
      (status) => status.wireName == value,
      orElse: () => ChatMessageStatus.complete,
    );
  }
}

enum AutoRecordStatus {
  created('created'),
  review('review'),
  skipped('skipped'),
  undone('undone'),
  undoFailed('undo_failed'),
  expired('expired');

  const AutoRecordStatus(this.wireName);

  final String wireName;

  static AutoRecordStatus parse(String value) {
    return AutoRecordStatus.values.firstWhere(
      (status) => status.wireName == value,
      orElse: () => AutoRecordStatus.skipped,
    );
  }
}

enum AutoRecordOperation { create, update, delete }

enum TableChatActionStatus {
  applied,
  pendingConfirmation,
  pendingRetry,
  rejected,
  stale,
  failed,
  undone,
  expired,
}

class TableChatAction {
  const TableChatAction({
    required this.id,
    required this.operation,
    required this.title,
    required this.status,
    required this.createdAt,
    this.tableId,
    this.tableTitle,
    this.entryId,
    this.relatedEntryId,
    this.entryType,
    this.message,
    this.undoUntil,
    this.recoveryBatchId,
    this.expectedRevision,
    this.proposal = const {},
    this.requestFingerprint,
    this.intakeCoverageChecked,
    this.intakeCoverageTotal,
    this.intakeCoverageComplete,
    this.retryableIntake = false,
    this.intakeRetryAttempt = 0,
    this.intakeRetryOperationId,
    this.intakeRetryPending = false,
    this.reviewRequired = false,
    this.reviewReason,
  });

  final String id;
  final String operation;
  final String title;
  final TableChatActionStatus status;
  final DateTime createdAt;
  final String? tableId;
  final String? tableTitle;
  final String? entryId;
  final String? relatedEntryId;
  final String? entryType;
  final String? message;
  final DateTime? undoUntil;
  final String? recoveryBatchId;
  final int? expectedRevision;
  final Map<String, Object?> proposal;
  final String? requestFingerprint;
  final int? intakeCoverageChecked;
  final int? intakeCoverageTotal;
  final bool? intakeCoverageComplete;
  final bool retryableIntake;
  final int intakeRetryAttempt;
  final String? intakeRetryOperationId;
  final bool intakeRetryPending;
  final bool reviewRequired;
  final String? reviewReason;

  bool get canUndo =>
      status == TableChatActionStatus.applied &&
      undoUntil != null &&
      undoUntil!.isAfter(DateTime.now()) &&
      (recoveryBatchId != null ||
          (operation == 'content.create' && entryId != null));

  TableChatAction copyWith({
    TableChatActionStatus? status,
    String? message,
    String? recoveryBatchId,
    DateTime? undoUntil,
    Map<String, Object?>? proposal,
    int? expectedRevision,
    String? requestFingerprint,
    int? intakeCoverageChecked,
    int? intakeCoverageTotal,
    bool? intakeCoverageComplete,
    bool? retryableIntake,
    int? intakeRetryAttempt,
    String? intakeRetryOperationId,
    bool clearIntakeRetryOperationId = false,
    bool? intakeRetryPending,
    bool? reviewRequired,
    String? reviewReason,
  }) => TableChatAction(
    id: id,
    operation: operation,
    title: title,
    status: status ?? this.status,
    createdAt: createdAt,
    tableId: tableId,
    tableTitle: tableTitle,
    entryId: entryId,
    relatedEntryId: relatedEntryId,
    entryType: entryType,
    message: message ?? this.message,
    undoUntil: undoUntil ?? this.undoUntil,
    recoveryBatchId: recoveryBatchId ?? this.recoveryBatchId,
    expectedRevision: expectedRevision ?? this.expectedRevision,
    proposal: proposal ?? this.proposal,
    requestFingerprint: requestFingerprint ?? this.requestFingerprint,
    intakeCoverageChecked: intakeCoverageChecked ?? this.intakeCoverageChecked,
    intakeCoverageTotal: intakeCoverageTotal ?? this.intakeCoverageTotal,
    intakeCoverageComplete:
        intakeCoverageComplete ?? this.intakeCoverageComplete,
    retryableIntake: retryableIntake ?? this.retryableIntake,
    intakeRetryAttempt: intakeRetryAttempt ?? this.intakeRetryAttempt,
    intakeRetryOperationId: clearIntakeRetryOperationId
        ? null
        : intakeRetryOperationId ?? this.intakeRetryOperationId,
    intakeRetryPending: intakeRetryPending ?? this.intakeRetryPending,
    reviewRequired: reviewRequired ?? this.reviewRequired,
    reviewReason: reviewReason ?? this.reviewReason,
  );

  Map<String, dynamic> toJson() => {
    'kind': 'table',
    'id': id,
    'operation': operation,
    'title': title,
    'status': status.name,
    'created_at': createdAt.toIso8601String(),
    'table_id': tableId,
    'table_title': tableTitle,
    'entry_id': entryId,
    'related_entry_id': relatedEntryId,
    'entry_type': entryType,
    'message': message,
    'undo_until': undoUntil?.toIso8601String(),
    'recovery_batch_id': recoveryBatchId,
    'expected_revision': expectedRevision,
    'proposal': proposal,
    'request_fingerprint': requestFingerprint,
    'intake_coverage_checked': intakeCoverageChecked,
    'intake_coverage_total': intakeCoverageTotal,
    'intake_coverage_complete': intakeCoverageComplete,
    'retryable_intake': retryableIntake,
    'intake_retry_attempt': intakeRetryAttempt,
    'intake_retry_operation_id': intakeRetryOperationId,
    'intake_retry_pending': intakeRetryPending,
    'review_required': reviewRequired,
    'review_reason': reviewReason,
  };

  static TableChatAction fromJson(Map<String, dynamic> json) {
    final rawProposal = json['proposal'];
    return TableChatAction(
      id: json['id'].toString(),
      operation: json['operation']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      status: TableChatActionStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => TableChatActionStatus.failed,
      ),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      tableId: json['table_id']?.toString(),
      tableTitle: json['table_title']?.toString(),
      entryId: json['entry_id']?.toString(),
      relatedEntryId: json['related_entry_id']?.toString(),
      entryType: json['entry_type']?.toString(),
      message: json['message']?.toString(),
      undoUntil: DateTime.tryParse(json['undo_until']?.toString() ?? ''),
      recoveryBatchId: json['recovery_batch_id']?.toString(),
      expectedRevision: (json['expected_revision'] as num?)?.toInt(),
      proposal: rawProposal is Map
          ? Map<String, Object?>.from(rawProposal)
          : const {},
      requestFingerprint: json['request_fingerprint'] as String?,
      intakeCoverageChecked: json['intake_coverage_checked'] is int
          ? json['intake_coverage_checked'] as int
          : null,
      intakeCoverageTotal: json['intake_coverage_total'] is int
          ? json['intake_coverage_total'] as int
          : null,
      intakeCoverageComplete: json['intake_coverage_complete'] is bool
          ? json['intake_coverage_complete'] as bool
          : null,
      retryableIntake: json['retryable_intake'] == true,
      intakeRetryAttempt: json['intake_retry_attempt'] is int
          ? json['intake_retry_attempt'] as int
          : 0,
      intakeRetryOperationId: json['intake_retry_operation_id']?.toString(),
      intakeRetryPending: json['intake_retry_pending'] == true,
      reviewRequired: json['review_required'] == true,
      reviewReason: json['review_reason']?.toString(),
    );
  }
}

enum GenerationStatus {
  requesting('requesting'),
  responseReady('response_ready'),
  completed('completed'),
  interrupted('interrupted'),
  failed('failed');

  const GenerationStatus(this.wireName);

  final String wireName;

  static GenerationStatus parse(String value) {
    return GenerationStatus.values.firstWhere(
      (status) => status.wireName == value,
      orElse: () => GenerationStatus.failed,
    );
  }
}

/// Durable state for one model request. Completed response/tool data is kept
/// locally so result creation can be replayed after an application restart.
class GenerationRun {
  const GenerationRun({
    required this.assistantMessageId,
    required this.conversationId,
    required this.userMessageId,
    required this.status,
    required this.responseText,
    required this.toolCalls,
    required this.createdAt,
    required this.updatedAt,
    this.error,
  });

  final String assistantMessageId;
  final String conversationId;
  final String userMessageId;
  final GenerationStatus status;
  final String responseText;
  final List<Map<String, String>> toolCalls;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? error;

  GenerationRun copyWith({
    GenerationStatus? status,
    String? responseText,
    List<Map<String, String>>? toolCalls,
    DateTime? updatedAt,
    Object? error = _unset,
  }) {
    return GenerationRun(
      assistantMessageId: assistantMessageId,
      conversationId: conversationId,
      userMessageId: userMessageId,
      status: status ?? this.status,
      responseText: responseText ?? this.responseText,
      toolCalls: toolCalls ?? this.toolCalls,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.autoTitle,
    this.preview = '',
    AiPermissions aiPermissions = const AiPermissions(),
    this.aiPolicy,
  }) : _legacyPermissions = aiPermissions;

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool autoTitle;
  final String preview;
  final AiPermissions _legacyPermissions;

  /// New conversations persist an action-level policy. Conversations from
  /// older versions keep their three-boolean snapshot until migrated.
  final AiPolicy? aiPolicy;

  /// Compatibility projection consumed by code that has not migrated to
  /// [AiPolicy] yet.
  AiPermissions get aiPermissions =>
      aiPolicy?.legacyCompatibilityPermissions ?? _legacyPermissions;

  /// Existing sessions derive a custom policy without widening permission.
  AiPolicy get effectiveAiPolicy =>
      aiPolicy ?? AiPolicy.fromLegacyPermissions(aiPermissions);

  Conversation copyWith({
    String? title,
    DateTime? updatedAt,
    bool? autoTitle,
    String? preview,
    AiPermissions? aiPermissions,
    Object? aiPolicy = _unset,
  }) {
    final nextAiPolicy = identical(aiPolicy, _unset)
        ? (aiPermissions == null ? this.aiPolicy : null)
        : aiPolicy as AiPolicy?;
    return Conversation(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      autoTitle: autoTitle ?? this.autoTitle,
      preview: preview ?? this.preview,
      aiPermissions: aiPermissions ?? this.aiPermissions,
      aiPolicy: nextAiPolicy,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'auto_title': autoTitle,
    'preview': preview,
    'ai_permissions': aiPermissions.toJson(),
    'ai_policy': aiPolicy?.toJson(),
  };

  static Conversation fromJson(Map<String, dynamic> json) {
    final rawPermissions = json['ai_permissions'];
    final rawPolicy = json['ai_policy'];
    return Conversation(
      id: json['id'].toString(),
      title: json['title']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
      autoTitle: json['auto_title'] == true,
      preview: json['preview']?.toString() ?? '',
      aiPermissions: rawPermissions is Map
          ? AiPermissions.fromJson(Map<String, dynamic>.from(rawPermissions))
          : const AiPermissions(),
      aiPolicy: rawPolicy is Map
          ? AiPolicy.fromJson(Map<String, dynamic>.from(rawPolicy))
          : null,
    );
  }
}

/// Projects an action-level policy into the legacy three-boolean API.
///
/// Each coarse flag stays enabled only when every action covered by that flag
/// remains available. This keeps old consumers from treating one narrow grant
/// as access to a whole capability group.
extension AiPolicyLegacyCompatibility on AiPolicy {
  AiPermissions get legacyCompatibilityPermissions => AiPermissions(
    read: _legacyGroupEnabled(const {
      AiPermissionAction.tableRead,
      AiPermissionAction.contentRead,
      AiPermissionAction.globalKnowledgeRead,
      AiPermissionAction.globalKnowledgeSearch,
      AiPermissionAction.conversationHistorySearch,
      AiPermissionAction.conversationHistoryRead,
    }),
    create: _legacyGroupEnabled(const {
      AiPermissionAction.contentCreate,
      AiPermissionAction.tableCreate,
      AiPermissionAction.globalKnowledgeCreate,
    }),
    modifyDelete: _legacyGroupEnabled(const {
      AiPermissionAction.contentUpdate,
      AiPermissionAction.contentDelete,
      AiPermissionAction.contentMove,
      AiPermissionAction.tableBodyUpdate,
      AiPermissionAction.tableUpdate,
      AiPermissionAction.tableDelete,
      AiPermissionAction.fieldAdjust,
      AiPermissionAction.inboxTargetAdjust,
      AiPermissionAction.restore,
      AiPermissionAction.globalKnowledgeUpdate,
      AiPermissionAction.globalKnowledgeDelete,
    }),
  );

  bool _legacyGroupEnabled(Set<AiPermissionAction> actions) =>
      actions.every((action) => decisionFor(action) != AiPolicyDecision.deny);
}

class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.storageKey,
    required this.fileName,
    required this.mimeType,
    required this.createdAt,
    this.width,
    this.height,
  });

  final String id;
  final String storageKey;
  final String fileName;
  final String mimeType;
  final DateTime createdAt;
  final int? width;
  final int? height;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'storage_key': storageKey,
      'file_name': fileName,
      'mime_type': mimeType,
      'created_at': createdAt.toIso8601String(),
      'width': width,
      'height': height,
    };
  }

  static ChatAttachment fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      id: json['id'].toString(),
      storageKey: json['storage_key'].toString(),
      fileName: json['file_name']?.toString() ?? 'image',
      mimeType: json['mime_type']?.toString() ?? 'image/jpeg',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
    );
  }
}

class AutoRecordAction {
  const AutoRecordAction({
    required this.id,
    required this.type,
    required this.title,
    required this.status,
    required this.createdAt,
    this.resultId,
    this.captureId,
    this.reason,
    this.undoUntil,
    this.operation = AutoRecordOperation.create,
  });

  final String id;
  final ResultType type;
  final String title;
  final AutoRecordStatus status;
  final DateTime createdAt;
  final String? resultId;
  final String? captureId;
  final String? reason;
  final DateTime? undoUntil;
  final AutoRecordOperation operation;

  bool get canUndo =>
      status == AutoRecordStatus.created &&
      resultId != null &&
      undoUntil != null &&
      undoUntil!.isAfter(DateTime.now());

  AutoRecordAction copyWith({
    AutoRecordStatus? status,
    String? reason,
    AutoRecordOperation? operation,
  }) {
    return AutoRecordAction(
      id: id,
      type: type,
      title: title,
      status: status ?? this.status,
      createdAt: createdAt,
      resultId: resultId,
      captureId: captureId,
      reason: reason ?? this.reason,
      undoUntil: undoUntil,
      operation: operation ?? this.operation,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'kind': 'auto',
      'id': id,
      'type': type.wireName,
      'title': title,
      'status': status.wireName,
      'created_at': createdAt.toIso8601String(),
      'result_id': resultId,
      'capture_id': captureId,
      'reason': reason,
      'undo_until': undoUntil?.toIso8601String(),
      'operation': operation.name,
    };
  }

  static AutoRecordAction fromJson(Map<String, dynamic> json) {
    return AutoRecordAction(
      id: json['id'].toString(),
      type: ResultType.parse(json['type'].toString()),
      title: json['title']?.toString() ?? '',
      status: AutoRecordStatus.parse(json['status'].toString()),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      resultId: json['result_id']?.toString(),
      captureId: json['capture_id']?.toString(),
      reason: json['reason']?.toString(),
      undoUntil: DateTime.tryParse(json['undo_until']?.toString() ?? ''),
      operation: AutoRecordOperation.values.firstWhere(
        (value) => value.name == json['operation'],
        orElse: () => AutoRecordOperation.create,
      ),
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.attachments = const [],
    this.actions = const [],
    this.tableActions = const [],
    this.error,
    this.reasoningContent = '',
    this.toolTranscript = const [],
  });

  final String id;
  final String conversationId;
  final ChatRole role;
  final String content;
  final ChatMessageStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatAttachment> attachments;
  final List<AutoRecordAction> actions;
  final List<TableChatAction> tableActions;
  final String? error;
  final String reasoningContent;
  final List<Map<String, dynamic>> toolTranscript;

  bool get isUser => role == ChatRole.user;

  ChatMessage copyWith({
    String? content,
    ChatMessageStatus? status,
    DateTime? updatedAt,
    List<ChatAttachment>? attachments,
    List<AutoRecordAction>? actions,
    List<TableChatAction>? tableActions,
    Object? error = _unset,
    String? reasoningContent,
    List<Map<String, dynamic>>? toolTranscript,
  }) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      role: role,
      content: content ?? this.content,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      attachments: attachments ?? this.attachments,
      actions: actions ?? this.actions,
      tableActions: tableActions ?? this.tableActions,
      error: identical(error, _unset) ? this.error : error as String?,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      toolTranscript: toolTranscript ?? this.toolTranscript,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'conversation_id': conversationId,
    'role': role.wireName,
    'content': content,
    'status': status.wireName,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'attachments': attachments.map((item) => item.toJson()).toList(),
    'actions': actions.map((item) => item.toJson()).toList(),
    'table_actions': tableActions.map((item) => item.toJson()).toList(),
    'error': error,
    'reasoning_content': reasoningContent,
    'tool_transcript': toolTranscript,
  };

  static ChatMessage fromJson(Map<String, dynamic> json) {
    final attachments = json['attachments'];
    final actions = json['actions'];
    final tableActions = json['table_actions'];
    final transcript = json['tool_transcript'];
    return ChatMessage(
      id: json['id'].toString(),
      conversationId: json['conversation_id'].toString(),
      role: ChatRole.parse(json['role']?.toString() ?? ''),
      content: json['content']?.toString() ?? '',
      status: ChatMessageStatus.parse(json['status']?.toString() ?? ''),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
      attachments: attachments is List
          ? attachments
                .whereType<Map>()
                .map(
                  (item) =>
                      ChatAttachment.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList(growable: false)
          : const [],
      actions: actions is List
          ? actions
                .whereType<Map>()
                .where((item) => item['kind'] != 'table')
                .map(
                  (item) => AutoRecordAction.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
      tableActions: tableActions is List
          ? tableActions
                .whereType<Map>()
                .map(
                  (item) =>
                      TableChatAction.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList(growable: false)
          : const [],
      error: json['error']?.toString(),
      reasoningContent: json['reasoning_content']?.toString() ?? '',
      toolTranscript: transcript is List
          ? transcript
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false)
          : const [],
    );
  }
}

class ChatAttachmentInput {
  const ChatAttachmentInput({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

class LocalTrashEntry {
  const LocalTrashEntry({
    required this.id,
    required this.kind,
    required this.expiresAt,
    required this.payload,
  });

  final String id;
  final String kind;
  final DateTime expiresAt;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'expires_at': expiresAt.toIso8601String(),
    'payload': payload,
  };

  static LocalTrashEntry fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    if (rawPayload is! Map) {
      throw const FormatException('回收站条目 payload 格式错误');
    }
    return LocalTrashEntry(
      id: json['id'].toString(),
      kind: json['kind']?.toString() ?? '',
      expiresAt:
          DateTime.tryParse(json['expires_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      payload: Map<String, dynamic>.from(rawPayload),
    );
  }
}

const Object _unset = Object();
