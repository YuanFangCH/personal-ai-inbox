import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/large_scenario_runner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final scenarios = loadLargeScenarios();

  for (final scenario in scenarios) {
    testWidgets('${scenario.id} ${scenario.name}', (tester) async {
      await runLargeScenario(scenario);
    });
  }
}
