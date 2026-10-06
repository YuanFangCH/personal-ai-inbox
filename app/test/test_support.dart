import 'package:flutter/material.dart';
import 'package:personal_ai_inbox/data/settings_service.dart';

class FakeSettingsService extends SettingsService {
  FakeSettingsService({
    String deviceId = 'test-device',
    ThemeMode themeMode = ThemeMode.light,
    String modelBaseUrl = 'https://api.deepseek.com',
    String modelName = 'deepseek-flash',
    String? modelKey,
  }) : _settings = AppSettings(
         deviceId: deviceId,
         themeMode: themeMode,
         modelBaseUrl: modelBaseUrl,
         modelName: modelName,
         hasModelKey: modelKey != null,
         showCompletedTodos: false,
         calendarMonthDetailed: true,
         allowImageEgress: true,
       ),
       _modelKey = modelKey;

  AppSettings _settings;
  String? _modelKey;

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<String?> readModelKey() async => _modelKey;

  @override
  Future<bool> hasModelKey() async => _modelKey?.isNotEmpty == true;

  @override
  Future<void> saveModelKey(String apiKey) async {
    _modelKey = apiKey.trim().isEmpty ? null : apiKey.trim();
    _settings = _settings.copyWith(hasModelKey: _modelKey != null);
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
    _settings = _settings.copyWith(
      themeMode: themeMode,
      modelBaseUrl: modelBaseUrl,
      modelName: modelName,
      showCompletedTodos: showCompletedTodos,
      calendarMonthDetailed: calendarMonthDetailed,
      allowImageEgress: allowImageEgress,
    );
  }
}
