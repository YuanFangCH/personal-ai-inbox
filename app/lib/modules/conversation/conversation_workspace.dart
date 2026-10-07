import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/chat_models.dart';
import '../../data/chat_repository.dart';
import '../../data/share_payload.dart';
import '../../services/chat_service.dart';
import '../../services/image_input_service.dart';
import '../../services/model_client.dart';
import '../results/result_library.dart';
import 'auto_record_processor.dart';

/// Application module that owns the local AI conversation lifecycle.
///
/// The rest of the app sees immutable conversation/message snapshots and
/// commands. Persistence, model streaming, attachment storage and guarded
/// automatic recording remain implementation details behind this seam.
class ConversationWorkspace extends ChangeNotifier {
  ConversationWorkspace({
    required ChatRepository repository,
    required ResultLibrary results,
    required ChatService chatService,
    required AutoRecordProcessor autoRecordProcessor,
    ImageInputService? imageInputService,
  }) : _repository = repository,
       _results = results,
       _chatService = chatService,
       _autoRecordProcessor = autoRecordProcessor,
       _imageInputService = imageInputService ?? ImageInputService();

  final ChatRepository _repository;
  final ResultLibrary _results;
  final ChatService _chatService;
  final AutoRecordProcessor _autoRecordProcessor;
  final ImageInputService _imageInputService;

  List<Conversation> _conversations = const [];
  final Map<String, List<ChatMessage>> _messagesByConversation = {};
  String? _activeConversationId;
  String? _pendingOpenConversationId;
  StreamSubscription<ChatStreamDelta>? _chatSubscription;
  Completer<void>? _chatStreamDone;
  bool _cancelChatRequested = false;
  bool _isChatGenerating = false;

  List<Conversation> get conversations => List.unmodifiable(_conversations);

  String? get activeConversationId => _activeConversationId;

  bool get isChatGenerating => _isChatGenerating;

  List<ChatMessage> messagesFor(String conversationId) {
    return List.unmodifiable(
      _messagesByConversation[conversationId] ?? const [],
    );
  }

  Conversation? findConversation(String id) {
    for (final conversation in _conversations) {
      if (conversation.id == id) {
        return conversation;
      }
    }
    return null;
  }

  Future<void> initialize() async {
    await _repository.initialize();
    await _repository.deleteEmptyConversations();
    await refresh();
  }

  Future<void> refresh() async {
    _conversations = await _repository.listConversations();
    if (_activeConversationId != null &&
        findConversation(_activeConversationId!) == null) {
      _activeConversationId = null;
    }
    notifyListeners();
  }

  Future<Conversation> createConversation() async {
    final conversation = await _repository.createConversation();
    _conversations = [
      conversation,
      ..._conversations.where((item) => item.id != conversation.id),
    ];
    _messagesByConversation[conversation.id] = [];
    _activeConversationId = conversation.id;
    notifyListeners();
    return conversation;
  }

  String? consumePendingConversationId() {
    final value = _pendingOpenConversationId;
    _pendingOpenConversationId = null;
    return value;
  }

  Future<void> openConversation(String id) async {
    _activeConversationId = id;
    _messagesByConversation[id] = await _repository.listMessages(id);
    notifyListeners();
  }

  Future<void> renameConversation(String id, String title) async {
    final conversation = await _repository.findConversation(id);
    final normalized = title.trim();
    if (conversation == null || normalized.isEmpty) {
      return;
    }
    final updated = conversation.copyWith(
      title: normalized,
      autoTitle: false,
      updatedAt: DateTime.now(),
    );
    await _repository.saveConversation(updated);
    await refresh();
  }

  Future<void> deleteConversation(String id) async {
    await cancelGeneration();
    await _repository.deleteConversation(id);
    _messagesByConversation.remove(id);
    if (_activeConversationId == id) {
      _activeConversationId = null;
    }
    await refresh();
  }

  Future<void> handleSharedPayload(SharedCapturePayload payload) async {
    if (payload.isEmpty) {
      return;
    }
    final rawImages = await payload.readImages();
    final images = await _imageInputService.fromBytes(rawImages);
    final conversation = await createConversation();
    _pendingOpenConversationId = conversation.id;
    unawaited(
      sendChatMessage(conversation.id, text: payload.text, attachments: images),
    );
    notifyListeners();
  }

  Future<void> sendChatMessage(
    String conversationId, {
    String text = '',
    List<ChatAttachmentInput> attachments = const [],
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty && attachments.isEmpty) {
      return;
    }
    if (_isChatGenerating) {
      await cancelGeneration();
    }

    final conversation = await _repository.findConversation(conversationId);
    if (conversation == null) {
      throw StateError('会话不存在或已删除');
    }

    final history = await _repository.listMessages(conversationId);
    final userMessageId = _repository.newMessageId();
    final savedAttachments = await _repository.saveAttachments(
      conversationId: conversationId,
      messageId: userMessageId,
      inputs: attachments,
    );
    final now = DateTime.now();
    final userMessage = ChatMessage(
      id: userMessageId,
      conversationId: conversationId,
      role: ChatRole.user,
      content: normalized,
      status: ChatMessageStatus.complete,
      createdAt: now,
      updatedAt: now,
      attachments: savedAttachments,
    );
    await _repository.saveMessage(userMessage);
    _replaceMessage(userMessage);

    final isFirstUserMessage = !history.any(
      (message) => message.role == ChatRole.user,
    );
    final updatedConversation = conversation.copyWith(
      title: isFirstUserMessage && conversation.autoTitle
          ? _conversationTitle(normalized, attachments)
          : conversation.title,
      autoTitle: isFirstUserMessage && conversation.autoTitle
          ? false
          : conversation.autoTitle,
      preview: _messagePreview(normalized, attachments.isNotEmpty),
      updatedAt: now,
    );
    await _repository.saveConversation(updatedConversation);
    _replaceConversation(updatedConversation);

    final assistantMessageId = _repository.newMessageId();
    var assistant = ChatMessage(
      id: assistantMessageId,
      conversationId: conversationId,
      role: ChatRole.assistant,
      content: '',
      status: ChatMessageStatus.streaming,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.saveMessage(assistant);
    _replaceMessage(assistant);

    _isChatGenerating = true;
    _cancelChatRequested = false;
    _activeConversationId = conversationId;
    notifyListeners();

    final toolCalls = <int, ToolCallAccumulator>{};
    var lastPersistAt = DateTime.now();
    try {
      final stream = await _chatService.streamReply(
        conversationId: conversationId,
      );
      final done = Completer<void>();
      _chatStreamDone = done;
      _chatSubscription = stream.listen(
        (delta) {
          if (_cancelChatRequested) {
            return;
          }
          if (delta.content.isNotEmpty) {
            assistant = assistant.copyWith(
              content: '${assistant.content}${delta.content}',
              updatedAt: DateTime.now(),
            );
            _replaceMessage(assistant);
          }
          if (delta.toolCallIndex != null) {
            final index = delta.toolCallIndex!;
            final current = toolCalls.putIfAbsent(
              index,
              ToolCallAccumulator.new,
            );
            current
              ..id = delta.toolCallId ?? current.id
              ..name = delta.toolCallName ?? current.name
              ..arguments.write(delta.toolArguments);
          }
          final currentTime = DateTime.now();
          if (currentTime.difference(lastPersistAt) >
              const Duration(milliseconds: 140)) {
            lastPersistAt = currentTime;
            unawaited(_repository.saveMessage(assistant));
          }
          notifyListeners();
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!done.isCompleted) {
            done.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!done.isCompleted) {
            done.complete();
          }
        },
        cancelOnError: false,
      );
      await done.future;

      if (_cancelChatRequested) {
        assistant = assistant.copyWith(
          content: assistant.content.trim().isEmpty
              ? '已停止生成'
              : assistant.content,
          status: ChatMessageStatus.interrupted,
          updatedAt: DateTime.now(),
        );
      } else {
        final actions = await _autoRecordProcessor.processToolCalls(
          assistantMessageId,
          toolCalls.values.toList(growable: false),
        );
        assistant = assistant.copyWith(
          status: ChatMessageStatus.complete,
          actions: actions,
          updatedAt: DateTime.now(),
          error: null,
        );
      }
    } catch (error) {
      assistant = assistant.copyWith(
        status: ChatMessageStatus.failed,
        error: error is StateError ? error.message : error.toString(),
        updatedAt: DateTime.now(),
      );
    } finally {
      await _repository.saveMessage(assistant);
      _replaceMessage(assistant);
      final latestConversation =
          await _repository.findConversation(conversationId) ??
          updatedConversation;
      final withPreview = latestConversation.copyWith(
        preview: _messagePreview(assistant.content, false),
        updatedAt: DateTime.now(),
      );
      await _repository.saveConversation(withPreview);
      _replaceConversation(withPreview);
      _chatSubscription = null;
      _chatStreamDone = null;
      _isChatGenerating = false;
      notifyListeners();
    }
  }

  Future<void> cancelGeneration() async {
    if (!_isChatGenerating) {
      return;
    }
    _cancelChatRequested = true;
    await _chatSubscription?.cancel();
    if (_chatStreamDone?.isCompleted == false) {
      _chatStreamDone!.complete();
    }
    notifyListeners();
  }

  Future<void> retryAssistantMessage(String messageId) async {
    final message = await _repository.findMessage(messageId);
    if (message == null ||
        message.role != ChatRole.assistant ||
        message.status != ChatMessageStatus.failed) {
      return;
    }
    final messages = await _repository.listMessages(message.conversationId);
    ChatMessage? previousUser;
    for (final candidate in messages) {
      if (candidate.createdAt.isAfter(message.createdAt)) {
        break;
      }
      if (candidate.role == ChatRole.user) {
        previousUser = candidate;
      }
    }
    if (previousUser == null) {
      return;
    }
    final inputs = <ChatAttachmentInput>[];
    for (final attachment in previousUser.attachments) {
      final bytes = await _repository.readAttachment(attachment);
      if (bytes != null) {
        inputs.add(
          ChatAttachmentInput(
            bytes: bytes,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
          ),
        );
      }
    }
    await _repository.deleteMessage(messageId);
    await _repository.deleteMessage(previousUser.id);
    _messagesByConversation[message.conversationId] = messages
        .where(
          (candidate) =>
              candidate.id != messageId && candidate.id != previousUser!.id,
        )
        .toList(growable: false);
    await sendChatMessage(
      message.conversationId,
      text: previousUser.content,
      attachments: inputs,
    );
  }

  Future<Uint8List?> readAttachment(ChatAttachment attachment) {
    return _repository.readAttachment(attachment);
  }

  Future<void> undoAutoRecord(String actionId) async {
    final action = await _repository.findAutoRecordAction(actionId);
    if (action == null || !action.canUndo || action.resultId == null) {
      return;
    }
    final result = _results.findDocument(action.resultId!);
    if (result == null || result.revision != 1) {
      await _updateAutoRecordAction(
        actionId,
        action.copyWith(reason: '成果已被修改，不能撤销'),
      );
      return;
    }
    await _results.deleteDocument(result.id);
    await _updateAutoRecordAction(
      actionId,
      action.copyWith(status: AutoRecordStatus.undone),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_chatSubscription?.cancel());
    _chatService.close();
    super.dispose();
  }

  void _replaceMessage(ChatMessage message) {
    final values = List<ChatMessage>.from(
      _messagesByConversation[message.conversationId] ?? const [],
    );
    final index = values.indexWhere((item) => item.id == message.id);
    if (index < 0) {
      values.add(message);
    } else {
      values[index] = message;
    }
    values.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _messagesByConversation[message.conversationId] = values;
  }

  void _replaceConversation(Conversation conversation) {
    _conversations = [
      conversation,
      ..._conversations.where((item) => item.id != conversation.id),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> _updateAutoRecordAction(
    String actionId,
    AutoRecordAction updated,
  ) async {
    final message = await _findMessageByAction(actionId);
    if (message == null) {
      return;
    }
    final updatedMessage = message.copyWith(
      actions: message.actions
          .map((action) => action.id == actionId ? updated : action)
          .toList(growable: false),
      updatedAt: DateTime.now(),
    );
    await _repository.saveMessage(updatedMessage);
    _replaceMessage(updatedMessage);
    notifyListeners();
  }

  Future<ChatMessage?> _findMessageByAction(String actionId) async {
    for (final messages in _messagesByConversation.values) {
      for (final message in messages) {
        if (message.actions.any((action) => action.id == actionId)) {
          return message;
        }
      }
    }
    for (final conversation in await _repository.listConversations()) {
      for (final message in await _repository.listMessages(conversation.id)) {
        if (message.actions.any((action) => action.id == actionId)) {
          return message;
        }
      }
    }
    return null;
  }

  String _conversationTitle(
    String text,
    List<ChatAttachmentInput> attachments,
  ) {
    final firstLine = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (firstLine.isNotEmpty) {
      final runes = firstLine.runes.take(28).toList(growable: false);
      return String.fromCharCodes(runes);
    }
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '图片记录 · $month-$day $hour:$minute';
  }

  String _messagePreview(String content, bool hasImage) {
    final normalized = content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isNotEmpty) {
      return normalized.length <= 80
          ? normalized
          : '${normalized.substring(0, 80)}...';
    }
    return hasImage ? '[图片]' : '';
  }
}
