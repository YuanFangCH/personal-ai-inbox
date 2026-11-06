import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/core/ai_policy.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/data/table_repository.dart';
import 'package:personal_ai_inbox/modules/capture/capture_workflow.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_background_control.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_task_store.dart';
import 'package:personal_ai_inbox/modules/conversation/auto_record_processor.dart';
import 'package:personal_ai_inbox/modules/conversation/content_duplicate_policy.dart';
import 'package:personal_ai_inbox/modules/conversation/conversation_workspace.dart';
import 'package:personal_ai_inbox/modules/conversation/table_action_processor.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';
import 'package:personal_ai_inbox/modules/tables/table_library.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';
import 'package:personal_ai_inbox/services/chat_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'test_support.dart';

void main() {
  test('authorization guard rejection keeps the same retry id pending without a terminal receipt', () async {
    final harness = await _RetryHarness.create();
    addTearDown(harness.close);
    await harness.workspace.sendChatMessage(
      harness.conversation.id,
      text: '接收归档编号 ACME-778 的记录',
    );
    var assistant = harness.workspace
        .messagesFor(harness.conversation.id)
        .singleWhere((message) => message.role == ChatRole.assistant);
    var action = assistant.tableActions.single;
    final task = harness.taskStore.checkpoint.turns.singleWhere(
      (turn) => turn.assistantMessageId == assistant.id,
    );
    await harness.workspace.addTaskBudget(
      taskId: task.taskId,
      additionalRequests: 2,
    );
    harness.source.incompleteThrough = 1;
    harness.revokePolicyAtGuard = true;
    await harness.workspace.retryIncompleteIntakeAction(action.id);

    assistant = (await harness.chats.findMessage(assistant.id))!;
    action = assistant.tableActions.single;
    final retryId = action.intakeRetryOperationId;
    expect(retryId, 'intake-retry:${action.id}:1');
    expect(action.intakeRetryPending, isTrue, reason: '${action.toJson()}');
    expect(action.status, TableChatActionStatus.pendingRetry);
    expect(action.message, contains('操作编号尚未结算'));
    expect(harness.source.calls, 2);
    expect(harness.tables.entries, hasLength(1));

    harness.revokePolicyAtGuard = false;
    await harness.workspace.retryIncompleteIntakeAction(action.id);
    await harness.backend.waitForRequests(3);
    assistant = (await harness.chats.findMessage(assistant.id))!;
    action = assistant.tableActions.single;
    expect(action.status, TableChatActionStatus.applied);
    expect(action.intakeRetryOperationId, retryId);
    expect(harness.source.calls, 2);
    expect(harness.tables.entries, hasLength(1));
    expect((await harness.tables.readEntry(action.entryId!))?.revision, 2);
    await _waitFor(() => harness.taskStore.checkpoint.turns.isEmpty);
    expect(action.entryId, isNotNull);
  });

  test('incomplete intake retry persists across restart and uses a fresh id after a second conflict', () async {
    final harness = await _RetryHarness.create();
    addTearDown(harness.close);
    final sending = harness.workspace.sendChatMessage(
      harness.conversation.id,
      text: '接收归档编号 ACME-778 的记录',
    );
    await sending.timeout(const Duration(seconds: 5));

    var assistant = harness.workspace
        .messagesFor(harness.conversation.id)
        .singleWhere((message) => message.role == ChatRole.assistant);
    var action = assistant.tableActions.single;
    expect(action.retryableIntake, isTrue);
    expect(action.intakeCoverageChecked, 0);
    expect(action.intakeCoverageTotal, 1);
    expect(action.message, contains('原始接收内容已保留'));
    expect(harness.source.calls, 1);
    expect(harness.tables.entries, hasLength(1));
    var generation = await harness.chats.findGeneration(assistant.id);
    expect(
      generation?.toolCalls.single['completed_action_json'],
      contains('0'),
    );
    expect(
      assistant.toolTranscript.last['content'],
      contains('"status":"conflict"'),
    );

    await harness.chats.setAiPolicy(
      harness.conversation.id,
      AiPolicy.forPreset(AiPolicyPreset.readOnly),
    );
    await harness.workspace.retryIncompleteIntakeAction(action.id);
    assistant = (await harness.chats.findMessage(assistant.id))!;
    action = assistant.tableActions.single;
    final persistedRetryId = action.intakeRetryOperationId;
    expect(persistedRetryId, 'intake-retry:${action.id}:1');
    expect(action.intakeRetryPending, isTrue);
    expect(action.message, contains('权限尚未允许'));
    expect(harness.source.calls, 1, reason: 'denied retry must not scan');

    await harness.chats.setAiPolicy(harness.conversation.id, _writePolicy());
    await harness.workspace.retryIncompleteIntakeAction(action.id);
    assistant = (await harness.chats.findMessage(assistant.id))!;
    action = assistant.tableActions.single;
    expect(action.intakeRetryOperationId, persistedRetryId);
    expect(action.intakeRetryPending, isTrue);
    expect(action.message, contains('预算不足'));
    expect(harness.source.calls, 1, reason: 'exhausted retry must not scan');
    final pendingAssistantId = assistant.id;
    final task = harness.taskStore.checkpoint.turns.singleWhere(
      (turn) => turn.assistantMessageId == pendingAssistantId,
    );
    await harness.workspace.addTaskBudget(
      taskId: task.taskId,
      additionalRequests: 2,
    );

    await harness.workspace.shutdown();
    await harness.chats.setAiPolicy(harness.conversation.id, _writePolicy());
    await harness.reboot();
    assistant = (await harness.chats.findMessage(pendingAssistantId))!;
    action = assistant.tableActions.single;
    expect(action.intakeRetryPending, isTrue);
    expect(action.intakeRetryOperationId, persistedRetryId);

    await harness.workspace.retryIncompleteIntakeAction(action.id);
    assistant = (await harness.chats.findMessage(assistant.id))!;
    action = assistant.tableActions.single;
    expect(harness.source.calls, 2);
    expect(action.retryableIntake, isTrue);
    expect(action.intakeRetryPending, isFalse);
    expect(action.intakeRetryOperationId, persistedRetryId);
    expect(action.intakeCoverageChecked, 0);
    expect(action.intakeCoverageTotal, 1);
    expect(action.message, contains('仍有 1 个未检查'));
    expect(harness.tables.entries, hasLength(1));

    await harness.workspace.retryIncompleteIntakeAction(action.id);
    await harness.backend.waitForRequests(3);
    assistant = (await harness.chats.findMessage(assistant.id))!;
    action = assistant.tableActions.single;
    expect(harness.source.calls, 3);
    expect(action.status, TableChatActionStatus.applied);
    expect(action.retryableIntake, isFalse);
    expect(action.intakeRetryOperationId, 'intake-retry:${action.id}:2');
    expect(action.entryId, isNotNull);
    final entry = await harness.tables.readEntry(action.entryId!);
    expect(entry?.revision, 2);
    expect(entry?.body, contains('ACME-778'));
    expect(
      assistant.toolTranscript.last['content'],
      contains('"status":"succeeded"'),
    );

    await harness.backend.respond(2, '重扫完成，已补充原记录。');
    await _waitFor(
      () =>
          harness.workspace.taskStore is MemoryAgentTaskStore &&
          (harness.workspace.taskStore as MemoryAgentTaskStore)
              .checkpoint
              .turns
              .isEmpty,
    );
    generation = await harness.chats.findGeneration(assistant.id);
    expect(
      generation?.toolCalls.single['completed_action_json'],
      contains('applied'),
    );
    expect(harness.tables.entries, hasLength(1));
  });

  test(
    'restart reconciles a committed retry before exposing the task',
    () async {
      final harness = await _RetryHarness.create();
      addTearDown(harness.close);
      await harness.workspace.sendChatMessage(
        harness.conversation.id,
        text: '接收归档编号 ACME-778 的记录',
      );

      var assistant = harness.workspace
          .messagesFor(harness.conversation.id)
          .singleWhere((message) => message.role == ChatRole.assistant);
      final originalAction = assistant.tableActions.single;
      expect(originalAction.retryableIntake, isTrue);
      final taskId = harness.taskStore.checkpoint.turns.single.taskId;
      expect(
        harness.taskStore.checkpoint.turns.single.status,
        AgentTurnCheckpointStatus.waitingInput,
      );

      harness.source.incompleteThrough = harness.source.calls;
      final retryId = 'intake-retry:${originalAction.id}:1';
      final applied = await harness.tableProcessor.retryIncompleteIntake(
        originalAction,
        operationId: retryId,
      );
      expect(applied.status, TableChatActionStatus.applied);
      expect(harness.tables.entries.single.revision, 2);

      // Model the process exit after the applied action is saved but before its
      // generation receipt and transcript are updated.
      final persistedApplied = applied.copyWith(
        intakeRetryAttempt: 1,
        intakeRetryOperationId: retryId,
        intakeRetryPending: false,
      );
      await harness.chats.saveMessage(
        assistant.copyWith(tableActions: [persistedApplied]),
      );
      final unrelatedAction = TableChatAction(
        id: 'act_unrelated_pending',
        operation: 'table.create',
        title: '另一个待确认结构操作',
        status: TableChatActionStatus.pendingConfirmation,
        createdAt: assistant.createdAt,
        message: '等待用户确认。',
      );
      final unrelatedAssistant = ChatMessage(
        id: 'assistant_unrelated_pending',
        conversationId: assistant.conversationId,
        role: ChatRole.assistant,
        content: '另一个操作等待确认。',
        status: ChatMessageStatus.complete,
        createdAt: assistant.createdAt.add(const Duration(seconds: 1)),
        updatedAt: assistant.updatedAt.add(const Duration(seconds: 1)),
        tableActions: [unrelatedAction],
      );
      await harness.chats.saveMessage(unrelatedAssistant);
      final tornGeneration = await harness.chats.findGeneration(assistant.id);
      expect(
        tornGeneration?.toolCalls.single['completed_receipt_json'],
        contains('conflict'),
      );
      final requestsBeforeRestart = harness.backend.requests;

      await harness.workspace.shutdown();
      await harness.reboot();

      assistant = (await harness.chats.findMessage(assistant.id))!;
      final recoveredAction = assistant.tableActions.single;
      final recoveredGeneration = await harness.chats.findGeneration(
        assistant.id,
      );
      final recoveredRun = harness.taskStore.checkpoint.turns.singleWhere(
        (turn) => turn.taskId == taskId,
      );
      expect(recoveredAction.status, TableChatActionStatus.applied);
      expect(recoveredAction.intakeRetryOperationId, retryId);
      expect(
        recoveredGeneration?.toolCalls.single['completed_receipt_json'],
        contains('succeeded'),
      );
      expect(
        assistant.toolTranscript.last['content'],
        contains('"status":"succeeded"'),
      );
      expect(recoveredRun.status, AgentTurnCheckpointStatus.paused);
      expect(
        harness.workspace.tasksNeedingAction.single.awaitingInput,
        isFalse,
      );
      expect(
        (await harness.chats.findMessage(unrelatedAssistant.id))!
            .tableActions
            .single
            .status,
        TableChatActionStatus.pendingConfirmation,
      );
      expect(harness.backend.requests, requestsBeforeRestart);
      expect(harness.tables.entries, hasLength(1));
      expect(harness.tables.entries.single.revision, 2);

      await harness.workspace.shutdown();
      final checkpoint = harness.taskStore.checkpoint;
      await harness.taskStore.save(
        AgentTaskCheckpoint(
          budget: checkpoint.budget,
          runBudgets: checkpoint.runBudgets,
          activeBudgetRunId: checkpoint.activeBudgetRunId,
          turns: [
            for (final turn in checkpoint.turns)
              turn.taskId == taskId
                  ? turn.copyWith(
                      status: AgentTurnCheckpointStatus.waitingInput,
                    )
                  : turn,
          ],
        ),
      );
      await harness.reboot();
      final secondRecovery = harness.taskStore.checkpoint.turns.singleWhere(
        (turn) => turn.taskId == taskId,
      );
      final secondGeneration = await harness.chats.findGeneration(assistant.id);
      final secondAssistant = (await harness.chats.findMessage(assistant.id))!;
      expect(secondRecovery.status, AgentTurnCheckpointStatus.paused);
      expect(
        secondGeneration?.toolCalls.single['completed_receipt_json'],
        contains('succeeded'),
      );
      expect(
        secondAssistant.toolTranscript.last['content'],
        contains('"status":"succeeded"'),
      );
      expect(harness.backend.requests, requestsBeforeRestart);
      expect(harness.tables.entries.single.revision, 2);

      await harness.workspace.shutdown();
      final ambiguousCheckpoint = harness.taskStore.checkpoint;
      await harness.taskStore.save(
        AgentTaskCheckpoint(
          budget: ambiguousCheckpoint.budget,
          runBudgets: ambiguousCheckpoint.runBudgets,
          activeBudgetRunId: ambiguousCheckpoint.activeBudgetRunId,
          turns: [
            for (final turn in ambiguousCheckpoint.turns)
              turn.taskId == taskId
                  ? turn.copyWith(
                      status: AgentTurnCheckpointStatus.waitingInput,
                    )
                  : turn,
          ],
        ),
      );
      final validGeneration = await harness.chats.findGeneration(assistant.id);
      final validToolCall = validGeneration!.toolCalls.single;
      await harness.chats.saveGeneration(
        validGeneration.copyWith(
          toolCalls: [
            ...validGeneration.toolCalls,
            {...validToolCall, 'id': 'tool_call_ambiguous'},
          ],
        ),
      );
      await harness.reboot();
      final ambiguousRun = harness.taskStore.checkpoint.turns.singleWhere(
        (turn) => turn.taskId == taskId,
      );
      expect(ambiguousRun.status, AgentTurnCheckpointStatus.needsReview);
      expect(harness.workspace.tasksNeedingAction.single.needsReview, isTrue);
      expect(harness.backend.requests, requestsBeforeRestart);
      expect(harness.tables.entries.single.revision, 2);

      await harness.workspace.shutdown();
      final malformedCheckpoint = harness.taskStore.checkpoint;
      await harness.taskStore.save(
        AgentTaskCheckpoint(
          budget: malformedCheckpoint.budget,
          runBudgets: malformedCheckpoint.runBudgets,
          activeBudgetRunId: malformedCheckpoint.activeBudgetRunId,
          turns: [
            for (final turn in malformedCheckpoint.turns)
              turn.taskId == taskId
                  ? turn.copyWith(
                      status: AgentTurnCheckpointStatus.waitingInput,
                    )
                  : turn,
          ],
        ),
      );
      await harness.chats.saveGeneration(
        validGeneration.copyWith(
          toolCalls: [
            validToolCall,
            {
              'index': '9',
              'id': 'tool_call_malformed',
              'name': 'content.create',
              'arguments': '{}',
              'completed_action_kind': 'table',
              'completed_action_json': '{malformed',
              'completed_receipt_json': '{}',
            },
          ],
        ),
      );
      await harness.reboot();
      final malformedRun = harness.taskStore.checkpoint.turns.singleWhere(
        (turn) => turn.taskId == taskId,
      );
      expect(malformedRun.status, AgentTurnCheckpointStatus.needsReview);
      expect(harness.workspace.tasksNeedingAction.single.needsReview, isTrue);
      expect(harness.backend.requests, requestsBeforeRestart);
      expect(harness.tables.entries.single.revision, 2);

      await harness.workspace.shutdown();
      final duplicateCallIdCheckpoint = harness.taskStore.checkpoint;
      await harness.taskStore.save(
        AgentTaskCheckpoint(
          budget: duplicateCallIdCheckpoint.budget,
          runBudgets: duplicateCallIdCheckpoint.runBudgets,
          activeBudgetRunId: duplicateCallIdCheckpoint.activeBudgetRunId,
          turns: [
            for (final turn in duplicateCallIdCheckpoint.turns)
              turn.taskId == taskId
                  ? turn.copyWith(
                      status: AgentTurnCheckpointStatus.waitingInput,
                    )
                  : turn,
          ],
        ),
      );
      final duplicateAction = Map<String, dynamic>.from(
        jsonDecode(validToolCall['completed_action_json']!) as Map,
      )..['id'] = 'act_other_tool_call';
      final duplicateCall = {
        ...validToolCall,
        'index': '9',
        'arguments': '{"id":"another"}',
        'completed_action_json': jsonEncode(duplicateAction),
      };
      await harness.chats.saveGeneration(
        validGeneration.copyWith(toolCalls: [validToolCall, duplicateCall]),
      );
      await harness.reboot();
      final duplicateCallIdRun = harness.taskStore.checkpoint.turns.singleWhere(
        (turn) => turn.taskId == taskId,
      );
      expect(duplicateCallIdRun.status, AgentTurnCheckpointStatus.needsReview);
      expect(harness.workspace.tasksNeedingAction.single.needsReview, isTrue);
      expect(harness.backend.requests, requestsBeforeRestart);
      expect(harness.tables.entries.single.revision, 2);
    },
  );
}

AiPolicy _writePolicy() => AiPolicy.custom(
  tableScope: const AiResourceScope.all(),
  decisions: const {
    AiPermissionAction.contentCreate: AiPolicyDecision.allow,
    AiPermissionAction.contentRead: AiPolicyDecision.allow,
    AiPermissionAction.contentUpdate: AiPolicyDecision.allow,
  },
);

class _RetryHarness {
  _RetryHarness({
    required this.vault,
    required this.index,
    required this.chats,
    required this.results,
    required this.tables,
    required this.taskStore,
    required this.source,
    required this.backend,
    required this.autoRecordProcessor,
    required this.capture,
    required this.settings,
    required this.modelClient,
  });

  final MemoryVaultStore vault;
  final MemoryIndexDatabase index;
  final ChatRepository chats;
  final ResultLibrary results;
  final TableLibrary tables;
  final MemoryAgentTaskStore taskStore;
  final _IncompleteThenAugmentSource source;
  final _RetryBackend backend;
  late TableActionProcessor tableProcessor;
  late Conversation conversation;
  bool revokePolicyAtGuard = false;
  int _policyChecks = 0;
  final AutoRecordProcessor autoRecordProcessor;
  final CaptureWorkflow capture;
  final FakeSettingsService settings;
  ModelClient modelClient;
  late ConversationWorkspace workspace;

  static Future<_RetryHarness> create() async {
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    final tables = TableLibrary(
      repository: TableRepository(vault: vault, index: index),
    );
    await tables.initialize();
    final table = tables.tables.first;
    final now = DateTime(2026, 11, 5, 10);
    await tables.createEntry(
      TableEntryDocument(
        id: 'nt_acme_778',
        type: TableContentType.note,
        tableId: table.id,
        title: '设备归档',
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: '订单编号 ACME-778 已接收。',
      ),
    );
    final resultRepository = ResultRepository(
      vault: vault,
      index: index,
      deviceId: 'intake-retry-test',
    );
    await resultRepository.initialize();
    final results = ResultLibrary(repository: resultRepository);
    await results.initialize();
    final chats = ChatRepository(
      store: MemoryConversationStore(),
      attachments: MemoryAttachmentStore(),
    );
    await chats.initialize();
    final settings = FakeSettingsService(modelKey: 'intake-retry-test');
    final backend = _RetryBackend(tableId: table.id);
    final modelClient = backend.createClient();
    final capture = CaptureWorkflow(
      repository: resultRepository,
      results: results,
      indexDatabase: index,
      captureService: CaptureService(
        settings: settings,
        parser: const DeterministicParser(),
        modelClient: modelClient,
      ),
    );
    await capture.initialize();
    final autoRecordProcessor = AutoRecordProcessor(
      chatRepository: chats,
      results: results,
      captures: capture,
      deviceId: () => resultRepository.deviceId,
    );
    final taskStore = MemoryAgentTaskStore()
      ..checkpoint = const AgentTaskCheckpoint(
        budget: AgentBudgetCheckpoint(grantedRequests: 2),
      );
    final harness = _RetryHarness(
      vault: vault,
      index: index,
      chats: chats,
      results: results,
      tables: tables,
      taskStore: taskStore,
      source: _IncompleteThenAugmentSource(),
      backend: backend,
      autoRecordProcessor: autoRecordProcessor,
      capture: capture,
      settings: settings,
      modelClient: modelClient,
    );
    await harness._createWorkspace();
    harness.conversation = await harness.workspace.createConversation(
      policy: _writePolicy(),
    );
    return harness;
  }

  Future<void> _createWorkspace() async {
    late ConversationWorkspace next;
    final processor = TableActionProcessor(
      chatRepository: chats,
      tables: tables,
      semanticDuplicateDecisionSource: source,
      policyResolver: (conversation) {
        if (!revokePolicyAtGuard) return conversation.effectiveAiPolicy;
        _policyChecks++;
        return _policyChecks == 3
            ? AiPolicy.forPreset(AiPolicyPreset.readOnly)
            : conversation.effectiveAiPolicy;
      },
    );
    tableProcessor = processor;
    next = ConversationWorkspace(
      repository: chats,
      results: results,
      chatService: ChatService(
        settings: settings,
        repository: chats,
        results: results,
        tables: tables,
        modelClient: modelClient,
        writeToolExecutor: (call) => next.executeWriteTool(call),
      ),
      autoRecordProcessor: autoRecordProcessor,
      tableActionProcessor: processor,
      taskStore: taskStore,
      backgroundAgent: DisabledAgentBackgroundControl(),
      defaultPolicy: _writePolicy,
      defaultPermissions: () => const AiPermissions(),
    );
    workspace = next;
    await workspace.initialize();
  }

  Future<void> reboot() async {
    modelClient = backend.createClient();
    await _createWorkspace();
  }

  Future<void> close() async {
    await workspace.shutdown();
    await chats.close();
    await results.shutdown();
    results.dispose();
  }
}

class _IncompleteThenAugmentSource implements SemanticDuplicateDecisionSource {
  int calls = 0;
  int incompleteThrough = 2;

  @override
  Future<SemanticDuplicateDecision> decide(
    SemanticDuplicateRequest request,
  ) async {
    calls++;
    if (calls <= incompleteThrough) {
      return SemanticDuplicateDecision(
        action: SemanticDuplicateAction.conflict,
        comparisonComplete: false,
        reason: '查重候选尚未全部检查。',
      );
    }
    final candidate = request.candidates.single;
    final evidence = request.signal
        .sharedVerifiableSemanticEvidenceWith(candidate.signal)
        .toList();
    return SemanticDuplicateDecision(
      action: SemanticDuplicateAction.augment,
      targetId: candidate.entry.id,
      expectedRevision: candidate.entry.revision,
      evidence: evidence,
      bodyAddition: '复核后补充的归档事实。',
    );
  }
}

class _RetryBackend {
  _RetryBackend({required this.tableId});

  final String tableId;
  final List<Completer<void>> _requestReached = [];
  final List<String?> _texts = [null, '首次检查完成。', '重扫完成，已补充原记录。'];
  int requests = 0;

  ModelClient createClient() => ModelClient(
    client: MockClient.streaming((request, body) async {
      final index = requests++;
      if (_requestReached.length <= index) {
        _requestReached.add(Completer<void>());
      }
      _requestReached[index].complete();
      final text = _texts[index];
      return _sseResponse(
        text == null
            ? {
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_intake_retry',
                          'type': 'function',
                          'function': {
                            'name': 'content.create',
                            'arguments': jsonEncode({
                              'table_id': tableId,
                              'type': 'note',
                              'title': '设备归档',
                              'body': '订单编号 ACME-778 已归档。',
                              'idempotency_key': 'retry-test-source',
                            }),
                          },
                        },
                      ],
                    },
                  },
                ],
              }
            : {
                'choices': [
                  {
                    'delta': {'content': text},
                  },
                ],
              },
      );
    }),
  );

  Future<void> waitForRequests(int count) async {
    while (_requestReached.length < count) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await _requestReached[count - 1].future.timeout(const Duration(seconds: 3));
  }

  Future<void> respond(int index, String text) async {
    if (index < _texts.length) _texts[index] = text;
  }
}

http.StreamedResponse _sseResponse(Map<String, Object?> event) =>
    http.StreamedResponse(
      Stream.fromIterable([
        utf8.encode('data: ${jsonEncode(event)}\n\n'),
        utf8.encode('data: [DONE]\n\n'),
      ]),
      200,
      headers: const {'content-type': 'text/event-stream'},
    );

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}
