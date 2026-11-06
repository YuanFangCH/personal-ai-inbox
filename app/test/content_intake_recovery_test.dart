import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/table_repository.dart';
import 'package:personal_ai_inbox/modules/conversation/content_intake.dart';
import 'package:personal_ai_inbox/modules/tables/table_library.dart';

void main() {
  for (final stage in ['prepared', 'committed']) {
    test('recovers intake when $stage receipt write fails', () async {
      final vault = _FaultVault();
      Future<TableLibrary> open() async {
        final tables = TableLibrary(
          repository: TableRepository(
            vault: vault,
            index: MemoryIndexDatabase(),
          ),
        );
        await tables.initialize();
        return tables;
      }

      final tables = await open();
      final table = await tables.createTable(title: '恢复');
      final request = ContentIntakeRequest(
        operationId: 'fault-op',
        tableId: table.id,
        type: TableContentType.note,
        title: '原内容',
      );
      final intake = ContentIntake(tables: tables);
      final preparation = await intake.prepare(request);
      vault.failPhase = stage;
      await expectLater(intake.commit(preparation), throwsStateError);
      final restartedTables = await open();
      final restarted = ContentIntake(tables: restartedTables);
      final result = await restarted.commit(await restarted.prepare(request));
      expect(result.outcome, ContentIntakeOutcome.created);
      expect(result.replayed, stage == 'committed');
      expect(result.oldRevision, 0);
      expect(result.newRevision, 1);
      expect(restartedTables.entries, hasLength(1));
      expect(restartedTables.entries.single.id, result.entryId);
      final mismatched = ContentIntakeRequest(
        operationId: 'fault-op',
        tableId: table.id,
        type: TableContentType.note,
        title: '不同内容',
      );
      await expectLater(restarted.prepare(mismatched), throwsStateError);
    });
  }

  test(
    'uncertain write preserves journal and refuses automatic replay',
    () async {
      final vault = _FaultVault();
      final tables = TableLibrary(
        repository: TableRepository(vault: vault, index: MemoryIndexDatabase()),
      );
      await tables.initialize();
      final table = await tables.createTable(title: '外部修改');
      final request = ContentIntakeRequest(
        operationId: 'uncertain',
        tableId: table.id,
        type: TableContentType.note,
        title: '原文',
      );
      final intake = ContentIntake(tables: tables);
      final prepared = await intake.prepare(request);
      vault.failPhase = 'committed';
      await expectLater(intake.commit(prepared), throwsStateError);
      await tables.refresh();
      final entry = tables.entries.single;
      await tables.updateEntry(
        entry.copyWith(body: '后来人工编辑'),
        expectedRevision: 1,
      );
      final path = TableRepository.intakeOperationPath('uncertain');
      final before = vault.files[path];
      await expectLater(
        ContentIntake(tables: tables).prepare(request),
        throwsStateError,
      );
      expect(vault.files[path], before);
      expect((await tables.readEntry(entry.id))!.body, '后来人工编辑');
    },
  );
}

class _FaultVault extends MemoryVaultStore {
  String? failPhase;
  @override
  Future<void> write(String relativePath, String contents) async {
    if (relativePath.contains('/intake-operations/') &&
        jsonDecode(contents)['phase'] == failPhase) {
      failPhase = null;
      throw StateError('injected receipt failure');
    }
    await super.write(relativePath, contents);
  }
}
