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

  bool get canUndo =>
      status == TableChatActionStatus.applied &&
      recoveryBatchId != null &&
      undoUntil != null &&
      undoUntil!.isAfter(DateTime.now());

  TableChatAction copyWith({
    TableChatActionStatus? status,
    String? message,
    String? recoveryBatchId,
    DateTime? undoUntil,
    Map<String, Object?>? proposal,
    int? expectedRevision,
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
    this.aiPermissions = const AiPermissions(),
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool autoTitle;
  final String preview;
  final AiPermissions aiPermissions;

  Conversation copyWith({
    String? title,
    DateTime? updatedAt,
    bool? autoTitle,
    String? preview,
    AiPermissions? aiPermissions,
  }) {
    return Conversation(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      autoTitle: autoTitle ?? this.autoTitle,
      preview: preview ?? this.preview,
      aiPermissions: aiPermissions ?? this.aiPermissions,
    );
  }
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

const Object _unset = Object();
