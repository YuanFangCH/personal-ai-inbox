import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';

import '../test/test_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full-agent switch applies and restores on Android', (
    tester,
  ) async {
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(deviceId: 'full-agent-android'),
    );
    addTearDown(runtime.dispose);
    final conversation = await runtime.conversations.createConversation(
      policy: AiPolicy.forPreset(AiPolicyPreset.standard),
    );
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_settings')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings_full_agent_mode')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(runtime.preferences.settings.fullAgentMode, isTrue);
    expect(
      runtime.conversations
          .effectivePolicyFor(runtime.conversations.findConversation(conversation.id))
          .preset,
      AiPolicyPreset.fullAccess,
    );

    await tester.tap(find.byKey(const Key('settings_full_agent_mode')));
    await tester.pumpAndSettle();
    expect(runtime.preferences.settings.fullAgentMode, isFalse);
    expect(
      runtime.conversations
          .effectivePolicyFor(runtime.conversations.findConversation(conversation.id))
          .preset,
      AiPolicyPreset.standard,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
