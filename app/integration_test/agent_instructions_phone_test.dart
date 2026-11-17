import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/services/agent_background_service.dart';

import '../test/test_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AGENTS.md editor opens, saves and undoes on Android', (
    tester,
  ) async {
    final vault = MemoryVaultStore();
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: vault,
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(
        deviceId: 'agent-instructions-phone',
      ),
    );
    final background = _NoopBackgroundPort();
    await tester.pumpWidget(
      PersonalAiInboxApp(runtime: runtime, backgroundAgent: background),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet_nav_settings')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('settings_agent_instructions')),
    );
    await tester.tap(find.byKey(const Key('settings_agent_instructions')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField), 'Android 合成长期规则');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(vault.files['AGENTS.md'], 'Android 合成长期规则');

    await tester.tap(find.text('撤销最近一次改动'));
    await tester.pumpAndSettle();
    expect(vault.files['AGENTS.md'], isNull);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    runtime.dispose();
  });
}

class _NoopBackgroundPort implements AgentBackgroundPort {
  final ValueNotifier<AgentBackgroundSnapshot> _status = ValueNotifier(
    const AgentBackgroundSnapshot.initial(),
  );

  @override
  Stream<AgentBackgroundCommand> get commands => const Stream.empty();

  @override
  ValueListenable<AgentBackgroundSnapshot> get status => _status;

  @override
  Future<void> initialize() async {}
}
