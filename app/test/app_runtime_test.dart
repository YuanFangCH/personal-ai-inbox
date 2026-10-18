import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/sync_provider.dart';

import 'test_support.dart';

void main() {
  test('bootstraps modules in a temporary memory configuration and shuts down safely', () async {
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(deviceId: 'runtime-test'),
    );
    final created = await runtime.results.createManual(
      type: ResultType.knowledge,
      title: 'Runtime lifecycle',
      body: 'Synthetic content',
    );

    expect(runtime.results.findDocument(created.id), isNotNull);
    await runtime.shutdown();
    await runtime.shutdown();
  });

  test(
    'uses the injected sync provider instead of the sandbox default',
    () async {
      final provider = _RecordingSyncProvider();
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(deviceId: 'runtime-sync'),
        syncProvider: provider,
      );

      await runtime.sync.syncNow();

      expect(provider.connectCalls, 1);
      expect(provider.listCalls, 1);
      await runtime.shutdown();
    },
  );
}

class _RecordingSyncProvider implements SyncProvider {
  int connectCalls = 0;
  int listCalls = 0;

  @override
  String get displayName => 'recording';

  @override
  Future<void> connect() async {
    connectCalls++;
  }

  @override
  Future<List<SyncRemoteObject>> listObjects() async {
    listCalls++;
    return const [];
  }

  @override
  Future<SyncRemoteObject> putObject({
    required String id,
    required String path,
    required String contents,
    required SyncWriteCondition condition,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteObject(String id, String? etag) async {}
}
