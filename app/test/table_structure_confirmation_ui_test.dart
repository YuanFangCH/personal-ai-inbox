import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';

import 'test_support.dart';

void main() {
  testWidgets('table structure proposal confirms inline in its conversation', (
    tester,
  ) async {
    final store = MemoryConversationStore();
    await store.open();
    final now = DateTime.now();
    final conversation = Conversation(
      id: 'cnv_structure_ui',
      title: '表结构确认',
      createdAt: now,
      updatedAt: now,
      autoTitle: false,
    );
    await store.upsertConversation(conversation);
    const candidateId = 'act_structure_ui';
    await store.upsertMessage(
      ChatMessage(
        id: 'msg_structure_ui',
        conversationId: conversation.id,
        role: ChatRole.assistant,
        content: '我准备创建考试安排表。',
        status: ChatMessageStatus.complete,
        createdAt: now,
        updatedAt: now,
        tableActions: [
          TableChatAction(
            id: candidateId,
            operation: 'table.create',
            title: '考试安排',
            status: TableChatActionStatus.pendingConfirmation,
            createdAt: now,
            tableId: 'tb_confirm_ui',
            tableTitle: '考试安排',
            proposal: const {
              'operation': 'create',
              'table_id': 'tb_confirm_ui',
              'expected_revision': null,
              'title': '考试安排',
              'payload': {'title': '考试安排'},
            },
          ),
        ],
      ),
    );

    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      conversationStoreOverride: store,
      attachmentStoreOverride: MemoryAttachmentStore(),
      settingsOverride: FakeSettingsService(deviceId: 'table-approval-ui'),
    );
    addTearDown(runtime.dispose);
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_inbox')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation_manage')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('conversation_${conversation.id}')));
    await tester.pumpAndSettle();

    expect(find.text('需要确认的表结构变更'), findsOneWidget);
    expect(find.textContaining('将新建表“考试安排”'), findsOneWidget);
    expect(
      runtime.tables.findTable('tb_confirm_ui'),
      isNull,
      reason:
          'The proposal card must not change the table before confirmation.',
    );
    await tester.tap(
      find.byKey(const Key('confirm_table_action_act_structure_ui')),
    );
    await tester.pumpAndSettle();
    expect(runtime.tables.findTable('tb_confirm_ui')?.title, '考试安排');
    expect(find.text('已创建表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
