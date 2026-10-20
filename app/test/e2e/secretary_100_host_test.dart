import 'package:flutter_test/flutter_test.dart';

import 'realistic_runner.dart';
import 'secretary_scenario.dart';
import 'secretary_scenarios.g.dart';

void main() {
  for (final scenario in secretaryScenarioMaps.map(SecretaryScenario.fromMap)) {
    testWidgets('${scenario.id} ${scenario.title}', (tester) async {
      await runSecretaryScenario(tester, scenario, usePersistentStorage: false);
      // ignore: avoid_print
      print('SEC_CASE_RESULT|${scenario.id}|passed');
    });
  }
}
