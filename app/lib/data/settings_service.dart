import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/models.dart';

export '../core/models.dart' show AppSettings;

abstract interface class PreferencesStore {
  Future<String?> getString(String key);

  Future<bool?> getBool(String key);

  Future<void> setString(String key, String value);

  Future<void> setBool(String key, bool value);

  Future<void> remove(String key);
}

final class SharedPreferencesStore implements PreferencesStore {
  SharedPreferencesStore([SharedPreferencesAsync? preferences])
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> getString(String key) => _preferences.getString(key);

  @override
  Future<bool?> getBool(String key) => _preferences.getBool(key);

  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(key, value);

  @override
  Future<void> setBool(String key, bool value) =>
      _preferences.setBool(key, value);

  @override
  Future<void> remove(String key) => _preferences.remove(key);
}

abstract interface class SecureKeyStore {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

final class FlutterSecureKeyStore implements SecureKeyStore {
  FlutterSecureKeyStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

class SettingsService {
  SettingsService({
    SharedPreferencesAsync? preferences,
    PreferencesStore? preferenceStore,
    FlutterSecureStorage? secureStorage,
    SecureKeyStore? keyStore,
  }) : _preferences = preferences,
       _preferenceStore = preferenceStore,
       _secureStore =
           keyStore ??
           FlutterSecureKeyStore(secureStorage ?? const FlutterSecureStorage());

  static const _snapshotKey = 'settings_snapshot';
  static const _deviceIdKey = 'device_id';
  static const _themeKey = 'theme_mode';
  static const _modelUrlKey = 'model_base_url';
  static const _modelNameKey = 'model_name';
  static const _showCompletedKey = 'show_completed_todos';
  static const _calendarMonthDetailedKey = 'calendar_month_detailed';
  static const _allowImageEgressKey = 'allow_image_egress';
  static const _legacyModelApiKey = 'model_api_key';
  static const _modelKeySlotPrefix = 'model_api_key.slot.';

  final SharedPreferencesAsync? _preferences;
  PreferencesStore? _preferenceStore;
  final SecureKeyStore _secureStore;

  PreferencesStore get _prefs =>
      _preferenceStore ??= SharedPreferencesStore(_preferences);

  Future<AppSettings> load() async {
    var deviceId = await _prefs.getString(_deviceIdKey);
    if (deviceId == null || deviceId.trim().isEmpty) {
      deviceId =
          'device_${const Uuid().v4().replaceAll('-', '').substring(0, 12)}';
      await _prefs.setString(_deviceIdKey, deviceId);
    }

    final snapshotJson = await _prefs.getString(_snapshotKey);
    if (snapshotJson == null) {
      final migrated = await _loadLegacySettings(deviceId);
      await _writeSnapshot(migrated);
      return migrated;
    }

    final decoded = jsonDecode(snapshotJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('端配置快照格式错误；原始配置已保留。');
    }
    final version = decoded['schema_version'];
    if (version is! int || version > AppSettings.currentSchemaVersion) {
      throw const FormatException('端配置版本高于当前应用支持范围；原始配置已保留。');
    }
    final parsed = _settingsFromMap(decoded, deviceId);
    final settings = parsed.copyWith(
      hasModelKey: await _hasKeyForSlot(parsed.modelKeySlotId),
    );
    if (version < AppSettings.currentSchemaVersion) {
      final migrated = settings.copyWith(
        schemaVersion: AppSettings.currentSchemaVersion,
      );
      await _writeSnapshot(migrated);
      return migrated;
    }
    return settings;
  }

  Future<AppSettings> _loadLegacySettings(String deviceId) async => AppSettings(
    deviceId: deviceId,
    themeMode: _parseTheme(await _prefs.getString(_themeKey)),
    modelBaseUrl:
        await _prefs.getString(_modelUrlKey) ?? 'https://api.deepseek.com',
    modelName: await _prefs.getString(_modelNameKey) ?? 'deepseek-flash',
    hasModelKey: await _hasKeyForSlot(null),
    showCompletedTodos: await _prefs.getBool(_showCompletedKey) ?? false,
    calendarMonthDetailed:
        await _prefs.getBool(_calendarMonthDetailedKey) ?? true,
    allowImageEgress: await _prefs.getBool(_allowImageEgressKey) ?? true,
  );

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
    final current = await load();
    final next = current.copyWith(
      themeMode: themeMode,
      modelBaseUrl: modelBaseUrl?.trim(),
      modelName: modelName?.trim(),
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
    await saveConfiguration(next);
  }

  Future<AppSettings> saveConfiguration(
    AppSettings configuration, {
    String? apiKey,
    bool replaceApiKey = false,
  }) async {
    final errors = configuration.validate();
    if (errors.isNotEmpty) throw ArgumentError(errors.join('；'));
    final old = await load();
    var next = configuration.copyWith(
      schemaVersion: AppSettings.currentSchemaVersion,
    );
    String? newlyWrittenSlot;
    if (replaceApiKey) {
      final normalizedKey = apiKey?.trim() ?? '';
      if (normalizedKey.isEmpty) {
        next = next.copyWith(modelKeySlotId: '');
      } else {
        newlyWrittenSlot = const Uuid().v4().replaceAll('-', '');
        await _secureStore.write(
          key: '$_modelKeySlotPrefix$newlyWrittenSlot',
          value: normalizedKey,
        );
        next = next.copyWith(modelKeySlotId: newlyWrittenSlot);
      }
    }

    try {
      await _writeSnapshot(next);
    } catch (_) {
      if (newlyWrittenSlot != null) {
        try {
          await _secureStore.delete(
            key: '$_modelKeySlotPrefix$newlyWrittenSlot',
          );
        } catch (_) {}
      }
      rethrow;
    }

    if (replaceApiKey) {
      await _deleteKeySlot(old.modelKeySlotId);
    }
    return next.copyWith(
      hasModelKey: replaceApiKey
          ? apiKey?.trim().isNotEmpty == true
          : old.hasModelKey,
    );
  }

  Future<Map<String, Object?>> exportPortableSettings() async {
    final settings = await load();
    return {
      'portable_schema_version': 1,
      'theme_mode': _themeName(settings.themeMode),
      'model_base_url': settings.modelBaseUrl,
      'model_name': settings.modelName,
      'show_completed_todos': settings.showCompletedTodos,
      'calendar_month_detailed': settings.calendarMonthDetailed,
      'allow_image_egress': settings.allowImageEgress,
      'default_ai_permissions': settings.defaultAiPermissions.toJson(),
      'capability_overrides': {
        'vision': settings.capabilityOverrides.vision,
        'tool_calls': settings.capabilityOverrides.toolCalls,
        'json_output': settings.capabilityOverrides.jsonOutput,
      },
      'response_header_timeout_seconds': settings.responseHeaderTimeoutSeconds,
      'stream_idle_timeout_seconds': settings.streamIdleTimeoutSeconds,
      'total_timeout_seconds': settings.totalTimeoutSeconds,
      'context_message_limit': settings.contextMessageLimit,
      'image_message_limit': settings.imageMessageLimit,
      'image_limit': settings.imageLimit,
    };
  }

  Future<AppSettings> importPortableSettings(
    Map<String, dynamic> values,
  ) async {
    const allowed = {
      'portable_schema_version',
      'theme_mode',
      'model_base_url',
      'model_name',
      'show_completed_todos',
      'calendar_month_detailed',
      'allow_image_egress',
      'default_ai_permissions',
      'capability_overrides',
      'response_header_timeout_seconds',
      'stream_idle_timeout_seconds',
      'total_timeout_seconds',
      'context_message_limit',
      'image_message_limit',
      'image_limit',
    };
    final unknown = values.keys.where((key) => !allowed.contains(key));
    if (unknown.isNotEmpty) {
      throw FormatException('设置文件包含不支持的字段：${unknown.join('、')}');
    }
    if (values['portable_schema_version'] != 1) {
      throw const FormatException('设置文件版本不受支持');
    }
    final current = await load();
    final capabilities = values['capability_overrides'];
    if (capabilities is! Map<String, dynamic>) {
      throw const FormatException('模型能力覆盖格式错误');
    }
    final defaultAiPermissions = _readPortableAiPermissions(values);
    final candidate = current.copyWith(
      themeMode: _parseTheme(_stringValue(values, 'theme_mode')),
      modelBaseUrl: _requiredString(values, 'model_base_url'),
      modelName: _requiredString(values, 'model_name'),
      showCompletedTodos: _requiredBool(values, 'show_completed_todos'),
      calendarMonthDetailed: _requiredBool(values, 'calendar_month_detailed'),
      allowImageEgress: _requiredBool(values, 'allow_image_egress'),
      defaultAiPermissions: defaultAiPermissions,
      capabilityOverrides: ModelCapabilityOverrides(
        vision: _nullableBool(capabilities, 'vision'),
        toolCalls: _nullableBool(capabilities, 'tool_calls'),
        jsonOutput: _nullableBool(capabilities, 'json_output'),
      ),
      responseHeaderTimeoutSeconds: _requiredInt(
        values,
        'response_header_timeout_seconds',
      ),
      streamIdleTimeoutSeconds: _requiredInt(
        values,
        'stream_idle_timeout_seconds',
      ),
      totalTimeoutSeconds: _requiredInt(values, 'total_timeout_seconds'),
      contextMessageLimit: _requiredInt(values, 'context_message_limit'),
      imageMessageLimit: _requiredInt(values, 'image_message_limit'),
      imageLimit: _requiredInt(values, 'image_limit'),
    );
    return saveConfiguration(candidate);
  }

  AiPermissions _readPortableAiPermissions(Map<String, dynamic> values) {
    final raw = values['default_ai_permissions'];
    if (raw == null) return const AiPermissions();
    if (raw is! Map) throw const FormatException('默认 AI 权限配置格式错误');
    return AiPermissions.fromJson(
      raw.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  Future<AppSettings> restoreDefaults() async {
    final current = await load();
    final defaults = AppSettings(
      deviceId: current.deviceId,
      themeMode: ThemePreference.system,
      modelBaseUrl: 'https://api.deepseek.com',
      modelName: 'deepseek-flash',
      hasModelKey: current.hasModelKey,
      modelKeySlotId: current.modelKeySlotId,
      showCompletedTodos: false,
      calendarMonthDetailed: true,
      allowImageEgress: true,
    );
    return saveConfiguration(defaults);
  }

  Future<String?> readModelKey() async {
    final settings = await load();
    return _readKeyForSlot(settings.modelKeySlotId);
  }

  Future<String?> _readKeyForSlot(String? slotId) async {
    if (slotId == '') return null;
    if (slotId == null) return _secureStore.read(key: _legacyModelApiKey);
    return _secureStore.read(key: '$_modelKeySlotPrefix$slotId');
  }

  Future<bool> _hasKeyForSlot(String? slotId) async {
    final value = await _readKeyForSlot(slotId);
    return value != null && value.trim().isNotEmpty;
  }

  Future<bool> hasModelKey() async {
    final value = await readModelKey();
    return value != null && value.trim().isNotEmpty;
  }

  Future<void> saveModelKey(String apiKey) async {
    final settings = await load();
    await saveConfiguration(settings, apiKey: apiKey, replaceApiKey: true);
  }

  Future<void> _deleteKeySlot(String? slotId) async {
    try {
      if (slotId == null) {
        await _secureStore.delete(key: _legacyModelApiKey);
      } else if (slotId.isNotEmpty) {
        await _secureStore.delete(key: '$_modelKeySlotPrefix$slotId');
      }
    } catch (_) {
      // The snapshot already points to the new slot; an orphan can be cleaned
      // up later without making the committed configuration ambiguous.
    }
  }

  Future<void> _writeSnapshot(AppSettings settings) async {
    await _prefs.setString(_snapshotKey, jsonEncode(_settingsToMap(settings)));
  }

  Map<String, Object?> _settingsToMap(AppSettings settings) => {
    'schema_version': AppSettings.currentSchemaVersion,
    'device_id': settings.deviceId,
    'theme_mode': _themeName(settings.themeMode),
    'model_base_url': settings.modelBaseUrl,
    'model_name': settings.modelName,
    'model_key_slot_id': settings.modelKeySlotId,
    'show_completed_todos': settings.showCompletedTodos,
    'calendar_month_detailed': settings.calendarMonthDetailed,
    'allow_image_egress': settings.allowImageEgress,
    'default_ai_permissions': settings.defaultAiPermissions.toJson(),
    'capability_overrides': {
      'vision': settings.capabilityOverrides.vision,
      'tool_calls': settings.capabilityOverrides.toolCalls,
      'json_output': settings.capabilityOverrides.jsonOutput,
    },
    'response_header_timeout_seconds': settings.responseHeaderTimeoutSeconds,
    'stream_idle_timeout_seconds': settings.streamIdleTimeoutSeconds,
    'total_timeout_seconds': settings.totalTimeoutSeconds,
    'context_message_limit': settings.contextMessageLimit,
    'image_message_limit': settings.imageMessageLimit,
    'image_limit': settings.imageLimit,
  };

  AppSettings _settingsFromMap(Map<String, dynamic> map, String deviceId) {
    final overrides = map['capability_overrides'];
    if (overrides != null && overrides is! Map<String, dynamic>) {
      throw const FormatException('模型能力覆盖配置格式错误；原始配置已保留。');
    }
    final modelKeySlotId = map['model_key_slot_id'];
    if (modelKeySlotId != null && modelKeySlotId is! String) {
      throw const FormatException('模型密钥槽引用格式错误；原始配置已保留。');
    }
    return AppSettings(
      deviceId: _stringValue(map, 'device_id') ?? deviceId,
      themeMode: _parseTheme(_stringValue(map, 'theme_mode')),
      modelBaseUrl:
          _stringValue(map, 'model_base_url') ?? 'https://api.deepseek.com',
      modelName: _stringValue(map, 'model_name') ?? 'deepseek-flash',
      hasModelKey: false,
      showCompletedTodos: _boolValue(map, 'show_completed_todos') ?? false,
      calendarMonthDetailed: _boolValue(map, 'calendar_month_detailed') ?? true,
      allowImageEgress: _boolValue(map, 'allow_image_egress') ?? true,
      defaultAiPermissions: _readAiPermissions(map),
      schemaVersion: map['schema_version'] as int,
      modelKeySlotId: modelKeySlotId as String?,
      capabilityOverrides: ModelCapabilityOverrides(
        vision: _nullableBool(overrides, 'vision'),
        toolCalls: _nullableBool(overrides, 'tool_calls'),
        jsonOutput: _nullableBool(overrides, 'json_output'),
      ),
      responseHeaderTimeoutSeconds:
          _intValue(map, 'response_header_timeout_seconds') ?? 45,
      streamIdleTimeoutSeconds:
          _intValue(map, 'stream_idle_timeout_seconds') ?? 60,
      totalTimeoutSeconds: _intValue(map, 'total_timeout_seconds') ?? 300,
      contextMessageLimit: _intValue(map, 'context_message_limit') ?? 20,
      imageMessageLimit: _intValue(map, 'image_message_limit') ?? 4,
      imageLimit: _intValue(map, 'image_limit') ?? 8,
    );
  }

  AiPermissions _readAiPermissions(Map<String, dynamic> map) {
    final value = map['default_ai_permissions'];
    if (value == null) return const AiPermissions();
    if (value is! Map) {
      throw const FormatException('默认 AI 权限配置格式错误；原始配置已保留。');
    }
    return AiPermissions.fromJson(
      value.map((key, item) => MapEntry(key.toString(), item)),
    );
  }

  String? _stringValue(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! String) throw FormatException('设置字段 $key 类型错误；原始配置已保留。');
    return value;
  }

  String _requiredString(Map<String, dynamic> map, String key) {
    final value = _stringValue(map, key);
    if (value == null) throw FormatException('设置字段 $key 缺失');
    return value;
  }

  bool? _boolValue(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! bool) throw FormatException('设置字段 $key 类型错误；原始配置已保留。');
    return value;
  }

  int? _intValue(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! int) throw FormatException('设置字段 $key 类型错误；原始配置已保留。');
    return value;
  }

  bool _requiredBool(Map<String, dynamic> map, String key) {
    final value = _boolValue(map, key);
    if (value == null) throw FormatException('设置字段 $key 缺失');
    return value;
  }

  int _requiredInt(Map<String, dynamic> map, String key) {
    final value = _intValue(map, key);
    if (value == null) throw FormatException('设置字段 $key 缺失');
    return value;
  }

  bool? _nullableBool(Map<String, dynamic>? map, String key) {
    if (map == null) return null;
    final value = map[key];
    if (value == null) return null;
    if (value is! bool) throw FormatException('模型能力字段 $key 类型错误；原始配置已保留。');
    return value;
  }

  Future<Map<String, Object?>> exportMigrationPreferences() async => {
    _deviceIdKey: await _prefs.getString(_deviceIdKey),
    _themeKey: await _prefs.getString(_themeKey),
    _modelUrlKey: await _prefs.getString(_modelUrlKey),
    _modelNameKey: await _prefs.getString(_modelNameKey),
    _showCompletedKey: await _prefs.getBool(_showCompletedKey),
    _calendarMonthDetailedKey: await _prefs.getBool(_calendarMonthDetailedKey),
    _allowImageEgressKey: await _prefs.getBool(_allowImageEgressKey),
    _snapshotKey: await _prefs.getString(_snapshotKey),
  };

  Future<void> restoreMigrationPreferences(Map<String, dynamic> values) async {
    const keys = [
      _deviceIdKey,
      _themeKey,
      _modelUrlKey,
      _modelNameKey,
      _showCompletedKey,
      _calendarMonthDetailedKey,
      _allowImageEgressKey,
      _snapshotKey,
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

  ThemePreference _parseTheme(String? value) => switch (value) {
    'light' => ThemePreference.light,
    'dark' => ThemePreference.dark,
    _ => ThemePreference.system,
  };

  String _themeName(ThemePreference value) => switch (value) {
    ThemePreference.light => 'light',
    ThemePreference.dark => 'dark',
    ThemePreference.system => 'system',
  };
}
