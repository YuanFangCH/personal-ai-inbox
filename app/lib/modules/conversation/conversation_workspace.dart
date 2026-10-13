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
  Completer<void>? _chatGenerationFinished;
  final Map<String, Future<void>> _messageSaveQueues = {};
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
    await _recoverPendingGenerations();
    await _repository.deleteEmptyConversations();
    await refresh();
  }

  Future<void> _recoverPendingGenerations() async {
    for (final generation in await _repository.listRecoverableGenerations()) {
      final assistant = await _repository.findMessage(
        generation.assistantMessageId,
      );
      if (generation.status == GenerationStatus.requesting) {
        if (assistant != null &&
            assistant.status == ChatMessageStatus.streaming) {
          await _repository.saveMessage(
            assistant.copyWith(
              status: ChatMessageStatus.interrupted,
              error: '应用在模型响应完成前关闭；保留原消息，请手动重试。',
              updatedAt: DateTime.now(),
            ),
          );
        }
        await _repository.saveGeneration(
          generation.copyWith(
            status: GenerationStatus.interrupted,
            error: '应用在模型响应完成前关闭；未自动重发请求。',
            updatedAt: DateTime.now(),
          ),
        );
        continue;
      }

      final calls = _toolCallsFrom(generation.toolCalls);
      final actions = await _autoRecordProcessor.processToolCalls(
        generation.assistantMessageId,
        calls,
      );
      final completedMessage =
          (assistant ??
                  ChatMessage(
                    id: generation.assistantMessageId,
                    conversationId: generation.conversationId,
                    role: ChatRole.assistant,
                    content: generation.responseText,
                    status: ChatMessageStatus.streaming,
                    createdAt: generation.createdAt,
                    updatedAt: generation.updatedAt,
                  ))
              .copyWith(
                content: generation.responseText,
                status: ChatMessageStatus.complete,
                actions: actions,
                updatedAt: DateTime.now(),
                error: null,
              );
      await _repository.saveMessage(completedMessage);
      await _repository.saveGeneration(
        generation.copyWith(
          status: GenerationStatus.completed,
          updatedAt: DateTime.now(),
          error: null,
        ),
      );
    }

    // Cover a crash after the streaming message was saved but before the
    // generation row was inserted. It is never safe to resend automatically.
    for (final conversation in await _repository.listConversations()) {
      for (final message in await _repository.listMessages(conversation.id)) {
        if (message.role == ChatRole.assistant &&
            message.status == ChatMessageStatus.streaming &&
            await _repository.findGeneration(message.id) == null) {
          await _repository.saveMessage(
            message.copyWith(
              status: ChatMessageStatus.interrupted,
              error: '应用在模型响应完成前关闭；保留原消息，请手动重试。',
              updatedAt: DateTime.now(),
            ),
          );
        }
      }
    }
  }

  List<ToolCallAccumulator> _toolCallsFrom(List<Map<String, String>> values) {
    return [
      for (final value in values)
        ToolCallAccumulator()
          ..index = int.tryParse(value['index'] ?? '')
          ..id = value['id']
          ..name = value['name']
          ..arguments.write(value['arguments'] ?? ''),
    ];
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
    await _saveMessage(userMessage);
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

    await _generateReply(
      conversationId,
      updatedConversation,
      userMessageId: userMessage.id,
    );
  }

  Future<void> _generateReply(
    String conversationId,
    Conversation updatedConversation, {
    required String userMessageId,
    Set<String> excludedMessageIds = const {},
  }) async {
    final now = DateTime.now();
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
    await _saveMessage(assistant);
    _replaceMessage(assistant);
    var generation = GenerationRun(
      assistantMessageId: assistantMessageId,
      conversationId: conversationId,
      userMessageId: userMessageId,
      status: GenerationStatus.requesting,
      responseText: '',
      toolCalls: const [],
      createdAt: now,
      updatedAt: now,
    );
    await _repository.saveGeneration(generation);

    _isChatGenerating = true;
    _cancelChatRequested = false;
    _chatGenerationFinished = Completer<void>();
    _activeConversationId = conversationId;
    notifyListeners();

    final toolCalls = <int, ToolCallAccumulator>{};
    var lastPersistAt = DateTime.now();
    ChatStreamTermination? termination;
    final done = Completer<void>();
    _chatStreamDone = done;
    try {
      final stream = await _chatService.streamReply(
        conversationId: conversationId,
        excludedMessageIds: excludedMessageIds,
      );
      if (!_cancelChatRequested) {
        _chatSubscription = stream.listen(
          (delta) {
            if (_cancelChatRequested || termination != null) {
              return;
            }
            if (delta.termination != null) {
              termination = delta.termination;
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
                ..index = index
                ..id = delta.toolCallId ?? current.id
                ..name = delta.toolCallName ?? current.name
                ..arguments.write(delta.toolArguments);
            }
            final currentTime = DateTime.now();
            if (currentTime.difference(lastPersistAt) >
                const Duration(milliseconds: 140)) {
              lastPersistAt = currentTime;
              unawaited(_saveMessage(assistant));
            }
            notifyListeners();
            if (termination != null && !done.isCompleted) {
              done.complete();
            }
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
      }

      if (_cancelChatRequested) {
        assistant = assistant.copyWith(
          content: assistant.content.trim().isEmpty
              ? '已停止生成'
              : assistant.content,
          status: ChatMessageStatus.interrupted,
          updatedAt: DateTime.now(),
        );
      } else if (termination != ChatStreamTermination.completed) {
        assistant = assistant.copyWith(
          status: ChatMessageStatus.failed,
          error: termination == ChatStreamTermination.incomplete
              ? '模型响应不完整，未执行自动记录；可手动重试。'
              : '连接在确认完成前结束，未执行自动记录；可手动重试。',
          updatedAt: DateTime.now(),
        );
      } else {
        generation = generation.copyWith(
          status: GenerationStatus.responseReady,
          responseText: assistant.content,
          toolCalls: toolCalls.entries
              .map(
                (entry) => <String, String>{
                  'index': entry.key.toString(),
                  if (entry.value.id != null) 'id': entry.value.id!,
                  if (entry.value.name != null) 'name': entry.value.name!,
                  'arguments': entry.value.arguments.toString(),
                },
              )
              .toList(growable: false),
          updatedAt: DateTime.now(),
          error: null,
        );
        await _repository.saveGeneration(generation);
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
      try {
        await _saveMessage(assistant);
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
        if (generation.status == GenerationStatus.responseReady &&
            assistant.status == ChatMessageStatus.complete) {
          await _repository.saveGeneration(
            generation.copyWith(
              status: GenerationStatus.completed,
              updatedAt: DateTime.now(),
              error: null,
            ),
          );
        } else if (generation.status == GenerationStatus.requesting) {
          await _repository.saveGeneration(
            generation.copyWith(
              status: _cancelChatRequested
                  ? GenerationStatus.interrupted
                  : GenerationStatus.failed,
              updatedAt: DateTime.now(),
              error: assistant.error,
            ),
          );
        }
      } catch (_) {
        // A persistence error must not leave the workspace locked in streaming.
      } finally {
        final subscription = _chatSubscription;
        _chatSubscription = null;
        _chatStreamDone = null;
        if (subscription != null) {
          unawaited(subscription.cancel());
        }
        _isChatGenerating = false;
        _cancelChatRequested = false;
        final finished = _chatGenerationFinished;
        _chatGenerationFinished = null;
        notifyListeners();
        if (finished != null && !finished.isCompleted) {
          finished.complete();
        }
      }
    }
  }

  Future<void> _saveMessage(ChatMessage message) {
    final previous = _messageSaveQueues[message.id] ?? Future<void>.value();
    late final Future<void> queued;
    queued = previous
        .catchError((_) {})
        .then((_) => _repository.saveMessage(message))
        .whenComplete(() {
          if (identical(_messageSaveQueues[message.id], queued)) {
            _messageSaveQueues.remove(message.id);
          }
        });
    _messageSaveQueues[message.id] = queued;
    return queued;
  }

  Future<void> cancelGeneration() async {
    if (!_isChatGenerating) {
      return;
    }
    _cancelChatRequested = true;
    final subscription = _chatSubscription;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    if (_chatStreamDone?.isCompleted == false) {
      _chatStreamDone!.complete();
    }
    await _chatGenerationFinished?.future;
    notifyListeners();
  }

  Future<void> retryAssistantMessage(String messageId) async {
    final message = await _repository.findMessage(messageId);
    if (message == null ||
        message.role != ChatRole.assistant ||
        (message.status != ChatMessageStatus.failed &&
            message.status != ChatMessageStatus.interrupted)) {
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
    final conversation = await _repository.findConversation(
      message.conversationId,
    );
    if (conversation == null) {
      return;
    }
    await _generateReply(
      message.conversationId,
      conversation,
      userMessageId: previousUser.id,
      excludedMessageIds: {message.id},
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
