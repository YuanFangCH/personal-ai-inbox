import 'dart:async';

import 'vault_store.dart';

class MemoryVaultStore implements VaultStore {
  final Map<String, String> _files = {};
  Future<void> _exclusiveTail = Future<void>.value();

  Map<String, String> get files => Map.unmodifiable(_files);

  @override
  Future<void> initialize() async {}

  @override
  Future<T> exclusive<T>(Future<T> Function() operation) {
    final previous = _exclusiveTail;
    final finished = Completer<void>();
    _exclusiveTail = finished.future;
    return () async {
      await previous;
      try {
        return await operation();
      } finally {
        finished.complete();
      }
    }();
  }

  @override
  Future<String?> read(String relativePath) async => _files[relativePath];

  @override
  Future<void> write(String relativePath, String contents) async {
    _files[relativePath] = contents;
  }

  @override
  Future<void> delete(String relativePath) async {
    _files.remove(relativePath);
  }

  @override
  Future<List<String>> listMarkdownFiles() async {
    final files =
        _files.keys
            .where((path) => path.endsWith('.md'))
            .toList(growable: false)
          ..sort();
    return files;
  }

  @override
  Future<String> describeRoot() async => '内存存储';
}
