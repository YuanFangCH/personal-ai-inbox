import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'vault_store.dart';

class IoVaultStore implements VaultStore {
  IoVaultStore._(this._root);

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
