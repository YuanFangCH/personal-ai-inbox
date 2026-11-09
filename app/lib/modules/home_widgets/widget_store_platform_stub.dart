import 'widget_store_backend.dart';

final Map<String, String> _webStoreContents = {};

WidgetStoreBackend createWidgetStoreBackend(String directory) =>
    _MemoryWidgetStoreBackend(directory);

class _MemoryWidgetStoreBackend implements WidgetStoreBackend {
  const _MemoryWidgetStoreBackend(this.directory);

  final String directory;

  @override
  Future<String?> read() async => _webStoreContents[directory];

  @override
  Future<void> write(String contents) async {
    _webStoreContents[directory] = contents;
  }
}
