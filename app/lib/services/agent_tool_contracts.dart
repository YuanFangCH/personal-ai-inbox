import 'dart:convert';

enum ChatWriteToolOutcome {
  succeeded,
  failed,
  waitingConfirmation,
  conflict,
  rejected,
}

class ChatWriteToolCall {
  /// [turnId] must be the persisted assistant message ID when one exists.
  const ChatWriteToolCall({
    required this.turnId,
    required this.conversationId,
    required this.round,
    required this.index,
    required this.callId,
    required this.name,
    required this.wireName,
    required this.rawArguments,
    required this.arguments,
  });

  final String turnId;
  final String conversationId;
  final int round;
  final int index;
  final String callId;
  final String name;
  final String wireName;
  final String rawArguments;
  final Map<String, dynamic> arguments;
}

class ChatWriteToolReceipt {
  ChatWriteToolReceipt.succeeded({
    required String this.operationId,
    this.message = '操作已在本地完成并取得执行回执。',
    Map<String, Object?> data = const {},
  }) : outcome = ChatWriteToolOutcome.succeeded,
       code = null,
       retryable = false,
       data = Map.unmodifiable(Map.of(data)) {
    _validateOperationId();
  }

  ChatWriteToolReceipt.failed({
    required String this.code,
    required this.message,
    this.operationId,
    this.retryable = false,
    Map<String, Object?> data = const {},
  }) : outcome = ChatWriteToolOutcome.failed,
       data = Map.unmodifiable(Map.of(data));

  ChatWriteToolReceipt.waitingConfirmation({
    required String this.operationId,
    this.message = '操作意图已保存，仍在等待当前对话确认。',
    Map<String, Object?> data = const {},
  }) : outcome = ChatWriteToolOutcome.waitingConfirmation,
       code = null,
       retryable = false,
       data = Map.unmodifiable(Map.of(data)) {
    _validateOperationId();
  }

  ChatWriteToolReceipt.conflict({
    required String this.operationId,
    required this.message,
    Map<String, Object?> data = const {},
  }) : outcome = ChatWriteToolOutcome.conflict,
       code = 'conflict',
       retryable = false,
       data = Map.unmodifiable(Map.of(data)) {
    _validateOperationId();
  }

  ChatWriteToolReceipt.rejected({
    required String this.code,
    required this.message,
    this.operationId,
    Map<String, Object?> data = const {},
  }) : outcome = ChatWriteToolOutcome.rejected,
       retryable = false,
       data = Map.unmodifiable(Map.of(data));

  final ChatWriteToolOutcome outcome;
  final String? operationId;
  final String? code;
  final String message;
  final bool retryable;
  final Map<String, Object?> data;

  bool get succeeded => outcome == ChatWriteToolOutcome.succeeded;

  String get toolContent => jsonEncode({
    'status': outcome.name,
    'operation_id': operationId,
    if (code != null) 'code': code,
    'message': message,
    'retryable': retryable,
    'data': data,
  });

  void _validateOperationId() {
    if (operationId == null || operationId!.trim().isEmpty) {
      throw ArgumentError.value(operationId, 'operationId');
    }
  }
}

typedef ChatWriteToolExecutor = Future<ChatWriteToolReceipt> Function(
  ChatWriteToolCall call,
);
