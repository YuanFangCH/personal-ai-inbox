import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/services/model_capabilities.dart';

void main() {
  test(
    'unknown models remain text-only unless the user overrides capability',
    () {
      const defaults = AppSettings(
        deviceId: 'device-test',
        themeMode: ThemePreference.system,
        modelBaseUrl: 'https://example.com/v1',
        modelName: 'unlisted-model',
        hasModelKey: false,
        showCompletedTodos: false,
        calendarMonthDetailed: true,
      );
      final fallback = ModelCapabilities.resolve(defaults);
      expect(fallback.vision, isFalse);
      expect(fallback.toolCalls, isFalse);
      expect(fallback.jsonOutput, isFalse);

      final configured = defaults.copyWith(
        capabilityOverrides: const ModelCapabilityOverrides(
          vision: true,
          toolCalls: false,
        ),
      );
      final capabilities = ModelCapabilities.resolve(configured);
      expect(capabilities.vision, isTrue);
      expect(capabilities.toolCalls, isFalse);
      expect(capabilities.jsonOutput, isFalse);
    },
  );

  test('default model declaration can be explicitly disabled', () {
    final settings =
        const AppSettings(
          deviceId: 'device-test',
          themeMode: ThemePreference.system,
          modelBaseUrl: 'https://example.com/v1',
          modelName: 'deepseek-flash',
          hasModelKey: false,
          showCompletedTodos: false,
          calendarMonthDetailed: true,
        ).copyWith(
          capabilityOverrides: const ModelCapabilityOverrides(
            vision: false,
            toolCalls: false,
            jsonOutput: false,
          ),
        );

    final capabilities = ModelCapabilities.resolve(settings);
    expect(capabilities.vision, isFalse);
    expect(capabilities.toolCalls, isFalse);
    expect(capabilities.jsonOutput, isFalse);
  });
}
