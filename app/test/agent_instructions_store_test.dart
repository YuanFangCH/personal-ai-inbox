import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/agent_instructions.dart';
import 'package:personal_ai_inbox/data/agent_instructions_store.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';

void main() {
  late MemoryVaultStore vault;
  late AgentInstructionsStore store;
  var now = DateTime.utc(2026, 11, 17);

  setUp(() {
    vault = MemoryVaultStore();
    store = AgentInstructionsStore(vault, clock: () => now);
  });

  test('only direct durable-rule requests authorize instruction tools', () {
    expect(requestsInstructionEdit('以后会下雨吗？'), isFalse);
    expect(requestsInstructionEdit('修改 AGENTS.md 吗？'), isFalse);
    expect(requestsInstructionEdit('以后请用简体中文回答。'), isTrue);
    expect(requestsInstructionEdit('从今以后记住我不吃香菜。'), isTrue);
    expect(requestsInstructionEdit('请修改 AGENTS.md：默认用简体中文。'), isTrue);
  });

  test('saves, retries idempotently, and undoes by revision', () async {
    final applied = await store.edit(
      operationId: 'op-1',
      expectedRevision: 'missing',
      edits: const [(oldText: null, newText: '长期规则')],
      canCommit: () async => true,
    );
    expect(applied.status, InstructionWriteStatus.applied);
    final retry = await store.edit(
      operationId: 'op-1',
      expectedRevision: 'missing',
      edits: const [(oldText: null, newText: '长期规则')],
      canCommit: () async => false,
    );
    expect(retry.status, InstructionWriteStatus.applied);
    final undone = await store.undo(
      operationId: 'op-1',
      expectedRevision: applied.revision!,
    );
    expect(undone.status, InstructionWriteStatus.applied);
    expect(vault.files[AgentInstructionsStore.path], isNull);
  });

  test('rejects stale or ambiguous edits without changing content', () async {
    await store.save(expectedRevision: 'missing', markdown: '甲\n甲');
    final current = await store.load() as InstructionsReady;
    final stale = await store.edit(
      operationId: 'stale',
      expectedRevision: 'missing',
      edits: const [(oldText: '甲', newText: '乙')],
      canCommit: () async => true,
    );
    expect(stale.status, InstructionWriteStatus.conflict);
    final ambiguous = await store.edit(
      operationId: 'ambiguous',
      expectedRevision: current.snapshot.revision,
      edits: const [(oldText: '甲', newText: '乙')],
      canCommit: () async => true,
    );
    expect(ambiguous.status, InstructionWriteStatus.conflict);
    expect(vault.files[AgentInstructionsStore.path], '甲\n甲');
  });

  test(
    'rejects empty matches and non-final or repeated append edits',
    () async {
      final saved = await store.save(
        expectedRevision: 'missing',
        markdown: '原文',
      );
      final edits = [
        const [
          (oldText: null, newText: '追加一'),
          (oldText: null, newText: '追加二'),
        ],
        const [(oldText: null, newText: '先追加'), (oldText: '原文', newText: '改写')],
        const [(oldText: '', newText: '不能匹配空原文')],
      ];
      for (var i = 0; i < edits.length; i++) {
        final result = await store.edit(
          operationId: 'invalid-edit-$i',
          expectedRevision: saved.revision!,
          edits: edits[i],
          canCommit: () async => true,
        );
        expect(result.status, InstructionWriteStatus.conflict);
      }
      expect(vault.files[AgentInstructionsStore.path], '原文');
    },
  );

  test(
    'rechecks authorization immediately before replacing the file',
    () async {
      var checks = 0;
      final result = await store.edit(
        operationId: 'revoked-during-turn',
        expectedRevision: 'missing',
        edits: const [(oldText: null, newText: '不得写入')],
        canCommit: () async => ++checks == 1,
      );
      expect(result.status, InstructionWriteStatus.rejected);
      expect(result.code, 'not_authorized');
      expect(vault.files[AgentInstructionsStore.path], isNull);
    },
  );

  test('does not undo after another instruction write', () async {
    final first = await store.save(
      expectedRevision: 'missing',
      markdown: '第一条',
    );
    await store.save(expectedRevision: first.revision!, markdown: '第二条');
    final result = await store.undo(
      operationId: first.operationId!,
      expectedRevision: first.revision!,
    );
    expect(result.status, InstructionWriteStatus.conflict);
    expect(vault.files[AgentInstructionsStore.path], '第二条');
  });

  test('expires undo after ten minutes', () async {
    final result = await store.save(
      expectedRevision: 'missing',
      markdown: '规则',
    );
    now = now.add(const Duration(minutes: 11));
    final undo = await store.undo(
      operationId: result.operationId!,
      expectedRevision: result.revision!,
    );
    expect(undo.status, InstructionWriteStatus.rejected);
  });
}
