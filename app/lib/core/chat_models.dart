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
  undone('undone');

  const AutoRecordStatus(this.wireName);

  final String wireName;

  static AutoRecordStatus parse(String value) {
    return AutoRecordStatus.values.firstWhere(
      (status) => status.wireName == value,
      orElse: () => AutoRecordStatus.skipped,
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
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool autoTitle;
  final String preview;

  Conversation copyWith({
    String? title,
    DateTime? updatedAt,
    bool? autoTitle,
    String? preview,
  }) {
    return Conversation(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      autoTitle: autoTitle ?? this.autoTitle,
      preview: preview ?? this.preview,
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

  bool get canUndo =>
      status == AutoRecordStatus.created &&
      resultId != null &&
      undoUntil != null &&
      undoUntil!.isAfter(DateTime.now());

  AutoRecordAction copyWith({AutoRecordStatus? status, String? reason}) {
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.wireName,
      'title': title,
      'status': status.wireName,
      'created_at': createdAt.toIso8601String(),
      'result_id': resultId,
      'capture_id': captureId,
      'reason': reason,
      'undo_until': undoUntil?.toIso8601String(),
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
    this.error,
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
  final String? error;

  bool get isUser => role == ChatRole.user;

  ChatMessage copyWith({
    String? content,
    ChatMessageStatus? status,
    DateTime? updatedAt,
    List<ChatAttachment>? attachments,
    List<AutoRecordAction>? actions,
    Object? error = _unset,
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
      error: identical(error, _unset) ? this.error : error as String?,
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
