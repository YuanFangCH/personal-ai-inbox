import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/settings_service.dart';

void main() {
  test('persists home table order and calendar filters per device', () async {
    final preferences = _MemoryPreferencesStore({'device_id': 'device_views'});
    final service = SettingsService(
      preferenceStore: preferences,
      keyStore: _MemorySecureKeyStore(),
    );
    final current = await service.load();
    await service.saveConfiguration(
      current.copyWith(
        homeTableOrder: const ['tb_exam', 'tb_homework'],
        calendarVisibleTableIds: const ['tb_exam'],
      ),
    );
    final reopened = await service.load();
    expect(reopened.homeTableOrder, ['tb_exam', 'tb_homework']);
    expect(reopened.calendarVisibleTableIds, ['tb_exam']);
    final portable = await service.exportPortableSettings();
    expect(portable.containsKey('home_table_order'), isFalse);
    expect(portable.containsKey('calendar_visible_table_ids'), isFalse);
  });

  test(
    'migrates old preferences and preserves invalid existing values',
    () async {
      final preferences = _MemoryPreferencesStore({
        'device_id': 'device_legacy',
        'model_base_url': 'not a valid URL',
        'model_name': 'legacy-model',
        'allow_image_egress': false,
      });
      final keys = _MemorySecureKeyStore()
        ..values['model_api_key'] = 'legacy-key';
      final service = SettingsService(
        preferenceStore: preferences,
        keyStore: keys,
      );

      final settings = await service.load();
      final persisted = preferences.strings['settings_snapshot'];

      expect(settings.deviceId, 'device_legacy');
      expect(settings.modelBaseUrl, 'not a valid URL');
      expect(settings.allowImageEgress, isFalse);
      expect(settings.hasModelKey, isTrue);
      expect(settings.defaultAiPermissions, const AiPermissions());
      expect(settings.effectiveDefaultAiPolicy.preset, AiPolicyPreset.standard);
      expect(settings.calendarVisibleTableIds, ['*']);
      expect(settings.validate(), isNotEmpty);
      expect(
        jsonDecode(persisted!)['schema_version'],
        AppSettings.currentSchemaVersion,
      );
      expect(jsonDecode(persisted), contains('default_ai_policy'));
      expect(persisted, isNot(contains('legacy-key')));
    },
  );

  test(
    'rotates API keys through secure slots and exports no identity or key',
    () async {
      final preferences = _MemoryPreferencesStore({
        'device_id': 'device_local',
      });
      final keys = _MemorySecureKeyStore();
      final service = SettingsService(
        preferenceStore: preferences,
        keyStore: keys,
      );
      final initial = await service.load();
      final first = await service.saveConfiguration(
        initial,
        apiKey: ' first-secret ',
        replaceApiKey: true,
      );
      final firstSlot = first.modelKeySlotId!;
      expect(await service.readModelKey(), 'first-secret');

      final second = await service.saveConfiguration(
        first.copyWith(modelName: 'rotated-model'),
        apiKey: 'second-secret',
        replaceApiKey: true,
      );
      expect(second.deviceId, 'device_local');
      expect(await service.readModelKey(), 'second-secret');
      expect(keys.values.containsKey('model_api_key.slot.$firstSlot'), isFalse);

      final portable = await service.exportPortableSettings();
      expect(portable.containsKey('device_id'), isFalse);
      expect(portable.containsKey('model_key_slot_id'), isFalse);
      expect(jsonEncode(portable), isNot(contains('second-secret')));

      final cleared = await service.saveConfiguration(
        second,
        apiKey: '',
        replaceApiKey: true,
      );
      expect(cleared.hasModelKey, isFalse);
      expect(await service.readModelKey(), isNull);
    },
  );

  test(
    'rejects invalid configuration before writing any snapshot changes',
    () async {
      final prefs = _MemoryPreferencesStore({'device_id': 'device_safe'});
      final service = SettingsService(
        preferenceStore: prefs,
        keyStore: _MemorySecureKeyStore(),
      );
      final current = await service.load();
      final before = prefs.strings['settings_snapshot'];

      await expectLater(
        service.saveConfiguration(
          current.copyWith(
            modelBaseUrl: 'https://user:password@example.com?token=secret',
          ),
        ),
        throwsArgumentError,
      );

      expect(prefs.strings['settings_snapshot'], before);
    },
  );

  test('portable import applies validated preferences and keeps local identity/key', () async {
    final preferences = _MemoryPreferencesStore({'device_id': 'device-local'});
    final service = SettingsService(
      preferenceStore: preferences,
      keyStore: _MemorySecureKeyStore(),
    );
    final initial = await service.load();
    const permissions = AiPermissions(
      read: false,
      create: true,
      modifyDelete: false,
    );
    final defaultPolicy = AiPolicy.custom(
      decisions: AiPolicy.forPreset(AiPolicyPreset.standard).decisions,
      version: 3,
      tableScope: AiResourceScope.selected(const ['tb_school']),
      knowledgeReadScope: const AiResourceScope.none(),
    ).withDecision(AiPermissionAction.contentCreate, AiPolicyDecision.allow);
    final withPermissions = await service.saveConfiguration(
      initial.copyWith(
        defaultAiPermissions: permissions,
        defaultAiPolicy: defaultPolicy,
        capabilityOverrides: const ModelCapabilityOverrides(thinking: false),
      ),
    );
    final keyed = await service.saveConfiguration(
      withPermissions,
      apiKey: 'local-secret',
      replaceApiKey: true,
    );
    final portable = await service.exportPortableSettings();
    expect(portable['default_ai_policy'], isA<Map>());
    portable['model_name'] = 'portable-model';

    final snapshotBeforeImport = preferences.strings['settings_snapshot'];
    await expectLater(
      service.importPortableSettings({
        ...portable,
        'device_id': 'foreign-device',
      }),
      throwsFormatException,
    );
    expect(preferences.strings['settings_snapshot'], snapshotBeforeImport);

    final imported = await service.importPortableSettings(portable);

    expect(imported.modelName, 'portable-model');
    expect(imported.effectiveDefaultAiPolicy.preset, AiPolicyPreset.custom);
    expect(
      imported.effectiveDefaultAiPolicy.decisionFor(
        AiPermissionAction.contentCreate,
      ),
      AiPolicyDecision.allow,
    );
    expect(
      imported.effectiveDefaultAiPolicy.tableScope.covers('tb_school'),
      isTrue,
    );
    expect(imported.capabilityOverrides.thinking, isFalse);
    expect(imported.deviceId, 'device-local');
    expect(imported.modelKeySlotId, keyed.modelKeySlotId);
    expect(await service.readModelKey(), 'local-secret');
  });

  test('legacy portable settings enable all AI permission defaults', () async {
    final service = SettingsService(
      preferenceStore: _MemoryPreferencesStore({'device_id': 'device-import'}),
      keyStore: _MemorySecureKeyStore(),
    );
    await service.load();
    final legacy = await service.exportPortableSettings();
    legacy.remove('default_ai_permissions');

    final imported = await service.importPortableSettings(legacy);

    expect(imported.defaultAiPermissions, const AiPermissions());
    expect(imported.effectiveDefaultAiPolicy.preset, AiPolicyPreset.standard);
  });

  test('reset defaults preserves device ID and secure key reference', () async {
    final service = SettingsService(
      preferenceStore: _MemoryPreferencesStore({'device_id': 'device-local'}),
      keyStore: _MemorySecureKeyStore(),
    );
    final initial = await service.load();
    final configured = await service.saveConfiguration(
      initial.copyWith(
        modelName: 'custom-model',
        allowImageEgress: false,
        defaultAiPermissions: const AiPermissions(
          read: false,
          create: false,
          modifyDelete: false,
        ),
      ),
      apiKey: 'local-secret',
      replaceApiKey: true,
    );

    final restored = await service.restoreDefaults();

    expect(restored.deviceId, 'device-local');
    expect(restored.modelKeySlotId, configured.modelKeySlotId);
    expect(restored.hasModelKey, isTrue);
    expect(restored.modelName, 'deepseek-flash');
    expect(restored.allowImageEgress, isTrue);
    expect(restored.defaultAiPermissions, const AiPermissions());
    expect(restored.effectiveDefaultAiPolicy.preset, AiPolicyPreset.standard);
  });

  test('migrates v4 restricted permissions without adding access', () async {
    final preferences = _MemoryPreferencesStore({
      'device_id': 'device-v4',
      'settings_snapshot': jsonEncode({
        'schema_version': 4,
        'device_id': 'device-v4',
        'theme_mode': 'system',
        'model_base_url': 'https://api.deepseek.com',
        'model_name': 'deepseek-flash',
        'model_key_slot_id': null,
        'show_completed_todos': false,
        'calendar_month_detailed': true,
        'allow_image_egress': true,
        'default_ai_permissions': {
          'read': false,
          'create': true,
          'modify_delete': false,
        },
        'capability_overrides': {
          'vision': null,
          'tool_calls': null,
          'json_output': null,
          'thinking': null,
        },
        'response_header_timeout_seconds': 45,
        'stream_idle_timeout_seconds': 60,
        'total_timeout_seconds': 300,
        'context_message_limit': 20,
        'image_message_limit': 4,
        'image_limit': 8,
        'home_table_order': <String>[],
        'calendar_visible_table_ids': ['*'],
      }),
    });
    final service = SettingsService(
      preferenceStore: preferences,
      keyStore: _MemorySecureKeyStore(),
    );

    final settings = await service.load();
    final policy = settings.effectiveDefaultAiPolicy;

    expect(settings.schemaVersion, 5);
    expect(policy.preset, AiPolicyPreset.custom);
    expect(
      policy.decisionFor(AiPermissionAction.tableRead),
      AiPolicyDecision.deny,
    );
    expect(
      policy.decisionFor(AiPermissionAction.contentCreate),
      AiPolicyDecision.allow,
    );
    expect(
      policy.decisionFor(AiPermissionAction.tableDelete),
      AiPolicyDecision.deny,
    );
    final persisted = jsonDecode(
      preferences.strings['settings_snapshot']!,
    ) as Map<String, dynamic>;
    expect(persisted['schema_version'], 5);
    expect(persisted['default_ai_policy'], isA<Map>());
  });

  test('accepts loopback HTTP and enforces timeout and context ranges', () {
    final base = AppSettings(
      deviceId: 'device-validate',
      themeMode: ThemePreference.system,
      modelBaseUrl: 'http://127.0.0.1:8080/v1',
      modelName: 'local-model',
      hasModelKey: false,
      showCompletedTodos: false,
      calendarMonthDetailed: true,
    );
    expect(base.validate(), isEmpty);
    expect(
      base.copyWith(modelBaseUrl: 'http://remote.example/v1').validate(),
      isNotEmpty,
    );
    expect(
      base.copyWith(totalTimeoutSeconds: 20).validate(),
      contains('请求总时限不能小于响应头或流空闲期限'),
    );
    expect(
      base.copyWith(contextMessageLimit: 21).validate(),
      contains('上下文消息数必须在 2–20 条之间'),
    );
  });

  test('settings policy and legacy permission updates stay consistent', () {
    final base = AppSettings(
      deviceId: 'device-policy',
      themeMode: ThemePreference.system,
      modelBaseUrl: 'https://api.deepseek.com',
      modelName: 'deepseek-flash',
      hasModelKey: false,
      showCompletedTodos: false,
      calendarMonthDetailed: true,
    );
    final withPolicy = base.copyWith(
      defaultAiPolicy: AiPolicy.forPreset(AiPolicyPreset.readOnly),
    );

    expect(withPolicy.effectiveDefaultAiPolicy.preset, AiPolicyPreset.readOnly);
    expect(
      withPolicy.defaultAiPermissions,
      const AiPermissions(read: true, create: false, modifyDelete: false),
    );

    final legacyUpdate = withPolicy.copyWith(
      defaultAiPermissions: const AiPermissions(
        read: false,
        create: true,
        modifyDelete: false,
      ),
    );
    expect(legacyUpdate.defaultAiPolicy, isNull);
    expect(
      legacyUpdate.effectiveDefaultAiPolicy.decisionFor(
        AiPermissionAction.tableRead,
      ),
      AiPolicyDecision.deny,
    );
  });

  test(
    'invalid portable import leaves the persisted snapshot unchanged',
    () async {
      final preferences = _MemoryPreferencesStore({
        'device_id': 'device-import',
      });
      final service = SettingsService(
        preferenceStore: preferences,
        keyStore: _MemorySecureKeyStore(),
      );
      await service.load();
      final before = preferences.strings['settings_snapshot'];
      final portable = await service.exportPortableSettings();
      portable['model_base_url'] = 'http://remote.example/v1';

      await expectLater(
        service.importPortableSettings(portable),
        throwsArgumentError,
      );

      expect(preferences.strings['settings_snapshot'], before);
    },
  );

  test('snapshot switch failure removes the staged API key slot', () async {
    final preferences = _MemoryPreferencesStore({'device_id': 'device-atomic'});
    final keys = _MemorySecureKeyStore();
    final service = SettingsService(
      preferenceStore: preferences,
      keyStore: keys,
    );
    final current = await service.load();
    final previousSnapshot = preferences.strings['settings_snapshot'];
    preferences.failSnapshotWrites = true;

    await expectLater(
      service.saveConfiguration(
        current,
        apiKey: 'staged-secret',
        replaceApiKey: true,
      ),
      throwsStateError,
    );

    expect(preferences.strings['settings_snapshot'], previousSnapshot);
    expect(
      keys.values.keys.where((key) => key.startsWith('model_api_key.slot.')),
      isEmpty,
    );
  });
}

class _MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

class _MemoryPreferencesStore implements PreferencesStore {
  _MemoryPreferencesStore([Map<String, Object> initial = const {}]) {
    for (final entry in initial.entries) {
      if (entry.value is String) strings[entry.key] = entry.value as String;
      if (entry.value is bool) booleans[entry.key] = entry.value as bool;
    }
  }

  final Map<String, String> strings = {};
  final Map<String, bool> booleans = {};
  bool failSnapshotWrites = false;

  @override
  Future<String?> getString(String key) async => strings[key];

  @override
  Future<bool?> getBool(String key) async => booleans[key];

  @override
  Future<void> setString(String key, String value) async {
    if (failSnapshotWrites && key == 'settings_snapshot') {
      throw StateError('snapshot write failed');
    }
    strings[key] = value;
  }

  @override
  Future<void> setBool(String key, bool value) async {
    booleans[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    strings.remove(key);
    booleans.remove(key);
  }
}
