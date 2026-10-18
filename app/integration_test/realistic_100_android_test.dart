import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/e2e/realistic_runner.dart';
import '../test/e2e/realistic_scenario.dart';
import '../test/e2e/realistic_scenarios.g.dart';

/// Android leg of the realistic matrix.
///
/// Run with:
///   flutter test integration_test/realistic_100_android_test.dart `
///     -d emulator-5560 --dart-define=E2E_PLATFORM=phone
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const platformName = String.fromEnvironment(
    'E2E_PLATFORM',
    defaultValue: 'phone',
  );
  final platform = RealisticPlatform.parse(platformName);
  if (!platform.isAndroid) {
    throw StateError('E2E_PLATFORM must be phone or tablet, got $platformName');
  }
  final scenarios = realisticScenarioMaps
      .map(RealisticScenario.fromMap)
      .where((scenario) => scenario.platform == platform)
      .toList(growable: false);

  for (final scenario in scenarios) {
    testWidgets('${scenario.id} ${scenario.title}', (tester) async {
      await runRealisticScenario(tester, scenario, simulateViewport: false);
    });
  }
}
