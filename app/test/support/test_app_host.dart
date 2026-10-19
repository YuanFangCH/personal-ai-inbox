import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/attachment_store.dart';
import 'package:personal_ai_inbox/data/attachment_store_factory.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/conversation_store.dart';
import 'package:personal_ai_inbox/data/conversation_store_factory.dart';
import 'package:personal_ai_inbox/data/device_paths.dart';
import 'package:personal_ai_inbox/data/index_database.dart';
import 'package:personal_ai_inbox/data/index_database_factory.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/data/settings_service.dart';
import 'package:personal_ai_inbox/data/share_payload.dart';
import 'package:personal_ai_inbox/data/sqlite_migration_coordinator.dart';
import 'package:personal_ai_inbox/data/sync_engine.dart';
import 'package:personal_ai_inbox/data/sync_provider.dart';
import 'package:personal_ai_inbox/data/vault_store.dart';
import 'package:personal_ai_inbox/data/vault_store_factory.dart';
import 'package:personal_ai_inbox/modules/capture/capture_workflow.dart';
import 'package:personal_ai_inbox/modules/conversation/auto_record_processor.dart';
import 'package:personal_ai_inbox/modules/conversation/conversation_workspace.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';
import 'package:personal_ai_inbox/modules/settings/device_preferences.dart';
import 'package:personal_ai_inbox/modules/sync/sync_workspace.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';
import 'package:personal_ai_inbox/services/chat_service.dart';
import 'package:personal_ai_inbox/services/image_input_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

export 'package:personal_ai_inbox/modules/capture/capture_workflow.dart'
    show CaptureOutcome, CaptureOutcomeStatus;

/// Test-only host for module integration tests.
///
/// UI and existing tests still cross this seam while pages migrate to the
/// module snapshots. Business rules and persistence live in [AppRuntime]
/// modules, not in this class.
class TestAppHost extends ChangeNotifier {
  factory TestAppHost({
    required ResultRepository repository,
    required IndexDatabase indexDatabase,
    required CaptureService captureService,
    required SettingsService settingsService,
    required SyncEngine syncEngine,
    ChatRepository? chatRepository,
    ChatService? chatService,
    ImageInputService? imageInputService,
  }) {
    final resolvedChatRepository =
        chatRepository ??
        ChatRepository(
          store: MemoryConversationStore(),
          attachments: MemoryAttachmentStore(),
        );
    final resolvedChatService =
        chatService ??
        ChatService(
          settings: settingsService,
          repository: resolvedChatRepository,
        );
    final preferences = DevicePreferences(
      adapter: SettingsServiceDevicePreferencesAdapter(settingsService),
    );
    final results = ResultLibrary(repository: repository);
    final capture = CaptureWorkflow(
      repository: repository,
      results: results,
      indexDatabase: indexDatabase,
      captureService: captureService,
    );
    final conversations = ConversationWorkspace(
      repository: resolvedChatRepository,
      results: results,
      chatService: resolvedChatService,
      autoRecordProcessor: AutoRecordProcessor(
        chatRepository: resolvedChatRepository,
        results: results,
        captures: capture,
        deviceId: () => repository.deviceId,
      ),
      defaultPermissions: () => preferences.settings.defaultAiPermissions,
      imageInputService: imageInputService,
    );
    final sync = SyncWorkspace(
      engine: syncEngine,
      repository: repository,
      results: results,
    );
    return TestAppHost._(
      AppRuntime(
        preferences: preferences,
        results: results,
        capture: capture,
        conversations: conversations,
        sync: sync,
        closeAdapters: () async {
          await resolvedChatRepository.close();
          await indexDatabase.close();
        },
      ),
    );
  }

  TestAppHost._(this._runtime) {
    _runtime.preferences.addListener(_handleModuleChange);
    _runtime.results.addListener(_handleModuleChange);
    _runtime.capture.addListener(_handleModuleChange);
    _runtime.conversations.addListener(_handleModuleChange);
    _runtime.sync.addListener(_handleModuleChange);
  }

  bool _isDisposed = false;

  static Future<TestAppHost> bootstrap({
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
    final settingsService = SettingsService();
    final migration = supportPath == 'memory'
        ? null
        : SqliteMigrationCoordinator(
            supportPath: supportPath,
            settings: settingsService,
          );
    try {
      await migration?.prepare();
    } catch (_) {
      await migration?.rollback();
      rethrow;
    }

    IndexDatabase? index;
    ConversationStore? conversationStore;
    ChatRepository? chatRepository;
    TestAppHost? controller;
    try {
      index = indexOverride ?? await createPlatformIndexDatabase(supportPath);
      final settings = await settingsService.load();
      final repository = ResultRepository(
        vault: vault,
        index: index,
        deviceId: settings.deviceId,
      );
      final syncEngine = SyncEngine(
        repository: repository,
        provider: MemorySyncProvider(),
        deviceId: settings.deviceId,
      );
      conversationStore =
          conversationStoreOverride ??
          await createConversationStore(supportPath);
      chatRepository = ChatRepository(
        store: conversationStore,
        attachments: attachmentStoreOverride ?? await createAttachmentStore(),
      );
      controller = TestAppHost(
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
      );
      await controller.initialize();
      if (controller.errorMessage != null) {
        throw StateError(controller.errorMessage!);
      }
      await migration?.complete();
      return controller;
    } catch (error, stackTrace) {
      controller?.dispose();
      await chatRepository?.close();
      await index?.close();
      await migration?.rollback();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  final AppRuntime _runtime;
  bool _localBusy = false;

  bool isReady = false;
  String? errorMessage;
  String? noticeMessage;
  AppSettings? settings;

  bool get isBusy => _localBusy || _runtime.sync.isBusy;

  ResultLibrary get resultLibrary => _runtime.results;

  AppRuntime get runtime => _runtime;

  CaptureWorkflow get captureWorkflow => _runtime.capture;

  ConversationWorkspace get conversationWorkspace => _runtime.conversations;

  DevicePreferences get devicePreferences => _runtime.preferences;

  SyncWorkspace get syncWorkspace => _runtime.sync;

  String get vaultRoot => _runtime.results.vaultRoot;

  List<ResultDocument> get documents => _runtime.results.documents;

  List<ResultDocument> get canonicalDocuments =>
      _runtime.results.canonicalDocuments;

  List<ResultDocument> get draftDocuments => _runtime.results.draftDocuments;

  List<ResultDocument> get todos => _runtime.results.todos;

  List<ResultDocument> get events => _runtime.results.events;

  List<ResultDocument> get matters => _runtime.results.matters;

  List<ResultDocument> get knowledge => _runtime.results.knowledge;

  List<CaptureRecord> get captures => _runtime.capture.captures;

  List<CaptureRecord> get reviewCaptures => _runtime.capture.reviewCaptures;

  List<Conversation> get conversations => _runtime.conversations.conversations;

  String? get activeConversationId =>
      _runtime.conversations.activeConversationId;

  bool get isChatGenerating => _runtime.conversations.isChatGenerating;

  List<String> get conflictFiles => _runtime.sync.conflictFiles;

  SyncReport? get lastSyncReport => _runtime.sync.lastReport;

  String get syncProviderName => _runtime.sync.providerName;

  List<ChatMessage> messagesFor(String conversationId) {
    return _runtime.conversations.messagesFor(conversationId);
  }

  Conversation? findConversation(String id) {
    return _runtime.conversations.findConversation(id);
  }

  ResultDocument? findDocument(String id) {
    return _runtime.results.findDocument(id);
  }

  Future<void> initialize() async {
    try {
      await _runtime.initialize();
      settings = _runtime.preferences.settings;
      isReady = true;
    } catch (error, stackTrace) {
      errorMessage = '初始化失败：$error';
      debugPrint('TestAppHost initialization failed: $error\n$stackTrace');
      isReady = true;
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    await _runtime.refresh();
    settings = _runtime.preferences.settings;
    notifyListeners();
  }

  Future<CaptureOutcome> captureText(String text, {bool preferModel = true}) {
    return _runtime.capture.captureText(text, preferModel: preferModel);
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
  }) {
    return _runtime.results.createManual(
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
  }

  Future<void> saveDocument(ResultDocument document) {
    return _runtime.results.saveDocument(document);
  }

  Future<void> toggleTodo(ResultDocument document, bool done) {
    return _runtime.results.toggleTodo(document, done);
  }

  Future<void> deleteDocument(String id) {
    return _runtime.results.deleteDocument(id);
  }

  Future<void> acceptCapture(
    CaptureRecord capture, {
    ResultType? type,
    String? title,
  }) async {
    await _runtime.capture.acceptCapture(capture, type: type, title: title);
  }

  Future<void> rejectCapture(CaptureRecord capture) {
    return _runtime.capture.rejectCapture(capture);
  }

  Future<Conversation> createConversation() {
    return _runtime.conversations.createConversation();
  }

  String? consumePendingConversationId() {
    return _runtime.conversations.consumePendingConversationId();
  }

  Future<void> openConversation(String id) {
    return _runtime.conversations.openConversation(id);
  }

  Future<void> renameConversation(String id, String title) {
    return _runtime.conversations.renameConversation(id, title);
  }

  Future<void> deleteConversation(String id) {
    return _runtime.conversations.deleteConversation(id);
  }

  Future<void> handleSharedPayload(SharedCapturePayload payload) {
    return _runtime.conversations.handleSharedPayload(payload);
  }

  Future<void> sendChatMessage(
    String conversationId, {
    String text = '',
    List<ChatAttachmentInput> attachments = const [],
  }) async {
    try {
      await _runtime.conversations.sendChatMessage(
        conversationId,
        text: text,
        attachments: attachments,
      );
    } on StateError catch (error) {
      errorMessage = error.message;
      notifyListeners();
    }
  }

  Future<void> cancelChatGeneration() {
    return _runtime.conversations.cancelGeneration();
  }

  Future<void> retryAssistantMessage(String messageId) {
    return _runtime.conversations.retryAssistantMessage(messageId);
  }

  Future<Uint8List?> readAttachment(ChatAttachment attachment) {
    return _runtime.conversations.readAttachment(attachment);
  }

  Future<void> undoAutoRecord(String actionId) {
    return _runtime.conversations.undoAutoRecord(actionId);
  }

  Future<void> resolveConflict(String path, {required bool useRemote}) {
    return _runtime.sync.resolveConflict(path, useRemote: useRemote);
  }

  Future<void> syncNow() async {
    _localBusy = true;
    noticeMessage = null;
    notifyListeners();
    try {
      await _runtime.sync.syncNow();
      noticeMessage = _runtime.sync.errorMessage;
    } finally {
      _localBusy = false;
      notifyListeners();
    }
  }

  Future<void> rebuildIndex() async {
    _localBusy = true;
    notifyListeners();
    try {
      await _runtime.results.rebuildIndex();
      noticeMessage = '索引已从 Markdown 重建';
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      _localBusy = false;
      notifyListeners();
    }
  }

  Future<void> saveSettings({
    ThemePreference? themeMode,
    String? modelBaseUrl,
    String? modelName,
    String? apiKey,
    bool? showCompletedTodos,
    bool? calendarMonthDetailed,
    bool? allowImageEgress,
    AiPermissions? defaultAiPermissions,
  }) async {
    await _runtime.preferences.update(
      themeMode: themeMode,
      modelBaseUrl: modelBaseUrl,
      modelName: modelName,
      apiKey: apiKey,
      showCompletedTodos: showCompletedTodos,
      calendarMonthDetailed: calendarMonthDetailed,
      allowImageEgress: allowImageEgress,
      defaultAiPermissions: defaultAiPermissions,
    );
    settings = _runtime.preferences.settings;
    notifyListeners();
  }

  Future<void> clearNotice() async {
    noticeMessage = null;
    errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _detachModuleListeners();
    _runtime.dispose();
    super.dispose();
  }

  Future<void> shutdown() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _detachModuleListeners();
    await _runtime.shutdown();
    super.dispose();
  }

  void _detachModuleListeners() {
    _runtime.preferences.removeListener(_handleModuleChange);
    _runtime.results.removeListener(_handleModuleChange);
    _runtime.capture.removeListener(_handleModuleChange);
    _runtime.conversations.removeListener(_handleModuleChange);
    _runtime.sync.removeListener(_handleModuleChange);
  }

  void _handleModuleChange() {
    settings = _runtime.preferences.settings;
    if (_runtime.sync.errorMessage != null) {
      noticeMessage = _runtime.sync.errorMessage;
    }
    notifyListeners();
  }
}
