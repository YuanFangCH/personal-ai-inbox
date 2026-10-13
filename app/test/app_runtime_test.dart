import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';

import 'test_support.dart';

void main() {
  test('bootstraps modules in a temporary memory configuration and shuts down safely', () async {
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(deviceId: 'runtime-test'),
    );
    final created = await runtime.results.createManual(
      type: ResultType.knowledge,
      title: 'Runtime lifecycle',
      body: 'Synthetic content',
    );

    expect(runtime.results.findDocument(created.id), isNotNull);
    await runtime.shutdown();
    await runtime.shutdown();
  });
}
