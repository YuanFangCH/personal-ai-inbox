import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/settings_service.dart';

class FakeSettingsService extends SettingsService {
  FakeSettingsService({
    String deviceId = 'test-device',
    ThemePreference themeMode = ThemePreference.light,
    String modelBaseUrl = 'https://api.deepseek.com',
    String modelName = 'deepseek-flash',
    String? modelKey,
    AiPermissions defaultAiPermissions = const AiPermissions(),
  }) : _settings = AppSettings(
         deviceId: deviceId,
         themeMode: themeMode,
         modelBaseUrl: modelBaseUrl,
         modelName: modelName,
         hasModelKey: modelKey != null,
         showCompletedTodos: false,
         calendarMonthDetailed: true,
         allowImageEgress: true,
         defaultAiPermissions: defaultAiPermissions,
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
  Future<AppSettings> saveConfiguration(
    AppSettings configuration, {
    String? apiKey,
    bool replaceApiKey = false,
  }) async {
    if (replaceApiKey) {
      _modelKey = apiKey?.trim().isEmpty == true ? null : apiKey?.trim();
    }
    _settings = configuration.copyWith(hasModelKey: _modelKey != null);
    return _settings;
  }

  @override
  Future<void> saveGeneral({
    ThemePreference? themeMode,
    String? modelBaseUrl,
    String? modelName,
    bool? showCompletedTodos,
    bool? calendarMonthDetailed,
    bool? allowImageEgress,
    AiPermissions? defaultAiPermissions,
    ModelCapabilityOverrides? capabilityOverrides,
    int? responseHeaderTimeoutSeconds,
    int? streamIdleTimeoutSeconds,
    int? totalTimeoutSeconds,
    int? contextMessageLimit,
    int? imageMessageLimit,
    int? imageLimit,
  }) async {
    _settings = _settings.copyWith(
      themeMode: themeMode,
      modelBaseUrl: modelBaseUrl,
      modelName: modelName,
      showCompletedTodos: showCompletedTodos,
      calendarMonthDetailed: calendarMonthDetailed,
      allowImageEgress: allowImageEgress,
      defaultAiPermissions: defaultAiPermissions,
      capabilityOverrides: capabilityOverrides,
      responseHeaderTimeoutSeconds: responseHeaderTimeoutSeconds,
      streamIdleTimeoutSeconds: streamIdleTimeoutSeconds,
      totalTimeoutSeconds: totalTimeoutSeconds,
      contextMessageLimit: contextMessageLimit,
      imageMessageLimit: imageMessageLimit,
      imageLimit: imageLimit,
    );
  }
}
