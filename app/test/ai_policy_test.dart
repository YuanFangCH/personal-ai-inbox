import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/models.dart';

void main() {
  test('four presets have the intended action behavior', () {
    final readOnly = AiPolicy.forPreset(AiPolicyPreset.readOnly);
    final standard = AiPolicy.forPreset(AiPolicyPreset.standard);
    final fullAccess = AiPolicy.forPreset(AiPolicyPreset.fullAccess);
    final custom = AiPolicy.custom(
      decisions: const {AiPermissionAction.contentRead: AiPolicyDecision.allow},
      tableScope: AiResourceScope.selected(const ['tb_notes']),
    );

    expect(readOnly.preset, AiPolicyPreset.readOnly);
    expect(
      readOnly.decisionFor(AiPermissionAction.tableRead),
      AiPolicyDecision.allow,
    );
    expect(
      readOnly.decisionFor(AiPermissionAction.tableDelete),
      AiPolicyDecision.deny,
    );

    expect(standard.preset, AiPolicyPreset.standard);
    expect(
      standard.decisionFor(AiPermissionAction.contentUpdate),
      AiPolicyDecision.allow,
    );
    expect(
      standard.decisionFor(AiPermissionAction.tableDelete),
      AiPolicyDecision.ask,
    );
    expect(
      standard.decisionFor(AiPermissionAction.globalKnowledgeUpdate),
      AiPolicyDecision.ask,
    );

    expect(fullAccess.preset, AiPolicyPreset.fullAccess);
    for (final action in AiPermissionAction.values) {
      expect(
        fullAccess.decisionFor(action),
        AiPolicyDecision.allow,
        reason: action.wireName,
      );
    }
    expect(
      fullAccess.decisionFor(
        AiPermissionAction.tableDelete,
        tableIds: const ['tb_inbox_todo'],
      ),
      AiPolicyDecision.allow,
      reason: 'full access includes the seeded inbox tables',
    );

    expect(custom.preset, AiPolicyPreset.custom);
    expect(
      custom.decisionFor(
        AiPermissionAction.contentRead,
        tableIds: const ['tb_notes'],
      ),
      AiPolicyDecision.allow,
    );
    expect(
      custom.decisionFor(AiPermissionAction.contentDelete),
      AiPolicyDecision.deny,
      reason: 'custom decisions fail closed when an action is omitted',
    );
  });

  test('table scope is enforced for every table touched by a move', () {
    final policy = AiPolicy.custom(
      decisions: const {AiPermissionAction.contentMove: AiPolicyDecision.allow},
      tableScope: AiResourceScope.selected(const ['tb_source']),
    );

    expect(
      policy.decisionFor(
        AiPermissionAction.contentMove,
        tableIds: const ['tb_source'],
      ),
      AiPolicyDecision.allow,
    );
    expect(
      policy.decisionFor(
        AiPermissionAction.contentMove,
        tableIds: const ['tb_source', 'tb_target'],
      ),
      AiPolicyDecision.deny,
    );
  });

  test('table creation requires unrestricted table scope', () {
    final selectedScope = AiPolicy.custom(
      decisions: const {AiPermissionAction.tableCreate: AiPolicyDecision.allow},
      tableScope: AiResourceScope.selected(const ['tb_allowed']),
    );
    final standard = AiPolicy.forPreset(AiPolicyPreset.standard);
    final fullAccess = AiPolicy.forPreset(AiPolicyPreset.fullAccess);

    expect(
      selectedScope.decisionFor(AiPermissionAction.tableCreate),
      AiPolicyDecision.deny,
    );
    final noScope = AiPolicy.custom(
      decisions: const {AiPermissionAction.tableCreate: AiPolicyDecision.allow},
      tableScope: const AiResourceScope.none(),
    );
    expect(
      noScope.decisionFor(AiPermissionAction.tableCreate),
      AiPolicyDecision.deny,
    );
    expect(
      standard.decisionFor(AiPermissionAction.tableCreate),
      AiPolicyDecision.ask,
    );
    expect(
      fullAccess.decisionFor(AiPermissionAction.tableCreate),
      AiPolicyDecision.allow,
    );
  });

  test('knowledge and conversation reads use independent scopes', () {
    final policy = AiPolicy.custom(
      decisions: const {
        AiPermissionAction.globalKnowledgeRead: AiPolicyDecision.allow,
        AiPermissionAction.globalKnowledgeSearch: AiPolicyDecision.allow,
        AiPermissionAction.conversationHistoryRead: AiPolicyDecision.allow,
        AiPermissionAction.conversationHistorySearch: AiPolicyDecision.allow,
      },
      knowledgeReadScope: AiResourceScope.selected(const ['kn_school']),
      conversationHistoryReadScope: const AiResourceScope.none(),
    );

    expect(
      policy.decisionFor(
        AiPermissionAction.globalKnowledgeRead,
        knowledgeId: 'kn_school',
      ),
      AiPolicyDecision.allow,
    );
    expect(
      policy.decisionFor(
        AiPermissionAction.globalKnowledgeRead,
        knowledgeId: 'kn_private',
      ),
      AiPolicyDecision.deny,
    );
    expect(
      policy.decisionFor(
        AiPermissionAction.conversationHistoryRead,
        conversationId: 'conv_other',
      ),
      AiPolicyDecision.deny,
      reason: 'knowledge access must not grant history access',
    );
  });

  test(
    'legacy permissions preserve capabilities without granting full access',
    () {
      final legacy = AiPolicy.fromLegacyPermissions(const AiPermissions());

      expect(legacy.preset, AiPolicyPreset.custom);
      expect(legacy.preset, isNot(AiPolicyPreset.fullAccess));
      expect(
        legacy.decisionFor(AiPermissionAction.contentCreate),
        AiPolicyDecision.allow,
      );
      expect(
        legacy.decisionFor(AiPermissionAction.tableCreate),
        AiPolicyDecision.ask,
      );
      expect(
        legacy.decisionFor(AiPermissionAction.tableDelete),
        AiPolicyDecision.ask,
      );
      expect(
        legacy.decisionFor(AiPermissionAction.globalKnowledgeDelete),
        AiPolicyDecision.ask,
      );
    },
  );

  test('legacy disabled capabilities remain denied', () {
    final noRead = AiPolicy.fromLegacyPermissions(
      const AiPermissions(read: false),
    );
    final createOnly = AiPolicy.fromLegacyPermissions(
      const AiPermissions(modifyDelete: false),
    );
    final noWrites = AiPolicy.fromLegacyPermissions(
      const AiPermissions(read: false, create: false, modifyDelete: false),
    );

    expect(
      noRead.decisionFor(AiPermissionAction.tableRead),
      AiPolicyDecision.deny,
    );
    expect(
      noRead.decisionFor(AiPermissionAction.conversationHistorySearch),
      AiPolicyDecision.deny,
    );
    expect(
      createOnly.decisionFor(AiPermissionAction.contentCreate),
      AiPolicyDecision.allow,
    );
    expect(
      createOnly.decisionFor(AiPermissionAction.contentDelete),
      AiPolicyDecision.deny,
    );
    expect(
      createOnly.decisionFor(AiPermissionAction.tableCreate),
      AiPolicyDecision.ask,
    );
    expect(
      createOnly.decisionFor(AiPermissionAction.tableDelete),
      AiPolicyDecision.deny,
    );
    expect(
      noWrites.decisionFor(AiPermissionAction.globalKnowledgeCreate),
      AiPolicyDecision.deny,
    );
  });

  test('policy and legacy permission wire formats remain explicit', () {
    final policy = AiPolicy.forPreset(
      AiPolicyPreset.standard,
      version: 3,
      tableScope: AiResourceScope.selected(const ['tb_school', 'tb_home']),
      knowledgeReadScope: const AiResourceScope.none(),
      conversationHistoryReadScope: const AiResourceScope.all(),
    );
    final decoded = AiPolicy.fromJson(policy.toJson());

    expect(decoded.version, 3);
    expect(decoded.preset, AiPolicyPreset.standard);
    expect(decoded.tableScope.covers('tb_school'), isTrue);
    expect(decoded.tableScope.covers('tb_private'), isFalse);
    expect(
      decoded.decisionFor(AiPermissionAction.tableDelete),
      AiPolicyDecision.ask,
    );
    expect(
      decoded.decisionFor(
        AiPermissionAction.globalKnowledgeRead,
        knowledgeId: 'kn_school',
      ),
      AiPolicyDecision.deny,
    );

    const legacy = AiPermissions(
      read: false,
      create: true,
      modifyDelete: false,
    );
    expect(AiPermissions.fromJson(legacy.toJson()), legacy);
  });
}
