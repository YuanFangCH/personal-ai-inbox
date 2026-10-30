import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/core/markdown_codec.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/sync_provider.dart';

import 'test_support.dart';

void main() {
  testWidgets(
    'renders the legacy migration gate instead of writable app pages',
    (tester) async {
      final vault = MemoryVaultStore();
      await vault.initialize();
      final now = DateTime.parse('2026-10-30T09:00:00+08:00');
      final matter = ResultDocument(
        id: 'matter_gate_ui',
        type: ResultType.matter,
        title: '只读事项',
        status: ResultStatus.canonical,
        originDevice: 'migration-test',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '不应编辑的旧正文',
      );
      await vault.write(
        matter.markdownPath,
        const MarkdownCodec().encode(matter),
      );
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: vault,
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(deviceId: 'migration-gate-ui'),
      );

      await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
      await tester.pumpAndSettle();

      expect(find.text('旧资料只读预检'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('只读事项'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('只读事项'), findsOneWidget);
      expect(find.text('不应编辑的旧正文'), findsNothing);
      expect(find.byKey(const Key('nav_home')), findsNothing);
      expect(find.text('重新检查'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await runtime.shutdown();
    },
  );

  test(
    'keeps a legacy vault in read-only migration review at startup',
    () async {
      final vault = MemoryVaultStore();
      await vault.initialize();
      final now = DateTime.parse('2026-10-30T09:00:00+08:00');
      final matter = ResultDocument(
        id: 'matter_startup_review',
        type: ResultType.matter,
        title: '待迁移事项',
        status: ResultStatus.canonical,
        originDevice: 'migration-test',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '正文只读展示',
      );
      await vault.write(
        matter.markdownPath,
        const MarkdownCodec().encode(matter),
      );

      final runtime = await AppRuntime.bootstrap(
        vaultOverride: vault,
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(deviceId: 'migration-review'),
      );
      expect(runtime.migrationGate.requiresReadOnly, isTrue);
      expect(runtime.migrationGate.preview?.legacyRecords.single.id, matter.id);
      expect(
        runtime.migrationGate.preview?.legacyRecords.single.body,
        matter.body,
      );
      expect(runtime.results.documents, isEmpty);
      expect(runtime.tables.tables, isEmpty);
      await runtime.shutdown();
    },
  );

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
    expect(runtime.tables.tables, hasLength(3));
    final table = await runtime.tables.createTable(title: '运行时表');
    expect(runtime.tables.findTable(table.id)?.title, '运行时表');
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
