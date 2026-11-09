abstract interface class WidgetStoreBackend {
  Future<String?> read();

  Future<void> write(String contents);
}
