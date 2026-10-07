import 'package:flutter/material.dart';
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
    ThemeMode? themeMode,
    String? modelBaseUrl,
    String? modelName,
    String? apiKey,
    bool? showCompletedTodos,
    bool? calendarMonthDetailed,
    bool? allowImageEgress,
  }) {
    return _enqueue<void>(() async {
      final next = await _guard<AppSettings>(
        code: 'settings_update_failed',
        message: '端配置更新失败',
        operation: () async {
          await _adapter.saveGeneral(
            themeMode: themeMode,
            modelBaseUrl: modelBaseUrl,
            modelName: modelName,
            showCompletedTodos: showCompletedTodos,
            calendarMonthDetailed: calendarMonthDetailed,
            allowImageEgress: allowImageEgress,
          );
          if (apiKey != null) {
            await _adapter.saveModelKey(apiKey);
          }
          return _adapter.load();
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
          await _adapter.saveModelKey(apiKey);
          return _adapter.load();
        },
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
    ThemeMode? themeMode,
    String? modelBaseUrl,
    String? modelName,
    bool? showCompletedTodos,
    bool? calendarMonthDetailed,
    bool? allowImageEgress,
  });

  Future<String?> readModelKey();

  Future<void> saveModelKey(String apiKey);
}

final class SettingsServiceDevicePreferencesAdapter
    implements DevicePreferencesAdapter {
  SettingsServiceDevicePreferencesAdapter(this._settingsService);

  final SettingsService _settingsService;

  @override
  Future<AppSettings> load() => _settingsService.load();

  @override
  Future<void> saveGeneral({
    ThemeMode? themeMode,
    String? modelBaseUrl,
    String? modelName,
    bool? showCompletedTodos,
    bool? calendarMonthDetailed,
    bool? allowImageEgress,
  }) {
    return _settingsService.saveGeneral(
      themeMode: themeMode,
      modelBaseUrl: modelBaseUrl,
      modelName: modelName,
      showCompletedTodos: showCompletedTodos,
      calendarMonthDetailed: calendarMonthDetailed,
      allowImageEgress: allowImageEgress,
    );
  }

  @override
  Future<String?> readModelKey() => _settingsService.readModelKey();

  @override
  Future<void> saveModelKey(String apiKey) {
    return _settingsService.saveModelKey(apiKey);
  }
}
