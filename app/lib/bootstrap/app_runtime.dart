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
import '../modules/conversation/auto_record_processor.dart';
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
  }) async {
    final vault = vaultOverride ?? await createPlatformVaultStore();
    final supportPath = vaultOverride == null
        ? await appSupportPath()
        : 'memory';
    final settingsService = settingsOverride ?? SettingsService();
    final migration =
        migrationCoordinatorOverride ??
        (vaultOverride != null
            ? null
            : await createMigrationCoordinator(
                supportPath: supportPath,
                settings: settingsService,
              ));
    try {
      await migration?.prepare();
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
        onMigrationComplete: tables.initialize,
      );
      final chatService = ChatService(
        settings: settingsService,
        repository: chatRepository,
        results: results,
        tables: tables,
        modelClient: modelClient,
      );
      final capture = CaptureWorkflow(
        repository: repository,
        results: results,
        tables: tables,
        indexDatabase: index,
        captureService: CaptureService(
          settings: settingsService,
          parser: const DeterministicParser(),
          modelClient: modelClient,
        ),
      );
      final conversations = ConversationWorkspace(
        repository: chatRepository,
        results: results,
        chatService: chatService,
        autoRecordProcessor: AutoRecordProcessor(
          chatRepository: chatRepository,
          results: results,
          captures: capture,
          deviceId: () => repository.deviceId,
        ),
        tableActionProcessor: TableActionProcessor(
          chatRepository: chatRepository,
          tables: tables,
        ),
        defaultPermissions: () => preferences.settings.defaultAiPermissions,
        imageInputService: ImageInputService(),
      );
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
        sync: sync,
        fileInputService: fileInputService ?? const FileInputService(),
        voiceService: voiceService ?? SystemVoiceService(),
        closeAdapters: () async {
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
    required this.sync,
    this.fileInputService = const FileInputService(),
    VoiceService? voiceService,
    this.closeAdapters,
  }) : migrationGate = migrationGate ?? TableMigrationGate.disabled(),
       voiceService = voiceService ?? SystemVoiceService();

  final DevicePreferences preferences;
  final ResultLibrary results;
  final TableLibrary tables;
  final TableMigrationGate migrationGate;
  final Future<void> Function()? initializeConversationStore;
  final CaptureWorkflow capture;
  final ConversationWorkspace conversations;
  final SyncWorkspace sync;
  final FileInputService fileInputService;
  final VoiceService voiceService;
  final Future<void> Function()? closeAdapters;
  bool _disposed = false;
  bool _modulesInitialized = false;
  Future<void>? _shutdownFuture;

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
    try {
      await conversations.shutdown();
      await voiceService.close();
      await sync.shutdown();
      await results.shutdown();
      await preferences.shutdown();
    } finally {
      dispose();
      await closeAdapters?.call();
    }
  }
}
