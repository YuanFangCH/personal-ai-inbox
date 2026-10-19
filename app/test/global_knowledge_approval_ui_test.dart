import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';

import 'test_support.dart';

void main() {
  testWidgets(
    'AI knowledge candidates can be confirmed in chat and pending page',
    (tester) async {
      tester.view.physicalSize = const Size(480, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(deviceId: 'global-approval-ui'),
      );
      addTearDown(runtime.dispose);
      final current = await runtime.conversations.createConversation();
      final inChat = await runtime.results.proposeGlobalKnowledgeChange(
        operation: GlobalKnowledgeOperation.create,
        candidateId: 'gkc_ui_chat',
        sourceConversationId: current.id,
        sourceMessageId: 'msg_ui_chat',
        proposal: const {
          'title': '本学期',
          'body': '用于教学周计算。',
          'facts': {'semester_start': '2026-09-01', 'week_count': 16},
        },
      );
      final pending = await runtime.results.proposeGlobalKnowledgeChange(
        operation: GlobalKnowledgeOperation.create,
        candidateId: 'gkc_ui_pending',
        sourceConversationId: 'other-conversation',
        sourceMessageId: 'msg_ui_pending',
        proposal: const {
          'title': '下学期',
          'body': '待校历确认。',
          'facts': {'week_count': 18},
        },
      );
      expect(inChat.status, GlobalKnowledgeCandidateStatus.pending);
      expect(pending.status, GlobalKnowledgeCandidateStatus.pending);

      await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_inbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conversation_manage')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('conversation_${current.id}')));
      await tester.pumpAndSettle();
      expect(find.textContaining('本学期'), findsOneWidget);
      await tester.tap(find.text('确认新增').first);
      await tester.pumpAndSettle();
      expect(
        runtime.results.globalKnowledgeCandidates
            .singleWhere((item) => item.id == inChat.id)
            .status,
        GlobalKnowledgeCandidateStatus.applied,
      );

      await tester.tap(find.byKey(const Key('conversation_manage')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conversation_pending_page')));
      await tester.pumpAndSettle();
      expect(find.textContaining('下学期'), findsOneWidget);
      await tester.tap(find.text('确认新增').first);
      await tester.pumpAndSettle();
      expect(
        runtime.results.globalKnowledgeCandidates
            .singleWhere((item) => item.id == pending.id)
            .status,
        GlobalKnowledgeCandidateStatus.applied,
      );
      expect(
        runtime.results.knowledge.where((item) => item.isGlobalKnowledge),
        hasLength(2),
      );
    },
  );
}
