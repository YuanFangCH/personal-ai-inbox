import 'package:flutter_test/flutter_test.dart';

import 'realistic_scenario.dart';
import 'secretary_scenario.dart';
import 'secretary_scenarios.g.dart';

void main() {
  final scenarios = secretaryScenarioMaps
      .map(SecretaryScenario.fromMap)
      .toList(growable: false);

  test('SEC matrix has 100 unique executable case records', () {
    expect(scenarios, hasLength(100));
    expect(scenarios.map((item) => item.id).toSet(), hasLength(100));
    expect(scenarios.map((item) => item.id).toSet(), {
      for (var index = 1; index <= 100; index++)
        'SEC-${index.toString().padLeft(3, '0')}',
    });
    for (final item in scenarios) {
      expect(item.title.trim(), isNotEmpty, reason: item.id);
      expect(item.assertions.trim(), isNotEmpty, reason: item.id);
      expect(
        secretaryCategoryCounts,
        contains(item.category),
        reason: '${item.id} has no executable category',
      );
    }
  });

  test('platform allocation is phone 50, tablet 25 and Windows 25', () {
    expect(
      scenarios.where((item) => item.platform == RealisticPlatform.phone),
      hasLength(50),
    );
    expect(
      scenarios.where((item) => item.platform == RealisticPlatform.tablet),
      hasLength(25),
    );
    expect(
      scenarios.where((item) => item.platform == RealisticPlatform.windows),
      hasLength(25),
    );
  });

  test('category totals match the approved new-feature matrix', () {
    for (final entry in secretaryCategoryCounts.entries) {
      expect(
        scenarios.where((item) => item.category == entry.key),
        hasLength(entry.value),
        reason: entry.key,
      );
    }
  });

  test('every row requires a data or effect assertion', () {
    const supportedSteps = {
      'navigateInbox',
      'baselineState',
      'scenarioOperation',
      'visibleTitle',
      'stateResult',
      'noException',
    };
    for (final item in scenarios) {
      expect(item.steps, hasLength(6), reason: item.id);
      expect(item.steps.toSet().length, 6, reason: '${item.id} repeats a step');
      expect(
        item.steps.toSet().difference(supportedSteps),
        isEmpty,
        reason: '${item.id} uses an unknown operation',
      );
      expect(
        item.steps.where(
          (step) => const {
            'baselineState',
            'stateResult',
            'noException',
          }.contains(step),
        ),
        hasLength(3),
        reason: '${item.id} lacks state assertions',
      );
      expect(
        item.assertions,
        isNot(anyOf(contains('无异常'), contains('有文字'))),
        reason: '${item.id} may not rely on a UI-only assertion',
      );
    }
  });
}
