import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/e2e/realistic_runner.dart';
import '../test/e2e/realistic_scenario.dart';
import '../test/e2e/secretary_scenario.dart';
import '../test/e2e/secretary_scenarios.g.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const platformName = String.fromEnvironment(
    'E2E_PLATFORM',
    defaultValue: 'phone',
  );
  final platform = RealisticPlatform.parse(platformName);
  const selectedIds = String.fromEnvironment('E2E_CASE_IDS');
  final filter = selectedIds.isEmpty
      ? const <String>{}
      : selectedIds.split(',').toSet();
  if (!platform.isAndroid) {
    throw StateError('E2E_PLATFORM must be phone or tablet, got $platformName');
  }
  final scenarios = secretaryScenarioMaps
      .map(SecretaryScenario.fromMap)
      .where(
        (item) =>
            item.platform == platform &&
            (filter.isEmpty || filter.contains(item.id)),
      )
      .toList(growable: false);
  final expectedCount = filter.isEmpty
      ? (platform == RealisticPlatform.phone ? 50 : 25)
      : filter.length;
  if (scenarios.length != expectedCount) {
    throw StateError(
      '$platformName matrix expected $expectedCount cases, got ${scenarios.length}',
    );
  }

  for (final scenario in scenarios) {
    testWidgets('${scenario.id} ${scenario.title}', (tester) async {
      await runSecretaryScenario(tester, scenario, simulateViewport: false);
      // ignore: avoid_print
      print('SEC_CASE_RESULT|${scenario.id}|passed');
    });
  }
}
