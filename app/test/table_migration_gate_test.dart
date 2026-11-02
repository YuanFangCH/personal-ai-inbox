import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/markdown_codec.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/table_migration_service.dart';
import 'package:personal_ai_inbox/data/table_repository.dart';
import 'package:personal_ai_inbox/modules/tables/table_migration_gate.dart';
import 'package:personal_ai_inbox/ui/pages/table_migration_read_only_page.dart';

void main() {
  testWidgets('migration confirms, backs up and cleans sources before restart', (
    tester,
  ) async {
    final vault = MemoryVaultStore();
    await vault.initialize();
    final now = DateTime.parse('2026-10-30T09:00:00+08:00');
    final matter = ResultDocument(
      id: 'matter_gate_confirm',
      type: ResultType.matter,
      title: '待迁移作业',
      status: ResultStatus.canonical,
      originDevice: 'migration-gate-test',
      revision: 1,
      createdAt: now,
      updatedAt: now,
      body: '旧资料正文',
    );
    const codec = MarkdownCodec();
    final oldSource = codec.encode(matter);
    await vault.write(matter.markdownPath, oldSource);

    late final TableMigrationGate gate;
    final service = TableMigrationService(
      vault: vault,
      index: MemoryIndexDatabase(),
      clock: () => now,
      createDatabaseSnapshot: (id) async => 'db-snapshot/$id.json',
      estimateDatabaseSnapshotBytes: () async => 128,
      availableSpaceProbe: (path) async => 1 << 30,
      runWithWriteBarrier: (operation) =>
          gate.runStartupMigrationBarrier(operation),
    );
    gate = TableMigrationGate(service: service);
    await gate.initialize();
    expect(gate.requiresReadOnly, isTrue);
    expect(gate.preview?.canApply, isTrue);
    expect(await vault.read(TableRepository.tablePath(matter.id)), isNull);

    await tester.pumpWidget(
      MaterialApp(home: TableMigrationReadOnlyPage(gate: gate)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('迁移到表格式'));
    await tester.pumpAndSettle();
    expect(find.text('确认迁移旧资料'), findsOneWidget);
    expect(await vault.read(TableRepository.tablePath(matter.id)), isNull);

    await tester.tap(find.text('开始迁移'));
    await tester.pumpAndSettle();

    expect(gate.migrationComplete, isTrue);
    expect(await vault.read(matter.markdownPath), isNull);
    expect(
      await vault.read(
        'vault/.table-migrations/backups/${gate.receipt!.migrationId}/${matter.markdownPath}',
      ),
      oldSource,
    );
    expect(await vault.read(TableRepository.tablePath(matter.id)), isNotNull);
    expect(find.text('迁移副本已生成'), findsOneWidget);
    final restarted = TableMigrationGate(service: service);
    await restarted.initialize();
    expect(restarted.error, isNull);
    expect(restarted.requiresReadOnly, isFalse);
    expect(restarted.migrationComplete, isTrue);
    expect(restarted.preview!.hasLegacyContent, isFalse);
    restarted.dispose();
    gate.dispose();
  });
}
