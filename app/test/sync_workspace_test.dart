import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/markdown_codec.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/data/sync_engine.dart';
import 'package:personal_ai_inbox/data/sync_provider.dart';
import 'package:personal_ai_inbox/modules/sync/sync_workspace.dart';

void main() {
  const codec = MarkdownCodec();
  late MemoryVaultStore vault;
  late MemoryIndexDatabase index;
  late ResultRepository repository;
  late MemorySyncProvider provider;
  late SyncEngine engine;
  late SyncWorkspace workspace;

  setUp(() async {
    vault = MemoryVaultStore();
    index = MemoryIndexDatabase();
    repository = ResultRepository(
      vault: vault,
      index: index,
      deviceId: 'test-device',
    );
    await repository.initialize();
    provider = MemorySyncProvider();
    engine = SyncEngine(
      repository: repository,
      provider: provider,
      deviceId: 'test-device',
    );
    workspace = SyncWorkspace(engine: engine, repository: repository);
    await workspace.initialize();
  });

  tearDown(() {
    workspace.dispose();
  });

  test('syncNow exposes the report and refreshes conflict files', () async {
    await repository.create(
      type: ResultType.knowledge,
      title: '同步知识',
      body: '正文',
    );

    await workspace.syncNow();

    expect(workspace.providerName, '本地同步演练');
    expect(workspace.lastReport, isNotNull);
    expect(workspace.lastReport!.uploaded, 1);
    expect(workspace.lastReport!.failed, 0);
    expect(workspace.conflictFiles, isEmpty);
    expect(workspace.errorMessage, isNull);
    expect(workspace.isBusy, isFalse);
  });

  test(
    'resolveConflict uses the remote version and removes the copy',
    () async {
      final local = await repository.create(
        type: ResultType.knowledge,
        title: '原始标题',
        body: '正文',
      );
      await workspace.syncNow();
      final indexed = await repository.findIndexed(local.id);
      await repository.save(local.copyWith(title: '本地标题'));
      await provider.putObject(
        id: local.id,
        path: local.markdownPath,
        contents: codec.encode(local.copyWith(title: '远端标题')),
        etag: indexed!.remoteEtag,
      );

      await workspace.syncNow();

      expect(workspace.lastReport!.conflicts, 1);
      expect(workspace.conflictFiles, hasLength(1));

      await workspace.resolveConflict(
        workspace.conflictFiles.single,
        useRemote: true,
      );

      final resolved = await repository.readDocument(local.id);
      expect(workspace.conflictFiles, isEmpty);
      expect(workspace.errorMessage, isNull);
      expect(resolved!.title, '远端标题');
    },
  );

  test('syncNow keeps busy true until the engine completes', () async {
    final blockingProvider = _BlockingSyncProvider();
    final blockingEngine = SyncEngine(
      repository: repository,
      provider: blockingProvider,
      deviceId: 'test-device',
    );
    final blockingWorkspace = SyncWorkspace(
      engine: blockingEngine,
      repository: repository,
    );
    addTearDown(blockingWorkspace.dispose);
    await blockingWorkspace.initialize();

    final sync = blockingWorkspace.syncNow();
    await blockingProvider.entered.future;

    expect(blockingWorkspace.isBusy, isTrue);

    blockingProvider.release.complete();
    await sync;

    expect(blockingWorkspace.isBusy, isFalse);
  });

  test('syncNow converts a provider failure into errorMessage', () async {
    final failingEngine = SyncEngine(
      repository: repository,
      provider: _FailingSyncProvider(),
      deviceId: 'test-device',
    );
    final failingWorkspace = SyncWorkspace(
      engine: failingEngine,
      repository: repository,
    );
    addTearDown(failingWorkspace.dispose);
    await failingWorkspace.initialize();

    await failingWorkspace.syncNow();

    expect(failingWorkspace.isBusy, isFalse);
    expect(failingWorkspace.errorMessage, contains('network failed'));
    expect(failingWorkspace.lastReport!.failed, 1);
  });
}

class _BlockingSyncProvider extends MemorySyncProvider {
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  String get displayName => '受控同步通道';

  @override
  Future<void> connect() async {
    if (!entered.isCompleted) {
      entered.complete();
    }
    await release.future;
  }
}

class _FailingSyncProvider extends MemorySyncProvider {
  @override
  String get displayName => '故障同步通道';

  @override
  Future<void> connect() async {
    throw StateError('network failed');
  }
}
