abstract interface class VaultStore {
  Future<void> initialize();

  Future<String?> read(String relativePath);

  Future<void> write(String relativePath, String contents);

  Future<void> delete(String relativePath);

  Future<List<String>> listMarkdownFiles();

  Future<String> describeRoot();
}
