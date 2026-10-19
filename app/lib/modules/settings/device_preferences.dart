import 'package:flutter/foundation.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/settings_service.dart';
import 'package:personal_ai_inbox/domain/app_failure.dart';

/// Deep module for one device's configuration snapshot.
///
/// The adapter seam hides SharedPreferences, secure storage, device identity,
/// and the existing SettingsService implementation.
class DevicePreferences extends ChangeNotifier {
  DevicePreferences({DevicePreferencesAdapter? adapter})
    : _adapter =
          adapter ?? SettingsServiceDevicePreferencesAdapter(SettingsService());

  final DevicePreferencesAdapter _adapter;
  Future<void> _queue = Future<void>.value();
  AppSettings? _settings;

  AppSettings get settings {
    final value = _settings;
    if (value == null) {
      throw const AppOperationException(
        AppFailure(code: 'settings_not_initialized', message: '端配置尚未初始化'),
      );
    }
    return value;
  }

  Future<void> initialize() {
    return _enqueue<void>(() async {
      final next = await _guard<AppSettings>(
        code: 'settings_initialize_failed',
        message: '端配置加载失败',
        operation: _adapter.load,
      );
      _settings = next;
      notifyListeners();
    });
  }

  Future<void> update({
    ThemePreference? themeMode,
    String? modelBaseUrl,
    String? modelName,
    String? apiKey,
    bool? showCompletedTodos,
    bool? calendarMonthDetailed,
    bool? allowImageEgress,
    ModelCapabilityOverrides? capabilityOverrides,
    int? responseHeaderTimeoutSeconds,
    int? streamIdleTimeoutSeconds,
    int? totalTimeoutSeconds,
    int? contextMessageLimit,
    int? imageMessageLimit,
    int? imageLimit,
    AiPermissions? defaultAiPermissions,
  }) {
    return _enqueue<void>(() async {
      final current = _settings ?? await _adapter.load();
      final candidate = current.copyWith(
        themeMode: themeMode,
        modelBaseUrl: modelBaseUrl?.trim(),
        modelName: modelName?.trim(),
        showCompletedTodos: showCompletedTodos,
        calendarMonthDetailed: calendarMonthDetailed,
        allowImageEgress: allowImageEgress,
        capabilityOverrides: capabilityOverrides,
        responseHeaderTimeoutSeconds: responseHeaderTimeoutSeconds,
        streamIdleTimeoutSeconds: streamIdleTimeoutSeconds,
        totalTimeoutSeconds: totalTimeoutSeconds,
        contextMessageLimit: contextMessageLimit,
        imageMessageLimit: imageMessageLimit,
        imageLimit: imageLimit,
        defaultAiPermissions: defaultAiPermissions,
      );
      final next = await _guard<AppSettings>(
        code: 'settings_update_failed',
        message: '端配置更新失败',
        operation: () async {
          final errors = candidate.validate();
          if (errors.isNotEmpty) {
            throw AppOperationException(
              AppFailure(
                code: 'settings_validation_failed',
                message: errors.join('；'),
                cause: ArgumentError(errors.join('；')),
              ),
            );
          }
          return _adapter.saveConfiguration(
            candidate,
            apiKey: apiKey,
            replaceApiKey: apiKey != null,
          );
        },
      );
      _settings = next;
      notifyListeners();
    });
  }

  Future<String?> readModelKey() {
    return _enqueue<String?>(
      () => _guard<String?>(
        code: 'settings_model_key_read_failed',
        message: '模型密钥读取失败',
        operation: _adapter.readModelKey,
      ),
    );
  }

  Future<void> saveModelKey(String apiKey) {
    return _enqueue<void>(() async {
      final next = await _guard<AppSettings>(
        code: 'settings_model_key_save_failed',
        message: '模型密钥保存失败',
        operation: () async {
          return _adapter.saveConfiguration(
            settings,
            apiKey: apiKey,
            replaceApiKey: true,
          );
        },
      );
      _settings = next;
      notifyListeners();
    });
  }

  Future<void> shutdown() => _queue;

  Future<Map<String, Object?>> exportPortableSettings() => _enqueue(
    () => _guard(
      code: 'settings_export_failed',
      message: '导出设置失败',
      operation: _adapter.exportPortableSettings,
    ),
  );

  Future<void> importPortableSettings(Map<String, dynamic> values) {
    return _enqueue<void>(() async {
      final next = await _guard<AppSettings>(
        code: 'settings_import_failed',
        message: '导入设置失败',
        operation: () => _adapter.importPortableSettings(values),
      );
      _settings = next;
      notifyListeners();
    });
  }

  Future<void> restoreDefaults() {
    return _enqueue<void>(() async {
      final next = await _guard<AppSettings>(
        code: 'settings_reset_failed',
        message: '恢复默认设置失败',
        operation: _adapter.restoreDefaults,
      );
      _settings = next;
      notifyListeners();
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<T> _guard<T>({
    required String code,
    required String message,
    required Future<T> Function() operation,
  }) async {
    try {
      return await operation();
    } on AppOperationException {
      rethrow;
    } catch (error, stackTrace) {
      throw AppOperationException(
        AppFailure(
          code: code,
          message: message,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}

/// Adapter seam for platform preferences and secure storage.
abstract interface class DevicePreferencesAdapter {
  Future<AppSettings> load();

  Future<void> saveGeneral({
    ThemePreference? themeMode,
    String? modelBaseUrl,
    String? modelName,
    bool? showCompletedTodos,
    bool? calendarMonthDetailed,
    bool? allowImageEgress,
    AiPermissions? defaultAiPermissions,
  });

  Future<String?> readModelKey();

  Future<void> saveModelKey(String apiKey);

  Future<AppSettings> saveConfiguration(
    AppSettings configuration, {
    String? apiKey,
    bool replaceApiKey = false,
  });

  Future<Map<String, Object?>> exportPortableSettings();

  Future<AppSettings> importPortableSettings(Map<String, dynamic> values);

  Future<AppSettings> restoreDefaults();
}

final class SettingsServiceDevicePreferencesAdapter
    implements DevicePreferencesAdapter {
  SettingsServiceDevicePreferencesAdapter(this._settingsService);

  final SettingsService _settingsService;

  @override
  Future<AppSettings> load() => _settingsService.load();

  @override
  Future<void> saveGeneral({
    ThemePreference? themeMode,
    String? modelBaseUrl,
    String? modelName,
    bool? showCompletedTodos,
    bool? calendarMonthDetailed,
    bool? allowImageEgress,
    AiPermissions? defaultAiPermissions,
  }) {
    return _settingsService.saveGeneral(
      themeMode: themeMode,
      modelBaseUrl: modelBaseUrl,
      modelName: modelName,
      showCompletedTodos: showCompletedTodos,
      calendarMonthDetailed: calendarMonthDetailed,
      allowImageEgress: allowImageEgress,
      defaultAiPermissions: defaultAiPermissions,
    );
  }

  @override
  Future<String?> readModelKey() => _settingsService.readModelKey();

  @override
  Future<void> saveModelKey(String apiKey) {
    return _settingsService.saveModelKey(apiKey);
  }

  @override
  Future<AppSettings> saveConfiguration(
    AppSettings configuration, {
    String? apiKey,
    bool replaceApiKey = false,
  }) => _settingsService.saveConfiguration(
    configuration,
    apiKey: apiKey,
    replaceApiKey: replaceApiKey,
  );

  @override
  Future<Map<String, Object?>> exportPortableSettings() =>
      _settingsService.exportPortableSettings();

  @override
  Future<AppSettings> importPortableSettings(Map<String, dynamic> values) =>
      _settingsService.importPortableSettings(values);

  @override
  Future<AppSettings> restoreDefaults() => _settingsService.restoreDefaults();
}
