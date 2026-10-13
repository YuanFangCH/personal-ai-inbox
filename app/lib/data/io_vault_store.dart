import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'vault_store.dart';

class IoVaultStore implements VaultStore {
  static final Map<String, Future<void>> _processWriteTails = {};

  IoVaultStore._(this._root);

  /// Creates a vault adapter rooted at an explicitly supplied directory.
  ///
  /// This also lets recovery tests use an isolated temporary directory.
  factory IoVaultStore.at(Directory root) => IoVaultStore._(root);

  final Directory _root;

  static Future<IoVaultStore> create() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'vault'));
    await root.create(recursive: true);
    return IoVaultStore._(root);
  }

  @override
  Future<void> initialize() => _root.create(recursive: true);

  @override
  Future<T> exclusive<T>(Future<T> Function() operation) {
    final rootKey = p.normalize(p.absolute(_root.path));
    final previous = _processWriteTails[rootKey] ?? Future<void>.value();
    final finished = Completer<void>();
    _processWriteTails[rootKey] = finished.future;
    return () async {
      await previous;
      try {
        final lockDirectory = Directory(
          p.join(_root.path, '.local-transactions'),
        );
        await lockDirectory.create(recursive: true);
        final lockFile = File(p.join(lockDirectory.path, 'write.lock'));
        final handle = await lockFile.open(mode: FileMode.append);
        var locked = false;
        try {
          await handle.lock(FileLock.exclusive);
          locked = true;
          return await operation();
        } finally {
          if (locked) {
            await handle.unlock();
          }
          await handle.close();
        }
      } finally {
        if (identical(_processWriteTails[rootKey], finished.future)) {
          _processWriteTails.remove(rootKey);
        }
        finished.complete();
      }
    }();
  }

  @override
  Future<String?> read(String relativePath) async {
    final file = _resolve(relativePath);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  @override
  Future<void> write(String relativePath, String contents) async {
    final file = _resolve(relativePath);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
  }

  @override
  Future<void> delete(String relativePath) async {
    final file = _resolve(relativePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<List<String>> listMarkdownFiles() async {
    if (!await _root.exists()) {
      return const [];
    }
    final files = <String>[];
    await for (final entity in _root.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && entity.path.endsWith('.md')) {
        files.add(
          p.relative(entity.path, from: _root.path).replaceAll('\\', '/'),
        );
      }
    }
    files.sort();
    return files;
  }

  @override
  Future<String> describeRoot() async => _root.path;

  File _resolve(String relativePath) {
    if (p.isAbsolute(relativePath)) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'Must be relative',
      );
    }
    final normalized = p.normalize(relativePath).replaceAll('\\', '/');
    if (normalized == '..' || normalized.startsWith('../')) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'Must stay in vault',
      );
    }
    return File(p.join(_root.path, normalized));
  }
}
