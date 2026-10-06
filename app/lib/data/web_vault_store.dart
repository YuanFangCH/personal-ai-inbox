import 'package:shared_preferences/shared_preferences.dart';

import 'vault_store.dart';

class WebVaultStore implements VaultStore {
  WebVaultStore(this._preferences);

  static const _prefix = 'personal_ai_inbox.vault.';

  final SharedPreferences _preferences;

  static Future<WebVaultStore> create() async {
    return WebVaultStore(await SharedPreferences.getInstance());
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> read(String relativePath) async {
    return _preferences.getString('$_prefix$relativePath');
  }

  @override
  Future<void> write(String relativePath, String contents) async {
    await _preferences.setString('$_prefix$relativePath', contents);
  }

  @override
  Future<void> delete(String relativePath) async {
    await _preferences.remove('$_prefix$relativePath');
  }

  @override
  Future<List<String>> listMarkdownFiles() async {
    final files =
        _preferences
            .getKeys()
            .where((key) => key.startsWith(_prefix))
            .map((key) => key.substring(_prefix.length))
            .where((path) => path.endsWith('.md'))
            .toList(growable: false)
          ..sort();
    return files;
  }

  @override
  Future<String> describeRoot() async => '浏览器本地存储';
}
