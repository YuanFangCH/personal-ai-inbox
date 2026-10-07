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
      final remote = {
        for (final object in await _provider.listObjects()) object.id: object,
      };
      final local = {
        for (final object in await _repository.listIndex()) object.id: object,
      };

      var uploaded = 0;
      var downloaded = 0;
      var conflicts = 0;
      var unchanged = 0;
      final failures = <SyncFailure>[];

      for (final record in local.values) {
        if (record.status != ResultStatus.canonical) {
          continue;
        }
        final remoteObject = remote.remove(record.id);
        try {
          final action = _decide(record, remoteObject);
          switch (action) {
            case _SyncAction.upload:
              final source = await _repository.readRaw(record.mdPath);
              if (source == null) {
                continue;
              }
              final stored = await _provider.putObject(
                id: record.id,
                path: record.mdPath,
                contents: source,
                etag: remoteObject?.etag,
              );
              await _repository.updateIndex(
                record.copyWith(
                  lastSyncedHash: record.localHash,
                  remoteEtag: stored.etag,
                  syncState: SyncState.synced,
                ),
              );
              uploaded++;
              break;
            case _SyncAction.download:
              await _download(remoteObject!);
              downloaded++;
              break;
            case _SyncAction.conflict:
              await _repository.writeConflictCopy(
                record.id,
                remoteObject!.content,
              );
              await _repository.updateIndex(
                record.copyWith(syncState: SyncState.conflict),
              );
              conflicts++;
              break;
            case _SyncAction.unchanged:
              unchanged++;
              break;
          }
        } catch (error) {
          failures.add(
            SyncFailure(
              stage: 'sync-local',
              code: 'sync_object_failed',
              message: error.toString(),
              objectId: record.id,
              retryable: true,
              occurredAt: DateTime.now(),
            ),
          );
        }
      }

      for (final remoteObject in remote.values) {
        try {
          await _download(remoteObject);
          downloaded++;
        } catch (error) {
          failures.add(
            SyncFailure(
              stage: 'download-remote',
              code: 'sync_object_failed',
              message: error.toString(),
              objectId: remoteObject.id,
              retryable: true,
              occurredAt: DateTime.now(),
            ),
          );
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
      final failure = SyncFailure(
        stage: 'connect',
        code: 'sync_round_failed',
        message: error.toString(),
        retryable: true,
        occurredAt: DateTime.now(),
      );
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

  _SyncAction _decide(IndexedResult local, SyncRemoteObject? remote) {
    if (remote == null) {
      return _SyncAction.upload;
    }
    if (local.lastSyncedHash == null) {
      return local.localHash == remote.hash
          ? _SyncAction.unchanged
          : _SyncAction.conflict;
    }
    final remoteChanged = remote.hash != local.lastSyncedHash;
    final localChanged = local.localHash != local.lastSyncedHash;
    if (!remoteChanged && !localChanged) {
      return _SyncAction.unchanged;
    }
    if (!remoteChanged) {
      return _SyncAction.upload;
    }
    if (!localChanged) {
      return _SyncAction.download;
    }
    return _SyncAction.conflict;
  }

  Future<void> _download(SyncRemoteObject remote) async {
    final document = _codec.decode(remote.content);
    final previous = await _repository.findIndexed(document.id);
    if (previous != null && previous.mdPath != document.markdownPath) {
      await _repository.deleteRaw(previous.mdPath);
    }
    await _repository.saveRawDownload(remote, document);
  }
}

enum _SyncAction { upload, download, conflict, unchanged }

extension on ResultRepository {
  Future<void> saveRawDownload(
    SyncRemoteObject remote,
    ResultDocument document,
  ) async {
    final markdown = remote.content;
    await writeRaw(document.markdownPath, markdown);
    await updateIndex(
      IndexedResult(
        id: document.id,
        type: document.type,
        title: document.title,
        status: document.status,
        revision: document.revision,
        updatedAt: document.updatedAt,
        deleted: document.deleted,
        mdPath: document.markdownPath,
        localHash: remote.hash,
        lastSyncedHash: remote.hash,
        remoteEtag: remote.etag,
        matterId: document.matterId,
        syncState: document.deleted ? SyncState.deleted : SyncState.synced,
      ),
    );
  }
}
