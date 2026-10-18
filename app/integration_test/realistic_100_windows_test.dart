import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/e2e/realistic_runner.dart';
import '../test/e2e/realistic_scenario.dart';
import '../test/e2e/realistic_scenarios.g.dart';

/// Windows desktop leg of the realistic matrix.
///
/// Run with:
///   flutter test integration_test/realistic_100_windows_test.dart -d windows
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final scenarios = realisticScenarioMaps
      .map(RealisticScenario.fromMap)
      .where((scenario) => scenario.platform == RealisticPlatform.windows)
      .toList(growable: false);

  for (final scenario in scenarios) {
    testWidgets('${scenario.id} ${scenario.title}', (tester) async {
      // Desktop runs as a large window; the runner pins a 1440x900 logical
      // viewport so layout assertions are stable across machines.
      await runRealisticScenario(tester, scenario);
    });
  }
}
