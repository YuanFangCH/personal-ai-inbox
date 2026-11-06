// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart'
    show Key, ListView, NavigationBar, SelectableText, ValueKey, debugDumpApp;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/ai_policy.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/data/io_vault_store.dart';
import 'package:personal_ai_inbox/data/sqlite_conversation_store.dart';
import 'package:personal_ai_inbox/data/sqlite_index_database.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_background_control.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_task_store.dart';
import 'package:personal_ai_inbox/modules/tables/table_library.dart';
import 'package:personal_ai_inbox/services/agent_background_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import '../test/test_support.dart';

const _modelPort = 47631;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment(
    'E2E_AGENT_PHASE',
    defaultValue: 'longrun',
  );
  const profile = String.fromEnvironment(
    'E2E_DEVICE_PROFILE',
    defaultValue: 'phone',
  );
  const durationSeconds = int.fromEnvironment(
    'E2E_DURATION_SECONDS',
    defaultValue: 900,
  );
  testWidgets('production agent device acceptance: $profile / $phase', (
    tester,
  ) async {
    if (profile != 'phone' && profile != 'tablet') {
      fail('E2E_DEVICE_PROFILE must be phone or tablet.');
    }
    if (phase == 'recover_after_force_stop') {
      print('AGENT_TEST_READY|' + profile + '|' + phase);
      await _verifyExplicitRecovery(tester, profile);
      return;
    }

    final harness = await _ProductionHarness.open(
      profile: profile,
      phase: phase,
      resetSyntheticData: phase != 'recover_after_force_stop',
      startModelServer: true,
    );
    print('AGENT_TEST_SETUP|harness_open');
    addTearDown(harness.close);

    final logicalWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    if (profile == 'phone') {
      expect(logicalWidth, lessThan(600));
    } else {
      expect(logicalWidth, greaterThanOrEqualTo(600));
    }
    print('AGENT_TEST_SETUP|pump_widget_start');
    await tester.pumpWidget(PersonalAiInboxApp(runtime: harness.runtime));
    print('AGENT_TEST_SETUP|pump_widget_done');
    print('AGENT_TEST_SETUP|pump_start');
    await tester.pump();
    print('AGENT_TEST_SETUP|pump_done');
    print('AGENT_TEST_READY|' + profile + '|' + phase);

    switch (phase) {
      case 'longrun':
        try {
          await _runFifteenMinuteBusinessTask(
            tester,
            harness,
            Duration(seconds: durationSeconds),
          );
        } on Object catch (error, stackTrace) {
          await harness.emitFailureArchive(error, stackTrace);
          rethrow;
        }
        break;
      case 'prepare_force_stop':
        await _prepareForceStop(tester, harness);
        break;
      case 'activity_recreate':
        await _verifyActivityRecreation(tester, harness);
        break;
      case 'service_interrupted':
        await _verifyNativeServiceStop(
          tester,
          harness,
          failureCode: 'service_interrupted',
        );
        break;
      case 'service_timeout':
        await _verifyNativeServiceStop(
          tester,
          harness,
          failureCode: 'data_sync_timeout',
        );
        break;
      case 'notification_denied':
        await _verifyNotificationDenial(tester, harness);
        break;
      case 'service_restricted':
        await _verifyServiceRestricted(tester, harness);
        break;
      default:
        fail('Unknown E2E_AGENT_PHASE: $phase');
    }
  }, timeout: const Timeout(Duration(minutes: 22)));
}

Future<void> _runFifteenMinuteBusinessTask(
  WidgetTester tester,
  _ProductionHarness harness,
  Duration duration,
) async {
  if (duration < const Duration(minutes: 15)) {
    fail('Sustained acceptance must run for at least 900 wall-clock seconds.');
  }
  final table = harness.runtime.tables.tableForInboxAssignment(
    InboxAssignmentKind.event,
  );
  if (table == null) fail('Synthetic event inbox table was not initialized.');
  final conversation = await harness.runtime.conversations.createConversation(
    policy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
  );
  await harness.runtime.conversations.openConversation(conversation.id);
  await tester.tap(find.byKey(const Key('nav_inbox')));
  await tester.pump(const Duration(milliseconds: 300));
  harness.fixture.conversationId = conversation.id;
  harness.longrunConversationId = conversation.id;
  final timer = Stopwatch()..start();
  var didPauseResume = false;
  Object? failure;
  harness.fixture.stopAfter(duration);
  final turn = harness.runtime.conversations.sendChatMessage(
    conversation.id,
    text: '持续整理合成测试资料；每完成一条都读取并核对本地回执，直到任务结束。',
  );
  harness.activeBusinessTurn = turn;
  unawaited(
    turn.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        failure = error;
      },
    ),
  );
  print(
    'AGENT_LONGTASK_STARTED|' +
        harness.profile +
        '|' +
        conversation.id +
        '|' +
        DateTime.now().toIso8601String(),
  );

  var lastVerified = 0;
  var observedFinalStreamPrefix = false;
  while (harness.backgroundService.snapshot.state !=
          AgentBackgroundState.completed &&
      timer.elapsed < duration + const Duration(minutes: 2)) {
    await _pumpReal(tester, const Duration(seconds: 1));
    if (harness.fixture.finalTextFirstDeltaSent.isCompleted &&
        !observedFinalStreamPrefix) {
      const prefix = '合成资料已写入';
      try {
        await _waitFor(
          tester,
          () => harness.runtime.conversations
              .messagesFor(conversation.id)
              .where((message) => !message.isUser)
              .any(
                (message) =>
                    message.status == ChatMessageStatus.streaming &&
                    message.content.contains(prefix),
              ),
          timeout: const Duration(seconds: 10),
        );
      } on Object catch (error) {
        final finalStreamDiagnostic = <String, Object?>{
          'error': error.toString(),
          'conversation_id': conversation.id,
          'active_conversation_id':
              harness.runtime.conversations.activeConversationId,
          'is_chat_generating': harness.runtime.conversations.isChatGenerating,
          'background_state': harness.backgroundService.snapshot.state.name,
          'background_task_id': harness.backgroundService.snapshot.taskId,
          'verified_count': harness.fixture.verifiedCount,
          'request_count': harness.fixture.requestCount,
          'messages': harness.runtime.conversations
              .messagesFor(conversation.id)
              .map(
                (message) => <String, Object?>{
                  'id': message.id,
                  'is_user': message.isUser,
                  'status': message.status.wireName,
                  'content': message.content,
                },
              )
              .toList(growable: false),
        };
        await harness.fixture.record({
          'kind': 'final_stream_wait_failed',
          ...finalStreamDiagnostic,
        });
        print(
          'AGENT_LONGRUN_FINAL_STREAM_DIAGNOSTIC|' +
              jsonEncode(finalStreamDiagnostic),
        );
        rethrow;
      }
      await tester.pump(const Duration(milliseconds: 100));
      final navigationBar = find.byType(NavigationBar);
      final homeDestination = find.byKey(const Key('nav_home')).hitTestable();
      if (navigationBar.evaluate().isNotEmpty &&
          homeDestination.evaluate().isNotEmpty) {
        await tester.tap(homeDestination);
        await tester.pump(const Duration(milliseconds: 500));
      }
      final secretaryDestination = find
          .byKey(const Key('nav_inbox'))
          .hitTestable();
      if (navigationBar.evaluate().isNotEmpty) {
        expect(secretaryDestination, findsOneWidget);
        await tester.tap(secretaryDestination);
        await tester.pump(const Duration(milliseconds: 500));
      }
      await _scrollConversationToBottom(tester);
      final renderedPrefix = find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            (widget.textSpan?.toPlainText() ?? widget.data ?? '').contains(
              prefix,
            ),
      );
      if (renderedPrefix.evaluate().isEmpty) {
        final assistant = harness.runtime.conversations
            .messagesFor(conversation.id)
            .lastWhere((message) => !message.isUser);
        print(
          'AGENT_LONGRUN_UI_DIAGNOSTIC|' +
              jsonEncode({
                'current_conversation':
                    harness.runtime.conversations.activeConversationId,
                'message_id': assistant.id,
                'message_status': assistant.status.wireName,
                'message_content': assistant.content,
                'navigation_selected_index': navigationBar.evaluate().isEmpty
                    ? null
                    : tester.widget<NavigationBar>(navigationBar).selectedIndex,
                'secretary_mounted': find
                    .byKey(const ValueKey('persistent_secretary'))
                    .evaluate()
                    .isNotEmpty,
                'message_row_mounted': find
                    .byKey(ValueKey('message_${assistant.id}'))
                    .evaluate()
                    .isNotEmpty,
                'selectable_text_count': find
                    .byType(SelectableText)
                    .evaluate()
                    .length,
                'conversation_list_mounted': find
                    .byKey(const ValueKey('conversation_message_list'))
                    .evaluate()
                    .isNotEmpty,
              }),
        );
        debugDumpApp();
      }
      expect(
        renderedPrefix,
        findsWidgets,
        reason: 'The first SSE fragment must render in the production UI.',
      );
      final prefixRect = tester.getRect(renderedPrefix.first);
      final screenRect = Rect.fromLTWH(
        0,
        0,
        tester.view.physicalSize.width / tester.view.devicePixelRatio,
        tester.view.physicalSize.height / tester.view.devicePixelRatio,
      );
      expect(
        prefixRect.overlaps(screenRect),
        isTrue,
        reason:
            'The streamed assistant prefix must be on-screen before release.',
      );
      final partial = harness.runtime.conversations
          .messagesFor(conversation.id)
          .lastWhere((message) => !message.isUser);
      await harness.fixture.record({
        'kind': 'stream_partial_consumed',
        'elapsed_ms': timer.elapsedMilliseconds,
        'assistant_message_id': partial.id,
        'assistant_status': partial.status.wireName,
        'visible_prefix_length': prefix.length,
        'widget_rendered': true,
        'widget_rect': {
          'left': prefixRect.left,
          'top': prefixRect.top,
          'right': prefixRect.right,
          'bottom': prefixRect.bottom,
        },
        'text_delta_frames': harness.fixture.textDeltaFrames,
      });
      harness.fixture.releaseFinalTextDelta();
      observedFinalStreamPrefix = true;
    }
    if (harness.fixture.verifiedCount > lastVerified) {
      lastVerified = harness.fixture.verifiedCount;
      await harness.runtime.tables.refresh();
      final checkpoint = await harness.taskStore.load();
      harness.lastObservedCheckpoint = checkpoint;
      harness.observeLongrunCheckpoint(checkpoint);
      final entryId = harness.fixture.lastReceiptEntryId;
      expect(
        harness.runtime.tables.entries.where((entry) => entry.id == entryId),
        hasLength(1),
        reason:
            'The verified create receipt must resolve to exactly one indexed entry. '
            'entry_id=$entryId title=${harness.fixture.lastCreatedTitle} '
            'entries=${harness.runtime.tables.entries.map((entry) => '${entry.id}:${entry.title}').join('|')}',
      );
      expect(
        checkpoint.budget.usedRequests,
        inInclusiveRange(
          harness.fixture.requestCount,
          harness.fixture.requestCount + 1,
        ),
        reason: 'Persisted budget may include the single request reserved before the fixture receives it.',
      );
      expect(
        harness.fixture.toolDeltaFrames,
        greaterThanOrEqualTo(lastVerified * 2),
      );
      await harness.fixture.record({
        'kind': 'business_progress',
        'elapsed_ms': timer.elapsedMilliseconds,
        'verified_count': lastVerified,
        'entry_count': harness.runtime.tables.entries.length,
        'used_requests': checkpoint.budget.usedRequests,
        'model_request_count': harness.fixture.requestCount,
        'tool_delta_frames': harness.fixture.toolDeltaFrames,
        'checkpoint_turns': checkpoint.turns.length,
      });
      if (!didPauseResume) {
        await _switchMainPages(tester);
        await harness.fixture.record({
          'kind': 'page_switch',
          'elapsed_ms': timer.elapsedMilliseconds,
          'from': 'home',
          'through': 'tables',
          'to': 'secretary',
        });
        final runningTurns = checkpoint.turns
            .where(
              (turn) =>
                  turn.conversationId == conversation.id &&
                  turn.status == AgentTurnCheckpointStatus.running,
            )
            .toList(growable: false);
        expect(
          runningTurns,
          hasLength(1),
          reason: 'The business pause must target exactly one current task.',
        );
        await harness.runtime.conversations.pauseGeneration(
          reason: '验收任务主动暂停以检查持久检查点。',
        );
        await _waitFor(
          tester,
          () => !harness.runtime.conversations.isChatGenerating,
        );
        final paused = await harness.taskStore.load();
        harness.lastObservedCheckpoint = paused;
        harness.observeLongrunCheckpoint(paused);
        expect(
          paused.turns.where(
            (turn) =>
                turn.taskId == runningTurns.single.taskId &&
                turn.assistantMessageId ==
                    runningTurns.single.assistantMessageId &&
                turn.status == AgentTurnCheckpointStatus.paused,
          ),
          hasLength(1),
        );
        final pausedTurn = runningTurns.single;
        await harness.runtime.conversations.resumeTasks(
          taskId: pausedTurn.effectiveBudgetRunId,
        );
        await _waitFor(
          tester,
          () => harness.runtime.conversations.isChatGenerating,
        );
        await harness.fixture.record({
          'kind': 'pause_resume',
          'elapsed_ms': timer.elapsedMilliseconds,
          'checkpoint_turns': paused.turns.length,
        });
        print(
          'AGENT_BACKGROUND_LOCK_READY|' +
              harness.profile +
              '|' +
              timer.elapsedMilliseconds.toString(),
        );
        didPauseResume = true;
      }
      print(
        'AGENT_LONGTASK_PROGRESS|' +
            harness.profile +
            '|' +
            '$lastVerified' +
            '|' +
            timer.elapsedMilliseconds.toString() +
            '|' +
            checkpoint.budget.usedRequests.toString() +
            '|' +
            checkpoint.turns.length.toString(),
      );
    }
  }
  timer.stop();
  if (harness.backgroundService.snapshot.state !=
      AgentBackgroundState.completed) {
    fail('Business task exceeded the wall-clock timeout.');
  }
  if (failure != null) fail('Production task failed: $failure');
  expect(timer.elapsed, greaterThanOrEqualTo(duration));
  expect(harness.fixture.verifiedCount, greaterThanOrEqualTo(1));
  final status = await harness.backgroundService.refreshStatus();
  expect(status.state, AgentBackgroundState.completed);
  await harness.runtime.tables.refresh();
  final notes = harness.runtime.tables.entries
      .where(
        (entry) =>
            entry.title.startsWith('Luna ' + harness.profile + ' entry '),
      )
      .toList(growable: false);
  expect(notes, isNotEmpty);
  expect(harness.fixture.writeReceipts, notes.length);
  // The final verification directly completes the task, so the fixture may
  // observe one fewer echoed verify tool message than verify results.
  expect(
    harness.fixture.verifyToolCalls,
    inInclusiveRange(
      harness.fixture.verifiedCount - 1,
      harness.fixture.verifiedCount,
    ),
  );
  expect(harness.fixture.readToolCalls, greaterThan(0));
  expect(harness.fixture.finalTextFirstDeltaSent.isCompleted, isTrue);
  expect(harness.fixture.finalTextSecondDeltaSent.isCompleted, isTrue);
  expect(observedFinalStreamPrefix, isTrue);
  expect(harness.fixture.textDeltaFrames, 2);
  expect(
    harness.runtime.conversations
        .messagesFor(conversation.id)
        .where((message) => !message.isUser)
        .last
        .content,
    '合成资料已写入并通过本地回执核对。',
  );
  final checkpoint = await harness.taskStore.load();
  expect(
    checkpoint.budget.usedRequests,
    harness.fixture.requestCount,
    reason: 'Final persisted budget must equal fixture model request count.',
  );
  expect(
    harness.fixture.toolDeltaFrames,
    greaterThanOrEqualTo(harness.fixture.verifiedCount * 4),
  );
  await harness.fixture.record({
    'kind': 'business_task_complete',
    'profile': harness.profile,
    'wall_clock_seconds': timer.elapsed.inSeconds,
    'model_requests': harness.fixture.requestCount,
    'tool_delta_frames': harness.fixture.toolDeltaFrames,
    'text_delta_frames': harness.fixture.textDeltaFrames,
    'stream_partial_consumed': observedFinalStreamPrefix,
    'read_tool_calls': harness.fixture.readToolCalls,
    'write_receipts': harness.fixture.writeReceipts,
    'verify_tool_calls': harness.fixture.verifyToolCalls,
    'verified_entries': harness.fixture.verifiedCount,
    'checkpoint_budget_requests': checkpoint.budget.usedRequests,
    'checkpoint_turns': checkpoint.turns.length,
  });
  print(
    'AGENT_LONGTASK_RESULT|' +
        harness.profile +
        '|passed|' +
        timer.elapsed.inSeconds.toString() +
        '|' +
        harness.fixture.verifiedCount.toString(),
  );
}

Future<void> _switchMainPages(WidgetTester tester) async {
  final more = find.byKey(const Key('nav_more'));
  if (more.evaluate().isNotEmpty) {
    await tester.tap(more);
    await tester.pump(const Duration(milliseconds: 300));
  }
  final tables = find.byKey(const Key('sheet_nav_matters'));
  if (tables.evaluate().isNotEmpty) {
    await tester.tap(tables);
  } else {
    await tester.tap(find.byKey(const Key('nav_matters')));
  }
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.byKey(const Key('nav_inbox')));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _scrollConversationToBottom(WidgetTester tester) async {
  final listFinder = find.byKey(const ValueKey('conversation_message_list'));
  if (listFinder.evaluate().isEmpty) {
    print('AGENT_LONGRUN_SCROLL_DIAGNOSTIC|conversation_list_not_mounted');
    return;
  }
  final list = tester.widget<ListView>(listFinder);
  final controller = list.controller;
  if (controller == null || !controller.hasClients) {
    print('AGENT_LONGRUN_SCROLL_DIAGNOSTIC|controller_unavailable');
    return;
  }
  if (!controller.position.hasContentDimensions) {
    await tester.pump();
  }
  controller.jumpTo(controller.position.maxScrollExtent);
  await tester.pump(const Duration(milliseconds: 100));
  controller.jumpTo(controller.position.maxScrollExtent);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _prepareForceStop(
  WidgetTester tester,
  _ProductionHarness harness,
) async {
  final conversation = await _startTask(harness, '创建一条合成资料，然后等待我核对后继续。');
  harness.fixture.conversationId = conversation.id;
  await harness.fixture.blocked.future.timeout(const Duration(minutes: 2));
  await harness.runtime.tables.refresh();
  final checkpoint = await harness.taskStore.load();
  final runningTurns = checkpoint.turns
      .where((turn) => turn.status == AgentTurnCheckpointStatus.running)
      .toList(growable: false);
  expect(
    runningTurns,
    hasLength(1),
    reason: 'force-stop fixture must identify its one running task',
  );
  final runningTurn = runningTurns.single;
  final title = harness.fixture.lastCreatedTitle;
  expect(title, isNotNull);
  final entry = harness.runtime.tables.entries.singleWhere(
    (value) => value.title == title,
  );
  final operationId = harness.fixture.lastOperationId;
  expect(operationId, isNotEmpty);
  expect(harness.fixture.lastReceiptStatus, 'succeeded');
  expect(harness.fixture.lastReceiptActionId, operationId);
  expect(harness.fixture.lastReceiptEntryId, entry.id);
  expect(harness.fixture.lastReceiptTableId, harness.fixture.tableId);
  expect(entry.tableId, harness.fixture.lastReceiptTableId);
  await harness.fixture.record({
    'kind': 'force_stop_ready',
    'conversation_id': conversation.id,
    'task_id': runningTurn.taskId,
    'assistant_message_id': runningTurn.assistantMessageId,
    'operation_id': operationId,
    'entry_id': entry.id,
    'receipt_status': harness.fixture.lastReceiptStatus,
    'receipt_action_id': harness.fixture.lastReceiptActionId,
    'receipt_entry_id': harness.fixture.lastReceiptEntryId,
    'receipt_table_id': harness.fixture.lastReceiptTableId,
    'table_id': harness.fixture.tableId,
    'title': title,
    'model_requests': await harness.fixture.readModelRequestCount(),
  });
  print(
    'AGENT_FORCE_STOP_READY|' +
        conversation.id +
        '|' +
        operationId +
        '|' +
        entry.id,
  );
  await Completer<void>().future;
}

Future<void> _verifyExplicitRecovery(
  WidgetTester tester,
  String profile,
) async {
  final harness = await _ProductionHarness.open(
    profile: profile,
    phase: 'recover_after_force_stop',
    resetSyntheticData: false,
    startModelServer: false,
    observeRequestsBeforeResume: true,
  );
  addTearDown(harness.close);
  await tester.pumpWidget(PersonalAiInboxApp(runtime: harness.runtime));
  await tester.pump();

  final ready = await harness.fixture.readLastKind('force_stop_ready');
  expect(ready, isNotNull, reason: 'force-stop fixture was not persisted');
  final event = ready!;
  final conversationId = event['conversation_id'].toString();
  final taskId = event['task_id'].toString();
  final operationId = event['operation_id'].toString();
  final entryId = event['entry_id'].toString();
  final title = event['title'].toString();
  expect(event['receipt_status'], 'succeeded');
  expect(event['receipt_action_id'], operationId);
  expect(event['receipt_entry_id'], entryId);
  expect(event['receipt_table_id'], event['table_id']);
  expect(taskId, isNotEmpty);
  expect(event['assistant_message_id'], isNotEmpty);
  final requestsBefore = await harness.fixture.readModelRequestCount();
  expect(requestsBefore, event['model_requests']);
  await _waitReal(tester, const Duration(seconds: 15));
  expect(await harness.fixture.readModelRequestCount(), requestsBefore);
  expect(
    await harness.fixture.readEventCount('pre_resume_request_rejected'),
    0,
    reason: 'reopened work must not send HTTP before explicit resume',
  );
  expect(harness.runtime.conversations.isChatGenerating, isFalse);
  expect(harness.runtime.conversations.hasTasksNeedingReview, isTrue);
  await harness.runtime.tables.refresh();
  expect(
    harness.runtime.tables.entries.where((entry) => entry.id == entryId),
    hasLength(1),
  );
  expect(
    harness.runtime.tables.entries.where((entry) => entry.title == title),
    hasLength(1),
  );
  await harness.runtime.conversations.openConversation(conversationId);
  await harness.fixture.startServer();
  await harness.runtime.conversations.resumeTasks(
    taskId: taskId,
    approveUncertainEffects: true,
  );
  await _waitFor(
    tester,
    () =>
        harness.fixture.verifiedCount > 0 &&
        !harness.runtime.conversations.isChatGenerating &&
        !harness.runtime.conversations.hasTasksNeedingReview,
    timeout: const Duration(minutes: 2),
  );
  await harness.runtime.tables.refresh();
  expect(
    harness.runtime.tables.entries.where((entry) => entry.id == entryId),
    hasLength(1),
  );
  expect(harness.fixture.lastOperationId, operationId);
  expect(harness.fixture.lastReceiptStatus, 'succeeded');
  expect(harness.fixture.lastReceiptActionId, operationId);
  expect(harness.fixture.lastReceiptEntryId, entryId);
  expect(harness.fixture.lastReceiptTableId, event['table_id']);
  final recoveredEntry = harness.runtime.tables.entries.singleWhere(
    (entry) => entry.id == entryId,
  );
  expect(recoveredEntry.tableId, event['receipt_table_id']);
  final recoveredReceipt = await harness.fixture.readLastKind('write_receipt');
  expect(recoveredReceipt, isNotNull);
  expect(recoveredReceipt!['operation_id'], operationId);
  expect(recoveredReceipt['status'], 'succeeded');
  expect(recoveredReceipt['action_id'], operationId);
  expect(recoveredReceipt['entry_id'], entryId);
  expect(recoveredReceipt['table_id'], event['table_id']);
  expect(harness.fixture.verifiedCount, greaterThan(0));
  expect(
    await harness.fixture.readEventCount('verification_result'),
    greaterThanOrEqualTo(1),
  );
  expect(
    await harness.fixture.readModelRequestCount(),
    greaterThan(requestsBefore),
  );
  await harness.fixture.record({
    'kind': 'force_stop_recovery_complete',
    'conversation_id': conversationId,
    'operation_id': operationId,
    'entry_id': entryId,
    'model_requests_before_continue': requestsBefore,
    'model_requests_after_continue': await harness.fixture
        .readModelRequestCount(),
  });
  print('AGENT_FORCE_STOP_RECOVERY_RESULT|' + profile + '|passed|' + entryId);
}

Future<void> _verifyActivityRecreation(
  WidgetTester tester,
  _ProductionHarness harness,
) async {
  await _startBlockedTask(harness);
  await harness.fixture.blocked.future.timeout(const Duration(minutes: 2));
  final originalReceipt = await _captureWriteReceipt(harness.fixture);
  final verifiedBefore = harness.fixture.verifiedCount;
  final taskId = harness.backgroundService.snapshot.taskId;
  expect(taskId, isNotEmpty);
  print('AGENT_ACTIVITY_RECREATE_READY|' + harness.profile);
  await _waitReal(tester, const Duration(seconds: 12));
  final status = await harness.backgroundService.refreshStatus();
  expect(status.state, AgentBackgroundState.running);
  expect(status.taskId, taskId);
  expect(status.activityAttached, isTrue);
  final checkpoint = await harness.taskStore.load();
  expect(
    checkpoint.turns.where((turn) => turn.assistantMessageId == taskId),
    hasLength(1),
  );
  await harness.runtime.tables.refresh();
  expect(
    harness.runtime.tables.entries.where(
      (entry) => entry.title == harness.fixture.lastCreatedTitle,
    ),
    hasLength(1),
  );
  harness.fixture.releaseBlocked();
  await _waitFor(tester, () => !harness.runtime.conversations.isChatGenerating);
  await harness.runtime.tables.refresh();
  expect(harness.fixture.verifiedCount, greaterThan(verifiedBefore));
  expect(
    harness.runtime.tables.entries.where(
      (entry) => entry.title == harness.fixture.lastCreatedTitle,
    ),
    hasLength(1),
  );
  final recreatedEntry = harness.runtime.tables.entries.singleWhere(
    (entry) => entry.title == harness.fixture.lastCreatedTitle,
  );
  expect(recreatedEntry.id, originalReceipt['entry_id']);
  expect(recreatedEntry.tableId, originalReceipt['table_id']);
  await _expectSameWriteReceipt(
    harness.fixture,
    originalReceipt,
    recreatedEntry.id,
  );
  print('AGENT_ACTIVITY_RECREATE_RESULT|' + harness.profile + '|passed');
}

Future<void> _verifyNativeServiceStop(
  WidgetTester tester,
  _ProductionHarness harness, {
  required String failureCode,
}) async {
  await _startBlockedTask(harness);
  await harness.fixture.blocked.future.timeout(const Duration(minutes: 2));
  final originalReceipt = await _captureWriteReceipt(harness.fixture);
  final verifiedBefore = harness.fixture.verifiedCount;
  final assistantMessageId = harness.backgroundService.snapshot.taskId;
  expect(assistantMessageId, isNotEmpty);
  final stableAssistantMessageId = assistantMessageId!;
  final checkpointBeforeStop = await harness.taskStore.load();
  final matchingTurns = checkpointBeforeStop.turns
      .where((turn) => turn.assistantMessageId == stableAssistantMessageId)
      .toList(growable: false);
  expect(matchingTurns, hasLength(1));
  final stableTaskId = matchingTurns.single.taskId;
  print(
    'AGENT_SERVICE_STOP_READY|' +
        harness.profile +
        '|' +
        failureCode +
        '|' +
        stableAssistantMessageId +
        '|' +
        stableTaskId,
  );
  await _waitFor(
    tester,
    () =>
        harness.backgroundService.snapshot.state ==
            AgentBackgroundState.paused &&
        harness.backgroundService.snapshot.failureCode == failureCode,
    timeout: const Duration(seconds: 45),
  );
  await _waitFor(
    tester,
    () => !harness.runtime.conversations.isChatGenerating,
    timeout: const Duration(seconds: 45),
  );
  final checkpoint = await harness.taskStore.load();
  expect(
    checkpoint.turns.any(
      (turn) =>
          turn.status == AgentTurnCheckpointStatus.paused ||
          turn.status == AgentTurnCheckpointStatus.needsReview,
    ),
    isTrue,
  );
  await harness.runtime.tables.refresh();
  final created = harness.runtime.tables.entries
      .where((entry) => entry.title == harness.fixture.lastCreatedTitle)
      .toList(growable: false);
  expect(created, hasLength(1));
  expect(created.single.id, originalReceipt['entry_id']);
  expect(created.single.tableId, originalReceipt['table_id']);
  harness.fixture.releaseBlocked();
  await harness.runtime.conversations.resumeTasks(
    taskId: stableTaskId,
    approveUncertainEffects: true,
  );
  await _waitFor(
    tester,
    () =>
        !harness.runtime.conversations.isChatGenerating &&
        !harness.runtime.conversations.hasTasksNeedingReview &&
        harness.fixture.verifiedCount > verifiedBefore,
    timeout: const Duration(minutes: 2),
  );
  await harness.runtime.tables.refresh();
  expect(
    harness.runtime.tables.entries.where(
      (entry) => entry.id == created.single.id,
    ),
    hasLength(1),
  );
  expect(harness.fixture.verifiedCount, greaterThan(verifiedBefore));
  await _expectSameWriteReceipt(
    harness.fixture,
    originalReceipt,
    created.single.id,
  );
  print(
    'AGENT_SERVICE_STOP_RESULT|' +
        harness.profile +
        '|' +
        failureCode +
        '|passed',
  );
}

Future<void> _verifyNotificationDenial(
  WidgetTester tester,
  _ProductionHarness harness,
) async {
  print('AGENT_NOTIFICATION_DENIED_PREPARE|' + harness.profile);
  await harness.fixture.notificationDeniedPermissionBarrier.future.timeout(
    const Duration(seconds: 60),
    onTimeout: () => throw TimeoutException(
      'Host did not establish user-fixed notification denial.',
    ),
  );
  final status = harness.backgroundService.status;
  final deniedPermission = Completer<AgentBackgroundSnapshot>();
  void captureDeniedPermission() {
    final snapshot = status.value;
    if (snapshot.state == AgentBackgroundState.notificationPermissionDenied &&
        !deniedPermission.isCompleted) {
      deniedPermission.complete(snapshot);
    }
  }

  status.addListener(captureDeniedPermission);
  try {
    final conversation = await _startTask(harness, '创建一条通知拒绝场景的合成笔记并核验。');
    final permission = await deniedPermission.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException(
        'Workspace did not observe the denied permission request.',
      ),
    );
    expect(permission.state, AgentBackgroundState.notificationPermissionDenied);
    expect(permission.notificationPermissionGranted, isFalse);
    await _waitFor(
      tester,
      () => !harness.runtime.conversations.isChatGenerating,
    );
    await harness.runtime.tables.refresh();
    final entry = harness.runtime.tables.entries.singleWhere(
      (value) => value.title == harness.fixture.lastCreatedTitle,
    );
    expect(harness.fixture.verifiedCount, 1);
    final receipt = await _captureWriteReceipt(harness.fixture);
    expect(receipt['entry_id'], entry.id);
    expect(receipt['table_id'], entry.tableId);
    final assistant = harness.runtime.conversations
        .messagesFor(conversation.id)
        .lastWhere((message) => message.role == ChatRole.assistant);
    expect(assistant.status, ChatMessageStatus.complete);
    expect(assistant.error, contains('通知权限被拒绝'));

    // Native refresh reports the persisted background-task state, which may
    // describe an older service restriction. Permission capability has its
    // own field and is the value that remains current after this request.
    final refreshed = await harness.backgroundService.refreshStatus();
    expect(refreshed.notificationPermissionGranted, isFalse);
    expect(
      harness.runtime.tables.entries.where((value) => value.id == entry.id),
      hasLength(1),
    );
    print('AGENT_NOTIFICATION_DENIED_RESULT|' + conversation.id + '|passed');
  } finally {
    status.removeListener(captureDeniedPermission);
  }
}

Future<void> _verifyServiceRestricted(
  WidgetTester tester,
  _ProductionHarness harness,
) async {
  final status = harness.backgroundService.status;
  final restrictedEvent = Completer<AgentBackgroundSnapshot>();
  void captureRestrictedEvent() {
    final snapshot = status.value;
    if (snapshot.state == AgentBackgroundState.serviceRestricted &&
        !restrictedEvent.isCompleted) {
      restrictedEvent.complete(snapshot);
    }
  }

  status.addListener(captureRestrictedEvent);
  captureRestrictedEvent();
  try {
    print('AGENT_SERVICE_RESTRICTED_BACKGROUND_READY|${harness.profile}');
    await harness.fixture.serviceRestrictedBackgroundStartBarrier.future
        .timeout(
          const Duration(minutes: 2),
          onTimeout: () => throw StateError(
            'Host runner did not confirm the app was backgrounded before starting the restricted task.',
          ),
        );
    final conversation = await _startTask(harness, '创建一条服务受限场景的合成笔记并核验。');
    final restricted = await restrictedEvent.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => throw StateError(
        'Foreground-service restriction status event was not observed.',
      ),
    );
    expect(restricted.keepsRuntimeAlive, isFalse);
    expect(restricted.failureCode, isNotEmpty);
    final assistantMessageId = restricted.taskId;
    if (assistantMessageId == null || assistantMessageId.isEmpty) {
      fail('Restricted callback did not carry the original assistant task ID.');
    }
    AgentTurnCheckpoint? pausedTurn;
    final checkpointTimer = Stopwatch()..start();
    while (checkpointTimer.elapsed < const Duration(minutes: 2)) {
      final checkpoint = await harness.taskStore.load();
      final matchingTurns = checkpoint.turns
          .where((turn) => turn.assistantMessageId == assistantMessageId)
          .toList(growable: false);
      if (matchingTurns.length > 1) {
        fail('Restricted assistant ID matched multiple checkpoint turns.');
      }
      if (matchingTurns.length == 1) {
        final matchingTurn = matchingTurns.single;
        if (matchingTurn.status == AgentTurnCheckpointStatus.paused &&
            !harness.runtime.conversations.isChatGenerating) {
          pausedTurn = matchingTurn;
          break;
        }
      }
      await _pumpReal(tester, const Duration(milliseconds: 100));
    }
    if (pausedTurn == null) {
      fail('Restricted callback did not pause its matching checkpointed turn.');
    }
    final paused = pausedTurn;
    expect(paused.assistantMessageId, assistantMessageId);
    expect(harness.fixture.requestCount, 0);
    expect(await harness.fixture.readLastKind('write_receipt'), isNull);
    harness.fixture.serviceRestrictedAssistantMessageId = assistantMessageId;
    harness.fixture.serviceRestrictedTaskId = paused.taskId;
    print(
      'AGENT_SERVICE_RESTRICTED_READY|' +
          assistantMessageId +
          '|' +
          paused.taskId,
    );

    await harness.fixture.serviceRestrictedResumeBarrier.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => throw StateError(
        'Host runner did not acknowledge restored START_FOREGROUND before resume.',
      ),
    );
    await harness.runtime.conversations.resumeTasks(taskId: paused.taskId);
    await _waitFor(
      tester,
      () =>
          harness.fixture.verifiedCount > 0 &&
          !harness.runtime.conversations.isChatGenerating &&
          !harness.runtime.conversations.hasTasksNeedingReview,
      timeout: const Duration(minutes: 2),
    );
    await harness.runtime.tables.refresh();
    final created = harness.runtime.tables.entries
        .where((entry) => entry.title == harness.fixture.lastCreatedTitle)
        .toList(growable: false);
    expect(created, hasLength(1));
    expect(harness.fixture.verifiedCount, 1);
    final receipt = await _captureWriteReceipt(harness.fixture);
    await _expectSameWriteReceipt(harness.fixture, receipt, created.single.id);
    print(
      'AGENT_SERVICE_RESTRICTED_RESULT|' +
          harness.profile +
          '|' +
          conversation.id +
          '|' +
          assistantMessageId +
          '|' +
          paused.taskId +
          '|' +
          restricted.failureCode.toString() +
          '|passed',
    );
  } finally {
    status.removeListener(captureRestrictedEvent);
  }
}

Future<Conversation> _startTask(
  _ProductionHarness harness,
  String prompt,
) async {
  final conversation = await harness.runtime.conversations.createConversation(
    policy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
  );
  await harness.runtime.conversations.openConversation(conversation.id);
  harness.fixture.conversationId = conversation.id;
  unawaited(
    harness.runtime.conversations.sendChatMessage(
      conversation.id,
      text: prompt,
    ),
  );
  return conversation;
}

Future<Map<String, Object?>> _captureWriteReceipt(
  _DeterministicModelFixture fixture,
) async {
  final receipt = await fixture.readLastKind('write_receipt');
  expect(receipt, isNotNull, reason: 'business write receipt was not recorded');
  expect(receipt!['operation_id'], isNotEmpty);
  expect(receipt['status'], 'succeeded');
  expect(receipt['action_id'], receipt['operation_id']);
  expect(receipt['entry_id'], isNotEmpty);
  expect(receipt['table_id'], isNotEmpty);
  return receipt;
}

Future<void> _expectSameWriteReceipt(
  _DeterministicModelFixture fixture,
  Map<String, Object?> originalReceipt,
  String entryId,
) async {
  expect(fixture.lastOperationId, originalReceipt['operation_id']);
  expect(fixture.lastReceiptStatus, originalReceipt['status']);
  expect(fixture.lastReceiptActionId, originalReceipt['action_id']);
  expect(fixture.lastReceiptEntryId, originalReceipt['entry_id']);
  expect(fixture.lastReceiptTableId, originalReceipt['table_id']);
  expect(fixture.lastReceiptEntryId, entryId);
  final latestReceipt = await fixture.readLastKind('write_receipt');
  expect(latestReceipt, isNotNull);
  for (final key in const [
    'operation_id',
    'status',
    'action_id',
    'entry_id',
    'table_id',
  ]) {
    expect(
      latestReceipt![key],
      originalReceipt[key],
      reason: 'receipt $key changed',
    );
  }
}

Future<void> _startBlockedTask(_ProductionHarness harness) async {
  await _startTask(harness, '记录一条资料，实际写入后停在检查步骤。');
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() predicate, {
  Duration timeout = const Duration(minutes: 16),
}) async {
  final timer = Stopwatch()..start();
  while (timer.elapsed < timeout) {
    if (predicate()) return;
    await _pumpReal(tester, const Duration(milliseconds: 250));
  }
  fail('Condition did not become true within ' + timer.elapsed.toString());
}

Future<void> _pumpReal(WidgetTester tester, Duration duration) async {
  await tester.runAsync(() => Future<void>.delayed(duration));
  await tester.pump();
}

Future<void> _waitReal(WidgetTester tester, Duration duration) async {
  final timer = Stopwatch()..start();
  while (timer.elapsed < duration) {
    await _pumpReal(tester, const Duration(milliseconds: 250));
  }
}

class _ProductionHarness {
  _ProductionHarness({
    required this.profile,
    required this.root,
    required this.runtime,
    required this.fixture,
    required this.backgroundService,
    required this.taskStore,
    required this.modelHttpClient,
  });

  final String profile;
  final Directory root;
  final AppRuntime runtime;
  final _DeterministicModelFixture fixture;
  final AgentBackgroundService backgroundService;
  final VaultAgentTaskStore taskStore;
  final http.Client modelHttpClient;
  Future<void>? activeBusinessTurn;
  AgentTaskCheckpoint? lastObservedCheckpoint;
  String? longrunConversationId;
  String? longrunInitialTaskId;
  String? longrunInitialAssistantMessageId;

  void observeLongrunCheckpoint(AgentTaskCheckpoint checkpoint) {
    final conversationId = longrunConversationId;
    if (conversationId == null || longrunInitialTaskId != null) return;
    final candidates = checkpoint.turns
        .where(
          (turn) =>
              turn.conversationId == conversationId &&
              turn.status == AgentTurnCheckpointStatus.running,
        )
        .toList(growable: false);
    if (candidates.length != 1) return;
    longrunInitialTaskId = candidates.single.taskId;
    longrunInitialAssistantMessageId = candidates.single.assistantMessageId;
  }

  Future<_FailureArchiveFreeze> freezeForFailureArchive() async {
    final errors = <String, String>{};
    final generationWasActive = runtime.conversations.isChatGenerating;
    AgentTaskCheckpoint? beforePauseCheckpoint;
    try {
      beforePauseCheckpoint = await taskStore.load().timeout(
        const Duration(seconds: 8),
      );
      observeLongrunCheckpoint(beforePauseCheckpoint);
    } on Object catch (error) {
      errors['checkpoint_before_pause'] = error.toString();
    }
    final conversationId = longrunConversationId;
    final conversationTurns = beforePauseCheckpoint?.turns
        .where((turn) => turn.conversationId == conversationId)
        .toList(growable: false);
    final activeTurns = (conversationTurns ?? const <AgentTurnCheckpoint>[])
        .where((turn) => turn.status == AgentTurnCheckpointStatus.running)
        .toList(growable: false);
    final target = generationWasActive
        ? (activeTurns.length == 1 ? activeTurns.single : null)
        : _findInitialTarget(conversationTurns ?? const []);
    final pauseAttempted = generationWasActive;
    var pauseSourceSettled = !generationWasActive;
    var pauseOperationSucceeded = !generationWasActive;
    if (generationWasActive) {
      try {
        await runtime.conversations
            .pauseGeneration(reason: '失败归档前冻结合成任务状态。')
            .timeout(const Duration(seconds: 8));
        pauseSourceSettled = true;
        pauseOperationSucceeded = true;
      } on Object catch (error) {
        errors['pause_generation'] = error.toString();
      }
    }

    final generationStopwatch = Stopwatch()..start();
    while (runtime.conversations.isChatGenerating &&
        generationStopwatch.elapsed < const Duration(seconds: 8)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final generationStopped = !runtime.conversations.isChatGenerating;
    if (!generationStopped) {
      errors['generation_stop'] =
          'Generation remained active after bounded pause wait.';
    }

    var businessTurnSettled = activeBusinessTurn == null;
    final turn = activeBusinessTurn;
    if (turn != null) {
      try {
        await turn.timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            throw TimeoutException(
              'Business turn did not settle within 8 seconds.',
            );
          },
        );
        businessTurnSettled = true;
      } on Object catch (error) {
        errors['business_turn'] = error.toString();
        businessTurnSettled = false;
      }
    }

    var tableRefreshSettled = false;
    try {
      await runtime.tables.refresh().timeout(const Duration(seconds: 8));
      tableRefreshSettled = true;
    } on Object catch (error) {
      errors['table_refresh'] = error.toString();
    }

    AgentBackgroundSnapshot? backgroundSnapshot;
    try {
      backgroundSnapshot = await backgroundService.refreshStatus().timeout(
        const Duration(seconds: 8),
      );
    } on Object catch (error) {
      errors['background_status_refresh'] = error.toString();
    }

    AgentTaskCheckpoint? checkpoint;
    try {
      checkpoint = await taskStore.load().timeout(const Duration(seconds: 8));
    } on Object catch (error) {
      errors['checkpoint_load'] = error.toString();
    }
    final checkpointFilePresent = await File(
      p.join(root.path, 'vault', AgentTaskCheckpoint.storagePath),
    ).exists();
    final indexDatabaseFilePresent = await File(
      p.join(root.path, 'index.sqlite3'),
    ).exists();
    final matchingTargets = checkpoint?.turns
        .where(
          (turn) =>
              turn.conversationId == conversationId &&
              turn.taskId == target?.taskId &&
              turn.assistantMessageId == target?.assistantMessageId,
        )
        .toList(growable: false);
    final stableConversationTurns = checkpoint?.turns
        .where((turn) => turn.conversationId == conversationId)
        .toList(growable: false);
    final hasUnsettledConversationTurn =
        stableConversationTurns == null ||
        stableConversationTurns.isEmpty ||
        stableConversationTurns.any(
          (turn) =>
              turn.status == AgentTurnCheckpointStatus.running ||
              turn.status == AgentTurnCheckpointStatus.queued ||
              turn.status == AgentTurnCheckpointStatus.needsReview ||
              turn.status == AgentTurnCheckpointStatus.waitingInput,
        );
    final hasUnsettledCheckpointTurn =
        checkpoint == null ||
        checkpoint.turns.any(
          (turn) =>
              turn.status == AgentTurnCheckpointStatus.running ||
              turn.status == AgentTurnCheckpointStatus.queued ||
              turn.status == AgentTurnCheckpointStatus.needsReview ||
              turn.status == AgentTurnCheckpointStatus.waitingInput,
        );
    final checkpointMatchesTarget =
        target != null &&
        target.taskId == longrunInitialTaskId &&
        target.assistantMessageId == longrunInitialAssistantMessageId &&
        matchingTargets != null &&
        matchingTargets.length == 1 &&
        matchingTargets.single.status == AgentTurnCheckpointStatus.paused &&
        !hasUnsettledConversationTurn &&
        !hasUnsettledCheckpointTurn;
    if (!checkpointMatchesTarget) {
      errors['pause_checkpoint_identity'] = 'Final checkpoint did not uniquely match the original longrun conversation/task/assistant IDs in a stable paused state.';
    }
    final backgroundTargetMatches =
        backgroundSnapshot != null &&
        backgroundSnapshot.state != AgentBackgroundState.running &&
        (backgroundSnapshot.taskId == null ||
            backgroundSnapshot.taskId == longrunInitialAssistantMessageId);
    if (!backgroundTargetMatches) {
      errors['background_task_state'] = 'Background task is running, unreadable, or does not match the original assistant ID.';
    }
    final pauseSettled =
        pauseSourceSettled &&
        pauseOperationSucceeded &&
        checkpointMatchesTarget;

    return _FailureArchiveFreeze(
      generationWasActive: generationWasActive,
      pauseAttempted: pauseAttempted,
      pauseSourceSettled: pauseSourceSettled,
      pauseSettled: pauseSettled,
      pauseCheckpointSettled: checkpointMatchesTarget,
      pauseTargetTaskId: target?.taskId,
      pauseTargetAssistantMessageId: target?.assistantMessageId,
      longrunConversationId: conversationId,
      longrunInitialTaskId: longrunInitialTaskId,
      longrunInitialAssistantMessageId: longrunInitialAssistantMessageId,
      generationStopped: generationStopped,
      businessTurnSettled: businessTurnSettled,
      conversationTurnsStable:
          !hasUnsettledConversationTurn && !hasUnsettledCheckpointTurn,
      tableRefreshSettled: tableRefreshSettled,
      backgroundState: backgroundSnapshot?.state,
      backgroundTaskId: backgroundSnapshot?.taskId,
      backgroundStatusRefreshed: backgroundTargetMatches,
      checkpoint: checkpoint,
      checkpointFilePresent: checkpointFilePresent,
      indexDatabaseFilePresent: indexDatabaseFilePresent,
      errors: errors,
    );
  }

  AgentTurnCheckpoint? _findInitialTarget(List<AgentTurnCheckpoint> turns) {
    final taskId = longrunInitialTaskId;
    final assistantId = longrunInitialAssistantMessageId;
    final conversationId = longrunConversationId;
    if (taskId == null || assistantId == null || conversationId == null) {
      return null;
    }
    final matches = turns
        .where(
          (turn) =>
              turn.conversationId == conversationId &&
              turn.taskId == taskId &&
              turn.assistantMessageId == assistantId,
        )
        .toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }

  Future<void> emitFailureArchive(Object error, StackTrace stackTrace) async {
    try {
      final freeze = await freezeForFailureArchive();
      final eventFilePresent = await fixture.eventFile.exists();
      var eventText = '';
      String? eventReadError;
      if (eventFilePresent) {
        try {
          eventText = await fixture.eventFile.readAsString();
        } on Object catch (readError) {
          eventReadError = readError.toString();
        }
      }
      Map<String, Object?>? receipt;
      String? receiptReadError;
      try {
        receipt = await fixture.readLastKind('write_receipt');
      } on Object catch (readError) {
        receiptReadError = readError.toString();
      }
      final metadata = <String, Object?>{
        'schema_version': 1,
        'phase': 'longrun',
        'profile': profile,
        'captured_at': DateTime.now().toIso8601String(),
        'capture_stage': 'test_body_before_harness_teardown',
        'captured_before_harness_close': true,
        'conversation_id': fixture.conversationId,
        'longrun_initial_task_id': freeze.longrunInitialTaskId,
        'longrun_initial_assistant_message_id':
            freeze.longrunInitialAssistantMessageId,
        'failure': error.toString(),
        'stack_trace': stackTrace.toString(),
        'snapshot_consistent': freeze.snapshotConsistent,
        'quiescence': freeze.toJson(),
        'checkpoint': freeze.checkpoint?.toJson(),
        'checkpoint_file_present': freeze.checkpointFilePresent,
        'event_file_present': eventFilePresent,
        'event_file_read_error': eventReadError,
        'index_database_file_present': freeze.indexDatabaseFilePresent,
        'receipt_read_error': receiptReadError,
        'fixture': {
          'request_count': fixture.requestCount,
          'read_tool_calls': fixture.readToolCalls,
          'write_receipts': fixture.writeReceipts,
          'verify_tool_calls': fixture.verifyToolCalls,
          'verified_count': fixture.verifiedCount,
          'text_delta_frames': fixture.textDeltaFrames,
          'tool_delta_frames': fixture.toolDeltaFrames,
          'last_created_title': fixture.lastCreatedTitle,
          'last_operation_id': fixture.lastOperationId,
          'last_receipt_status': fixture.lastReceiptStatus,
          'last_receipt_action_id': fixture.lastReceiptActionId,
          'last_receipt_entry_id': fixture.lastReceiptEntryId,
          'last_receipt_table_id': fixture.lastReceiptTableId,
          'last_write_receipt_event': receipt,
          'table_entries': runtime.tables.entries
              .map(
                (entry) => <String, Object?>{
                  'id': entry.id,
                  'table_id': entry.tableId,
                  'title': entry.title,
                },
              )
              .toList(growable: false),
        },
        'event_file': eventText,
        'profile_root': root.path,
      };

      final archive = Archive()
        ..addFile(
          ArchiveFile.string('failure-metadata.json', jsonEncode(metadata)),
        );
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final bytes = await entity.readAsBytes();
        final archivePath = p
            .relative(entity.path, from: root.path)
            .replaceAll(r'\', '/');
        archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
      }
      final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
      if (bytes.length > 64 * 1024 * 1024) {
        throw StateError(
          'Synthetic failure archive exceeds the 64 MiB export limit.',
        );
      }
      final digest = crypto.sha256.convert(bytes).toString();
      final encoded = base64Encode(bytes);
      const chunkSize = 32000;
      final chunkCount = (encoded.length + chunkSize - 1) ~/ chunkSize;
      stdout.writeln(
        'AGENT_LONGRUN_FAILURE_ARCHIVE_BEGIN|v1|$digest|${bytes.length}|$chunkCount',
      );
      for (var index = 0; index < chunkCount; index++) {
        final start = index * chunkSize;
        final end = start + chunkSize < encoded.length
            ? start + chunkSize
            : encoded.length;
        stdout.writeln(
          'AGENT_LONGRUN_FAILURE_ARCHIVE_CHUNK|${index + 1}|${encoded.substring(start, end)}',
        );
      }
      stdout.writeln('AGENT_LONGRUN_FAILURE_ARCHIVE_END|v1|$digest');
      await stdout.flush();
    } on Object catch (archiveError, archiveStack) {
      stdout.writeln(
        'AGENT_LONGRUN_FAILURE_ARCHIVE_ERROR|${archiveError.toString()}|${archiveStack.toString().replaceAll('\n', ' ')}',
      );
      await stdout.flush();
    }
  }

  static Future<_ProductionHarness> open({
    required String profile,
    required String phase,
    required bool resetSyntheticData,
    required bool startModelServer,
    bool observeRequestsBeforeResume = false,
  }) async {
    print('AGENT_HARNESS_OPEN|support_dir');
    final support = await getApplicationSupportDirectory();
    final root = Directory(
      p.join(support.path, 'secretary-agent-acceptance', profile),
    );
    if (resetSyntheticData && await root.exists()) {
      print('AGENT_HARNESS_OPEN|reset_start');
      await root.delete(recursive: true);
      print('AGENT_HARNESS_OPEN|reset_done');
    }
    await root.create(recursive: true);
    print('AGENT_HARNESS_OPEN|root_ready');
    final vault = IoVaultStore.at(Directory(p.join(root.path, 'vault')));
    final index = SqliteIndexDatabase(p.join(root.path, 'index.sqlite3'));
    await index.open();
    print('AGENT_HARNESS_OPEN|index_open');
    final conversations = SqliteConversationStore(
      p.join(root.path, 'conversations.sqlite3'),
    );
    final modelHttpClient = http.Client();
    final fixture = _DeterministicModelFixture(
      profile: profile,
      phase: phase,
      eventFile: File(p.join(root.path, 'agent-events.jsonl')),
    );
    if (observeRequestsBeforeResume) {
      await fixture.startRequestObserver();
    }
    final settings = FakeSettingsService(
      deviceId: 'luna-' + profile,
      modelBaseUrl: 'http://127.0.0.1:' + '$_modelPort',
      modelName: 'deepseek-flash',
      modelKey: 'luna-synthetic-fixture-key',
      defaultAiPolicy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
    );
    final backgroundService = AgentBackgroundService.instance;
    final taskStore = VaultAgentTaskStore(vault);
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: vault,
      indexOverride: index,
      conversationStoreOverride: conversations,
      settingsOverride: settings,
      modelClient: ModelClient(client: modelHttpClient),
      agentTaskStore: taskStore,
      agentBackground: ServiceAgentBackgroundControl(backgroundService),
    );
    print('AGENT_HARNESS_OPEN|runtime_ready');
    fixture.tableId = runtime.tables
        .tableForInboxAssignment(InboxAssignmentKind.event)
        ?.id;
    if (startModelServer) {
      await fixture.startServer();
      print('AGENT_HARNESS_OPEN|model_server_ready');
    }
    return _ProductionHarness(
      profile: profile,
      root: root,
      runtime: runtime,
      fixture: fixture,
      backgroundService: backgroundService,
      taskStore: taskStore,
      modelHttpClient: modelHttpClient,
    );
  }

  Future<void> close() async {
    await fixture.close();
    await runtime.shutdown();
    modelHttpClient.close();
  }
}

class _FailureArchiveFreeze {
  const _FailureArchiveFreeze({
    required this.generationWasActive,
    required this.pauseAttempted,
    required this.pauseSourceSettled,
    required this.pauseSettled,
    required this.pauseCheckpointSettled,
    required this.pauseTargetTaskId,
    required this.pauseTargetAssistantMessageId,
    required this.longrunConversationId,
    required this.longrunInitialTaskId,
    required this.longrunInitialAssistantMessageId,
    required this.generationStopped,
    required this.businessTurnSettled,
    required this.conversationTurnsStable,
    required this.tableRefreshSettled,
    required this.backgroundState,
    required this.backgroundTaskId,
    required this.backgroundStatusRefreshed,
    required this.checkpoint,
    required this.checkpointFilePresent,
    required this.indexDatabaseFilePresent,
    required this.errors,
  });

  final bool generationWasActive;
  final bool pauseAttempted;
  final bool pauseSourceSettled;
  final bool pauseSettled;
  final bool pauseCheckpointSettled;
  final String? pauseTargetTaskId;
  final String? pauseTargetAssistantMessageId;
  final String? longrunConversationId;
  final String? longrunInitialTaskId;
  final String? longrunInitialAssistantMessageId;
  final bool generationStopped;
  final bool businessTurnSettled;
  final bool conversationTurnsStable;
  final bool tableRefreshSettled;
  final AgentBackgroundState? backgroundState;
  final String? backgroundTaskId;
  final bool backgroundStatusRefreshed;
  final AgentTaskCheckpoint? checkpoint;
  final bool checkpointFilePresent;
  final bool indexDatabaseFilePresent;
  final Map<String, String> errors;

  bool get snapshotConsistent =>
      pauseSettled &&
      pauseSourceSettled &&
      pauseCheckpointSettled &&
      generationStopped &&
      businessTurnSettled &&
      conversationTurnsStable &&
      tableRefreshSettled &&
      backgroundStatusRefreshed &&
      backgroundState != AgentBackgroundState.running &&
      longrunConversationId != null &&
      longrunInitialTaskId != null &&
      longrunInitialAssistantMessageId != null &&
      checkpoint != null &&
      checkpointFilePresent &&
      indexDatabaseFilePresent;

  Map<String, Object?> toJson() => {
    'generation_was_active': generationWasActive,
    'pause_attempted': pauseAttempted,
    'pause_source_settled': pauseSourceSettled,
    'pause_settled': pauseSettled,
    'pause_checkpoint_settled': pauseCheckpointSettled,
    'pause_target_task_id': pauseTargetTaskId,
    'pause_target_assistant_message_id': pauseTargetAssistantMessageId,
    'longrun_conversation_id': longrunConversationId,
    'longrun_initial_task_id': longrunInitialTaskId,
    'longrun_initial_assistant_message_id': longrunInitialAssistantMessageId,
    'generation_stopped': generationStopped,
    'business_turn_settled': businessTurnSettled,
    'conversation_turns_stable': conversationTurnsStable,
    'table_refresh_settled': tableRefreshSettled,
    'background_status_refreshed': backgroundStatusRefreshed,
    'background_state': backgroundState?.name,
    'background_task_id': backgroundTaskId,
    'checkpoint_loaded': checkpoint != null,
    'checkpoint_file_present': checkpointFilePresent,
    'index_database_file_present': indexDatabaseFilePresent,
    'errors': errors,
  };
}

class _DeterministicModelFixture {
  _DeterministicModelFixture({
    required this.profile,
    required this.phase,
    required this.eventFile,
  });

  final String profile;
  final String phase;
  final File eventFile;
  final Completer<void> blocked = Completer<void>();
  final Completer<void> _unblock = Completer<void>();
  final Completer<void> serviceRestrictedBackgroundStartBarrier =
      Completer<void>();
  final Completer<void> serviceRestrictedResumeBarrier = Completer<void>();
  final Completer<void> notificationDeniedPermissionBarrier = Completer<void>();
  final Completer<void> finalTextFirstDeltaSent = Completer<void>();
  final Completer<void> finalTextSecondDeltaSent = Completer<void>();
  final Completer<void> _releaseFinalTextDelta = Completer<void>();
  HttpServer? _server;
  Stopwatch? _clock;
  String? conversationId;
  String? serviceRestrictedAssistantMessageId;
  String? serviceRestrictedTaskId;
  Duration? _stopAt;
  int requestCount = 0;
  int readToolCalls = 0;
  int writeReceipts = 0;
  int verifyToolCalls = 0;
  int verifiedCount = 0;
  int toolDeltaFrames = 0;
  int textDeltaFrames = 0;
  int _nextEntry = 0;
  bool _didBlock = false;
  bool _rejectRequests = false;
  String? lastCreatedTitle;
  String lastOperationId = '';
  String lastReceiptStatus = '';
  String lastReceiptActionId = '';
  String lastReceiptEntryId = '';
  String lastReceiptTableId = '';
  String? tableId;
  final Set<String> _seenReadCallIds = {};
  final Set<String> _seenWriteCallIds = {};
  final Set<String> _seenVerifyCallIds = {};

  void stopAfter(Duration duration) {
    _clock = Stopwatch()..start();
    _stopAt = duration + const Duration(seconds: 2);
  }

  Future<void> startServer() async {
    if (_server != null) {
      _rejectRequests = false;
      return;
    }
    _clock ??= Stopwatch()..start();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _modelPort);
    _server!.listen((request) => unawaited(_handle(request)));
  }

  Future<void> startRequestObserver() async {
    if (_server != null) {
      throw StateError('Request observer must own the model loopback port.');
    }
    _clock ??= Stopwatch()..start();
    _rejectRequests = true;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _modelPort);
    _server!.listen((request) => unawaited(_handle(request)));
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    if (request.method == 'POST' &&
        request.uri.path == '/__acceptance/service_restricted_start') {
      if (phase != 'service_restricted') {
        response.statusCode = HttpStatus.conflict;
        await response.close();
        return;
      }
      await record({'kind': 'service_restricted_background_start_barrier'});
      response.statusCode = HttpStatus.ok;
      response.write('ack');
      await response.close();
      if (!serviceRestrictedBackgroundStartBarrier.isCompleted) {
        serviceRestrictedBackgroundStartBarrier.complete();
      }
      return;
    }
    if (request.method == 'POST' &&
        request.uri.path == '/__acceptance/service_restricted_resume') {
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      if (phase != 'service_restricted' ||
          body is! Map ||
          body['task_id'] != serviceRestrictedTaskId ||
          serviceRestrictedTaskId == null ||
          body['assistant_message_id'] != serviceRestrictedAssistantMessageId ||
          serviceRestrictedAssistantMessageId == null) {
        response.statusCode = HttpStatus.conflict;
        await response.close();
        return;
      }
      await record({
        'kind': 'service_restricted_resume_barrier',
        'assistant_message_id': serviceRestrictedAssistantMessageId,
        'task_id': serviceRestrictedTaskId,
      });
      response.statusCode = HttpStatus.ok;
      response.write('ack');
      await response.close();
      if (!serviceRestrictedResumeBarrier.isCompleted) {
        serviceRestrictedResumeBarrier.complete();
      }
      return;
    }
    if (request.method == 'POST' &&
        request.uri.path == '/__acceptance/notification_denied_permission') {
      if (phase != 'notification_denied') {
        response.statusCode = HttpStatus.conflict;
        await response.close();
        return;
      }
      await record({'kind': 'notification_denied_permission_barrier'});
      response.statusCode = HttpStatus.ok;
      response.write('ack');
      await response.close();
      if (!notificationDeniedPermissionBarrier.isCompleted) {
        notificationDeniedPermissionBarrier.complete();
      }
      return;
    }
    response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    response.headers.set('cache-control', 'no-cache');
    try {
      final body = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      if (phase == 'longrun' && requestCount == 0) {
        if (body['model'] != 'deepseek-flash') {
          throw StateError(
            'Longrun fixture error: first model request must use '
            'deepseek-flash; received model=${body['model'] ?? '<missing>'}.',
          );
        }
        final tools = body['tools'];
        if (tools is! List || tools.isEmpty) {
          throw StateError(
            'Longrun fixture error: first deepseek-flash request must include '
            'tool definitions; received tools=${tools is List ? tools.length : 0}.',
          );
        }
      }
      requestCount++;
      final configuredTools = body['tools'];
      if (configuredTools is! List || configuredTools.isEmpty) {
        await record({
          'kind': 'semantic_duplicate_request',
          'request_count': requestCount,
        });
        await _sendSemanticCreateDecision(response);
        return;
      }
      await record({
        'kind': 'model_request',
        'request_count': requestCount,
        'elapsed_ms': _clock?.elapsedMilliseconds ?? 0,
      });
      if (_rejectRequests) {
        await record({
          'kind': 'pre_resume_request_rejected',
          'request_count': requestCount,
        });
        response.statusCode = HttpStatus.serviceUnavailable;
        await response.close();
        return;
      }
      final messages = (body['messages'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      final toolMessages = messages.where(
        (message) => message['role'] == 'tool',
      );
      for (final message in toolMessages) {
        final callId = message['tool_call_id']?.toString() ?? '';
        if (callId.isEmpty) continue;
        if (message['name'] == 'table_list' && _seenReadCallIds.add(callId)) {
          readToolCalls++;
        } else if (message['name'] == 'content_create' &&
            _seenWriteCallIds.add(callId)) {
          writeReceipts++;
        } else if (message['name'] == 'content_verify' &&
            _seenVerifyCallIds.add(callId)) {
          verifyToolCalls++;
        }
      }
      final lastTool = toolMessages.isEmpty ? null : toolMessages.last;
      if (lastTool != null && lastTool['name'] == 'content_create') {
        final receipt = _jsonObject(lastTool['content']);
        if (receipt['status'] != 'succeeded') {
          throw StateError(
            'Production content_create returned no successful receipt.',
          );
        }
        lastOperationId = receipt['operation_id']?.toString() ?? '';
        lastReceiptStatus = receipt['status']?.toString() ?? '';
        final receiptData = _jsonObject(receipt['data']);
        lastReceiptActionId = receiptData['id']?.toString() ?? '';
        lastReceiptEntryId = receiptData['entry_id']?.toString() ?? '';
        lastReceiptTableId = receiptData['table_id']?.toString() ?? '';
        await record({
          'kind': 'write_receipt',
          'operation_id': lastOperationId,
          'status': receipt['status'],
          'action_id': lastReceiptActionId,
          'entry_id': lastReceiptEntryId,
          'table_id': lastReceiptTableId,
          'title': lastCreatedTitle,
          'conversation_id': conversationId,
        });
        if (!_didBlock &&
            (phase == 'prepare_force_stop' ||
                phase == 'activity_recreate' ||
                phase == 'service_interrupted' ||
                phase == 'service_timeout')) {
          _didBlock = true;
          if (!blocked.isCompleted) blocked.complete();
          print('AGENT_MODEL_BLOCKED|' + phase + '|' + lastOperationId);
          if (phase == 'prepare_force_stop') {
            await Completer<void>().future;
          } else {
            await _unblock.future.timeout(const Duration(minutes: 5));
          }
        }
        await _delay();
        await _sendTool(response, 'content_verify', {
          'operation_id': lastOperationId,
        });
        return;
      }
      if (lastTool != null && lastTool['name'] == 'content_verify') {
        final verification = _jsonObject(lastTool['content']);
        final verificationData = verification['data'];
        if (verification['status'] != 'ok' ||
            verificationData is! Map ||
            verificationData['verified'] != true) {
          throw StateError(
            'Local content_verify did not confirm the written entry.',
          );
        }
        verifiedCount++;
        await record({
          'kind': 'verification_result',
          'verified_count': verifiedCount,
          'elapsed_ms': _clock?.elapsedMilliseconds ?? 0,
          'content': lastTool['content']?.toString(),
        });
        if (_shouldFinish) {
          await _sendText(response, '合成资料已写入并通过本地回执核对。');
          return;
        }
      }
      await _delay();
      await _sendCreateRound(response, includeTableRead: lastTool == null);
    } on Object catch (error) {
      await record({'kind': 'fixture_error', 'error': error.toString()});
      try {
        response.statusCode = HttpStatus.internalServerError;
        await response.close();
      } on Object {
        // Expected if fault injection cancelled the app's HTTP request.
      }
    }
  }

  bool get _shouldFinish {
    if (phase == 'recover_after_force_stop' ||
        phase == 'activity_recreate' ||
        phase == 'service_interrupted' ||
        phase == 'service_timeout' ||
        phase == 'notification_denied' ||
        phase == 'service_restricted') {
      return verifiedCount >= 1;
    }
    return _stopAt != null && (_clock?.elapsed ?? Duration.zero) >= _stopAt!;
  }

  Future<void> _sendCreateRound(
    HttpResponse response, {
    required bool includeTableRead,
  }) async {
    _nextEntry++;
    final currentTableId = tableId;
    if (currentTableId == null)
      throw StateError('Event inbox table unavailable.');
    lastCreatedTitle = 'Luna ' + profile + ' entry ' + '$_nextEntry';
    final arguments = jsonEncode({
      'table_id': currentTableId,
      'type': 'note',
      'title': lastCreatedTitle,
      'body': '合成验收资料 ' + '$_nextEntry' + '；由真实 ModelClient 与内容工具写入。',
      'tags': ['luna-c', profile],
      'idempotency_key': 'luna-' + profile + '-operation-' + '$_nextEntry',
    });
    final calls = <Map<String, Object?>>[
      if (includeTableRead)
        {
          'index': 0,
          'id': 'luna_read_' + '$_nextEntry',
          'type': 'function',
          'function': {'name': 'table_list', 'arguments': '{}'},
        },
      {
        'index': includeTableRead ? 1 : 0,
        'id': 'luna_create_' + '$_nextEntry',
        'type': 'function',
        'function': {'name': 'content_create', 'arguments': arguments},
      },
    ];
    await _sendCalls(response, calls);
  }

  Future<void> _sendTool(
    HttpResponse response,
    String name,
    Map<String, Object?> arguments,
  ) async {
    await _sendCalls(response, [
      {
        'index': 0,
        'id': 'luna_' + name + '_' + '$requestCount',
        'type': 'function',
        'function': {'name': name, 'arguments': jsonEncode(arguments)},
      },
    ]);
  }

  Future<void> _sendCalls(
    HttpResponse response,
    List<Map<String, Object?>> calls,
  ) async {
    response.statusCode = HttpStatus.ok;
    await response.flush();
    for (final call in calls) {
      final function = call['function']! as Map<String, Object?>;
      final arguments = function['arguments']?.toString() ?? '{}';
      final split = arguments.length < 2 ? 1 : arguments.length ~/ 2;
      final firstFunctionDelta = <String, Object?>{
        if (function['name'] != null) 'name': function['name'],
        'arguments': arguments.substring(0, split),
      };
      final firstCallDelta = <String, Object?>{
        'index': call['index'],
        if (call['id'] != null) 'id': call['id'],
        if (call['type'] != null) 'type': call['type'],
        'function': firstFunctionDelta,
      };
      response.write(
        'data: ' +
            jsonEncode({
              'choices': [
                {
                  'delta': {
                    'tool_calls': [firstCallDelta],
                  },
                },
              ],
            }) +
            '\n\n',
      );
      await response.flush();
      toolDeltaFrames++;
      await record({
        'kind': 'tool_stream_delta',
        'request_count': requestCount,
        'delta_frame': toolDeltaFrames,
        'tool_index': call['index'],
        'fragment_length': arguments.substring(0, split).length,
      });

      final secondCallDelta = <String, Object?>{
        'index': call['index'],
        'function': {'arguments': arguments.substring(split)},
      };
      response.write(
        'data: ' +
            jsonEncode({
              'choices': [
                {
                  'delta': {
                    'tool_calls': [secondCallDelta],
                  },
                },
              ],
            }) +
            '\n\n',
      );
      await response.flush();
      toolDeltaFrames++;
      await record({
        'kind': 'tool_stream_delta',
        'request_count': requestCount,
        'delta_frame': toolDeltaFrames,
        'tool_index': call['index'],
        'fragment_length': arguments.substring(split).length,
      });
    }
    response.write(
      'data: ' +
          jsonEncode({
            'choices': [
              {'delta': <String, Object?>{}, 'finish_reason': 'tool_calls'},
            ],
          }) +
          '\n\n',
    );
    response.write('data: [DONE]\n\n');
    await response.close();
  }

  Future<void> _sendText(HttpResponse response, String text) async {
    response.bufferOutput = false;
    response.statusCode = HttpStatus.ok;
    await response.flush();
    await record({
      'kind': 'final_text_response_started',
      'request_count': requestCount,
      'verified_count': verifiedCount,
      'elapsed_ms': _clock?.elapsedMilliseconds ?? 0,
    });
    final split = phase == 'longrun' ? '合成资料已写入'.length : (text.length ~/ 2);
    final deltas = <String>[text.substring(0, split), text.substring(split)];
    for (var index = 0; index < deltas.length; index++) {
      response.write(
        'data: ' +
            jsonEncode({
              'choices': [
                {
                  'delta': {'content': deltas[index]},
                },
              ],
            }) +
            '\n\n',
      );
      await response.flush();
      textDeltaFrames++;
      if (phase == 'longrun' && index == 0) {
        print('AGENT_LONGRUN_FIXTURE_DELTA_SENT|${deltas[index]}');
      }
      await record({
        'kind': 'text_stream_delta',
        'request_count': requestCount,
        'delta_frame': textDeltaFrames,
        'fragment_length': deltas[index].length,
      });
      if (phase == 'longrun' && index == 0) {
        if (!finalTextFirstDeltaSent.isCompleted) {
          finalTextFirstDeltaSent.complete();
        }
        await _releaseFinalTextDelta.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw StateError(
            'Longrun did not observe and release the first streamed text delta.',
          ),
        );
        await record({
          'kind': 'final_text_first_delta_released',
          'elapsed_ms': _clock?.elapsedMilliseconds ?? 0,
        });
      }
      if (index == 1 && !finalTextSecondDeltaSent.isCompleted) {
        finalTextSecondDeltaSent.complete();
      }
    }
    response.write(
      'data: ' +
          jsonEncode({
            'choices': [
              {'delta': <String, Object?>{}, 'finish_reason': 'stop'},
            ],
          }) +
          '\n\n',
    );
    response.write('data: [DONE]\n\n');
    await response.close();
  }

  Future<void> _sendSemanticCreateDecision(HttpResponse response) async {
    response.statusCode = HttpStatus.ok;
    await response.flush();
    const decision =
        '{"action":"create","evidence":[],"body_addition":"",'
        '"field_additions":{},"reason":"synthetic distinct item"}';
    response.write(
      'data: ' +
          jsonEncode({
            'choices': [
              {
                'delta': {'content': decision},
              },
            ],
          }) +
          '\n\n',
    );
    await response.flush();
    response.write(
      'data: ' +
          jsonEncode({
            'choices': [
              {'delta': <String, Object?>{}, 'finish_reason': 'stop'},
            ],
          }) +
          '\n\n',
    );
    response.write('data: [DONE]\n\n');
    await response.close();
  }

  void releaseFinalTextDelta() {
    if (!_releaseFinalTextDelta.isCompleted) {
      _releaseFinalTextDelta.complete();
    }
  }

  Future<void> _delay() =>
      Future<void>.delayed(Duration(seconds: phase == 'longrun' ? 9 : 6));

  void releaseBlocked() {
    if (!_unblock.isCompleted) _unblock.complete();
  }

  Future<void> record(Map<String, Object?> event) async {
    await eventFile.parent.create(recursive: true);
    await eventFile.writeAsString(
      jsonEncode({...event, 'at': DateTime.now().toIso8601String()}) + '\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<int> readModelRequestCount() async {
    if (!await eventFile.exists()) return 0;
    return (await eventFile.readAsLines())
        .where((line) => _jsonObject(line)['kind'] == 'model_request')
        .length;
  }

  Future<int> readEventCount(String kind) async {
    if (!await eventFile.exists()) return 0;
    return (await eventFile.readAsLines())
        .where((line) => _jsonObject(line)['kind'] == kind)
        .length;
  }

  Future<Map<String, Object?>?> readLastKind(String kind) async {
    if (!await eventFile.exists()) return null;
    for (final line in (await eventFile.readAsLines()).reversed) {
      final event = _jsonObject(line);
      if (event['kind'] == kind) return event;
    }
    return null;
  }

  Future<void> close() async {
    releaseBlocked();
    releaseFinalTextDelta();
    await _server?.close(force: true);
  }

  static Map<String, dynamic> _jsonObject(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is! String || value.isEmpty) return {};
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } on FormatException {
      return {};
    }
  }
}
