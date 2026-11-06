import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/modules/capture/capture_workflow.dart';
import 'package:personal_ai_inbox/modules/conversation/auto_record_processor.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_background_control.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_task_store.dart';
import 'package:personal_ai_inbox/modules/conversation/conversation_workspace.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';
import 'package:personal_ai_inbox/services/chat_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';
import 'package:personal_ai_inbox/services/agent_background_service.dart';

import 'test_support.dart';

void main() {
  test(
    'startup settles running turn with matching completed evidence',
    () async {
      final script = _ScriptedChatClient();
      final (harness, _) = await _runningTurnRecoveryHarness(
        script,
        assistantStatus: ChatMessageStatus.complete,
        generationStatus: GenerationStatus.completed,
      );
      addTearDown(harness.close);

      expect(
        (await harness.chatRepository.findMessage('recovery-assistant'))
            ?.status,
        ChatMessageStatus.complete,
      );
      expect(harness.workspace.tasksNeedingAction, isEmpty);
      expect(harness.workspace.hasPendingChatTurns, isFalse);
      expect(harness.workspace.isChatGenerating, isFalse);
      expect(script.requests, isEmpty);
    },
  );

  test(
    'startup settles a running turn after response-ready recovery completes',
    () async {
      final script = _ScriptedChatClient();
      final (harness, _) = await _runningTurnRecoveryHarness(
        script,
        assistantStatus: ChatMessageStatus.streaming,
        generationStatus: GenerationStatus.responseReady,
      );
      addTearDown(harness.close);

      expect(
        (await harness.chatRepository.findMessage('recovery-assistant'))
            ?.status,
        ChatMessageStatus.complete,
      );
      expect(
        (await harness.chatRepository.findGeneration('recovery-assistant'))
            ?.status,
        GenerationStatus.completed,
      );
      expect(harness.workspace.tasksNeedingAction, isEmpty);
      expect(harness.workspace.hasPendingChatTurns, isFalse);
      expect(script.requests, isEmpty);
    },
  );

  test('startup keeps response-ready tool intent in review when assistant is missing', () async {
    final script = _ScriptedChatClient();
    final (harness, _) = await _runningTurnRecoveryHarness(
      script,
      assistantStatus: null,
      generationStatus: GenerationStatus.responseReady,
      toolCalls: const [
        {
          'index': '0',
          'id': 'recovery-tool-call',
          'name': 'propose_global_knowledge_change',
          'arguments': '{"operation":"create"}',
        },
      ],
    );
    addTearDown(harness.close);

    expect(
      await harness.chatRepository.findMessage('recovery-assistant'),
      isNull,
    );
    final generation = await harness.chatRepository.findGeneration(
      'recovery-assistant',
    );
    expect(generation?.status, GenerationStatus.responseReady);
    expect(generation?.toolCalls.single['completed_receipt_json'], isNull);
    expect(harness.workspace.tasksNeedingAction.single.needsReview, isTrue);
    expect(
      harness.workspace.tasksNeedingAction.single.taskIds,
      contains('recovery-task'),
    );
    expect(harness.workspace.hasPendingChatTurns, isTrue);
    expect(script.requests, isEmpty);
  });

  test('startup keeps running turn in review when completion evidence is incomplete', () async {
    final script = _ScriptedChatClient();
    final (harness, _) = await _runningTurnRecoveryHarness(
      script,
      assistantStatus: ChatMessageStatus.interrupted,
      generationStatus: GenerationStatus.completed,
    );
    addTearDown(harness.close);

    final task = harness.workspace.tasksNeedingAction.single;
    expect(task.needsReview, isTrue);
    expect(task.taskIds, contains('recovery-task'));
    expect(
      (await harness.chatRepository.findMessage('recovery-assistant'))?.status,
      ChatMessageStatus.interrupted,
    );
    expect(script.requests, isEmpty);

    final missingGenerationScript = _ScriptedChatClient();
    final (missingGenerationHarness, _) = await _runningTurnRecoveryHarness(
      missingGenerationScript,
      assistantStatus: ChatMessageStatus.complete,
      generationStatus: null,
    );
    addTearDown(missingGenerationHarness.close);
    expect(
      missingGenerationHarness.workspace.tasksNeedingAction.single.needsReview,
      isTrue,
    );
    expect(missingGenerationScript.requests, isEmpty);
  });

  test('request reservation is invisible until persistence succeeds', () async {
    final store = _BlockingTaskStore();
    final script = _ScriptedChatClient();
    final harness = await _SchedulerHarness.create(
      script.modelClient,
      taskStore: store,
    );
    addTearDown(harness.close);
    final conversation = await harness.workspace.createConversation();
    final sending = harness.workspace.sendChatMessage(
      conversation.id,
      text: '预算',
    );
    await script.waitForRequest(0);
    final gate = Completer<void>();
    store.gate = gate;
    final reserved = harness.workspace.reserveAuxiliaryModelRequest();
    await Future<void>.delayed(Duration.zero);
    final visibleCount = harness.workspace.agentBudget.usedRequests;
    gate.complete();
    expect(await reserved, isTrue);
    script.complete(0, '完成');
    await sending;
    expect(visibleCount, 1);
    expect(harness.workspace.agentBudget.usedRequests, 2);
  });
  test('failed request budget checkpoint prevents model dispatch', () async {
    final store = _FailingRequestReservationStore();
    final script = _ScriptedChatClient();
    final harness = await _SchedulerHarness.create(
      script.modelClient,
      taskStore: store,
    );
    addTearDown(harness.close);
    final conversation = await harness.workspace.createConversation();

    await harness.workspace
        .sendChatMessage(conversation.id, text: '预算落盘失败时不得发送请求')
        .timeout(const Duration(seconds: 2));

    expect(script.requests, isEmpty);
    expect(harness.workspace.agentBudget.usedRequests, 0);
    expect(store.checkpoint.budget.usedRequests, 0);
    expect(
      harness.workspace.messagesFor(conversation.id).last.status,
      ChatMessageStatus.failed,
    );
  });
  test('manual retry does not resume the original failed task', () async {
    final requests = <Map<String, dynamic>>[];
    final modelClient = ModelClient(
      client: MockClient.streaming((request, body) async {
        final payload =
            jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
        requests.add(payload);
        if (requests.length == 1) {
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"error":"unauthorized"}')),
            401,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': '重试成功。'},
                  },
                ],
              })}\n\n',
            ),
            utf8.encode(
              'data: ${jsonEncode({
                'choices': [
                  {'delta': {}, 'finish_reason': 'stop'},
                ],
              })}\n\n',
            ),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
          headers: const {'content-type': 'text/event-stream'},
        );
      }),
    );
    final taskStore = MemoryAgentTaskStore();
    final harness = await _SchedulerHarness.create(
      modelClient,
      taskStore: taskStore,
    );
    addTearDown(harness.close);
    final conversation = await harness.workspace.createConversation();

    await harness.workspace.sendChatMessage(
      conversation.id,
      text: '首次鉴权失败后显式重试',
    );
    final failedAssistant = harness.workspace
        .messagesFor(conversation.id)
        .singleWhere((message) => message.role == ChatRole.assistant);
    expect(failedAssistant.status, ChatMessageStatus.failed);
    final failedRun = taskStore.checkpoint.turns.single;
    expect(failedRun.status, AgentTurnCheckpointStatus.needsReview);
    expect(failedRun.assistantMessageId, failedAssistant.id);
    expect(requests, hasLength(1));

    await harness.workspace.retryAssistantMessage(failedAssistant.id);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final messages = harness.workspace.messagesFor(conversation.id);
    final successfulRetry = messages.lastWhere(
      (message) =>
          message.role == ChatRole.assistant &&
          message.id != failedAssistant.id,
    );
    expect(successfulRetry.status, ChatMessageStatus.complete);
    expect(successfulRetry.content, '重试成功。');
    expect(
      (await harness.chatRepository.findGeneration(successfulRetry.id))?.status,
      GenerationStatus.completed,
    );
    expect(
      requests,
      hasLength(2),
      reason: 'the original failed run must not issue a third model request',
    );
    final retainedFailedRun = taskStore.checkpoint.turns.singleWhere(
      (turn) => turn.taskId == failedRun.taskId,
    );
    expect(retainedFailedRun.status, AgentTurnCheckpointStatus.needsReview);
    expect(
      (await harness.chatRepository.findGeneration(failedAssistant.id))?.status,
      GenerationStatus.failed,
    );
    expect(
      harness.workspace.tasksNeedingAction
          .singleWhere((task) => task.taskIds.contains(failedRun.taskId))
          .needsReview,
      isTrue,
    );
  });
  test('independent tasks have separate request budgets', () async {
    final script = _ScriptedChatClient();
    final store = MemoryAgentTaskStore();
    final harness = await _SchedulerHarness.create(
      script.modelClient,
      taskStore: store,
    );
    addTearDown(harness.close);
    for (var i = 0; i < 2; i++) {
      final conversation = await harness.workspace.createConversation();
      final sending = harness.workspace.sendChatMessage(
        conversation.id,
        text: '独立任务$i',
      );
      await script.waitForRequest(i);
      expect(harness.workspace.agentBudget.usedRequests, 1);
      script.complete(i, '完成$i');
      await sending;
    }
    final decoded = AgentTaskCheckpoint.fromJson(store.checkpoint.toJson());
    expect(decoded.runBudgets, hasLength(2));
    expect(
      decoded.runBudgets.values.map((budget) => budget.usedRequests),
      everyElement(1),
    );
  });
  test(
    'active time checkpoints while response headers are still pending',
    () async {
      final store = MemoryAgentTaskStore();
      final script = _ScriptedChatClient();
      final harness = await _SchedulerHarness.create(
        script.modelClient,
        taskStore: store,
        streamPersistenceInterval: const Duration(milliseconds: 10),
      );
      addTearDown(harness.close);
      final conversation = await harness.workspace.createConversation();
      final sending = harness.workspace.sendChatMessage(
        conversation.id,
        text: '等待响应头时累计活动时间',
      );
      await script.waitForRequest(0);
      await Future<void>.delayed(const Duration(milliseconds: 45));

      expect(store.checkpoint.budget.usedActiveMillis, greaterThan(0));
      expect(store.checkpoint.runBudgets.values, isNotEmpty);
      expect(
        store.checkpoint.runBudgets.values.first.usedActiveMillis,
        greaterThan(0),
      );

      script.complete(0, '已完成');
      await sending.timeout(const Duration(seconds: 2));
    },
  );
  test(
    'concurrent budget clicks grant once and later click grants again',
    () async {
      final store = MemoryAgentTaskStore();
      final harness = await _SchedulerHarness.create(
        _ScriptedChatClient().modelClient,
        taskStore: store,
      );
      addTearDown(harness.close);
      await Future.wait([
        harness.workspace.addTaskBudget(additionalRequests: 240),
        harness.workspace.addTaskBudget(additionalRequests: 240),
      ]);
      expect(harness.workspace.agentBudget.grantedRequests, 480);
      expect(store.checkpoint.budget.grantedRequests, 480);
      await harness.workspace.addTaskBudget(additionalRequests: 240);
      expect(harness.workspace.agentBudget.grantedRequests, 720);
    },
  );
  for (final resume in [false, true]) {
    test(
      'failed budget save preserves authorization (resume=$resume)',
      () async {
        final store = _FailingTaskStore();
        final harness = await _SchedulerHarness.create(
          _ScriptedChatClient().modelClient,
          taskStore: store,
        );
        addTearDown(harness.close);
        final original = harness.workspace.agentBudget;
        store.failSave = true;
        Future<void> grant() => resume
            ? harness.workspace.resumeTasks(additionalRequests: 240)
            : harness.workspace.addTaskBudget(additionalRequests: 240);
        await expectLater(grant(), throwsStateError);
        expect(
          harness.workspace.agentBudget.grantedRequests,
          original.grantedRequests,
        );
        store.failSave = false;
        await grant();
        expect(
          harness.workspace.agentBudget.grantedRequests,
          original.grantedRequests + 240,
        );
        expect(
          store.checkpoint.budget.grantedRequests,
          original.grantedRequests + 240,
        );
      },
    );
  }
  test('same-conversation input becomes steering without cancelling', () async {
    final script = _ScriptedChatClient();
    final harness = await _SchedulerHarness.create(script.modelClient);
    addTearDown(harness.close);
    final conversation = await harness.workspace.createConversation();

    final first = harness.workspace.sendChatMessage(
      conversation.id,
      text: '先分析现有表',
    );
    final firstRequest = await script.waitForRequest(0);
    expect(firstRequest.lastUserText, '先分析现有表');

    final steering = harness.workspace.sendChatMessage(
      conversation.id,
      text: '补充：只检查本周',
    );
    await _waitFor(
      () => harness.workspace.isConversationSteering(conversation.id),
    );
    expect(harness.workspace.generatingConversationId, conversation.id);
    expect(firstRequest.isCompleted, isFalse);

    script.complete(0, '第一轮已完成。');
    final secondRequest = await script.waitForRequest(1);
    await first;
    expect(secondRequest.userTexts, ['先分析现有表', '补充：只检查本周']);
    expect(harness.workspace.generatingConversationId, conversation.id);

    script.complete(1, '已按本周范围继续处理。');
    await steering;

    final assistants = harness.workspace
        .messagesFor(conversation.id)
        .where((message) => message.role == ChatRole.assistant)
        .toList(growable: false);
    expect(assistants, hasLength(2));
    expect(
      assistants.map((message) => message.status),
      everyElement(ChatMessageStatus.complete),
    );
    expect(assistants.last.content, '已按本周范围继续处理。');
    expect(harness.workspace.agentBudget.usedRequests, 2);
  });

  test(
    'cancel during running checkpoint prevents first model dispatch',
    () async {
      final store = _BlockingRunningTaskStore();
      final script = _ScriptedChatClient();
      final harness = await _SchedulerHarness.create(
        script.modelClient,
        taskStore: store,
      );
      addTearDown(harness.close);
      final conversation = await harness.workspace.createConversation();
      final sending = harness.workspace.sendChatMessage(
        conversation.id,
        text: '在发送前取消',
      );

      await store.runningSaveStarted.future.timeout(const Duration(seconds: 2));
      await harness.workspace.cancelGeneration();
      store.releaseRunningSave.complete();
      await sending.timeout(const Duration(seconds: 2));

      expect(script.requests, isEmpty);
      final assistant = harness.workspace
          .messagesFor(conversation.id)
          .singleWhere((message) => message.role == ChatRole.assistant);
      expect(assistant.status, ChatMessageStatus.interrupted);
      expect(assistant.error, contains('模型请求尚未发送'));
      expect(
        store.checkpoint.turns,
        isEmpty,
        reason: store.checkpoint.turns.map((turn) => turn.toJson()).toString(),
      );
    },
  );

  test('other conversations run in FIFO order', () async {
    final script = _ScriptedChatClient();
    final store = MemoryAgentTaskStore();
    final harness = await _SchedulerHarness.create(
      script.modelClient,
      taskStore: store,
      streamPersistenceInterval: const Duration(milliseconds: 10),
    );
    addTearDown(harness.close);
    final firstConversation = await harness.workspace.createConversation();
    final secondConversation = await harness.workspace.createConversation();
    final thirdConversation = await harness.workspace.createConversation();

    final first = harness.workspace.sendChatMessage(
      firstConversation.id,
      text: '会话 A',
    );
    await script.waitForRequest(0);
    final second = harness.workspace.sendChatMessage(
      secondConversation.id,
      text: '会话 B',
    );
    final third = harness.workspace.sendChatMessage(
      thirdConversation.id,
      text: '会话 C',
    );
    await _waitFor(
      () =>
          harness.workspace.isConversationQueued(secondConversation.id) &&
          harness.workspace.isConversationQueued(thirdConversation.id),
    );
    expect(harness.workspace.pendingChatConversationIds, [
      firstConversation.id,
      secondConversation.id,
      thirdConversation.id,
    ]);
    final queuedTurn = store.checkpoint.turns.singleWhere(
      (turn) => turn.conversationId == secondConversation.id,
    );
    expect(queuedTurn.status, AgentTurnCheckpointStatus.queued);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      store
          .checkpoint
          .runBudgets[queuedTurn.effectiveBudgetRunId]!
          .usedActiveMillis,
      0,
      reason: 'a conversation waiting in FIFO does not consume active time',
    );

    script.complete(0, 'A 完成');
    final secondRequest = await script.waitForRequest(1);
    await first;
    expect(secondRequest.lastUserText, '会话 B');
    script.complete(1, 'B 完成');

    final thirdRequest = await script.waitForRequest(2);
    await second;
    expect(thirdRequest.lastUserText, '会话 C');
    script.complete(2, 'C 完成');
    await third;

    expect(script.requests.map((request) => request.lastUserText), [
      '会话 A',
      '会话 B',
      '会话 C',
    ]);
    for (final conversationId in [
      firstConversation.id,
      secondConversation.id,
      thirdConversation.id,
    ]) {
      expect(
        harness.workspace
            .messagesFor(conversationId)
            .lastWhere((message) => message.role == ChatRole.assistant)
            .status,
        ChatMessageStatus.complete,
      );
    }
  });

  test('explicit cancel keeps other conversations queued', () async {
    final script = _ScriptedChatClient();
    final harness = await _SchedulerHarness.create(script.modelClient);
    addTearDown(harness.close);
    final canceledConversation = await harness.workspace.createConversation();
    final queuedConversation = await harness.workspace.createConversation();

    final first = harness.workspace.sendChatMessage(
      canceledConversation.id,
      text: '会被停止',
    );
    await script.waitForRequest(0);
    final steering = harness.workspace.sendChatMessage(
      canceledConversation.id,
      text: '也会明确取消',
    );
    final other = harness.workspace.sendChatMessage(
      queuedConversation.id,
      text: '其他会话继续',
    );
    await _waitFor(
      () =>
          harness.workspace.isConversationSteering(canceledConversation.id) &&
          harness.workspace.isConversationQueued(queuedConversation.id),
    );

    final canceling = harness.workspace.cancelGeneration();
    script.complete(0, '不应显示');
    await canceling.timeout(const Duration(seconds: 2));
    await first.timeout(const Duration(seconds: 2));
    await steering.timeout(const Duration(seconds: 2));

    final otherRequest = await script.waitForRequest(1);
    expect(otherRequest.lastUserText, '其他会话继续');
    script.complete(1, '其他会话完成');
    await other.timeout(const Duration(seconds: 2));

    final canceledAssistants = harness.workspace
        .messagesFor(canceledConversation.id)
        .where((message) => message.role == ChatRole.assistant)
        .toList(growable: false);
    expect(canceledAssistants, hasLength(2));
    expect(
      canceledAssistants.map((message) => message.status),
      everyElement(ChatMessageStatus.interrupted),
    );
    expect(canceledAssistants.first.error, contains('用户取消'));
    expect(canceledAssistants.last.error, contains('没有发送到模型'));
    expect(
      harness.workspace.messagesFor(queuedConversation.id).last.status,
      ChatMessageStatus.complete,
    );
    expect(script.requests, hasLength(2));
  });

  test('manual pause releases the worker for another conversation', () async {
    final script = _ScriptedChatClient();
    final store = MemoryAgentTaskStore();
    final harness = await _SchedulerHarness.create(
      script.modelClient,
      taskStore: store,
    );
    addTearDown(harness.close);
    final firstConversation = await harness.workspace.createConversation();
    final secondConversation = await harness.workspace.createConversation();

    final first = harness.workspace.sendChatMessage(
      firstConversation.id,
      text: '暂停后继续其他会话',
    );
    await script.waitForRequest(0);
    await Future<void>.delayed(const Duration(milliseconds: 35));
    await harness.workspace.pauseGeneration();
    await first.timeout(const Duration(seconds: 2));
    final pausedTurn = store.checkpoint.turns.singleWhere(
      (turn) => turn.status == AgentTurnCheckpointStatus.paused,
    );
    final pausedActiveMillis = store
        .checkpoint
        .runBudgets[pausedTurn.effectiveBudgetRunId]!
        .usedActiveMillis;
    expect(pausedActiveMillis, greaterThan(0));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      store
          .checkpoint
          .runBudgets[pausedTurn.effectiveBudgetRunId]!
          .usedActiveMillis,
      pausedActiveMillis,
      reason: 'waiting on a paused task does not consume active time',
    );

    final second = harness.workspace.sendChatMessage(
      secondConversation.id,
      text: '先处理另一会话',
    );
    final secondRequest = await script.waitForRequest(1);
    expect(secondRequest.lastUserText, '先处理另一会话');
    script.complete(1, '另一会话已完成');
    await second.timeout(const Duration(seconds: 2));

    final waiting = harness.workspace.tasksNeedingAction.single;
    expect(waiting.conversationId, firstConversation.id);
    expect(waiting.budget.exhausted, isFalse);
    await harness.workspace.resumeTasks(taskId: waiting.taskIds.first);
    final resumedRequest = await script.waitForRequest(2);
    expect(resumedRequest.lastUserText, '暂停后继续其他会话');
    script.complete(2, '原任务继续完成');
    await _waitFor(
      () =>
          harness.workspace.messagesFor(firstConversation.id).last.status ==
          ChatMessageStatus.complete,
    );
  });

  test(
    'manual pause waits for its paused checkpoint before returning',
    () async {
      final script = _ScriptedChatClient();
      final store = _PausedCheckpointGateStore();
      final harness = await _SchedulerHarness.create(
        script.modelClient,
        taskStore: store,
      );
      addTearDown(harness.close);
      final conversation = await harness.workspace.createConversation();

      final sending = harness.workspace.sendChatMessage(
        conversation.id,
        text: '暂停后检查已保存的任务状态',
      );
      await script.waitForRequest(0);
      final runningTurn = store.checkpoint.turns.single;
      final taskId = runningTurn.taskId;
      final assistantMessageId = runningTurn.assistantMessageId;
      expect(assistantMessageId, isNotEmpty);

      var pauseReturned = false;
      final pausing = harness.workspace.pauseGeneration().then((_) {
        pauseReturned = true;
      });
      await store.pausedCheckpointSaveStarted.future.timeout(
        const Duration(seconds: 2),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final returnedBeforeCheckpoint = pauseReturned;
      store.releasePausedCheckpointSave();
      await pausing.timeout(const Duration(seconds: 2));
      expect(
        returnedBeforeCheckpoint,
        isFalse,
        reason: 'pause must wait for the final durable paused checkpoint',
      );

      final paused = await store.load();
      final pausedTurn = paused.turns.singleWhere(
        (turn) => turn.taskId == taskId,
      );
      expect(pausedTurn.assistantMessageId, assistantMessageId);
      expect(pausedTurn.status, AgentTurnCheckpointStatus.paused);
      await sending.timeout(const Duration(seconds: 2));
    },
  );

  test(
    'manual pause reports final checkpoint failure without hanging',
    () async {
      final script = _ScriptedChatClient();
      final store = _PauseCheckpointFailureStore();
      final harness = await _SchedulerHarness.create(
        script.modelClient,
        taskStore: store,
      );
      addTearDown(harness.close);
      final conversation = await harness.workspace.createConversation();

      Object? sendError;
      final sending = harness.workspace
          .sendChatMessage(conversation.id, text: '暂停时模拟检查点保存失败')
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace _) {
              sendError = error;
            },
          );
      await script.waitForRequest(0);
      final runningTurn = store.checkpoint.turns.single;

      await expectLater(
        harness.workspace.pauseGeneration().timeout(
          const Duration(milliseconds: 500),
        ),
        throwsA(isA<StateError>()),
      );

      expect(store.failedWrites, 2);
      expect(
        harness.workspace.tasksNeedingAction
            .expand((task) => task.taskIds)
            .toSet(),
        contains(runningTurn.taskId),
      );
      expect(
        store.checkpoint.turns
            .singleWhere((turn) => turn.taskId == runningTurn.taskId)
            .status,
        AgentTurnCheckpointStatus.running,
        reason: 'failed checkpoint writes must not claim a persisted pause',
      );
      await sending.timeout(const Duration(seconds: 2));
      expect(sendError, isA<StateError>());
    },
  );

  test(
    'exhausted run pauses alone and its task card targets its own budget',
    () async {
      final script = _ScriptedChatClient();
      final store = MemoryAgentTaskStore()
        ..checkpoint = const AgentTaskCheckpoint(
          budget: AgentBudgetCheckpoint(grantedRequests: 1),
        );
      final harness = await _SchedulerHarness.create(
        script.modelClient,
        taskStore: store,
      );
      addTearDown(harness.close);
      final exhaustedConversation = await harness.workspace
          .createConversation();
      final independentConversation = await harness.workspace
          .createConversation();

      final first = harness.workspace.sendChatMessage(
        exhaustedConversation.id,
        text: '先消耗唯一额度',
      );
      await script.waitForRequest(0);
      final continuation = harness.workspace.sendChatMessage(
        exhaustedConversation.id,
        text: '同一任务继续',
      );
      final independent = harness.workspace.sendChatMessage(
        independentConversation.id,
        text: '独立任务可运行',
      );
      await _waitFor(
        () =>
            harness.workspace.isConversationSteering(
              exhaustedConversation.id,
            ) &&
            harness.workspace.isConversationQueued(independentConversation.id),
      );
      script.complete(0, '首轮完成');
      await first.timeout(const Duration(seconds: 2));

      final independentRequest = await script.waitForRequest(1);
      expect(independentRequest.lastUserText, '独立任务可运行');
      await harness.workspace.pauseGeneration();
      await independent.timeout(const Duration(seconds: 2));

      final waiting = harness.workspace.tasksNeedingAction.firstWhere(
        (task) => task.conversationId == exhaustedConversation.id,
      );
      expect(waiting.conversationId, exhaustedConversation.id);
      expect(waiting.budget.exhausted, isTrue);
      expect(
        harness.workspace.tasksNeedingAction,
        hasLength(2),
        reason: harness.workspace.tasksNeedingAction
            .map((task) => '${task.budgetRunId}:${task.taskIds}')
            .join(', '),
      );
      expect(
        () => harness.workspace.resumeTasks(additionalRequests: 1),
        throwsStateError,
        reason:
            'with multiple budgets the caller must select the task explicitly',
      );
      await harness.workspace.resumeTasks(
        taskId: waiting.taskIds.first,
        additionalRequests: 1,
      );
      final resumedRequest = await script.waitForRequest(2);
      expect(resumedRequest.lastUserText, '同一任务继续');
      script.complete(2, '额度追加后完成');
      await continuation.timeout(const Duration(seconds: 2));
    },
  );

  test(
    'background lifecycle receives start, progress, and completion',
    () async {
      final script = _ScriptedChatClient();
      final background = _FakeBackgroundControl();
      final store = MemoryAgentTaskStore();
      final harness = await _SchedulerHarness.create(
        script.modelClient,
        backgroundAgent: background,
        taskStore: store,
      );
      addTearDown(harness.close);
      final conversation = await harness.workspace.createConversation();

      final sending = harness.workspace.sendChatMessage(
        conversation.id,
        text: '后台任务',
      );
      await script.waitForRequest(0);
      script.complete(0, '完成');
      await sending;

      expect(background.methods, [
        'initialize',
        'requestNotificationPermission',
        'startTask',
        'updateTask',
        'completeTask',
      ]);
      expect(background.lastTaskId, isNotEmpty);
      expect(store.checkpoint.budget.usedRequests, greaterThanOrEqualTo(1));
    },
  );

  test(
    'background denial is visible and does not claim background success',
    () async {
      final script = _ScriptedChatClient();
      final background = _FakeBackgroundControl(
        permissionState: AgentBackgroundState.notificationPermissionDenied,
        permissionMessage: '通知权限被拒绝。',
      );
      final taskStore = MemoryAgentTaskStore();
      final harness = await _SchedulerHarness.create(
        script.modelClient,
        backgroundAgent: background,
        taskStore: taskStore,
      );
      addTearDown(harness.close);
      final conversation = await harness.workspace.createConversation();

      final sending = harness.workspace.sendChatMessage(
        conversation.id,
        text: '前台继续',
      );
      await script.waitForRequest(0);
      script.complete(0, '仍可回复');
      await sending;

      final assistant = harness.workspace.messagesFor(conversation.id).last;
      expect(assistant.status, ChatMessageStatus.complete);
      expect(assistant.error, contains('通知权限被拒绝'));
      expect(assistant.error, contains('仅在前台运行'));
      final generation = await harness.chatRepository.findGeneration(
        assistant.id,
      );
      expect(generation?.error, contains('通知权限被拒绝'));
      expect(background.methods, [
        'initialize',
        'requestNotificationPermission',
      ], reason: 'denial should keep this turn entirely in foreground mode');
      expect(taskStore.checkpoint.budget.usedRequests, 1);
    },
  );

  test('restricted startup snapshot pauses before model dispatch without relying on command delivery', () async {
    final script = _ScriptedChatClient();
    final background = _FakeBackgroundControl(
      startState: AgentBackgroundState.serviceRestricted,
      startMessage: '系统限制前台服务启动；任务已保存为暂停。',
      startPauseCommandDelay: const Duration(milliseconds: 100),
    );
    final store = MemoryAgentTaskStore();
    final harness = await _SchedulerHarness.create(
      script.modelClient,
      backgroundAgent: background,
      taskStore: store,
    );
    addTearDown(harness.close);
    final conversation = await harness.workspace.createConversation();
    final sending = harness.workspace.sendChatMessage(
      conversation.id,
      text: '服务受限时不要派发模型请求',
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    final dispatched = script.requests.isNotEmpty;
    for (var index = 0; index < script.requests.length; index++) {
      if (!script.requests[index].isCompleted) {
        script.complete(index, '不应派发');
      }
    }
    await sending.timeout(const Duration(seconds: 2));

    expect(dispatched, isFalse);
    expect(script.requests, isEmpty);
    expect(background.startPauseCommandEmitted.isCompleted, isFalse);
    expect(
      harness.workspace.messagesFor(conversation.id).last.status,
      ChatMessageStatus.interrupted,
    );
    expect(
      store.checkpoint.turns.single.status,
      AgentTurnCheckpointStatus.paused,
    );
    expect(
      store.checkpoint.turns.single.assistantMessageId,
      harness.workspace.messagesFor(conversation.id).last.id,
    );
    await background.startPauseCommandEmitted.future.timeout(
      const Duration(seconds: 2),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      store.checkpoint.turns.single.status,
      AgentTurnCheckpointStatus.paused,
    );
  });

  test(
    'native pause command stops active task and preserves other queue',
    () async {
      final script = _ScriptedChatClient();
      final background = _FakeBackgroundControl();
      final store = MemoryAgentTaskStore();
      final harness = await _SchedulerHarness.create(
        script.modelClient,
        backgroundAgent: background,
        taskStore: store,
      );
      addTearDown(harness.close);
      final firstConversation = await harness.workspace.createConversation();
      final otherConversation = await harness.workspace.createConversation();

      final first = harness.workspace.sendChatMessage(
        firstConversation.id,
        text: '通知暂停',
      );
      await script.waitForRequest(0);
      final other = harness.workspace.sendChatMessage(
        otherConversation.id,
        text: '其他队列保留',
      );
      await _waitFor(
        () => harness.workspace.isConversationQueued(otherConversation.id),
      );
      await background.pause(taskId: 'stale-or-foreign-task');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(harness.workspace.isChatGenerating, isTrue);
      expect(background.methods, isNot(contains('pauseTask')));
      await background.pause();
      await first.timeout(const Duration(seconds: 2));
      await _waitFor(
        () => store.checkpoint.turns.any(
          (turn) => turn.status == AgentTurnCheckpointStatus.paused,
        ),
      );
      expect(background.methods, contains('pauseTask'));
      expect(harness.workspace.isTaskSchedulerPaused, isTrue);
      final otherRequest = await script.waitForRequest(1);
      expect(otherRequest.lastUserText, '其他队列保留');
      expect(harness.workspace.generatingConversationId, otherConversation.id);
      expect(
        store.checkpoint.turns.any(
          (turn) => turn.status == AgentTurnCheckpointStatus.paused,
        ),
        isTrue,
      );
      expect(script.requests, hasLength(2));
      script.complete(1, '另一会话已正常继续');
      await other.timeout(const Duration(seconds: 2));
    },
  );

  test(
    'agent adapter interfaces share policy, budget, and cancellation',
    () async {
      final script = _ScriptedChatClient();
      final store = MemoryAgentTaskStore()
        ..checkpoint = const AgentTaskCheckpoint(
          budget: AgentBudgetCheckpoint(grantedRequests: 2),
        );
      final harness = await _SchedulerHarness.create(
        script.modelClient,
        taskStore: store,
      );
      addTearDown(harness.close);
      final conversation = await harness.workspace.createConversation(
        policy: AiPolicy.forPreset(AiPolicyPreset.standard),
      );
      await harness.workspace.activeCancellationFuture().timeout(Duration.zero);

      final sending = harness.workspace.sendChatMessage(
        conversation.id,
        text: '运行中语义比较',
      );
      await script.waitForRequest(0);
      expect(harness.workspace.generatingConversationId, conversation.id);
      expect(
        (await harness.workspace.currentRunningPolicy())?.preset,
        AiPolicyPreset.standard,
      );
      await harness.workspace.setAiPolicy(
        conversation.id,
        AiPolicy.forPreset(AiPolicyPreset.readOnly),
      );
      expect(
        (await harness.workspace.currentRunningPolicy())?.preset,
        AiPolicyPreset.readOnly,
      );

      // The active main request has already reserved one of the two slots.
      expect(harness.workspace.agentBudget.usedRequests, 1);
      expect(await harness.workspace.reserveAuxiliaryModelRequest(), isTrue);
      expect(await harness.workspace.reserveAuxiliaryModelRequest(), isFalse);
      expect(harness.workspace.agentBudget.usedRequests, 2);

      var cancelled = false;
      final cancellation = harness.workspace.activeCancellationFuture().then(
        (_) => cancelled = true,
      );
      final canceling = harness.workspace.cancelGeneration();
      script.complete(0, '不应显示');
      await canceling.timeout(const Duration(seconds: 2));
      await sending.timeout(const Duration(seconds: 2));
      await cancellation.timeout(const Duration(seconds: 2));
      expect(cancelled, isTrue);
      expect(await harness.workspace.currentRunningPolicy(), isNull);
    },
  );
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not reached before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _FakeBackgroundControl implements AgentBackgroundControl {
  _FakeBackgroundControl({
    this.startState = AgentBackgroundState.running,
    this.startMessage,
    this.permissionState = AgentBackgroundState.idle,
    this.permissionMessage,
    this.startPauseCommandDelay,
  });

  final AgentBackgroundState startState;
  final String? startMessage;
  final AgentBackgroundState permissionState;
  final String? permissionMessage;
  final Duration? startPauseCommandDelay;
  final Completer<void> startPauseCommandEmitted = Completer<void>();
  final ValueNotifier<AgentBackgroundSnapshot> _status =
      ValueNotifier<AgentBackgroundSnapshot>(
        const AgentBackgroundSnapshot.initial(),
      );
  final StreamController<AgentBackgroundCommand> _commands =
      StreamController<AgentBackgroundCommand>.broadcast();

  final List<String> methods = [];
  String? lastTaskId;

  @override
  ValueListenable<AgentBackgroundSnapshot> get status => _status;

  @override
  Stream<AgentBackgroundCommand> get commands => _commands.stream;

  @override
  Future<void> initialize() async {
    methods.add('initialize');
  }

  @override
  Future<AgentBackgroundSnapshot> requestNotificationPermission() async {
    methods.add('requestNotificationPermission');
    return AgentBackgroundSnapshot(
      state: permissionState,
      message: permissionMessage,
    );
  }

  @override
  Future<AgentBackgroundSnapshot> startTask({
    required String taskId,
    required String title,
    required String text,
    double? progress,
  }) async {
    methods.add('startTask');
    lastTaskId = taskId;
    final pauseCommandDelay = startPauseCommandDelay;
    if (startState == AgentBackgroundState.serviceRestricted &&
        pauseCommandDelay != null) {
      Timer(pauseCommandDelay, () {
        _commands.add(
          AgentBackgroundCommand(
            type: AgentBackgroundCommandType.pause,
            taskId: taskId,
            reason: startMessage,
          ),
        );
        if (!startPauseCommandEmitted.isCompleted) {
          startPauseCommandEmitted.complete();
        }
      });
    }
    return _set(
      AgentBackgroundSnapshot(
        state: startState,
        taskId: taskId,
        message: startMessage,
      ),
    );
  }

  @override
  Future<AgentBackgroundSnapshot> updateTask({
    required String taskId,
    required String title,
    required String text,
    double? progress,
  }) async {
    methods.add('updateTask');
    return _set(
      AgentBackgroundSnapshot(
        state: AgentBackgroundState.running,
        taskId: taskId,
      ),
    );
  }

  @override
  Future<AgentBackgroundSnapshot> pauseTask({
    required String taskId,
    String reason = '用户暂停了后台任务。',
  }) async {
    methods.add('pauseTask');
    return _set(
      AgentBackgroundSnapshot(
        state: AgentBackgroundState.paused,
        taskId: taskId,
        message: reason,
      ),
    );
  }

  @override
  Future<AgentBackgroundSnapshot> completeTask({
    required String taskId,
    String message = '后台任务已完成。',
  }) async {
    methods.add('completeTask');
    return _set(
      AgentBackgroundSnapshot(
        state: AgentBackgroundState.completed,
        taskId: taskId,
        message: message,
      ),
    );
  }

  @override
  Future<AgentBackgroundSnapshot> cancelTask({
    required String taskId,
    String reason = '用户取消了后台任务。',
  }) async {
    methods.add('cancelTask');
    return _set(
      AgentBackgroundSnapshot(
        state: AgentBackgroundState.cancelled,
        taskId: taskId,
        message: reason,
      ),
    );
  }

  Future<void> pause({String? taskId}) async {
    taskId ??= lastTaskId;
    if (taskId == null) throw StateError('background task has not started');
    _commands.add(
      AgentBackgroundCommand(
        type: AgentBackgroundCommandType.pause,
        taskId: taskId,
        reason: '通知栏暂停',
      ),
    );
  }

  AgentBackgroundSnapshot _set(AgentBackgroundSnapshot snapshot) {
    _status.value = snapshot;
    return snapshot;
  }
}

class _ScriptedChatClient {
  _ScriptedChatClient() {
    modelClient = ModelClient(
      client: MockClient.streaming((request, body) async {
        final payload =
            jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
        final pending = _PendingChatRequest(payload);
        requests.add(pending);
        return pending.response.future;
      }),
    );
  }

  late final ModelClient modelClient;
  final List<_PendingChatRequest> requests = [];

  Future<_PendingChatRequest> waitForRequest(int index) async {
    await _waitFor(() => requests.length > index);
    return requests[index];
  }

  void complete(int index, String text) {
    requests[index].response.complete(_textResponse(text));
  }
}

class _PendingChatRequest {
  _PendingChatRequest(Map<String, dynamic> payload)
    : userTexts = [
        for (final rawMessage in payload['messages'] as List)
          if (rawMessage is Map &&
              rawMessage['role'] == 'user' &&
              rawMessage['content'] is String)
            rawMessage['content'] as String,
      ];

  final List<String> userTexts;
  final Completer<http.StreamedResponse> response =
      Completer<http.StreamedResponse>();

  bool get isCompleted => response.isCompleted;

  String get lastUserText => userTexts.last;
}

http.StreamedResponse _textResponse(String text) {
  final body = [
    'data: ${jsonEncode({
      'choices': [
        {
          'delta': {'content': text},
        },
      ],
    })}\n\n',
    'data: [DONE]\n\n',
  ];
  return http.StreamedResponse(
    Stream.fromIterable(body.map(utf8.encode)),
    200,
    headers: const {'content-type': 'text/event-stream'},
  );
}

class _BlockingTaskStore extends MemoryAgentTaskStore {
  Completer<void>? gate;
  @override
  Future<void> save(AgentTaskCheckpoint checkpoint) async {
    await gate?.future;
    await super.save(checkpoint);
  }
}

class _BlockingRunningTaskStore extends MemoryAgentTaskStore {
  final Completer<void> runningSaveStarted = Completer<void>();
  final Completer<void> releaseRunningSave = Completer<void>();

  @override
  Future<void> save(AgentTaskCheckpoint checkpoint) async {
    if (!runningSaveStarted.isCompleted &&
        checkpoint.turns.any(
          (turn) => turn.status == AgentTurnCheckpointStatus.running,
        )) {
      runningSaveStarted.complete();
      await releaseRunningSave.future;
    }
    await super.save(checkpoint);
  }
}

class _FailingTaskStore extends MemoryAgentTaskStore {
  bool failSave = false;

  @override
  Future<void> save(AgentTaskCheckpoint checkpoint) async {
    if (failSave) throw StateError('injected budget save failure');
    await super.save(checkpoint);
  }
}

class _FailingRequestReservationStore extends MemoryAgentTaskStore {
  bool _failed = false;

  @override
  Future<void> save(AgentTaskCheckpoint checkpoint) async {
    if (!_failed &&
        checkpoint.budget.usedRequests > this.checkpoint.budget.usedRequests) {
      _failed = true;
      throw StateError('injected request budget checkpoint failure');
    }
    await super.save(checkpoint);
  }
}

Future<(_SchedulerHarness, _ScriptedChatClient)> _runningTurnRecoveryHarness(
  _ScriptedChatClient script, {
  required ChatMessageStatus? assistantStatus,
  required GenerationStatus? generationStatus,
  List<Map<String, String>> toolCalls = const [],
}) async {
  final conversations = MemoryConversationStore();
  final timestamp = DateTime(2026, 11, 5, 12);
  await conversations.upsertConversation(
    Conversation(
      id: 'recovery-conversation',
      title: '恢复完成任务',
      createdAt: timestamp,
      updatedAt: timestamp,
      autoTitle: false,
    ),
  );
  await conversations.upsertMessage(
    ChatMessage(
      id: 'recovery-user',
      conversationId: 'recovery-conversation',
      role: ChatRole.user,
      content: '已经完成的请求',
      status: ChatMessageStatus.complete,
      createdAt: timestamp,
      updatedAt: timestamp,
    ),
  );
  if (assistantStatus != null) {
    await conversations.upsertMessage(
      ChatMessage(
        id: 'recovery-assistant',
        conversationId: 'recovery-conversation',
        role: ChatRole.assistant,
        content: '原请求已完整完成。',
        status: assistantStatus,
        createdAt: timestamp.add(const Duration(seconds: 1)),
        updatedAt: timestamp.add(const Duration(seconds: 1)),
      ),
    );
  }
  if (generationStatus != null) {
    await conversations.upsertGeneration(
      GenerationRun(
        assistantMessageId: 'recovery-assistant',
        conversationId: 'recovery-conversation',
        userMessageId: 'recovery-user',
        status: generationStatus,
        responseText: '原请求已完整完成。',
        toolCalls: toolCalls,
        createdAt: timestamp.add(const Duration(seconds: 1)),
        updatedAt: timestamp.add(const Duration(seconds: 1)),
      ),
    );
  }
  final taskStore = MemoryAgentTaskStore()
    ..checkpoint = const AgentTaskCheckpoint(
      budget: AgentBudgetCheckpoint(grantedRequests: 8, usedRequests: 1),
      turns: [
        AgentTurnCheckpoint(
          taskId: 'recovery-task',
          conversationId: 'recovery-conversation',
          userMessageId: 'recovery-user',
          assistantMessageId: 'recovery-assistant',
          kind: AgentTurnQueueKind.conversation,
          status: AgentTurnCheckpointStatus.running,
          sequence: 1,
        ),
      ],
    );
  final harness = await _SchedulerHarness.create(
    script.modelClient,
    taskStore: taskStore,
    conversationStore: conversations,
  );
  return (harness, script);
}

class _SchedulerHarness {
  _SchedulerHarness({
    required this.workspace,
    required this.chatRepository,
    required this.results,
  });

  final ConversationWorkspace workspace;
  final ChatRepository chatRepository;
  final ResultLibrary results;

  static Future<_SchedulerHarness> create(
    ModelClient modelClient, {
    AgentBackgroundControl? backgroundAgent,
    AgentTaskStore? taskStore,
    MemoryConversationStore? conversationStore,
    Duration streamPersistenceInterval = const Duration(milliseconds: 500),
  }) async {
    final settings = FakeSettingsService(modelKey: 'scheduler-test');
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    final repository = ResultRepository(
      vault: vault,
      index: index,
      deviceId: 'scheduler-test',
    );
    await repository.initialize();
    final results = ResultLibrary(repository: repository);
    await results.initialize();
    final capture = CaptureWorkflow(
      repository: repository,
      results: results,
      indexDatabase: index,
      captureService: CaptureService(
        settings: settings,
        parser: const DeterministicParser(),
        modelClient: modelClient,
      ),
    );
    await capture.initialize();
    final chatRepository = ChatRepository(
      store: conversationStore ?? MemoryConversationStore(),
      attachments: MemoryAttachmentStore(),
    );
    await chatRepository.initialize();
    final workspace = ConversationWorkspace(
      repository: chatRepository,
      results: results,
      chatService: ChatService(
        settings: settings,
        repository: chatRepository,
        modelClient: modelClient,
      ),
      autoRecordProcessor: AutoRecordProcessor(
        chatRepository: chatRepository,
        results: results,
        captures: capture,
        deviceId: () => repository.deviceId,
      ),
      defaultPolicy: () => AiPolicy.forPreset(AiPolicyPreset.standard),
      backgroundAgent: backgroundAgent,
      taskStore: taskStore,
      streamPersistenceInterval: streamPersistenceInterval,
    );
    await workspace.initialize();
    return _SchedulerHarness(
      workspace: workspace,
      chatRepository: chatRepository,
      results: results,
    );
  }

  Future<void> close() async {
    await workspace.shutdown();
    await chatRepository.close();
    await results.shutdown();
    results.dispose();
  }
}

class _PausedCheckpointGateStore extends MemoryAgentTaskStore {
  final Completer<void> pausedCheckpointSaveStarted = Completer<void>();
  final Completer<void> _releasePausedCheckpointSave = Completer<void>();

  void releasePausedCheckpointSave() {
    if (!_releasePausedCheckpointSave.isCompleted) {
      _releasePausedCheckpointSave.complete();
    }
  }

  @override
  Future<void> save(AgentTaskCheckpoint checkpoint) async {
    if (!pausedCheckpointSaveStarted.isCompleted &&
        checkpoint.turns.any(
          (turn) => turn.status == AgentTurnCheckpointStatus.paused,
        )) {
      pausedCheckpointSaveStarted.complete();
      await _releasePausedCheckpointSave.future;
    }
    await super.save(checkpoint);
  }
}

class _PauseCheckpointFailureStore extends MemoryAgentTaskStore {
  int failedWrites = 0;

  @override
  Future<void> save(AgentTaskCheckpoint checkpoint) async {
    if (failedWrites < 2 &&
        checkpoint.turns.any(
          (turn) =>
              turn.status == AgentTurnCheckpointStatus.paused ||
              turn.status == AgentTurnCheckpointStatus.needsReview,
        )) {
      failedWrites++;
      throw StateError('injected pause checkpoint save failure');
    }
    await super.save(checkpoint);
  }
}
