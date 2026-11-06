import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/data/io_vault_store.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/sqlite_conversation_store.dart';
import 'package:personal_ai_inbox/data/sqlite_index_database.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_task_store.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'test_support.dart';

void main() {
  test('restart restores a paused task budget and resumes only after one explicit grant', () async {
    final root = await Directory.systemTemp.createTemp(
      'secretary-agent-budget-recovery-',
    );
    final firstResponseCancelled = Completer<void>();
    final firstResponse = StreamController<List<int>>(
      onCancel: () {
        if (!firstResponseCancelled.isCompleted) {
          firstResponseCancelled.complete();
        }
      },
    );
    final resumedResponse = StreamController<List<int>>();
    final firstRequestStarted = Completer<void>();
    final resumedRequestStarted = Completer<void>();
    var requests = 0;
    late IoVaultStore vault;
    late SqliteConversationStore chats;
    late AppRuntime runtime;
    Future<AppRuntime> boot() async {
      vault = IoVaultStore.at(Directory('${root.path}/vault'));
      final index = SqliteIndexDatabase('${root.path}/index.sqlite');
      await index.open();
      chats = SqliteConversationStore('${root.path}/conversations.sqlite');
      return AppRuntime.bootstrap(
        vaultOverride: vault,
        indexOverride: index,
        conversationStoreOverride: chats,
        attachmentStoreOverride: MemoryAttachmentStore(),
        agentTaskStore: VaultAgentTaskStore(vault),
        settingsOverride: FakeSettingsService(modelKey: 'budget-recovery'),
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            await body.bytesToString();
            requests++;
            if (requests == 1) {
              if (!firstRequestStarted.isCompleted) {
                firstRequestStarted.complete();
              }
              return http.StreamedResponse(
                firstResponse.stream,
                200,
                headers: const {'content-type': 'text/event-stream'},
              );
            }
            if (requests == 2) {
              return _contentResponse('另一会话先完成。');
            }
            if (!resumedRequestStarted.isCompleted) {
              resumedRequestStarted.complete();
            }
            return http.StreamedResponse(
              resumedResponse.stream,
              200,
              headers: const {'content-type': 'text/event-stream'},
            );
          }),
        ),
      );
    }

    runtime = await boot();
    addTearDown(() async {
      if (!firstResponse.isClosed) await firstResponse.close();
      if (!resumedResponse.isClosed) await resumedResponse.close();
      await runtime.shutdown();
      await root.delete(recursive: true);
    });
    final firstConversation = await runtime.conversations.createConversation();
    final otherConversation = await runtime.conversations.createConversation();
    final firstSend = runtime.conversations.sendChatMessage(
      firstConversation.id,
      text: '暂停后恢复同一预算任务',
    );
    await firstRequestStarted.future.timeout(const Duration(seconds: 2));
    firstResponse.add(_contentEvent('任务首轮已输出片段。'));
    await _waitFor(() {
      final messages = runtime.conversations.messagesFor(firstConversation.id);
      return messages.last.content == '任务首轮已输出片段。';
    });
    await runtime.conversations.pauseGeneration().timeout(
      const Duration(seconds: 2),
    );
    await firstSend.timeout(const Duration(seconds: 2));
    await firstResponseCancelled.future.timeout(const Duration(seconds: 2));

    final pausedSnapshot = AgentTaskCheckpoint.fromJson(
      jsonDecode((await vault.read(AgentTaskCheckpoint.storagePath))!),
    );
    final pausedTurn = pausedSnapshot.turns.single;
    final taskId = pausedTurn.taskId;
    final firstRunId = pausedTurn.effectiveBudgetRunId;
    final firstAssistantId = pausedTurn.assistantMessageId;
    expect(pausedTurn.status, AgentTurnCheckpointStatus.paused);
    expect(firstAssistantId, isNotEmpty);
    expect(pausedSnapshot.runBudgets[firstRunId]?.usedRequests, 1);
    expect(
      pausedSnapshot.runBudgets[firstRunId]?.grantedRequests,
      AgentBudgetCheckpoint().grantedRequests,
    );

    final otherSend = runtime.conversations.sendChatMessage(
      otherConversation.id,
      text: '独立会话不占用前一任务额度',
    );
    await otherSend.timeout(const Duration(seconds: 3));
    final otherAssistant = runtime.conversations
        .messagesFor(otherConversation.id)
        .last;
    expect(otherAssistant.status, ChatMessageStatus.complete);
    expect(requests, 2);
    final beforeShutdown = AgentTaskCheckpoint.fromJson(
      jsonDecode((await vault.read(AgentTaskCheckpoint.storagePath))!),
    );
    final firstBudgetBeforeShutdown = beforeShutdown.runBudgets[firstRunId]!;
    final otherRunId = beforeShutdown.runBudgets.keys.singleWhere(
      (id) => id != firstRunId,
    );
    final otherTurnBudget = beforeShutdown.runBudgets[otherRunId]!;
    expect(firstBudgetBeforeShutdown.usedRequests, 1);
    expect(otherTurnBudget.grantedRequests, 240);
    await runtime.shutdown();

    runtime = await boot();
    expect(requests, 2, reason: '启动必须保留暂停状态且不自动派发模型请求。');
    final afterRestart = AgentTaskCheckpoint.fromJson(
      jsonDecode((await vault.read(AgentTaskCheckpoint.storagePath))!),
    );
    final restoredTurn = afterRestart.turns.single;
    expect(restoredTurn.taskId, taskId);
    expect(restoredTurn.assistantMessageId, firstAssistantId);
    expect(restoredTurn.status, AgentTurnCheckpointStatus.paused);
    expect(
      afterRestart.runBudgets[firstRunId]!.toJson(),
      firstBudgetBeforeShutdown.toJson(),
    );
    expect(afterRestart.runBudgets[firstRunId]!.usedRequests, 1);

    await Future.wait([
      runtime.conversations.resumeTasks(
        taskId: taskId,
        additionalRequests: 240,
        additionalActive: const Duration(hours: 2),
      ),
      runtime.conversations.resumeTasks(
        taskId: taskId,
        additionalRequests: 240,
        additionalActive: const Duration(hours: 2),
      ),
    ]);
    await resumedRequestStarted.future.timeout(const Duration(seconds: 3));
    final runningBudget = runtime.conversations.agentBudget;
    expect(runningBudget.usedRequests, 2);
    expect(runningBudget.grantedRequests, 480);
    expect(runningBudget.grantedActive, const Duration(hours: 4));
    final resumedSnapshot = AgentTaskCheckpoint.fromJson(
      jsonDecode((await vault.read(AgentTaskCheckpoint.storagePath))!),
    );
    final runningTurn = resumedSnapshot.turns.single;
    expect(runningTurn.taskId, taskId);
    expect(runningTurn.assistantMessageId, firstAssistantId);
    expect(resumedSnapshot.runBudgets[firstRunId]!.grantedRequests, 480);
    expect(resumedSnapshot.runBudgets[firstRunId]!.usedRequests, 2);
    final otherRunBudget = resumedSnapshot.runBudgets[otherRunId]!;
    expect(otherRunBudget.grantedRequests, 240);
    expect(otherRunBudget.usedRequests, 1);

    resumedResponse.add(_contentEvent('原任务已恢复并完成。'));
    resumedResponse.add(utf8.encode('data: [DONE]\n\n'));
    await resumedResponse.close();
    await _waitFor(() {
      final assistant = runtime.conversations
          .messagesFor(firstConversation.id)
          .last;
      return assistant.status == ChatMessageStatus.complete;
    });
    final finalAssistant = runtime.conversations
        .messagesFor(firstConversation.id)
        .last;
    expect(finalAssistant.id, firstAssistantId);
    expect(finalAssistant.content, '任务首轮已输出片段。原任务已恢复并完成。');
    expect(
      (await chats.findMessage(otherAssistant.id))?.status,
      ChatMessageStatus.complete,
    );
    expect(requests, 3);
    final finalSnapshot = AgentTaskCheckpoint.fromJson(
      jsonDecode((await vault.read(AgentTaskCheckpoint.storagePath))!),
    );
    expect(finalSnapshot.runBudgets[firstRunId]!.usedRequests, 2);
    expect(finalSnapshot.runBudgets[firstRunId]!.grantedRequests, 480);
    expect(
      finalSnapshot.runBudgets[firstRunId]!.grantedActive,
      const Duration(hours: 4),
    );
    expect(
      finalSnapshot.runBudgets[otherRunId]!.toJson(),
      otherTurnBudget.toJson(),
    );
  });
}

http.StreamedResponse _contentResponse(String content) => http.StreamedResponse(
  Stream.fromIterable([
    _contentEvent(content),
    utf8.encode('data: [DONE]\n\n'),
  ]),
  200,
  headers: const {'content-type': 'text/event-stream'},
);

List<int> _contentEvent(String content) => utf8.encode(
  'data: ${jsonEncode({
    'choices': [
      {
        'delta': {'content': content},
      },
    ],
  })}\n\n',
);

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not reached before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
