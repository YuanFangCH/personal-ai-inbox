import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_task_store.dart';

import 'test_support.dart';

void main() {
  testWidgets('incomplete intake card shows coverage and explicit retry', (
    tester,
  ) async {
    final conversationStore = MemoryConversationStore();
    final attachmentStore = MemoryAttachmentStore();
    final chats = ChatRepository(
      store: conversationStore,
      attachments: attachmentStore,
    );
    await chats.initialize();
    final taskStore = MemoryAgentTaskStore();
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      conversationStoreOverride: conversationStore,
      attachmentStoreOverride: attachmentStore,
      agentTaskStore: taskStore,
      settingsOverride: FakeSettingsService(deviceId: 'intake-retry-card'),
    );
    addTearDown(() async {
      runtime.dispose();
      await chats.close();
    });
    final conversation = await runtime.conversations.createConversation();
    final table = runtime.tables.tables.first;
    final now = DateTime(2026, 11, 5, 12);
    await chats.saveMessage(
      ChatMessage(
        id: 'msg_intake_retry_card_user',
        conversationId: conversation.id,
        role: ChatRole.user,
        content: '收到设备归档 ACME-778',
        status: ChatMessageStatus.complete,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final assistant = ChatMessage(
      id: 'msg_intake_retry_card_assistant',
      conversationId: conversation.id,
      role: ChatRole.assistant,
      content: '查重覆盖未完成，原内容没有写入。',
      status: ChatMessageStatus.complete,
      createdAt: now.add(const Duration(seconds: 1)),
      updatedAt: now.add(const Duration(seconds: 1)),
      tableActions: [
        TableChatAction(
          id: 'act_intake_retry_card',
          operation: 'content.create',
          title: '设备归档',
          status: TableChatActionStatus.failed,
          createdAt: now,
          tableId: table.id,
          message: '已检查 2/5 个候选，尚有 3 个未检查。',
          proposal: const {
            'table_id': 'table-for-test',
            'type': 'note',
            'title': '设备归档',
            'body': '订单编号 ACME-778 已归档。',
            'idempotency_key': 'retry-card',
          },
          requestFingerprint: 'fingerprint-retry-card',
          intakeCoverageChecked: 2,
          intakeCoverageTotal: 5,
          intakeCoverageComplete: false,
          retryableIntake: true,
        ),
      ],
    );
    await chats.saveMessage(assistant);
    await runtime.conversations.refresh();

    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_inbox')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation_manage')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('conversation_${conversation.id}')));
    await tester.pumpAndSettle();
    expect(find.textContaining('查重语义覆盖：已检查 2/5'), findsOneWidget);
    expect(find.textContaining('仍有 3 个未检查。原始内容和操作意图已保存'), findsOneWidget);
    expect(
      find.byKey(const Key('retry_intake_act_intake_retry_card')),
      findsOneWidget,
    );
    expect(find.text('重新扫描并继续'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('retry_intake_act_intake_retry_card')),
    );
    await tester.pumpAndSettle();

    final savedAssistant = await chats.findMessage(assistant.id);
    final savedAction = savedAssistant!.tableActions.single;
    expect(savedAction.status, TableChatActionStatus.pendingRetry);
    expect(savedAction.intakeRetryPending, isTrue);
    expect(
      savedAction.intakeRetryOperationId,
      'intake-retry:${savedAction.id}:1',
    );
    expect(savedAction.proposal['body'], '订单编号 ACME-778 已归档。');
    expect(savedAction.message, contains('原接收任务已不在等待队列'));
    expect(runtime.tables.entries, isEmpty);
    expect(taskStore.checkpoint.turns, isEmpty);
  });
}
