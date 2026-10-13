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
