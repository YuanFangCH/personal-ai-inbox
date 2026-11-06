import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_task_store.dart';

void main() {
  test('upgrade preserves original v1 snapshot and refuses corrupt state', () async {
    final vault = MemoryVaultStore();
    final store = VaultAgentTaskStore(vault);
    final legacy = const AgentTaskCheckpoint(
      budget: AgentBudgetCheckpoint(usedRequests: 19),
    ).toJson()..['schema_version'] = 1;
    final source = jsonEncode(legacy);
    await vault.write(store.relativePath, source);
    final loaded = await store.load();
    await store.save(loaded);
    expect(await vault.read('${store.relativePath}.v1.backup'), source);
    expect(jsonDecode((await vault.read(store.relativePath))!)['schema_version'], 2);
    await vault.write(store.relativePath, '{invalid');
    await expectLater(store.save(loaded), throwsFormatException);
    expect(await vault.read(store.relativePath), '{invalid');
    expect(await vault.read('${store.relativePath}.v1.backup'), source);
  });

  test('startup preflight upgrades v1 and preserves task identifiers and budget', () async {
    final vault = MemoryVaultStore();
    final store = VaultAgentTaskStore(vault);
    final legacy = AgentTaskCheckpoint(
      budget: const AgentBudgetCheckpoint(
        usedRequests: 19,
        usedActiveMillis: 1234,
        grantedRequests: 240,
      ),
      turns: const [
        AgentTurnCheckpoint(
          taskId: 'task-v1',
          conversationId: 'conversation-v1',
          userMessageId: 'user-v1',
          assistantMessageId: 'assistant-v1',
          kind: AgentTurnQueueKind.conversation,
          status: AgentTurnCheckpointStatus.running,
          sequence: 7,
        ),
      ],
    ).toJson();
    legacy['schema_version'] = 1;
    legacy.remove('run_budgets');
    legacy.remove('active_budget_run_id');
    ((legacy['turns'] as List).single as Map).remove('budget_run_id');
    final source = jsonEncode(legacy);
    await vault.write(store.relativePath, source);

    final checkpoint = await store.preflight();

    expect(await vault.read('${store.relativePath}.v1.backup'), source);
    expect(
      jsonDecode((await vault.read(store.relativePath))!)['schema_version'],
      2,
    );
    expect(checkpoint.turns.single.taskId, 'task-v1');
    expect(checkpoint.turns.single.assistantMessageId, 'assistant-v1');
    expect(checkpoint.turns.single.effectiveBudgetRunId, 'legacy');
    expect(checkpoint.runBudgets['legacy']!.usedRequests, 19);
    expect(checkpoint.runBudgets['legacy']!.usedActiveMillis, 1234);
    expect(await store.load(), checkpoint);
  });

  test('preflight preserves unsupported schema and status bytes', () async {
    final vault = MemoryVaultStore();
    final store = VaultAgentTaskStore(vault);
    const unsupportedSchema = '{"schema_version":99,"opaque":"keep"}';
    await vault.write(store.relativePath, unsupportedSchema);

    await expectLater(store.preflight(), throwsFormatException);

    expect(await vault.read(store.relativePath), unsupportedSchema);
    expect(await vault.read('${store.relativePath}.v1.backup'), isNull);

    final unsupportedStatus = jsonEncode({
      'schema_version': 2,
      'budget': const AgentBudgetCheckpoint().toJson(),
      'run_budgets': const <String, Object?>{},
      'turns': [
        {
          'task_id': 'unknown-status-task',
          'budget_run_id': 'unknown-status-task',
          'conversation_id': 'conversation',
          'user_message_id': 'user',
          'kind': 'conversation',
          'status': 'future_status',
          'sequence': 0,
          'thinking_enabled': false,
          'excluded_message_ids': const <String>[],
        },
      ],
    });
    await vault.write(store.relativePath, unsupportedStatus);

    await expectLater(store.preflight(), throwsFormatException);

    expect(await vault.read(store.relativePath), unsupportedStatus);
    expect(await vault.read('${store.relativePath}.v1.backup'), isNull);
  });

  test('missing primary with a legacy backup fails closed without losing it', () async {
    final vault = MemoryVaultStore();
    final store = VaultAgentTaskStore(vault);
    final legacy = AgentTaskCheckpoint(
      budget: const AgentBudgetCheckpoint(usedRequests: 17),
      turns: const [
        AgentTurnCheckpoint(
          taskId: 'task-in-backup',
          conversationId: 'conversation-in-backup',
          userMessageId: 'user-in-backup',
          assistantMessageId: 'assistant-in-backup',
          kind: AgentTurnQueueKind.conversation,
          status: AgentTurnCheckpointStatus.paused,
          sequence: 4,
        ),
      ],
    ).toJson();
    legacy['schema_version'] = 1;
    legacy.remove('run_budgets');
    legacy.remove('active_budget_run_id');
    ((legacy['turns'] as List).single as Map).remove('budget_run_id');
    final source = jsonEncode(legacy);
    await vault.write('${store.relativePath}.v1.backup', source);

    await expectLater(store.preflight(), throwsStateError);
    await expectLater(store.load(), throwsStateError);
    await expectLater(store.save(const AgentTaskCheckpoint()), throwsStateError);

    expect(await vault.read(store.relativePath), isNull);
    expect(await vault.read('${store.relativePath}.v1.backup'), source);
  });

  test('missing primary with a temporary write fails closed and preserves it', () async {
    final vault = MemoryVaultStore();
    final store = VaultAgentTaskStore(vault);
    const partialWrite = '{"schema_version":2,"turns":';
    await vault.write('${store.relativePath}.tmp', partialWrite);

    await expectLater(store.preflight(), throwsStateError);
    await expectLater(store.load(), throwsStateError);

    expect(await vault.read(store.relativePath), isNull);
    expect(await vault.read('${store.relativePath}.tmp'), partialWrite);
    expect(await vault.read('${store.relativePath}.v1.backup'), isNull);
  });

  test('missing primary with a migration restore file fails closed', () async {
    final vault = MemoryVaultStore();
    final store = VaultAgentTaskStore(vault);
    const restoreBytes = '{"schema_version":1,"restore":"pending"}';
    await vault.write('${store.relativePath}.restore.tmp', restoreBytes);

    await expectLater(store.preflight(), throwsStateError);
    await expectLater(store.load(), throwsStateError);

    expect(await vault.read(store.relativePath), isNull);
    expect(await vault.read('${store.relativePath}.restore.tmp'), restoreBytes);
  });

  test('existing primary remains authoritative when sidecars are present', () async {
    final vault = MemoryVaultStore();
    final store = VaultAgentTaskStore(vault);
    final primary = jsonEncode(
      const AgentTaskCheckpoint(
        budget: AgentBudgetCheckpoint(usedRequests: 8),
      ).toJson(),
    );
    const temporary = '{"schema_version":2,"partial":"newer?"}';
    await vault.write(store.relativePath, primary);
    await vault.write('${store.relativePath}.tmp', temporary);

    final checkpoint = await store.preflight();

    expect(checkpoint.budget.usedRequests, 8);
    expect(await vault.read(store.relativePath), primary);
    expect(await vault.read('${store.relativePath}.tmp'), temporary);
  });

  test('v1 upgrade refuses a backup with different source bytes', () async {
    final vault = MemoryVaultStore();
    final store = VaultAgentTaskStore(vault);
    final legacy = const AgentTaskCheckpoint(
      budget: AgentBudgetCheckpoint(usedRequests: 17),
    ).toJson()..['schema_version'] = 1;
    final source = jsonEncode(legacy);
    final older = const AgentTaskCheckpoint(
      budget: AgentBudgetCheckpoint(usedRequests: 5),
    ).toJson()..['schema_version'] = 1;
    final olderBackup = jsonEncode(older);
    await vault.write(store.relativePath, source);
    await vault.write('${store.relativePath}.v1.backup', olderBackup);

    await expectLater(store.preflight(), throwsStateError);
    await expectLater(
      store.save(const AgentTaskCheckpoint()),
      throwsStateError,
    );

    expect(await vault.read(store.relativePath), source);
    expect(await vault.read('${store.relativePath}.v1.backup'), olderBackup);
  });

  test('failed v1 upgrade restores source bytes and retains backup', () async {
    final legacy = const AgentTaskCheckpoint().toJson()
      ..['schema_version'] = 1
      ..remove('run_budgets')
      ..remove('active_budget_run_id');
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
  test('v2 preserves independent budgets and rejects missing references', () {
    final checkpoint = AgentTaskCheckpoint(
      budget: const AgentBudgetCheckpoint(usedRequests: 7),
      activeBudgetRunId: 'run_a',
      runBudgets: const {
        'run_a': AgentBudgetCheckpoint(usedRequests: 7),
        'run_b': AgentBudgetCheckpoint(usedRequests: 2),
      },
    );
    final decoded = AgentTaskCheckpoint.fromJson(checkpoint.toJson());
    expect(decoded.activeBudgetRunId, 'run_a');
    expect(decoded.runBudgets['run_a']!.usedRequests, 7);
    expect(decoded.runBudgets['run_b']!.usedRequests, 2);
    expect(
      () => AgentTaskCheckpoint.fromJson({
        ...checkpoint.toJson(),
        'active_budget_run_id': 'missing',
      }),
      throwsFormatException,
    );
  });

  test('v1 queued tasks retain their shared cumulative budget', () {
    final legacy = AgentTaskCheckpoint(
      budget: const AgentBudgetCheckpoint(usedRequests: 17),
      turns: const [
        AgentTurnCheckpoint(
          taskId: 'task',
          conversationId: 'conversation',
          userMessageId: 'message',
          kind: AgentTurnQueueKind.conversation,
          status: AgentTurnCheckpointStatus.running,
          sequence: 0,
        ),
      ],
    ).toJson();
    legacy['schema_version'] = 1;
    final decoded = AgentTaskCheckpoint.fromJson(legacy);
    expect(decoded.turns.single.effectiveBudgetRunId, 'legacy');
    expect(decoded.runBudgets['legacy']!.usedRequests, 17);
    expect(
      AgentTaskCheckpoint.fromJson(decoded.toJson())
          .runBudgets['legacy']!
          .usedRequests,
      17,
    );
  });
  test('budget checkpoint preserves valid overage and clamps remaining', () {
    final checkpoint = AgentTaskCheckpoint.fromJson({
      'schema_version': 1,
      'budget': {
        'used_requests': 241,
        'used_active_ms': const Duration(hours: 2).inMilliseconds + 1500,
        'granted_requests': 240,
        'granted_active_ms': const Duration(hours: 2).inMilliseconds,
      },
      'turns': const [],
    });

    expect(checkpoint.budget.usedRequests, 241);
    expect(
      checkpoint.budget.usedActiveMillis,
      const Duration(hours: 2).inMilliseconds + 1500,
    );
    expect(checkpoint.budget.remainingRequests, 0);
    expect(checkpoint.budget.remainingActive, Duration.zero);
    expect(checkpoint.budget.exhausted, isTrue);
    expect(checkpoint.toJson()['budget'], containsPair('used_requests', 241));
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
