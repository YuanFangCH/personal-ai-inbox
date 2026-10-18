import 'package:flutter_test/flutter_test.dart';

import 'realistic_runner.dart';
import 'realistic_scenario.dart';
import 'realistic_scenarios.g.dart';

/// Host-side smoke run: one scenario per category, executed on the Dart VM.
///
/// The full 100-scenario matrix runs on the three device legs. This smoke test
/// keeps the runner honest in CI without requiring an emulator.
void main() {
  final scenarios = {
    for (final scenario in realisticScenarioMaps.map(RealisticScenario.fromMap))
      scenario.id: scenario,
  };
  const selected = [
    'e2e_001', // capture
    'e2e_013', // review
    'e2e_023', // calendar
    'e2e_035', // matters
    'e2e_043', // knowledge
    'e2e_051', // chat text
    'e2e_052', // chat auto-record
    'e2e_063', // chat failure + retry
    'e2e_065', // chat stop
    'e2e_069', // sync
    'e2e_071', // sync conflict
    'e2e_085', // settings
    'e2e_093', // recovery
    'e2e_097', // mixed
  ];

  // Persistence scenarios use real file IO, which needs the live async clock of
  // a device (or `tester.runAsync`); they run on all three device legs. The
  // in-memory cold-start path is covered here by the recovery scenario.
  for (final id in selected) {
    final scenario = scenarios[id]!;
    testWidgets('${scenario.id} ${scenario.title}', (tester) async {
      await runRealisticScenario(tester, scenario);
    });
  }
}
