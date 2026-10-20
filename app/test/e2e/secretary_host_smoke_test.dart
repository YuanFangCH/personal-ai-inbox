import 'package:flutter_test/flutter_test.dart';

import 'realistic_runner.dart';
import 'secretary_scenario.dart';
import 'secretary_scenarios.g.dart';

void main() {
  final scenarios = {
    for (final item in secretaryScenarioMaps.map(SecretaryScenario.fromMap))
      item.id: item,
  };
  for (final id in const [
    'SEC-001',
    'SEC-011',
    'SEC-023',
    'SEC-041',
    'SEC-055',
    'SEC-073',
    'SEC-083',
    'SEC-091',
    'SEC-097',
    'SEC-098',
    'SEC-099',
  ]) {
    final scenario = scenarios[id]!;
    testWidgets('${scenario.id} ${scenario.title}', (tester) async {
      await runSecretaryScenario(tester, scenario, usePersistentStorage: false);
    });
  }
}
