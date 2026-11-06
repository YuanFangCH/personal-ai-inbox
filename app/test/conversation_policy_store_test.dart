import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';

void main() {
  test('legacy conversations derive a non-expanding effective policy', () {
    final conversation = Conversation(
      id: 'cnv_legacy',
      title: '旧会话',
      createdAt: DateTime(2026, 11, 3),
      updatedAt: DateTime(2026, 11, 3),
      autoTitle: false,
      aiPermissions: const AiPermissions(
        read: false,
        create: true,
        modifyDelete: false,
      ),
    );

    final policy = conversation.effectiveAiPolicy;
    expect(conversation.aiPolicy, isNull);
    expect(policy.preset, AiPolicyPreset.custom);
    expect(
      policy.decisionFor(AiPermissionAction.tableRead),
      AiPolicyDecision.deny,
    );
    expect(
      policy.decisionFor(AiPermissionAction.contentCreate),
      AiPolicyDecision.allow,
    );
    expect(
      policy.decisionFor(AiPermissionAction.tableDelete),
      AiPolicyDecision.deny,
    );
    expect(
      policy.decisionFor(AiPermissionAction.globalKnowledgeUpdate),
      AiPolicyDecision.ask,
    );
  });

  test('explicit policy drives the legacy compatibility projection', () {
    final conversation = Conversation(
      id: 'cnv_full',
      title: '全权会话',
      createdAt: DateTime(2026, 11, 3),
      updatedAt: DateTime(2026, 11, 3),
      autoTitle: false,
      aiPermissions: const AiPermissions(
        read: false,
        create: false,
        modifyDelete: false,
      ),
      aiPolicy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
    );

    expect(conversation.effectiveAiPolicy.preset, AiPolicyPreset.fullAccess);
    expect(conversation.aiPermissions, const AiPermissions());
    expect(
      conversation.effectiveAiPolicy.decisionFor(
        AiPermissionAction.tableDelete,
        tableIds: const ['tb_inbox_todo'],
      ),
      AiPolicyDecision.allow,
    );
  });

  test('legacy permission writes detach the action-level policy', () {
    final conversation = Conversation(
      id: 'cnv_policy',
      title: '策略会话',
      createdAt: DateTime(2026, 11, 3),
      updatedAt: DateTime(2026, 11, 3),
      autoTitle: false,
      aiPolicy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
    );

    final legacyUpdate = conversation.copyWith(
      aiPermissions: const AiPermissions(
        read: false,
        create: true,
        modifyDelete: false,
      ),
    );

    expect(legacyUpdate.aiPolicy, isNull);
    expect(
      legacyUpdate.effectiveAiPolicy.decisionFor(AiPermissionAction.tableRead),
      AiPolicyDecision.deny,
    );
    expect(
      legacyUpdate.effectiveAiPolicy.decisionFor(
        AiPermissionAction.contentCreate,
      ),
      AiPolicyDecision.allow,
    );
  });

  test('memory conversation store preserves the optional policy', () async {
    final store = MemoryConversationStore();
    await store.open();
    final policy = AiPolicy.forPreset(AiPolicyPreset.standard, version: 4);
    final conversation = Conversation(
      id: 'cnv_memory',
      title: '内存会话',
      createdAt: DateTime(2026, 11, 3),
      updatedAt: DateTime(2026, 11, 3),
      autoTitle: false,
      aiPolicy: policy,
    );

    await store.upsertConversation(conversation);
    final restored = (await store.findConversation(conversation.id))!;

    expect(restored.aiPolicy, isNotNull);
    expect(restored.aiPolicy!.preset, AiPolicyPreset.standard);
    expect(restored.aiPolicy!.version, 4);
    expect(
      restored.effectiveAiPolicy.decisionFor(AiPermissionAction.tableDelete),
      AiPolicyDecision.ask,
    );
  });

  test('chat repository updates one conversation policy', () async {
    final repository = ChatRepository(
      store: MemoryConversationStore(),
      attachments: MemoryAttachmentStore(),
    );
    await repository.initialize();
    final conversation = await repository.createConversation();
    final fullAccess = AiPolicy.forPreset(AiPolicyPreset.fullAccess);

    final updated = await repository.setAiPolicy(conversation.id, fullAccess);
    final restored = await repository.findConversation(conversation.id);

    expect(updated?.aiPolicy?.preset, AiPolicyPreset.fullAccess);
    expect(restored?.aiPolicy?.preset, AiPolicyPreset.fullAccess);
    expect(
      restored?.aiPermissions,
      const AiPermissions(),
      reason: 'legacy readers receive the conservative full projection',
    );
  });
}
