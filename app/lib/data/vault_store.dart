import 'dart:convert';

abstract interface class VaultStore {
  Future<void> initialize();

  /// Runs one vault operation under the platform's exclusive writer lock.
  Future<T> exclusive<T>(Future<T> Function() operation);

  Future<String?> read(String relativePath);

  Future<void> write(String relativePath, String contents);

  Future<void> delete(String relativePath);

  Future<List<String>> listMarkdownFiles();

  Future<String> describeRoot();
}

/// Native stores replace an existing file without a delete/rename gap.
abstract interface class AtomicVaultStore {
  Future<void> replaceAtomically(String relativePath, String contents);
  Future<List<int>?> readBytes(String relativePath);
}

extension AtomicVaultWrite on VaultStore {
  Future<void> writeAtomically(String path, String value) {
    final store = this;
    return store is AtomicVaultStore
        ? (store as AtomicVaultStore).replaceAtomically(path, value)
        : write(path, value);
  }

  Future<List<int>?> readRawBytes(String path) async {
    final store = this;
    if (store is AtomicVaultStore) {
      return (store as AtomicVaultStore).readBytes(path);
    }
    final text = await read(path);
    return text == null ? null : utf8.encode(text);
  }
}
