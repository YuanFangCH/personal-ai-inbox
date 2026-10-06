import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/chat_models.dart';
import '../core/deterministic_parser.dart';
import '../core/models.dart';
import '../data/attachment_store.dart';
import '../data/attachment_store_factory.dart';
import '../data/chat_repository.dart';
import '../data/conversation_store.dart';
import '../data/conversation_store_factory.dart';
import '../data/device_paths.dart';
import '../data/index_database.dart';
import '../data/index_database_factory.dart';
import '../data/memory_attachment_store.dart';
import '../data/memory_conversation_store.dart';
import '../data/result_repository.dart';
import '../data/settings_service.dart';
import '../data/share_payload.dart';
import '../data/sync_engine.dart';
import '../data/sync_provider.dart';
import '../data/vault_store.dart';
import '../data/vault_store_factory.dart';
import 'capture_service.dart';
import 'chat_service.dart';
import 'image_input_service.dart';
import 'model_client.dart';

class AppController extends ChangeNotifier {
  AppController({
    required ResultRepository repository,
    required IndexDatabase indexDatabase,
    required CaptureService captureService,
    required SettingsService settingsService,
    required SyncEngine syncEngine,
    ChatRepository? chatRepository,
    ChatService? chatService,
    ImageInputService? imageInputService,
    bool autoOpenStartupConversation = false,
  }) : _repository = repository,
       _index = indexDatabase,
       _captureService = captureService,
       _settingsService = settingsService,
       _syncEngine = syncEngine,
       _chatRepository =
           chatRepository ??
           ChatRepository(
             store: MemoryConversationStore(),
             attachments: MemoryAttachmentStore(),
           ),
       _chatService = chatService,
       _imageInputService = imageInputService ?? ImageInputService(),
       _autoOpenStartupConversation = autoOpenStartupConversation {
    _chatService ??= ChatService(
      settings: _settingsService,
      repository: _chatRepository,
    );
  }

  static Future<AppController> bootstrap({
    VaultStore? vaultOverride,
    IndexDatabase? indexOverride,
    ConversationStore? conversationStoreOverride,
    AttachmentStore? attachmentStoreOverride,
    ModelClient? modelClient,
  }) async {
    final vault = vaultOverride ?? await createPlatformVaultStore();
    final supportPath = vaultOverride == null
        ? await appSupportPath()
        : 'memory';
    final index =
        indexOverride ?? await createPlatformIndexDatabase(supportPath);
    final settingsService = SettingsService();
    final settings = await settingsService.load();
    final repository = ResultRepository(
      vault: vault,
      index: index,
      deviceId: settings.deviceId,
    );
    final provider = MemorySyncProvider();
    final syncEngine = SyncEngine(
      repository: repository,
      provider: provider,
      deviceId: settings.deviceId,
    );
    final chatRepository = ChatRepository(
      store:
          conversationStoreOverride ??
          await createConversationStore(supportPath),
      attachments: attachmentStoreOverride ?? await createAttachmentStore(),
    );
    final controller = AppController(
      repository: repository,
      indexDatabase: index,
      captureService: CaptureService(
        settings: settingsService,
        parser: const DeterministicParser(),
      ),
      settingsService: settingsService,
      syncEngine: syncEngine,
      chatRepository: chatRepository,
      chatService: ChatService(
        settings: settingsService,
        repository: chatRepository,
        modelClient: modelClient,
      ),
      autoOpenStartupConversation: true,
    );
    await controller.initialize();
    return controller;
  }

  final ResultRepository _repository;
  final IndexDatabase _index;
  final CaptureService _captureService;
  final SettingsService _settingsService;
  final SyncEngine _syncEngine;
  final ChatRepository _chatRepository;
  final ImageInputService _imageInputService;
  final bool _autoOpenStartupConversation;
  ChatService? _chatService;
  StreamSubscription<ChatStreamDelta>? _chatSubscription;
  Completer<void>? _chatStreamDone;
  bool _cancelChatRequested = false;
  bool _chatInitialized = false;
  String? _startupConversationId;
  String? _pendingOpenConversationId;

  bool isReady = false;
  bool isBusy = false;
  bool isChatGenerating = false;
  String? errorMessage;
  String? noticeMessage;
  String vaultRoot = '';
  AppSettings? settings;
  SyncReport? lastSyncReport;
  List<ResultDocument> documents = const [];
  List<CaptureRecord> captures = const [];
  List<String> conflictFiles = const [];
  List<Conversation> conversations = const [];
  String? activeConversationId;
  final Map<String, List<ChatMessage>> _messagesByConversation = {};

  List<ChatMessage> messagesFor(String conversationId) {
    return _messagesByConversation[conversationId] ?? const [];
  }

  Conversation? findConversation(String id) {
    for (final conversation in conversations) {
      if (conversation.id == id) {
        return conversation;
      }
    }
    return null;
  }

  @override
  void dispose() {
    unawaited(_chatSubscription?.cancel());
    _chatService?.close();
    super.dispose();
  }

  List<ResultDocument> get canonicalDocuments => documents
      .where((document) => document.status == ResultStatus.canonical)
      .toList();

  List<ResultDocument> get draftDocuments => documents
      .where((document) => document.status == ResultStatus.draft)
      .toList();

  List<ResultDocument> get todos => canonicalDocuments
      .where((document) => document.type == ResultType.todo)
      .toList();

  List<ResultDocument> get events => canonicalDocuments
      .where((document) => document.type == ResultType.event)
      .toList();

  List<ResultDocument> get matters => canonicalDocuments
      .where((document) => document.type == ResultType.matter)
      .toList();

  List<ResultDocument> get knowledge => canonicalDocuments
      .where((document) => document.type == ResultType.knowledge)
      .toList();

  List<CaptureRecord> get reviewCaptures => captures
      .where((capture) => capture.status == CaptureStatus.needsReview)
      .toList(growable: false);

  String get syncProviderName => _syncEngine.provider.displayName;

  Future<void> initialize() async {
    try {
      settings = await _settingsService.load();
      await _repository.initialize();
      if (!_chatInitialized) {
        await _chatRepository.initialize();
        _chatInitialized = true;
      }
      await refresh();
      final startupConversation = await createConversation();
      if (_autoOpenStartupConversation) {
        _startupConversationId = startupConversation.id;
      }
      isReady = true;
    } catch (error, stackTrace) {
      errorMessage = '初始化失败：$error';
      debugPrint('AppController initialization failed: $error\n$stackTrace');
      isReady = true;
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    documents = await _repository.listDocuments(includeDeleted: false);
    captures = await _captureRecords();
    conflictFiles = await _repository.listConflictFiles();
    vaultRoot = await _repository.describeVaultRoot();
    conversations = await _chatRepository.listConversations();
    notifyListeners();
  }

  Future<CaptureOutcome> captureText(
    String text, {
    bool preferModel = true,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return const CaptureOutcome.failure('请输入内容');
    }

    final now = DateTime.now();
    final capture = CaptureRecord(
      id: 'cap_${const Uuid().v4()}',
      deviceId: settings?.deviceId ?? 'unknown',
      capturedAt: now,
      sourceType: _sourceType(normalized),
      text: normalized,
      status: CaptureStatus.processing,
    );
    await _index.insertCapture(capture);
    await refresh();

    final analysis = await _captureService.analyze(
      text: normalized,
      now: now,
      preferModel: preferModel,
    );
    final candidate = analysis.candidate;
    final updated = capture.copyWith(
      candidateType: candidate.type,
      candidateTitle: candidate.title,
      candidateAt: candidate.start ?? candidate.due,
      confidence: candidate.confidence,
      reviewReason: candidate.reviewReason,
      status: candidate.needsReview || candidate.confidence < 0.72
          ? CaptureStatus.needsReview
          : CaptureStatus.accepted,
    );

    if (updated.status == CaptureStatus.needsReview) {
      await _index.updateCapture(updated);
      await refresh();
      return CaptureOutcome.review(updated, warning: analysis.warning);
    }

    final document = await _createFromCandidate(candidate);
    await _index.updateCapture(updated.copyWith(resultId: document.id));
    await refresh();
    return CaptureOutcome.created(
      document,
      usedModel: analysis.usedModel,
      warning: analysis.warning,
    );
  }

  Future<ResultDocument> createManual({
    required ResultType type,
    required String title,
    String body = '',
    ResultStatus status = ResultStatus.canonical,
    DateTime? due,
    String? matterId,
    DateTime? start,
    DateTime? end,
    bool allDay = false,
    String? recurrence,
    List<String> tags = const [],
  }) async {
    final document = await _repository.create(
      type: type,
      title: title,
      body: body,
      status: status,
      due: due,
      matterId: matterId,
      start: start,
      end: end,
      allDay: allDay,
      recurrence: recurrence,
      tags: tags,
    );
    await refresh();
    return document;
  }

  Future<void> saveDocument(ResultDocument document) async {
    await _repository.save(document);
    await refresh();
  }

  Future<void> toggleTodo(ResultDocument document, bool done) async {
    await _repository.markTodo(document, done);
    await refresh();
  }

  Future<void> deleteDocument(String id) async {
    await _repository.delete(id);
    await refresh();
  }

  Future<void> acceptCapture(
    CaptureRecord capture, {
    ResultType? type,
    String? title,
  }) async {
    final effectiveType = type ?? capture.candidateType ?? ResultType.knowledge;
    final document = await _repository.create(
      type: effectiveType,
      title: title?.trim().isNotEmpty == true
          ? title!.trim()
          : capture.candidateTitle ?? '待整理',
      body: capture.text,
      status: ResultStatus.canonical,
      due: effectiveType == ResultType.todo ? capture.candidateAt : null,
      start: effectiveType == ResultType.event ? capture.candidateAt : null,
      end: effectiveType == ResultType.event && capture.candidateAt != null
          ? capture.candidateAt!.add(const Duration(hours: 1))
          : null,
    );
    await _index.updateCapture(
      capture.copyWith(
        status: CaptureStatus.accepted,
        resultId: document.id,
        candidateType: effectiveType,
        candidateTitle: document.title,
      ),
    );
    await refresh();
  }

  Future<void> rejectCapture(CaptureRecord capture) async {
    await _index.updateCapture(capture.copyWith(status: CaptureStatus.failed));
    await refresh();
  }

  Future<Conversation> createConversation() async {
    final conversation = await _chatRepository.createConversation();
    conversations = [
      conversation,
      ...conversations.where((item) => item.id != conversation.id),
    ];
    _messagesByConversation[conversation.id] = [];
    activeConversationId = conversation.id;
    notifyListeners();
    return conversation;
  }

  String? consumePendingConversationId() {
    final value = _pendingOpenConversationId ?? _startupConversationId;
    _pendingOpenConversationId = null;
    _startupConversationId = null;
    return value;
  }

  Future<void> openConversation(String id) async {
    activeConversationId = id;
    _messagesByConversation[id] = await _chatRepository.listMessages(id);
    notifyListeners();
  }

  Future<void> renameConversation(String id, String title) async {
    final conversation = await _chatRepository.findConversation(id);
    final normalized = title.trim();
    if (conversation == null || normalized.isEmpty) {
      return;
    }
    final updated = conversation.copyWith(
      title: normalized,
      autoTitle: false,
      updatedAt: DateTime.now(),
    );
    await _chatRepository.saveConversation(updated);
    await refresh();
  }

  Future<void> deleteConversation(String id) async {
    await cancelChatGeneration();
    await _chatRepository.deleteConversation(id);
    _messagesByConversation.remove(id);
    if (activeConversationId == id) {
      activeConversationId = null;
    }
    await refresh();
  }

  Future<void> handleSharedPayload(SharedCapturePayload payload) async {
    if (payload.isEmpty) {
      return;
    }
    final rawImages = await payload.readImages();
    final images = await _imageInputService.fromBytes(rawImages);
    final startupId = _startupConversationId;
    _startupConversationId = null;
    final conversation = startupId == null
        ? await createConversation()
        : findConversation(startupId) ?? await createConversation();
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
    if (isChatGenerating) {
      await cancelChatGeneration();
    }

    final conversation = await _chatRepository.findConversation(conversationId);
    if (conversation == null) {
      errorMessage = '会话不存在或已删除';
      notifyListeners();
      return;
    }

    final history = await _chatRepository.listMessages(conversationId);
    final userMessageId = _chatRepository.newMessageId();
    final savedAttachments = await _chatRepository.saveAttachments(
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
    await _chatRepository.saveMessage(userMessage);
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
    await _chatRepository.saveConversation(updatedConversation);
    _replaceConversation(updatedConversation);

    final assistantMessageId = _chatRepository.newMessageId();
    var assistant = ChatMessage(
      id: assistantMessageId,
      conversationId: conversationId,
      role: ChatRole.assistant,
      content: '',
      status: ChatMessageStatus.streaming,
      createdAt: now,
      updatedAt: now,
    );
    await _chatRepository.saveMessage(assistant);
    _replaceMessage(assistant);

    isChatGenerating = true;
    _cancelChatRequested = false;
    activeConversationId = conversationId;
    notifyListeners();

    final toolCalls = <int, _ToolCallAccumulator>{};
    var lastPersistAt = DateTime.now();
    try {
      final stream = await _chatService!.streamReply(
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
              _ToolCallAccumulator.new,
            );
            current
              ..id = delta.toolCallId ?? current.id
              ..name = delta.toolCallName ?? current.name
              ..arguments.write(delta.toolArguments);
          }
          final now = DateTime.now();
          if (now.difference(lastPersistAt) >
              const Duration(milliseconds: 140)) {
            lastPersistAt = now;
            unawaited(_chatRepository.saveMessage(assistant));
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
        final actions = await _processToolCalls(
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
      await _chatRepository.saveMessage(assistant);
      _replaceMessage(assistant);
      final latestConversation =
          await _chatRepository.findConversation(conversationId) ??
          updatedConversation;
      final withPreview = latestConversation.copyWith(
        preview: _messagePreview(assistant.content, false),
        updatedAt: DateTime.now(),
      );
      await _chatRepository.saveConversation(withPreview);
      _replaceConversation(withPreview);
      _chatSubscription = null;
      _chatStreamDone = null;
      isChatGenerating = false;
      notifyListeners();
    }
  }

  Future<void> cancelChatGeneration() async {
    if (!isChatGenerating) {
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
    final message = await _chatRepository.findMessage(messageId);
    if (message == null ||
        message.role != ChatRole.assistant ||
        message.status != ChatMessageStatus.failed) {
      return;
    }
    final messages = await _chatRepository.listMessages(message.conversationId);
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
      final bytes = await _chatRepository.readAttachment(attachment);
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
    await _chatRepository.deleteMessage(messageId);
    await _chatRepository.deleteMessage(previousUser.id);
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
    return _chatRepository.readAttachment(attachment);
  }

  Future<void> undoAutoRecord(String actionId) async {
    final action = await _chatRepository.findAutoRecordAction(actionId);
    if (action == null || !action.canUndo || action.resultId == null) {
      return;
    }
    final result = findDocument(action.resultId!);
    if (result == null || result.revision != 1) {
      await _updateAutoRecordAction(
        actionId,
        action.copyWith(reason: '成果已被修改，不能撤销'),
      );
      return;
    }
    await _repository.delete(result.id);
    await _updateAutoRecordAction(
      actionId,
      action.copyWith(status: AutoRecordStatus.undone),
    );
    await refresh();
  }

  Future<void> resolveConflict(String path, {required bool useRemote}) async {
    if (useRemote) {
      await _repository.resolveConflictUsingRemote(path);
    } else {
      await _repository.keepLocalConflict(path);
    }
    await refresh();
  }

  Future<void> syncNow() async {
    isBusy = true;
    noticeMessage = null;
    notifyListeners();
    try {
      lastSyncReport = await _syncEngine.sync();
      if (lastSyncReport!.failed > 0) {
        noticeMessage = '同步有 ${lastSyncReport!.failed} 项失败';
      }
      await refresh();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> rebuildIndex() async {
    isBusy = true;
    notifyListeners();
    try {
      await _repository.rebuildIndex();
      await refresh();
      noticeMessage = '索引已从 Markdown 重建';
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> saveSettings({
    ThemeMode? themeMode,
    String? modelBaseUrl,
    String? modelName,
    String? apiKey,
    bool? showCompletedTodos,
    bool? allowImageEgress,
  }) async {
    await _settingsService.saveGeneral(
      themeMode: themeMode,
      modelBaseUrl: modelBaseUrl,
      modelName: modelName,
      showCompletedTodos: showCompletedTodos,
      allowImageEgress: allowImageEgress,
    );
    if (apiKey != null) {
      await _settingsService.saveModelKey(apiKey);
    }
    settings = await _settingsService.load();
    notifyListeners();
  }

  Future<void> clearNotice() async {
    noticeMessage = null;
    errorMessage = null;
    notifyListeners();
  }

  ResultDocument? findDocument(String id) {
    for (final document in documents) {
      if (document.id == id) {
        return document;
      }
    }
    return null;
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
    conversations = [
      conversation,
      ...conversations.where((item) => item.id != conversation.id),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
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

  Future<List<AutoRecordAction>> _processToolCalls(
    String assistantMessageId,
    List<_ToolCallAccumulator> calls,
  ) async {
    final actions = <AutoRecordAction>[];
    for (final call in calls) {
      if (call.name != 'create_result' || call.arguments.isEmpty) {
        continue;
      }
      final action = await _processAutoRecord(
        assistantMessageId,
        call.arguments.toString(),
      );
      if (action != null) {
        actions.add(action);
      }
    }
    return actions;
  }

  Future<AutoRecordAction?> _processAutoRecord(
    String assistantMessageId,
    String rawArguments,
  ) async {
    final actionId = _chatRepository.newActionId();
    final createdAt = DateTime.now();
    dynamic decoded;
    try {
      decoded = jsonDecode(rawArguments);
    } on FormatException {
      return AutoRecordAction(
        id: actionId,
        type: ResultType.knowledge,
        title: '无法解析的自动记录',
        status: AutoRecordStatus.skipped,
        createdAt: createdAt,
        reason: '模型返回的记录结构无效',
      );
    }
    if (decoded is! Map) {
      return AutoRecordAction(
        id: actionId,
        type: ResultType.knowledge,
        title: '无法解析的自动记录',
        status: AutoRecordStatus.skipped,
        createdAt: createdAt,
        reason: '模型返回的记录结构无效',
      );
    }
    final payload = decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    ResultType type;
    try {
      type = ResultType.parse(payload['type'].toString());
    } on FormatException {
      return AutoRecordAction(
        id: actionId,
        type: ResultType.knowledge,
        title: payload['title']?.toString() ?? '无法识别的记录',
        status: AutoRecordStatus.skipped,
        createdAt: createdAt,
        reason: '成果类型无效',
      );
    }
    final title = payload['title']?.toString().trim() ?? '';
    final body = payload['body']?.toString().trim() ?? '';
    final confidence = (payload['confidence'] as num?)?.toDouble() ?? 0;
    final sensitive = payload['sensitive'] == true;
    final recurrence = payload['recurrence']?.toString().trim() ?? '';
    final due = _parseDate(payload['due']);
    final start = _parseDate(payload['start']);
    final end = _parseDate(payload['end']);
    final allDay = payload['all_day'] == true;
    final tags = _stringList(payload['tags']);
    final candidateAt = type == ResultType.event ? start : due;

    String? reviewReason;
    if (title.isEmpty || body.isEmpty) {
      reviewReason = '标题或正文为空';
    } else if (confidence < 0.85) {
      reviewReason = '置信度低于 85%';
    } else if (sensitive) {
      reviewReason = '敏感内容需要人工确认';
    } else if (recurrence.isNotEmpty) {
      reviewReason = '重复规则需要人工确认';
    } else if (type == ResultType.event && start == null) {
      reviewReason = '事件缺少开始时间';
    } else if ((start ?? due) != null &&
        (start ?? due)!.isBefore(DateTime.now())) {
      reviewReason = '日期已经过去';
    } else if (_isDuplicate(type, title, candidateAt)) {
      return AutoRecordAction(
        id: actionId,
        type: type,
        title: title,
        status: AutoRecordStatus.skipped,
        createdAt: createdAt,
        reason: '已存在相同成果',
      );
    }

    if (reviewReason != null) {
      final capture = CaptureRecord(
        id: 'cap_${const Uuid().v4()}',
        deviceId: settings?.deviceId ?? 'unknown',
        capturedAt: createdAt,
        sourceType: CaptureSourceType.text,
        text: body.isEmpty ? title : body,
        status: CaptureStatus.needsReview,
        candidateType: type,
        candidateTitle: title.isEmpty ? '待整理' : title,
        candidateAt: candidateAt,
        confidence: confidence,
        reviewReason: reviewReason,
      );
      await _index.insertCapture(capture);
      await refresh();
      return AutoRecordAction(
        id: actionId,
        type: type,
        title: capture.candidateTitle!,
        status: AutoRecordStatus.review,
        createdAt: createdAt,
        captureId: capture.id,
        reason: reviewReason,
      );
    }

    final document = await _repository.create(
      type: type,
      title: title,
      body: body,
      status: ResultStatus.canonical,
      tags: tags,
      due: type == ResultType.todo ? due : null,
      start: type == ResultType.event ? start : null,
      end: type == ResultType.event ? end : null,
      allDay: allDay,
      createdAt: createdAt,
    );
    await refresh();
    return AutoRecordAction(
      id: actionId,
      type: type,
      title: document.title,
      status: AutoRecordStatus.created,
      createdAt: createdAt,
      resultId: document.id,
      undoUntil: createdAt.add(const Duration(minutes: 10)),
    );
  }

  bool _isDuplicate(ResultType type, String title, DateTime? at) {
    final normalized = title.trim().toLowerCase();
    for (final document in documents) {
      if (document.type != type ||
          document.deleted ||
          document.title.trim().toLowerCase() != normalized) {
        continue;
      }
      final existingAt = document.type == ResultType.event
          ? document.start
          : document.type == ResultType.todo
          ? document.due
          : null;
      if (at == null || existingAt == null) {
        return true;
      }
      if (existingAt.difference(at).abs() < const Duration(minutes: 1)) {
        return true;
      }
    }
    return false;
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
    await _chatRepository.saveMessage(updatedMessage);
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
    for (final conversation in await _chatRepository.listConversations()) {
      for (final message in await _chatRepository.listMessages(
        conversation.id,
      )) {
        if (message.actions.any((action) => action.id == actionId)) {
          return message;
        }
      }
    }
    return null;
  }

  DateTime? _parseDate(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') {
      return null;
    }
    return DateTime.tryParse(text)?.toLocal();
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<CaptureRecord>> _captureRecords() => _index.listCaptures();

  CaptureSourceType _sourceType(String text) {
    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme && !text.contains(RegExp(r'\s'))) {
      return CaptureSourceType.url;
    }
    return CaptureSourceType.text;
  }

  Future<ResultDocument> _createFromCandidate(
    ClassificationCandidate candidate,
  ) {
    return _repository.create(
      type: candidate.type,
      title: candidate.title,
      body: candidate.summary,
      status: ResultStatus.canonical,
      tags: candidate.tags,
      due: candidate.type == ResultType.todo ? candidate.due : null,
      start: candidate.type == ResultType.event ? candidate.start : null,
      end: candidate.type == ResultType.event ? candidate.end : null,
      allDay: candidate.allDay,
      recurrence: candidate.recurrence,
    );
  }
}

class CaptureOutcome {
  const CaptureOutcome._({
    required this.status,
    this.document,
    this.capture,
    this.usedModel = false,
    this.warning,
    this.message,
  });

  const CaptureOutcome.created(
    ResultDocument document, {
    bool usedModel = false,
    String? warning,
  }) : this._(
         status: CaptureOutcomeStatus.created,
         document: document,
         usedModel: usedModel,
         warning: warning,
       );

  const CaptureOutcome.review(CaptureRecord capture, {String? warning})
    : this._(
        status: CaptureOutcomeStatus.review,
        capture: capture,
        warning: warning,
      );

  const CaptureOutcome.failure(String message)
    : this._(status: CaptureOutcomeStatus.failure, message: message);

  final CaptureOutcomeStatus status;
  final ResultDocument? document;
  final CaptureRecord? capture;
  final bool usedModel;
  final String? warning;
  final String? message;
}

enum CaptureOutcomeStatus { created, review, failure }

class _ToolCallAccumulator {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}
