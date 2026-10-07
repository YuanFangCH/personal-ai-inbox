import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/data/settings_service.dart';
import 'package:personal_ai_inbox/domain/app_failure.dart';
import 'package:personal_ai_inbox/modules/settings/device_preferences.dart';

void main() {
  group('DevicePreferences', () {
    test(
      'initialize publishes the adapter snapshot and keeps deviceId',
      () async {
        final settings = _FakeSettingsService();
        final preferences = _preferences(settings);
        var notifications = 0;
        preferences.addListener(() => notifications++);

        await preferences.initialize();

        expect(preferences.settings.deviceId, 'device_test');
        expect(preferences.settings.modelBaseUrl, 'https://api.deepseek.com');
        expect(preferences.settings.modelName, 'deepseek-flash');
        expect(preferences.settings.hasModelKey, isFalse);
        expect(notifications, 1);

        await preferences.initialize();

        expect(preferences.settings.deviceId, 'device_test');
        expect(notifications, 2);
      },
    );

    test(
      'update persists the same fields as AppController.saveSettings',
      () async {
        final settings = _FakeSettingsService();
        final preferences = _preferences(settings);
        await preferences.initialize();

        await preferences.update(
          themeMode: ThemeMode.dark,
          modelBaseUrl: ' https://example.com/v1 ',
          modelName: ' model-a ',
          showCompletedTodos: true,
          calendarMonthDetailed: false,
          allowImageEgress: false,
        );

        expect(settings.saveGeneralCalls, 1);
        expect(preferences.settings.deviceId, 'device_test');
        expect(preferences.settings.themeMode, ThemeMode.dark);
        expect(preferences.settings.modelBaseUrl, 'https://example.com/v1');
        expect(preferences.settings.modelName, 'model-a');
        expect(preferences.settings.showCompletedTodos, isTrue);
        expect(preferences.settings.calendarMonthDetailed, isFalse);
        expect(preferences.settings.allowImageEgress, isFalse);
      },
    );

    test('update saves and clears the model key', () async {
      final settings = _FakeSettingsService();
      final preferences = _preferences(settings);
      await preferences.initialize();

      await preferences.update(apiKey: '  secret-key  ');

      expect(await preferences.readModelKey(), 'secret-key');
      expect(preferences.settings.hasModelKey, isTrue);

      await preferences.update(apiKey: '');

      expect(await preferences.readModelKey(), isNull);
      expect(preferences.settings.hasModelKey, isFalse);
    });

    test('saveModelKey trims, clears, and publishes key state', () async {
      final settings = _FakeSettingsService();
      final preferences = _preferences(settings);
      await preferences.initialize();

      await preferences.saveModelKey('  another-key  ');

      expect(settings.modelKey, 'another-key');
      expect(preferences.settings.hasModelKey, isTrue);

      await preferences.saveModelKey('   ');

      expect(settings.modelKey, isNull);
      expect(preferences.settings.hasModelKey, isFalse);
    });

    test('wraps adapter failures without swallowing them', () async {
      final settings = _FakeSettingsService()
        ..loadError = StateError('load failed');
      final preferences = _preferences(settings);

      await expectLater(
        preferences.initialize(),
        throwsA(
          isA<AppOperationException>()
              .having(
                (error) => error.failure.code,
                'failure code',
                'settings_initialize_failed',
              )
              .having(
                (error) => error.failure.cause,
                'cause',
                isA<StateError>(),
              ),
        ),
      );
    });

    test(
      'serializes overlapping operations and keeps the newest state',
      () async {
        final gate = Completer<void>();
        final settings = _FakeSettingsService(firstLoadGate: gate);
        final preferences = _preferences(settings);

        final initialize = preferences.initialize();
        final update = preferences.update(themeMode: ThemeMode.dark);
        gate.complete();
        await Future.wait([initialize, update]);

        expect(preferences.settings.themeMode, ThemeMode.dark);
      },
    );

    test('settings access fails before initialize', () {
      final preferences = _preferences(_FakeSettingsService());

      expect(
        () => preferences.settings,
        throwsA(
          isA<AppOperationException>().having(
            (error) => error.failure.code,
            'failure code',
            'settings_not_initialized',
          ),
        ),
      );
    });
  });
}

DevicePreferences _preferences(_FakeSettingsService settings) {
  return DevicePreferences(
    adapter: SettingsServiceDevicePreferencesAdapter(settings),
  );
}

final class _FakeSettingsService extends SettingsService {
  _FakeSettingsService({Completer<void>? firstLoadGate})
    : _firstLoadGate = firstLoadGate;

  AppSettings _settings = const AppSettings(
    deviceId: 'device_test',
    themeMode: ThemeMode.system,
    modelBaseUrl: 'https://api.deepseek.com',
    modelName: 'deepseek-flash',
    hasModelKey: false,
    showCompletedTodos: false,
    calendarMonthDetailed: true,
  );

  String? modelKey;
  Object? loadError;
  final Completer<void>? _firstLoadGate;
  bool _firstLoad = true;
  int saveGeneralCalls = 0;

  @override
  Future<AppSettings> load() async {
    final error = loadError;
    if (error != null) {
      throw error;
    }
    final gate = _firstLoadGate;
    if (_firstLoad && gate != null) {
      _firstLoad = false;
      await gate.future;
    } else {
      _firstLoad = false;
    }
    return _settings;
  }

  @override
  Future<void> saveGeneral({
    ThemeMode? themeMode,
    String? modelBaseUrl,
    String? modelName,
    bool? showCompletedTodos,
    bool? calendarMonthDetailed,
    bool? allowImageEgress,
  }) async {
    saveGeneralCalls++;
    _settings = _settings.copyWith(
      themeMode: themeMode,
      modelBaseUrl: modelBaseUrl?.trim(),
      modelName: modelName?.trim(),
      showCompletedTodos: showCompletedTodos,
      calendarMonthDetailed: calendarMonthDetailed,
      allowImageEgress: allowImageEgress,
    );
  }

  @override
  Future<String?> readModelKey() async => modelKey;

  @override
  Future<void> saveModelKey(String apiKey) async {
    final normalized = apiKey.trim();
    modelKey = normalized.isEmpty ? null : normalized;
    _settings = _settings.copyWith(hasModelKey: modelKey != null);
  }
}
