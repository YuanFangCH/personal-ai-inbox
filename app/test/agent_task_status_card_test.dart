import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/agent_usage.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_background_control.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_task_store.dart';
import 'package:personal_ai_inbox/ui/pages/conversation/agent_task_status_card.dart';

import 'test_support.dart';

Future<AppRuntime> restoredRuntime(AgentTurnCheckpointStatus status) async {
  final chats = MemoryConversationStore();
  final now = DateTime(2026, 11, 4);
  await chats.upsertConversation(
    Conversation(
      id: 'conv_restored_card',
      title: '恢复任务',
      createdAt: now,
      updatedAt: now,
      autoTitle: false,
    ),
  );
  await chats.upsertMessage(
    ChatMessage(
      id: 'msg_restored_card',
      conversationId: 'conv_restored_card',
      role: ChatRole.user,
      content: '继续整理',
      status: ChatMessageStatus.complete,
      createdAt: now,
      updatedAt: now,
    ),
  );
  final tasks = MemoryAgentTaskStore()
    ..checkpoint = AgentTaskCheckpoint(
      usage: const AgentUsage(usedRequests: 240),
      runUsage: const {'legacy': AgentUsage(usedRequests: 240)},
      activeRunId: 'legacy',
      turns: [
        AgentTurnCheckpoint(
          taskId: 'task_restored_card',
          runId: 'legacy',
          conversationId: 'conv_restored_card',
          userMessageId: 'msg_restored_card',
          kind: AgentTurnQueueKind.conversation,
          status: status,
          sequence: 0,
        ),
      ],
    );
  return AppRuntime.bootstrap(
    vaultOverride: MemoryVaultStore(),
    indexOverride: MemoryIndexDatabase(),
    conversationStoreOverride: chats,
    agentTaskStore: tasks,
    agentBackground: DisabledAgentBackgroundControl(),
    settingsOverride: FakeSettingsService(deviceId: 'restored-card'),
  );
}

void main() {
  testWidgets(
    'restored paused task exposes usage without budget continuation',
    (tester) async {
      final runtime = (await tester.runAsync(
        () => restoredRuntime(AgentTurnCheckpointStatus.paused),
      ))!;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AgentTaskStatusCard(workspace: runtime.conversations),
            ),
          ),
        );
        expect(find.text('任务已暂停'), findsOneWidget);
        expect(find.text('继续任务'), findsOneWidget);
        expect(find.textContaining('已使用 240 次模型请求'), findsOneWidget);
        expect(find.textContaining('追加 2 小时'), findsNothing);
        expect(runtime.conversations.agentUsage.usedRequests, 240);
        expect(runtime.conversations.isChatGenerating, isFalse);
      } finally {
        await tester.runAsync(runtime.shutdown);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('uncertain restored write requires review before continuation', (
    tester,
  ) async {
    final runtime = (await tester.runAsync(
      () => restoredRuntime(AgentTurnCheckpointStatus.running),
    ))!;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentTaskStatusCard(workspace: runtime.conversations),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('resume_agent_tasks')));
      await tester.pumpAndSettle();
      expect(find.text('核对中断操作'), findsOneWidget);
      await tester.tap(find.text('稍后核对'));
      await tester.pumpAndSettle();
      expect(runtime.conversations.hasTasksNeedingReview, isTrue);
      expect(runtime.conversations.agentUsage.usedRequests, 240);
      expect(runtime.conversations.isChatGenerating, isFalse);
    } finally {
      await tester.runAsync(runtime.shutdown);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
