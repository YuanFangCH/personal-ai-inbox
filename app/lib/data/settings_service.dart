import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class AppSettings {
  const AppSettings({
    required this.deviceId,
    required this.themeMode,
    required this.modelBaseUrl,
    required this.modelName,
    required this.hasModelKey,
    required this.showCompletedTodos,
    required this.calendarMonthDetailed,
    this.allowImageEgress = true,
  });

  final String deviceId;
  final ThemeMode themeMode;
  final String modelBaseUrl;
  final String modelName;
  final bool hasModelKey;
  final bool showCompletedTodos;
  final bool calendarMonthDetailed;
  final bool allowImageEgress;

  AppSettings copyWith({
    String? deviceId,
    ThemeMode? themeMode,
    String? modelBaseUrl,
    String? modelName,
    bool? hasModelKey,
    bool? showCompletedTodos,
    bool? calendarMonthDetailed,
    bool? allowImageEgress,
  }) {
    return AppSettings(
      deviceId: deviceId ?? this.deviceId,
      themeMode: themeMode ?? this.themeMode,
      modelBaseUrl: modelBaseUrl ?? this.modelBaseUrl,
      modelName: modelName ?? this.modelName,
      hasModelKey: hasModelKey ?? this.hasModelKey,
      showCompletedTodos: showCompletedTodos ?? this.showCompletedTodos,
      calendarMonthDetailed:
          calendarMonthDetailed ?? this.calendarMonthDetailed,
      allowImageEgress: allowImageEgress ?? this.allowImageEgress,
    );
  }
}

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
    ThemeMode? themeMode,
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

  ThemeMode _parseTheme(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  String _themeName(ThemeMode value) {
    return switch (value) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }
}
