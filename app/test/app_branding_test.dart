import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';

import 'test_support.dart';

void main() {
  testWidgets('Material app uses the confirmed product display name', (
    tester,
  ) async {
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(deviceId: 'branding-test'),
    );
    addTearDown(runtime.dispose);
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();

    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title, '懒狗秘书');
  });
}
