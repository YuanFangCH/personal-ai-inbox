import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/markdown_codec.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/core/table_markdown_codec.dart';
import 'package:personal_ai_inbox/data/disk_space_probe.dart';
import 'package:personal_ai_inbox/data/io_vault_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/settings_service.dart';
import 'package:personal_ai_inbox/data/sqlite_migration_coordinator.dart';
import 'package:personal_ai_inbox/data/table_migration_service.dart';
import 'package:personal_ai_inbox/data/table_repository.dart';
import 'package:personal_ai_inbox/modules/tables/table_migration_gate.dart';
import 'package:personal_ai_inbox/ui/pages/table_migration_read_only_page.dart';
import 'package:sqlite3/sqlite3.dart';

import '../test/test_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('legacy documents open in a read-only migration gate', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('table-migration-gate');
    addTearDown(() => root.delete(recursive: true));
    final vault = IoVaultStore.at(root);
    await vault.initialize();
    final now = DateTime.now();
    final legacy = ResultDocument(
      id: 'matter_android_gate',
      type: ResultType.matter,
      title: 'AVD 只读迁移样例',
      status: ResultStatus.canonical,
      originDevice: 'android-migration-test',
      revision: 1,
      createdAt: now,
      updatedAt: now,
      body: '此内容只在合成测试 vault 中。',
    );
    final codec = const MarkdownCodec();
    final source = codec.encode(legacy);
    await vault.write(legacy.markdownPath, source);

    final runtime = await AppRuntime.bootstrap(
      vaultOverride: vault,
      indexOverride: MemoryIndexDatabase(),
      conversationStoreOverride: MemoryConversationStore(),
      attachmentStoreOverride: MemoryAttachmentStore(),
      settingsOverride: FakeSettingsService(deviceId: 'android-migration-test'),
    );
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();

    expect(runtime.migrationGate.requiresReadOnly, isTrue);
    expect(find.text('旧资料只读预检'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('AVD 只读迁移样例'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('AVD 只读迁移样例'), findsOneWidget);
    expect(find.byKey(const Key('nav_home')), findsNothing);
    expect(await vault.read(legacy.markdownPath), source);

    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });

  testWidgets(
    'migration applies only after confirmation and preserves source',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'table-migration-confirmed',
      );
      addTearDown(() => root.delete(recursive: true));
      final vault = IoVaultStore.at(root);
      await vault.initialize();
      final now = DateTime.now();
      final legacy = ResultDocument(
        id: 'matter_android_confirm',
        type: ResultType.matter,
        title: 'AVD 确认迁移样例',
        status: ResultStatus.canonical,
        originDevice: 'android-migration-test',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '迁移后旧正文仍保留。',
      );
      const legacyCodec = MarkdownCodec();
      const tableCodec = TableMarkdownCodec();
      final source = legacyCodec.encode(legacy);
      await vault.write(legacy.markdownPath, source);

      late final TableMigrationGate gate;
      final service = TableMigrationService(
        vault: vault,
        index: MemoryIndexDatabase(),
        createDatabaseSnapshot: (migrationId) async =>
            'synthetic-database-snapshot/$migrationId.json',
        estimateDatabaseSnapshotBytes: () async => 64,
        availableSpaceProbe: availableBytesForPath,
        runWithWriteBarrier: (operation) =>
            gate.runStartupMigrationBarrier(operation),
      );
      gate = TableMigrationGate(service: service);
      addTearDown(gate.dispose);
      await gate.initialize();
      expect(gate.preview?.canApply, isTrue);
      expect(await vault.read(TableRepository.tablePath(legacy.id)), isNull);

      await tester.pumpWidget(
        MaterialApp(home: TableMigrationReadOnlyPage(gate: gate)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('迁移到表格式'));
      await tester.pumpAndSettle();
      expect(find.text('确认迁移旧资料'), findsOneWidget);
      expect(await vault.read(TableRepository.tablePath(legacy.id)), isNull);

      await tester.tap(find.text('开始迁移'));
      await tester.pumpAndSettle();

      expect(gate.migrationComplete, isTrue);
      expect(await vault.read(legacy.markdownPath), source);
      final migratedTable = tableCodec.decodeTable(
        (await vault.read(TableRepository.tablePath(legacy.id)))!,
      );
      expect(migratedTable.body, legacy.body);
      expect(find.text('迁移副本已生成'), findsOneWidget);
    },
  );

  testWidgets('runtime migration activates tables and reopens after restart', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp(
      'table-runtime-migration',
    );
    addTearDown(() => root.delete(recursive: true));
    final vaultRoot = Directory('${root.path}/vault');
    final supportRoot = Directory('${root.path}/support');
    await vaultRoot.create();
    await supportRoot.create();
    _createDatabase('${supportRoot.path}/index.sqlite3', 9, 'index_seed');
    _createDatabase(
      '${supportRoot.path}/conversations.sqlite3',
      5,
      'chat_seed',
    );
    final vault = IoVaultStore.at(vaultRoot);
    await vault.initialize();
    final now = DateTime.now();
    final matter = ResultDocument(
      id: 'matter_runtime_migration',
      type: ResultType.matter,
      title: 'AVD 作业表',
      status: ResultStatus.canonical,
      originDevice: 'runtime-migration-test',
      revision: 1,
      createdAt: now,
      updatedAt: now,
      body: '课程项目正文',
    );
    final todo = ResultDocument(
      id: 'todo_runtime_migration',
      type: ResultType.todo,
      title: '提交实验报告',
      status: ResultStatus.canonical,
      originDevice: 'runtime-migration-test',
      revision: 1,
      createdAt: now,
      updatedAt: now,
      body: '第 4 章实验',
      matterId: matter.id,
    );
    const codec = MarkdownCodec();
    final matterSource = codec.encode(matter);
    final todoSource = codec.encode(todo);
    await vault.write(matter.markdownPath, matterSource);
    await vault.write(todo.markdownPath, todoSource);
    final migration = SqliteMigrationCoordinator(
      supportPath: supportRoot.path,
      settings: _SnapshotSettings(),
    );

    Future<AppRuntime> bootstrap() => AppRuntime.bootstrap(
      vaultOverride: vault,
      indexOverride: MemoryIndexDatabase(),
      conversationStoreOverride: MemoryConversationStore(),
      attachmentStoreOverride: MemoryAttachmentStore(),
      settingsOverride: FakeSettingsService(deviceId: 'runtime-migration-test'),
      migrationCoordinatorOverride: migration,
    );

    final runtime = await bootstrap();
    expect(runtime.migrationGate.requiresReadOnly, isTrue);
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.text('迁移到表格式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始迁移'));
    await tester.pumpAndSettle();

    expect(runtime.migrationGate.migrationComplete, isTrue);
    expect(runtime.tables.findTable(matter.id)?.body, matter.body);
    expect(runtime.tables.entries.single.title, todo.title);
    expect(await vault.read(matter.markdownPath), matterSource);
    expect(await vault.read(todo.markdownPath), todoSource);
    expect(find.text('AVD 作业表'), findsWidgets);
    await tester.tap(find.text('AVD 作业表').first);
    await tester.pumpAndSettle();
    expect(find.text('课程项目正文'), findsOneWidget);
    expect(find.text('提交实验报告'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();

    final restarted = await bootstrap();
    expect(restarted.migrationGate.migrationComplete, isTrue);
    expect(restarted.tables.findTable(matter.id)?.body, matter.body);
    expect(restarted.tables.entries.single.title, todo.title);
    await restarted.shutdown();
  });
}

void _createDatabase(String path, int version, String table) {
  final database = sqlite3.open(path)
    ..execute('CREATE TABLE $table (value TEXT NOT NULL)')
    ..execute('INSERT INTO $table (value) VALUES (?)', ['fixture'])
    ..execute('PRAGMA user_version = $version');
  database.close();
}

class _SnapshotSettings extends SettingsService {
  @override
  Future<Map<String, Object?>> exportMigrationPreferences() async => const {
    'device_id': 'runtime-migration-test',
  };

  @override
  Future<void> restoreMigrationPreferences(Map<String, dynamic> values) async {}
}
