import 'package:flutter_test/flutter_test.dart';

import 'large_scenario_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scenarios = loadLargeScenarios();

  test('large scenario matrix contains 20 rich scenarios', () {
    expect(scenarios, hasLength(20));
    expect(scenarios.map((scenario) => scenario.id).toSet(), hasLength(20));
    expect(scenarios.map((scenario) => scenario.key).toSet(), hasLength(20));
    expect(
      scenarios.map((scenario) => scenario.category).toSet().length,
      greaterThanOrEqualTo(10),
    );

    for (final scenario in scenarios) {
      final calls = scenario.messages
          .expand((message) => message.calls)
          .toList(growable: false);
      expect(scenario.messages.length, greaterThanOrEqualTo(2));
      expect(calls.length, greaterThanOrEqualTo(6));
      expect(calls.where((call) => call.type.name == 'event').length, 2);
      expect(calls.where((call) => call.type.name == 'todo').length, 1);
      expect(calls.where((call) => call.type.name == 'knowledge').length, 2);
      expect(calls.where((call) => call.type.name == 'matter').length, 1);
      expect(calls.where((call) => call.expect == 'created').length, 6);
      expect(calls.where((call) => call.start != null).length, 2);
      expect(calls.where((call) => call.due != null).length, 1);
    }
  });

  for (final scenario in scenarios) {
    test('${scenario.id} ${scenario.name}', () async {
      await runLargeScenario(scenario);
    });
  }
}
