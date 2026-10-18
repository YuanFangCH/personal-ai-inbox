import 'package:flutter_test/flutter_test.dart';

import 'realistic_scenario.dart';
import 'realistic_scenarios.g.dart';

void main() {
  final scenarios = realisticScenarioMaps
      .map(RealisticScenario.fromMap)
      .toList(growable: false);

  test('matrix holds exactly 100 unique scenarios across three platforms', () {
    expect(scenarios, hasLength(100));
    expect(
      scenarios.map((scenario) => scenario.id).toSet(),
      hasLength(100),
      reason: 'scenario ids must be unique',
    );
    final counts = <RealisticPlatform, int>{};
    for (final scenario in scenarios) {
      counts[scenario.platform] = (counts[scenario.platform] ?? 0) + 1;
    }
    expect(counts[RealisticPlatform.phone], 50);
    expect(counts[RealisticPlatform.tablet], 25);
    expect(counts[RealisticPlatform.windows], 25);
  });

  test('every scenario is complex enough to be an end-to-end flow', () {
    for (final scenario in scenarios) {
      expect(
        scenario.steps.length,
        greaterThanOrEqualTo(6),
        reason: '${scenario.id} needs at least 6 steps',
      );
      final assertions = scenario.steps
          .where((step) => step.op == 'assert')
          .toList(growable: false);
      expect(
        assertions.length,
        greaterThanOrEqualTo(2),
        reason: '${scenario.id} needs at least 2 assertions',
      );
      expect(
        assertions.any(
          (step) =>
              step.args['kind'] != 'noException' &&
              step.args['kind'] != 'textVisible',
        ),
        isTrue,
        reason: '${scenario.id} needs a real state assertion',
      );
      final modules = scenario.steps
          .map((step) => step.op)
          .where(
            (op) => const {
              'capture',
              'quickCreate',
              'toggleTodo',
              'searchKnowledge',
              'openDoc',
              'newChat',
              'startChat',
              'retryChat',
              'stopChat',
              'undoAutoRecord',
              'resolveConflict',
              'sync',
              'theme',
              'imageEgress',
              'restart',
            }.contains(op),
          )
          .toSet();
      expect(
        modules.length,
        greaterThanOrEqualTo(2),
        reason: '${scenario.id} must cross at least two modules',
      );
    }
  });

  test('all ops and assertion kinds are implemented by the runner', () {
    for (final scenario in scenarios) {
      for (final step in scenario.steps) {
        expect(
          supportedOps.containsKey(step.op),
          isTrue,
          reason: '${scenario.id} uses unknown op ${step.op}',
        );
        if (step.op == 'assert') {
          final kind = step.args['kind'] as String;
          expect(
            supportedAsserts.contains(kind),
            isTrue,
            reason: '${scenario.id} uses unknown assertion $kind',
          );
        }
      }
    }
  });

  test('all twelve scenario categories are represented', () {
    final categories = scenarios.map((scenario) => scenario.category).toSet();
    expect(categories, hasLength(12));
    for (final category in const [
      'capture',
      'review',
      'calendar',
      'matters',
      'knowledge',
      'chat',
      'chatFailure',
      'sync',
      'persistence',
      'settings',
      'recovery',
      'mixed',
    ]) {
      expect(categories, contains(category));
    }
  });
}
