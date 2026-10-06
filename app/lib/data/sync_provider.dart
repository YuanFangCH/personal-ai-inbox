import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/models.dart';

abstract interface class SyncProvider {
  String get displayName;

  Future<void> connect();

  Future<List<SyncRemoteObject>> listObjects();

  Future<SyncRemoteObject> putObject({
    required String id,
    required String path,
    required String contents,
    String? etag,
  });

  Future<void> deleteObject(String id, String? etag);
}

class MemorySyncProvider implements SyncProvider {
  final Map<String, SyncRemoteObject> _objects = {};
  int _etag = 0;

  @override
  String get displayName => '本地同步演练';

  @override
  Future<void> connect() async {}

  @override
  Future<List<SyncRemoteObject>> listObjects() async {
    return _objects.values.toList(growable: false);
  }

  @override
  Future<SyncRemoteObject> putObject({
    required String id,
    required String path,
    required String contents,
    String? etag,
  }) async {
    final current = _objects[id];
    if (etag != null && current?.etag != etag) {
      throw StateError('Remote object changed');
    }
    final object = SyncRemoteObject(
      id: id,
      path: path,
      content: contents,
      hash: _hash(contents),
      etag: 'etag-${++_etag}',
    );
    _objects[id] = object;
    return object;
  }

  @override
  Future<void> deleteObject(String id, String? etag) async {
    final current = _objects[id];
    if (etag != null && current?.etag != etag) {
      throw StateError('Remote object changed');
    }
    _objects.remove(id);
  }

  String _hash(String value) {
    return 'sha256:${sha256.convert(utf8.encode(value))}';
  }
}
