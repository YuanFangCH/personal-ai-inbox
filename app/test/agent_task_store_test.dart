import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/agent_usage.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_task_store.dart';

void main() {
  test('v1 upgrade preserves usage and original snapshot', () async {
    final vault = MemoryVaultStore();
    final store = VaultAgentTaskStore(vault);
    final legacy =
        const AgentTaskCheckpoint(usage: AgentUsage(usedRequests: 19)).toJson()
          ..['schema_version'] = 1
          ..remove('run_usage')
          ..remove('active_run_id');
    final source = jsonEncode(legacy);
    await vault.write(store.relativePath, source);

    final loaded = await store.preflight();

    expect(await vault.read('${store.relativePath}.v1.backup'), source);
    expect(
      jsonDecode((await vault.read(store.relativePath))!)['schema_version'],
      AgentTaskCheckpoint.currentSchemaVersion,
    );
    expect(loaded.usage.usedRequests, 19);
  });

  test('v2 budget exhaustion migrates to usage and requeues paused task', () {
    final checkpoint = AgentTaskCheckpoint.fromJson({
      'schema_version': 2,
      'budget': {
        'used_requests': 240,
        'used_active_ms': 1000,
        'granted_requests': 240,
        'granted_active_ms': 2000,
      },
      'run_budgets': {
        'run_a': {
          'used_requests': 240,
          'used_active_ms': 1000,
          'granted_requests': 240,
          'granted_active_ms': 2000,
        },
      },
      'active_budget_run_id': 'run_a',
      'turns': [
        {
          'task_id': 'task',
          'budget_run_id': 'run_a',
          'conversation_id': 'conversation',
          'user_message_id': 'user',
          'kind': 'conversation',
          'status': 'paused',
          'sequence': 0,
        },
      ],
    });

    expect(checkpoint.usage.usedRequests, 240);
    expect(checkpoint.runUsage['run_a']!.usedRequests, 240);
    expect(checkpoint.turns.single.status, AgentTurnCheckpointStatus.queued);
    expect(checkpoint.turns.single.effectiveRunId, 'run_a');
  });

  test('v3 round-trips usage-only state', () {
    final checkpoint = AgentTaskCheckpoint(
      usage: const AgentUsage(
        usedRequests: 7,
        usedActiveMillis: 3000,
        usedToolCalls: 5,
      ),
      activeRunId: 'run_a',
      runUsage: const {
        'run_a': AgentUsage(usedRequests: 7, usedToolCalls: 5),
        'run_b': AgentUsage(usedRequests: 2),
      },
    );

    final decoded = AgentTaskCheckpoint.fromJson(checkpoint.toJson());

    expect(decoded.usage.usedRequests, 7);
    expect(decoded.usage.usedToolCalls, 5);
    expect(decoded.activeRunId, 'run_a');
    expect(decoded.runUsage['run_b']!.usedRequests, 2);
  });

  test('preflight preserves unsupported schema and status bytes', () async {
    final vault = MemoryVaultStore();
    final store = VaultAgentTaskStore(vault);
    const unsupportedSchema = '{"schema_version":99,"opaque":"keep"}';
    await vault.write(store.relativePath, unsupportedSchema);
    await expectLater(store.preflight(), throwsFormatException);
    expect(await vault.read(store.relativePath), unsupportedSchema);

    final unsupportedStatus = jsonEncode({
      'schema_version': 3,
      'usage': const AgentUsage().toJson(),
      'run_usage': const <String, Object?>{},
      'turns': [
        {
          'task_id': 'task',
          'run_id': 'task',
          'conversation_id': 'conversation',
          'user_message_id': 'user',
          'kind': 'conversation',
          'status': 'future_status',
          'sequence': 0,
        },
      ],
    });
    await vault.write(store.relativePath, unsupportedStatus);
    await expectLater(store.preflight(), throwsFormatException);
    expect(await vault.read(store.relativePath), unsupportedStatus);
  });

  test('missing primary with a legacy backup fails closed', () async {
    final vault = MemoryVaultStore();
    final store = VaultAgentTaskStore(vault);
    const source = '{"schema_version":1,"turns":[]}';
    await vault.write('${store.relativePath}.v1.backup', source);

    await expectLater(store.preflight(), throwsStateError);
    await expectLater(store.load(), throwsStateError);
    await expectLater(
      store.save(const AgentTaskCheckpoint()),
      throwsStateError,
    );
    expect(await vault.read('${store.relativePath}.v1.backup'), source);
  });

  test('missing primary with a temporary write fails closed', () async {
    final vault = MemoryVaultStore();
    final store = VaultAgentTaskStore(vault);
    const partialWrite = '{"schema_version":3,"turns":';
    await vault.write('${store.relativePath}.tmp', partialWrite);

    await expectLater(store.preflight(), throwsStateError);
    await expectLater(store.load(), throwsStateError);
    expect(await vault.read('${store.relativePath}.tmp'), partialWrite);
  });

  test('existing primary remains authoritative when sidecars exist', () async {
    final vault = MemoryVaultStore();
    final store = VaultAgentTaskStore(vault);
    final primary = jsonEncode(
      const AgentTaskCheckpoint(usage: AgentUsage(usedRequests: 8)).toJson(),
    );
    const temporary = '{"schema_version":3,"partial":"newer?"}';
    await vault.write(store.relativePath, primary);
    await vault.write('${store.relativePath}.tmp', temporary);

    final checkpoint = await store.preflight();

    expect(checkpoint.usage.usedRequests, 8);
    expect(await vault.read(store.relativePath), primary);
    expect(await vault.read('${store.relativePath}.tmp'), temporary);
  });

  test('upgrade refuses a backup with different source bytes', () async {
    final vault = MemoryVaultStore();
    final store = VaultAgentTaskStore(vault);
    final source = jsonEncode(
      const AgentTaskCheckpoint(usage: AgentUsage(usedRequests: 17)).toJson()
        ..['schema_version'] = 1,
    );
    final olderBackup = jsonEncode(
      const AgentTaskCheckpoint(usage: AgentUsage(usedRequests: 5)).toJson()
        ..['schema_version'] = 1,
    );
    await vault.write(store.relativePath, source);
    await vault.write('${store.relativePath}.v1.backup', olderBackup);

    await expectLater(store.preflight(), throwsStateError);
    expect(await vault.read(store.relativePath), source);
    expect(await vault.read('${store.relativePath}.v1.backup'), olderBackup);
  });

  test('failed upgrade restores source bytes and retains backup', () async {
    final legacy = const AgentTaskCheckpoint().toJson()
      ..['schema_version'] = 1
      ..remove('run_usage')
      ..remove('active_run_id');
    final source = jsonEncode(legacy);
    final vault = _FailingCheckpointUpgradeVault(
      checkpointPath: AgentTaskCheckpoint.storagePath,
      originalSource: source,
    );
    final store = VaultAgentTaskStore(vault);
    await vault.write(store.relativePath, source);

    await expectLater(store.preflight(), throwsStateError);

    expect(await vault.read(store.relativePath), source);
    expect(await vault.read('${store.relativePath}.v1.backup'), source);
  });
}

class _FailingCheckpointUpgradeVault extends MemoryVaultStore {
  _FailingCheckpointUpgradeVault({
    required this.checkpointPath,
    required this.originalSource,
  });

  final String checkpointPath;
  final String originalSource;

  @override
  Future<void> write(String relativePath, String contents) async {
    if (relativePath == checkpointPath && contents != originalSource) {
      throw StateError('simulated checkpoint replacement failure');
    }
    await super.write(relativePath, contents);
  }
}
