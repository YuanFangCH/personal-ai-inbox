import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/models.dart';

export '../core/models.dart' show AppSettings;

class SettingsService {
  SettingsService({
    SharedPreferencesAsync? preferences,
    FlutterSecureStorage? secureStorage,
  }) : _preferences = preferences,
       _secureStorage = secureStorage;

  static const _deviceIdKey = 'device_id';
  static const _themeKey = 'theme_mode';
  static const _modelUrlKey = 'model_base_url';
  static const _modelNameKey = 'model_name';
  static const _showCompletedKey = 'show_completed_todos';
  static const _calendarMonthDetailedKey = 'calendar_month_detailed';
  static const _allowImageEgressKey = 'allow_image_egress';
  static const _modelApiKey = 'model_api_key';

  SharedPreferencesAsync? _preferences;
  FlutterSecureStorage? _secureStorage;

  SharedPreferencesAsync get _prefs =>
      _preferences ??= SharedPreferencesAsync();

  FlutterSecureStorage get _secure =>
      _secureStorage ??= const FlutterSecureStorage();

  Future<AppSettings> load() async {
    var deviceId = await _prefs.getString(_deviceIdKey);
    if (deviceId == null || deviceId.trim().isEmpty) {
      deviceId =
          'device_${const Uuid().v4().replaceAll('-', '').substring(0, 12)}';
      await _prefs.setString(_deviceIdKey, deviceId);
    }

    return AppSettings(
      deviceId: deviceId,
      themeMode: _parseTheme(await _prefs.getString(_themeKey)),
      modelBaseUrl:
          await _prefs.getString(_modelUrlKey) ?? 'https://api.deepseek.com',
      modelName: await _prefs.getString(_modelNameKey) ?? 'deepseek-flash',
      hasModelKey: await hasModelKey(),
      showCompletedTodos: await _prefs.getBool(_showCompletedKey) ?? false,
      calendarMonthDetailed:
          await _prefs.getBool(_calendarMonthDetailedKey) ?? true,
      allowImageEgress: await _prefs.getBool(_allowImageEgressKey) ?? true,
    );
  }

  Future<void> saveGeneral({
    ThemePreference? themeMode,
    String? modelBaseUrl,
    String? modelName,
    bool? showCompletedTodos,
    bool? calendarMonthDetailed,
    bool? allowImageEgress,
  }) async {
    if (themeMode != null) {
      await _prefs.setString(_themeKey, _themeName(themeMode));
    }
    if (modelBaseUrl != null) {
      await _prefs.setString(_modelUrlKey, modelBaseUrl.trim());
    }
    if (modelName != null) {
      await _prefs.setString(_modelNameKey, modelName.trim());
    }
    if (showCompletedTodos != null) {
      await _prefs.setBool(_showCompletedKey, showCompletedTodos);
    }
    if (calendarMonthDetailed != null) {
      await _prefs.setBool(_calendarMonthDetailedKey, calendarMonthDetailed);
    }
    if (allowImageEgress != null) {
      await _prefs.setBool(_allowImageEgressKey, allowImageEgress);
    }
  }

  Future<String?> readModelKey() => _secure.read(key: _modelApiKey);

  Future<bool> hasModelKey() async {
    final value = await readModelKey();
    return value != null && value.trim().isNotEmpty;
  }

  Future<void> saveModelKey(String apiKey) async {
    final normalized = apiKey.trim();
    if (normalized.isEmpty) {
      await _secure.delete(key: _modelApiKey);
    } else {
      await _secure.write(key: _modelApiKey, value: normalized);
    }
  }

  /// Returns portable device preferences for a migration safety snapshot.
  /// The model API key is deliberately excluded; it stays in secure storage.
  Future<Map<String, Object?>> exportMigrationPreferences() async {
    final values = <String, Object?>{};
    for (final key in const [
      _deviceIdKey,
      _themeKey,
      _modelUrlKey,
      _modelNameKey,
    ]) {
      values[key] = await _prefs.getString(key);
    }
    for (final key in const [
      _showCompletedKey,
      _calendarMonthDetailedKey,
      _allowImageEgressKey,
    ]) {
      values[key] = await _prefs.getBool(key);
    }
    return values;
  }

  Future<void> restoreMigrationPreferences(Map<String, dynamic> values) async {
    const keys = [
      _deviceIdKey,
      _themeKey,
      _modelUrlKey,
      _modelNameKey,
      _showCompletedKey,
      _calendarMonthDetailedKey,
      _allowImageEgressKey,
    ];
    for (final key in keys) {
      final value = values[key];
      if (value is String) {
        await _prefs.setString(key, value);
      } else if (value is bool) {
        await _prefs.setBool(key, value);
      } else {
        await _prefs.remove(key);
      }
    }
  }

  ThemePreference _parseTheme(String? value) {
    return switch (value) {
      'light' => ThemePreference.light,
      'dark' => ThemePreference.dark,
      _ => ThemePreference.system,
    };
  }

  String _themeName(ThemePreference value) {
    return switch (value) {
      ThemePreference.light => 'light',
      ThemePreference.dark => 'dark',
      ThemePreference.system => 'system',
    };
  }
}
