import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/ai_policy.dart';
import '../core/deterministic_parser.dart';
import '../data/attachment_store.dart';
import '../data/attachment_store_factory.dart';
import '../data/chat_repository.dart';
import '../data/conversation_store.dart';
import '../data/conversation_store_factory.dart';
import '../data/disk_space_probe.dart';
import '../data/device_paths.dart';
import '../data/index_database.dart';
import '../data/index_database_factory.dart';
import '../data/memory_attachment_store.dart';
import '../data/memory_conversation_store.dart';
import '../data/result_repository.dart';
import '../data/settings_service.dart';
import '../data/migration_coordinator.dart';
import '../data/migration_coordinator_factory.dart';
import '../data/sync_engine.dart';
import '../data/sync_provider.dart';
import '../data/table_migration_service.dart';
import '../data/vault_store.dart';
import '../data/vault_store_factory.dart';
import '../modules/capture/capture_workflow.dart';
import '../modules/conversation/conversation_workspace.dart';
import '../modules/conversation/agent_background_control.dart';
import '../modules/conversation/agent_task_store.dart';
import '../modules/conversation/auto_record_processor.dart';
import '../modules/conversation/content_duplicate_policy.dart';
import '../modules/conversation/content_intake.dart';
import '../modules/conversation/model_duplicate_decision_source.dart';
import '../modules/conversation/table_action_processor.dart';
import '../modules/results/result_library.dart';
import '../modules/tables/table_library.dart';
import '../modules/tables/table_migration_gate.dart';
import '../modules/settings/device_preferences.dart';
import '../modules/sync/sync_workspace.dart';
import '../services/capture_service.dart';
import '../services/chat_service.dart';
import '../services/image_input_service.dart';
import '../services/file_input_service.dart';
import '../services/agent_background_service.dart';
import '../services/agent_execution_profile.dart';
import '../services/voice_service.dart';
import '../services/model_client.dart';

/// Composition root for the local core.
///
/// The runtime only wires modules and controls their lifecycle. Business
/// commands remain on the owning module interface.
final class AppRuntime {
  static Future<AppRuntime> bootstrap({
    VaultStore? vaultOverride,
    IndexDatabase? indexOverride,
    ConversationStore? conversationStoreOverride,
    AttachmentStore? attachmentStoreOverride,
    SettingsService? settingsOverride,
    MigrationCoordinator? migrationCoordinatorOverride,
    ModelClient? modelClient,
    SyncProvider? syncProvider,
    FileInputService? fileInputService,
    VoiceService? voiceService,
    AgentTaskStore? agentTaskStore,
    AgentBackgroundControl? agentBackground,
    Duration Function()? activeUsageElapsedDuration,
  }) async {
    final vault = vaultOverride ?? await createPlatformVaultStore();
    final supportPath = vaultOverride == null
        ? await appSupportPath()
        : 'memory';
    final settingsService = settingsOverride ?? SettingsService();
    final taskStore =
        agentTaskStore ??
        (vaultOverride != null
            ? MemoryAgentTaskStore()
            : VaultAgentTaskStore(vault));
    final migration =
        migrationCoordinatorOverride ??
        (vaultOverride != null
            ? null
            : await createMigrationCoordinator(
                supportPath: supportPath,
                settings: settingsService,
                additionalFilePaths: [
                  p.join(
                    await vault.describeRoot(),
                    AgentTaskCheckpoint.storagePath,
                  ),
                ],
              ));
    try {
      await migration?.prepare();
      await taskStore.preflight();
    } catch (_) {
      await migration?.rollback();
      rethrow;
    }

    IndexDatabase? index;
    ChatRepository? chatRepository;
    AppRuntime? runtime;
    try {
      index = indexOverride ?? await createPlatformIndexDatabase(supportPath);
      late final TableMigrationGate migrationGate;
      final tableMigrationService = TableMigrationService(
        vault: vault,
        index: index,
        createDatabaseSnapshot: migration?.createTableMigrationSnapshot,
        estimateDatabaseSnapshotBytes:
            migration?.estimateTableMigrationSnapshotBytes,
        availableSpaceProbe: availableBytesForPath,
        runWithWriteBarrier: (operation) =>
            migrationGate.runStartupMigrationBarrier(operation),
      );
      final settings = await settingsService.load();
      final repository = ResultRepository(
        vault: vault,
        index: index,
        deviceId: settings.deviceId,
      );
      final syncEngine = SyncEngine(
        repository: repository,
        provider: syncProvider ?? MemorySyncProvider(),
        deviceId: settings.deviceId,
      );
      final conversationStore =
          conversationStoreOverride ??
          (vaultOverride != null
              ? MemoryConversationStore()
              : await createConversationStore(supportPath));
      chatRepository = ChatRepository(
        store: conversationStore,
        attachments:
            attachmentStoreOverride ??
            (vaultOverride != null
                ? MemoryAttachmentStore()
                : await createAttachmentStore()),
      );
      final preferences = DevicePreferences(
        adapter: SettingsServiceDevicePreferencesAdapter(settingsService),
      );
      final results = ResultLibrary(repository: repository);
      final tables = TableLibrary(
        repository: repository.createTableRepository(),
      );
      migrationGate = TableMigrationGate(
        service: tableMigrationService,
        onMigrationComplete: () => runtime!._initializeModules(),
      );
      final captureSemanticRuntime = _CaptureSemanticRuntime();
      late final CaptureWorkflow capture;
      capture = CaptureWorkflow(
        repository: repository,
        results: results,
        tables: tables,
        indexDatabase: index,
        captureService: CaptureService(
          settings: settingsService,
          parser: const DeterministicParser(),
          modelClient: modelClient,
        ),
        duplicateDecisionSourceFactory: (context) {
          final source = ModelSemanticDuplicateDecisionSource.fromSettings(
            settings: settingsService,
            modelClient: modelClient,
            canReadCandidates: context.canReadCandidates,
            canModifyExisting: context.canModifyExisting,
            reserveModelRequest: (_) =>
                captureSemanticRuntime.reserve(context.scopeId),
            cancellation: () =>
                captureSemanticRuntime.cancellationFor(context.scopeId),
          );
          return _CaptureScopedSemanticDecisionSource(
            source: source,
            onFinished: () => captureSemanticRuntime.finish(context.scopeId),
          );
        },
        canReadDuplicateCandidates: (request) {
          final settings = preferences.settings;
          final policy = AgentExecutionProfile.fromSettings(settings)
              .policyFor(null, settings);
          final tableIds = request.candidates
              .map((candidate) => candidate.entry.tableId)
              .toSet();
          return Future<bool>.value(
            policy.decisionFor(
                  AiPermissionAction.contentRead,
                  tableIds: tableIds,
                ) ==
                AiPolicyDecision.allow,
          );
        },
        canModifyDuplicateCandidates: (request) {
          final settings = preferences.settings;
          final policy = AgentExecutionProfile.fromSettings(settings)
              .policyFor(null, settings);
          final tableIds = request.candidates
              .map((candidate) => candidate.entry.tableId)
              .toSet();
          return Future<bool>.value(
            policy.decisionFor(
                  AiPermissionAction.contentUpdate,
                  tableIds: tableIds,
                ) ==
                AiPolicyDecision.allow,
          );
        },
        // The per-capture source ignores this callback and reserves its own
        // capture-scoped budget through the factory above.
        reserveDuplicateModelRequest: (_) async => false,
        contentWriteAuthorization: (authorization) {
          final settings = preferences.settings;
          final policy = AgentExecutionProfile.fromSettings(settings)
              .policyFor(null, settings);
          final action = authorization.kind == ContentIntakeWriteKind.create
              ? AiPermissionAction.contentCreate
              : AiPermissionAction.contentUpdate;
          return Future<bool>.value(
            policy.decisionFor(action, tableIds: [authorization.tableId]) ==
                AiPolicyDecision.allow,
          );
        },
      );
      late final ConversationWorkspace conversations;
      final autoRecordProcessor = AutoRecordProcessor(
        chatRepository: chatRepository,
        results: results,
        captures: capture,
        deviceId: () => repository.deviceId,
      );
      final semanticDuplicateDecisionSource =
          ModelSemanticDuplicateDecisionSource.fromSettings(
            settings: settingsService,
            modelClient: modelClient,
            canReadCandidates: (request) async {
              final policy = await conversations.currentRunningPolicy();
              final tableIds = request.candidates
                  .map((candidate) => candidate.entry.tableId)
                  .toSet();
              return policy?.decisionFor(
                    AiPermissionAction.contentRead,
                    tableIds: tableIds,
                  ) ==
                  AiPolicyDecision.allow;
            },
            canModifyExisting: (request) async {
              final policy = await conversations.currentRunningPolicy();
              final tableIds = request.candidates
                  .map((candidate) => candidate.entry.tableId)
                  .toSet();
              return policy?.decisionFor(
                    AiPermissionAction.contentUpdate,
                    tableIds: tableIds,
                  ) ==
                  AiPolicyDecision.allow;
            },
            reserveModelRequest: (_) =>
                conversations.recordAuxiliaryModelRequest(),
            cancellation: () => conversations.activeCancellationFuture(),
          );
      ConversationWorkspace? policySource;
      final tableActionProcessor = TableActionProcessor(
        chatRepository: chatRepository,
        tables: tables,
        semanticDuplicateDecisionSource: semanticDuplicateDecisionSource,
        policyResolver: (conversation) =>
            policySource?.effectivePolicyFor(conversation) ??
            conversation.effectiveAiPolicy,
      );
      final chatService = ChatService(
        settings: settingsService,
        repository: chatRepository,
        results: results,
        tables: tables,
        modelClient: modelClient,
        writeToolExecutor: (call) => conversations.executeWriteTool(call),
        refreshSettings: preferences.initialize,
        refreshConversationState: () async {
          await policySource?.refreshAgentManagedState();
        },
      );
      final backgroundAgent =
          agentBackground ??
          (vaultOverride != null
              ? DisabledAgentBackgroundControl()
              : _defaultAgentBackground());
      conversations = ConversationWorkspace(
        repository: chatRepository,
        results: results,
        chatService: chatService,
        autoRecordProcessor: autoRecordProcessor,
        tableActionProcessor: tableActionProcessor,
        defaultPermissions: () => preferences.settings.defaultAiPermissions,
        defaultPolicy: () => preferences.settings.effectiveDefaultAiPolicy,
        fullAgentMode: () => preferences.settings.fullAgentMode,
        taskStore: taskStore,
        backgroundAgent: backgroundAgent,
        imageInputService: ImageInputService(),
        activeUsageElapsedDuration: activeUsageElapsedDuration,
      );
      policySource = conversations;
      final sync = SyncWorkspace(
        engine: syncEngine,
        repository: repository,
        results: results,
      );
      runtime = AppRuntime(
        preferences: preferences,
        results: results,
        tables: tables,
        migrationGate: migrationGate,
        initializeConversationStore: chatRepository.initialize,
        capture: capture,
        conversations: conversations,
        backgroundAgent: backgroundAgent,
        sync: sync,
        fileInputService: fileInputService ?? const FileInputService(),
        voiceService: voiceService ?? SystemVoiceService(),
        closeAdapters: () async {
          captureSemanticRuntime.cancelAll();
          await chatRepository!.close();
          await index!.close();
        },
      );
      await runtime.initialize();
      await migration?.complete();
      return runtime;
    } catch (error, stackTrace) {
      if (runtime != null) {
        await runtime.shutdown();
      } else {
        await chatRepository?.close();
        await index?.close();
      }
      await migration?.rollback();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  AppRuntime({
    required this.preferences,
    required this.results,
    required this.tables,
    TableMigrationGate? migrationGate,
    this.initializeConversationStore,
    required this.capture,
    required this.conversations,
    AgentBackgroundControl? backgroundAgent,
    required this.sync,
    this.fileInputService = const FileInputService(),
    VoiceService? voiceService,
    this.closeAdapters,
  }) : migrationGate = migrationGate ?? TableMigrationGate.disabled(),
       voiceService = voiceService ?? SystemVoiceService(),
       backgroundAgent = backgroundAgent ?? _defaultAgentBackground();

  final DevicePreferences preferences;
  final ResultLibrary results;
  final TableLibrary tables;
  final TableMigrationGate migrationGate;
  final Future<void> Function()? initializeConversationStore;
  final CaptureWorkflow capture;
  final ConversationWorkspace conversations;
  final AgentBackgroundControl backgroundAgent;
  final SyncWorkspace sync;
  final FileInputService fileInputService;
  final VoiceService voiceService;
  final Future<void> Function()? closeAdapters;
  bool _disposed = false;
  bool _modulesInitialized = false;
  Future<void>? _shutdownFuture;
  String? _shutdownError;

  String? get shutdownError => _shutdownError;

  Future<void> initialize() async {
    await preferences.initialize();
    if (migrationGate.isEnabled) {
      await initializeConversationStore?.call();
      await migrationGate.initialize();
      if (migrationGate.requiresReadOnly) {
        if (migrationGate.migrationComplete) await tables.initialize();
        return;
      }
    }
    await _initializeModules();
  }

  Future<void> _initializeModules() async {
    await results.initialize();
    await tables.initialize();
    await capture.initialize();
    await conversations.initialize();
    await sync.initialize();
    _modulesInitialized = true;
  }

  Future<void> refresh() async {
    await preferences.initialize();
    if (migrationGate.isEnabled) {
      await migrationGate.refresh();
      if (migrationGate.requiresReadOnly) return;
    }
    if (!_modulesInitialized) {
      await _initializeModules();
      return;
    }
    await results.refresh();
    await tables.refresh();
    await capture.refresh();
    await conversations.refresh();
    await sync.refresh();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    conversations.dispose();
    voiceService.dispose();
    sync.dispose();
    capture.dispose();
    results.dispose();
    tables.dispose();
    migrationGate.dispose();
    preferences.dispose();
  }

  Future<void> shutdown() => _shutdownFuture ??= _shutdown();

  Future<void> _shutdown() async {
    final errors = <Object>[];
    Future<void> collect(Future<void> Function() operation) async {
      try {
        await operation();
      } catch (error) {
        errors.add(error);
      }
    }

    await collect(conversations.shutdown);
    final workspaceError = conversations.shutdownError;
    if (workspaceError != null) errors.add(workspaceError);
    await collect(voiceService.close);
    await collect(sync.shutdown);
    await collect(results.shutdown);
    await collect(preferences.shutdown);
    dispose();
    final close = closeAdapters;
    if (close != null) {
      await collect(close);
    }
    if (errors.isNotEmpty) {
      _shutdownError = errors.map((error) => error.toString()).join('\n');
      debugPrint('AppRuntime shutdown completed with errors:\n$_shutdownError');
    }
  }
}

AgentBackgroundControl _defaultAgentBackground() {
  if (const bool.fromEnvironment('FLUTTER_TEST') ||
      BindingBase.debugBindingType() == null ||
      defaultTargetPlatform != TargetPlatform.android) {
    return DisabledAgentBackgroundControl();
  }
  return ServiceAgentBackgroundControl(AgentBackgroundService.instance);
}

class _CaptureScopedSemanticDecisionSource
    implements SemanticDuplicateDecisionSource {
  _CaptureScopedSemanticDecisionSource({
    required this.source,
    required this.onFinished,
  });

  final SemanticDuplicateDecisionSource source;
  final void Function() onFinished;

  @override
  Future<SemanticDuplicateDecision> decide(
    SemanticDuplicateRequest request,
  ) async {
    try {
      return await source.decide(request);
    } finally {
      onFinished();
    }
  }
}

class _CaptureSemanticRuntime {
  final Map<String, Completer<void>> _cancellations = {};

  Future<bool> reserve(String scopeId) async {
    _cancellations.putIfAbsent(scopeId, Completer<void>.new);
    return true;
  }

  Future<void> cancellationFor(String scopeId) =>
      _cancellations.putIfAbsent(scopeId, Completer<void>.new).future;

  void finish(String scopeId) {
    _cancellations.remove(scopeId);
  }

  void cancelAll() {
    for (final cancellation in _cancellations.values) {
      if (!cancellation.isCompleted) cancellation.complete();
    }
    _cancellations.clear();
  }
}
