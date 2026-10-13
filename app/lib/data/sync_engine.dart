import '../core/markdown_codec.dart';
import '../core/models.dart';
import 'result_repository.dart';
import 'sync_provider.dart';

class SyncEngine {
  SyncEngine({
    required ResultRepository repository,
    required SyncProvider provider,
    required this.deviceId,
    MarkdownCodec codec = const MarkdownCodec(),
  }) : _repository = repository,
       _provider = provider,
       _codec = codec;

  final ResultRepository _repository;
  final SyncProvider _provider;
  final MarkdownCodec _codec;
  final String deviceId;

  SyncProvider get provider => _provider;

  Future<SyncReport> sync() async {
    try {
      await _provider.connect();
      final objects = await _provider.listObjects();
      final remote = <String, SyncRemoteObject>{};
      final invalidIds = <String>{};
      final failures = <SyncFailure>[];
      for (final object in objects) {
        try {
          _validateRemote(object);
          if (remote.containsKey(object.id)) {
            remote.remove(object.id);
            invalidIds.add(object.id);
            throw FormatException('远端存在重复成果 ID：${object.id}');
          }
          if (!invalidIds.contains(object.id)) remote[object.id] = object;
        } catch (error) {
          invalidIds.add(object.id);
          remote.remove(object.id);
          failures.add(_failure('validate-remote', object.id, error));
        }
      }

      var uploaded = 0;
      var downloaded = 0;
      var conflicts = 0;
      var unchanged = 0;
      final local = await _repository.listIndex();
      final localIds = local.map((entry) => entry.id).toSet();
      for (final indexed in local) {
        if (indexed.status != ResultStatus.canonical) continue;
        if (invalidIds.contains(indexed.id)) continue;
        final remoteObject = remote.remove(indexed.id);
        try {
          final source = await _repository.readManagedResult(indexed.id);
          if (source == null) throw StateError('本地成果文件缺失：${indexed.id}');
          final document = _codec.decode(source);
          _validateLocal(document, indexed);
          final actualHash = _repository.hashMarkdown(source);
          final current = indexed.copyWith(
            localHash: actualHash,
            syncState: actualHash == indexed.lastSyncedHash
                ? SyncState.synced
                : SyncState.pendingUpload,
          );
          if (actualHash != indexed.localHash) {
            await _repository.updateIndex(current);
          }

          if (remoteObject == null) {
            final stored = await _putWithRejudge(
              id: indexed.id,
              path: document.markdownPath,
              contents: source,
              baselineHash: current.lastSyncedHash,
              observedRemote: null,
            );
            await _repository.acknowledgeSynced(
              id: indexed.id,
              expectedLocalHash: actualHash,
              remoteEtag: stored.etag,
            );
            uploaded++;
            continue;
          }

          final localChanged = current.lastSyncedHash == null
              ? actualHash != remoteObject.hash
              : actualHash != current.lastSyncedHash;
          final remoteChanged = current.lastSyncedHash == null
              ? actualHash != remoteObject.hash
              : remoteObject.hash != current.lastSyncedHash;

          if (actualHash == remoteObject.hash) {
            await _repository.acknowledgeSynced(
              id: indexed.id,
              expectedLocalHash: actualHash,
              remoteEtag: remoteObject.etag,
            );
            unchanged++;
          } else if (!remoteChanged && localChanged) {
            final stored = await _putWithRejudge(
              id: indexed.id,
              path: document.markdownPath,
              contents: source,
              baselineHash: current.lastSyncedHash,
              observedRemote: remoteObject,
            );
            await _repository.acknowledgeSynced(
              id: indexed.id,
              expectedLocalHash: actualHash,
              remoteEtag: stored.etag,
            );
            uploaded++;
          } else if (remoteChanged && !localChanged) {
            await _repository.importRemote(
              remote: remoteObject,
              expectedLocalHash: actualHash,
            );
            downloaded++;
          } else {
            await _repository.writeConflictCopy(
              indexed.id,
              remoteObject.content,
              remoteEtag: remoteObject.etag,
              localHash: actualHash,
            );
            final conflicted = await _repository.findIndexed(indexed.id);
            if (conflicted != null) {
              await _repository.updateIndex(
                conflicted.copyWith(syncState: SyncState.conflict),
              );
            }
            conflicts++;
          }
        } on _SyncRaceDetected catch (race) {
          try {
            await _repository.writeConflictCopy(
              indexed.id,
              race.remote.content,
              remoteEtag: race.remote.etag,
              localHash: race.localHash,
            );
            final conflicted = await _repository.findIndexed(indexed.id);
            if (conflicted != null) {
              await _repository.updateIndex(
                conflicted.copyWith(syncState: SyncState.conflict),
              );
            }
            conflicts++;
          } catch (error) {
            failures.add(_failure('sync-local', indexed.id, error));
          }
        } catch (error) {
          failures.add(_failure('sync-local', indexed.id, error));
        }
      }

      for (final object in remote.values) {
        if (invalidIds.contains(object.id) || localIds.contains(object.id)) {
          continue;
        }
        try {
          _validateRemote(object);
          await _repository.importRemote(
            remote: object,
            expectedLocalHash: null,
          );
          downloaded++;
        } catch (error) {
          failures.add(_failure('download-remote', object.id, error));
        }
      }
      return SyncReport(
        uploaded: uploaded,
        downloaded: downloaded,
        conflicts: conflicts,
        unchanged: unchanged,
        failed: failures.length,
        finishedAt: DateTime.now(),
        failures: List.unmodifiable(failures),
      );
    } catch (error) {
      final failure = _failure('connect', null, error);
      return SyncReport(
        uploaded: 0,
        downloaded: 0,
        conflicts: 0,
        unchanged: 0,
        failed: 1,
        finishedAt: DateTime.now(),
        message: error.toString(),
        failures: [failure],
      );
    }
  }

  Future<void> resolveConflict(
    String resultId, {
    required bool useRemote,
  }) async {
    await _provider.connect();
    final conflict = await _repository.findConflict(resultId);
    if (conflict == null) throw StateError('冲突记录不存在或已处理：$resultId');
    final currentObjects = await _provider.listObjects();
    final matching = currentObjects
        .where((object) => object.id == resultId)
        .toList();
    if (matching.length != 1) throw StateError('远端成果身份已变化，请重新同步：$resultId');
    final remote = matching.single;
    _validateRemote(remote);
    if (remote.hash != conflict.remoteHash ||
        remote.etag != conflict.remoteEtag) {
      throw StateError('远端版本在裁决期间已变化，请重新同步：$resultId');
    }
    if (useRemote) {
      final source = await _repository.readManagedResult(resultId);
      final localHash = source == null
          ? null
          : _repository.hashMarkdown(source);
      if (localHash != conflict.localHash) {
        throw StateError('本地成果在裁决期间已变化，请重新同步：$resultId');
      }
      await _repository.importRemote(
        remote: remote,
        expectedLocalHash: localHash,
      );
    } else {
      final source = await _repository.readManagedResult(resultId);
      if (source == null ||
          _repository.hashMarkdown(source) != conflict.localHash) {
        throw StateError('本地成果在裁决期间已变化，请重新同步：$resultId');
      }
      final indexed = await _repository.findIndexed(resultId);
      if (indexed == null) throw StateError('本地成果已不存在：$resultId');
      final stored = await _provider.putObject(
        id: resultId,
        path: indexed.mdPath,
        contents: source,
        condition: SyncWriteCondition.matchEtag(conflict.remoteEtag),
      );
      await _repository.acknowledgeSynced(
        id: resultId,
        expectedLocalHash: conflict.localHash,
        remoteEtag: stored.etag,
      );
    }
    await _repository.removeConflict(resultId, conflict.copyPath);
  }

  Future<SyncRemoteObject> _putWithRejudge({
    required String id,
    required String path,
    required String contents,
    required String? baselineHash,
    required SyncRemoteObject? observedRemote,
  }) async {
    var remote = observedRemote;
    var rejudges = 0;
    while (true) {
      try {
        return await _provider.putObject(
          id: id,
          path: path,
          contents: contents,
          condition: remote == null
              ? const SyncWriteCondition.createOnly()
              : SyncWriteCondition.matchEtag(remote.etag),
        );
      } on SyncPreconditionFailed {
        if (rejudges >= 2) rethrow;
        rejudges++;
        final refreshed = (await _provider.listObjects())
            .where((object) => object.id == id)
            .toList(growable: false);
        if (refreshed.length > 1) {
          throw StateError('远端成果 ID 重复，无法重判：$id');
        }
        remote = refreshed.isEmpty ? null : refreshed.single;
        if (remote == null) continue;
        _validateRemote(remote);
        final localHash = _repository.hashMarkdown(contents);
        if (remote.hash == localHash) return remote;
        if (remote.hash != baselineHash) {
          throw _SyncRaceDetected(remote, localHash);
        }
      }
    }
  }

  void _validateRemote(SyncRemoteObject remote) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(remote.id)) {
      throw FormatException('远端成果 ID 不合法：${remote.id}');
    }
    final document = _codec.decode(remote.content);
    if (document.id != remote.id ||
        document.markdownPath != remote.path ||
        document.status != ResultStatus.canonical ||
        remote.path != 'vault/${document.type.directory}/${remote.id}.md') {
      throw FormatException('远端成果身份、类型、状态或路径不匹配：${remote.id}');
    }
    if (_repository.hashMarkdown(remote.content) != remote.hash) {
      throw FormatException('远端成果内容 hash 不匹配：${remote.id}');
    }
  }

  void _validateLocal(ResultDocument document, IndexedResult indexed) {
    if (document.id != indexed.id ||
        document.markdownPath != indexed.mdPath ||
        document.status != ResultStatus.canonical ||
        indexed.mdPath !=
            'vault/${document.type.directory}/${document.id}.md') {
      throw StateError('本地成果身份、类型、状态或路径不匹配：${indexed.id}');
    }
  }

  SyncFailure _failure(String stage, String? id, Object error) => SyncFailure(
    stage: stage,
    code: error is SyncPreconditionFailed
        ? 'sync_precondition_failed'
        : 'sync_object_failed',
    message: error.toString(),
    objectId: id,
    retryable: true,
    occurredAt: DateTime.now(),
  );
}

class _SyncRaceDetected implements Exception {
  const _SyncRaceDetected(this.remote, this.localHash);

  final SyncRemoteObject remote;
  final String localHash;
}
