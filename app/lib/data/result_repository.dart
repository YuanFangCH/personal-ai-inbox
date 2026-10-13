import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../core/markdown_codec.dart';
import '../core/models.dart';
import 'index_database.dart';
import 'vault_store.dart';

class ResultRepository {
  ResultRepository({
    required VaultStore vault,
    required IndexDatabase index,
    required this.deviceId,
    MarkdownCodec codec = const MarkdownCodec(),
  }) : _vault = vault,
       _index = index,
       _codec = codec;

  final VaultStore _vault;
  final IndexDatabase _index;
  final MarkdownCodec _codec;
  final String deviceId;
  Future<void> _writeTail = Future<void>.value();

  Future<void> initialize() async {
    await _vault.initialize();
    await _withWriteLock(_recoverPendingTransactions);
    await rebuildIndex();
  }

  Future<List<ResultDocument>> listDocuments({
    ResultType? type,
    bool includeDeleted = false,
  }) async {
    final indexed = await _index.listResults();
    final documents = <ResultDocument>[];
    for (final entry in indexed) {
      if (!includeDeleted && entry.deleted) {
        continue;
      }
      if (type != null && entry.type != type) {
        continue;
      }
      final document = await readDocument(entry.id);
      if (document != null) {
        documents.add(document);
      }
    }
    documents.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return documents;
  }

  Future<ResultDocument?> readDocument(String id) {
    return _vault.exclusive(() => _readDocument(id));
  }

  Future<ResultDocument?> _readDocument(String id) async {
    final indexed = await _index.findResult(id);
    if (indexed == null) {
      return null;
    }
    final source = await _vault.read(indexed.mdPath);
    if (source == null) {
      return null;
    }
    try {
      return _codec.decode(source);
    } on FormatException {
      return null;
    }
  }

  Future<ResultDocument> create({
    required ResultType type,
    required String title,
    required String body,
    ResultStatus status = ResultStatus.canonical,
    List<String> tags = const [],
    List<String> links = const [],
    DateTime? due,
    String? matterId,
    DateTime? start,
    DateTime? end,
    bool allDay = false,
    String? recurrence,
    List<String> sourceEventIds = const [],
    List<String> sourceHashes = const [],
    DateTime? createdAt,
    String? idempotencyKey,
  }) async {
    return _withWriteLock(() async {
      await _recoverPendingTransactions();
      if (idempotencyKey != null && createdAt == null) {
        throw ArgumentError.value(
          null,
          'createdAt',
          'An idempotent create requires a stable creation time',
        );
      }
      final timestamp = createdAt ?? DateTime.now();
      final id = _newId(type, timestamp, idempotencyKey: idempotencyKey);
      final document = ResultDocument(
        id: id,
        type: type,
        title: title.trim().isEmpty ? type.label : title.trim(),
        status: status,
        originDevice: deviceId,
        revision: 1,
        createdAt: timestamp,
        updatedAt: timestamp,
        body: body.trim(),
        tags: _deduplicate(tags),
        links: _deduplicate(links),
        due: due,
        matterId: matterId,
        start: start,
        end: end,
        allDay: allDay,
        recurrence: recurrence,
        sourceEventIds: _deduplicate(sourceEventIds),
        sourceHashes: _deduplicate(sourceHashes),
      );
      final payloadHash = _idempotencyPayloadHash(document);
      IdempotentOperation? operation;
      if (idempotencyKey != null) {
        operation = await _index.findOperation(idempotencyKey);
        if (operation != null &&
            (operation.resultId != id ||
                operation.payloadHash != payloadHash)) {
          throw StateError('幂等键已用于不同的成果内容');
        }
        operation ??= IdempotentOperation(
          key: idempotencyKey,
          resultId: id,
          payloadHash: payloadHash,
          state: OperationState.prepared,
          createdAt: timestamp,
          updatedAt: timestamp,
        );
        await _index.upsertOperation(operation);
      }
      final existingSource = await _vault.read(document.markdownPath);
      if (operation != null &&
          operation.state != OperationState.prepared &&
          existingSource == null) {
        throw StateError('已完成成果缺失，拒绝重复创建：$id');
      }
      if (existingSource != null) {
        final existing = _codec.decode(existingSource);
        if (idempotencyKey == null ||
            !_sameLogicalContent(existing, document)) {
          throw StateError('成果文件已存在，拒绝覆盖：${document.id}');
        }
        await _indexDocument(
          existing,
          await _index.findResult(id),
          hashMarkdown(existingSource),
        );
        if (operation != null) {
          await _index.upsertOperation(
            operation.copyWith(
              state: OperationState.completed,
              updatedAt: DateTime.now(),
            ),
          );
        }
        return existing;
      }
      await _commitAndIndex(document, operation: operation);
      return document;
    });
  }

  Future<ResultDocument> save(
    ResultDocument document, {
    bool incrementRevision = true,
  }) async {
    final previous = await readDocument(document.id);
    final saved = document.copyWith(
      originDevice: deviceId,
      revision: incrementRevision && previous != null
          ? previous.revision + 1
          : document.revision,
      createdAt: previous?.createdAt ?? document.createdAt,
      updatedAt: DateTime.now(),
    );
    await _writeAndIndex(saved);
    return saved;
  }

  Future<void> markTodo(ResultDocument document, bool done) async {
    if (document.type != ResultType.todo) {
      return;
    }
    await save(document.copyWith(done: done));
  }

  Future<void> addLink(String id, String targetId) async {
    final document = await readDocument(id);
    if (document == null || id == targetId) {
      return;
    }
    await save(
      document.copyWith(links: _deduplicate([...document.links, targetId])),
    );
  }

  Future<void> removeLink(String id, String targetId) async {
    final document = await readDocument(id);
    if (document == null) {
      return;
    }
    await save(
      document.copyWith(
        links: document.links.where((link) => link != targetId).toList(),
      ),
    );
  }

  Future<void> delete(String id) async {
    final document = await readDocument(id);
    if (document == null) {
      return;
    }
    final tombstone = document.copyWith(
      deleted: true,
      body: '',
      updatedAt: DateTime.now(),
      revision: document.revision + 1,
      due: null,
      start: null,
      end: null,
    );
    await _writeAndIndex(tombstone);
  }

  Future<ResultDocument?> findDocument(String id) async {
    final document = await readDocument(id);
    if (document == null || document.deleted) {
      return null;
    }
    return document;
  }

  Future<ResultDocument?> findByIdempotencyKey({
    required ResultType type,
    required DateTime createdAt,
    required String idempotencyKey,
  }) async {
    final id = _newId(type, createdAt, idempotencyKey: idempotencyKey);
    final operation = await _index.findOperation(idempotencyKey);
    if (operation != null && operation.resultId != id) {
      return null;
    }
    final document = await readDocument(id);
    return document == null || document.deleted ? null : document;
  }

  Future<List<ResultDocument>> childrenOf(String matterId) async {
    final documents = await listDocuments();
    return documents
        .where((document) => document.matterId == matterId)
        .toList(growable: false);
  }

  Future<List<ResultDocument>> backlinksOf(String id) async {
    final documents = await listDocuments();
    return documents
        .where((document) => document.links.contains(id))
        .toList(growable: false);
  }

  Future<List<IndexedResult>> listIndex() => _index.listResults();

  Future<IndexedResult?> findIndexed(String id) => _index.findResult(id);

  Future<void> updateIndex(IndexedResult result) async {
    await _vault.exclusive(() => _index.upsertResult(result));
  }

  Future<void> rebuildIndex() async {
    return _withWriteLock(_rebuildIndex);
  }

  Future<void> _rebuildIndex() async {
    final previous = {
      for (final entry in await _index.listResults()) entry.id: entry,
    };
    final files = await _vault.listMarkdownFiles();
    final results = <IndexedResult>[];
    for (final path in files) {
      if (!_isManagedMarkdown(path)) {
        continue;
      }
      final source = await _vault.read(path);
      if (source == null) {
        continue;
      }
      try {
        final document = _codec.decode(source);
        final hash = hashMarkdown(source);
        final old = previous[document.id];
        results.add(
          IndexedResult(
            id: document.id,
            type: document.type,
            title: document.title,
            status: document.status,
            revision: document.revision,
            updatedAt: document.updatedAt,
            deleted: document.deleted,
            mdPath: path,
            localHash: hash,
            lastSyncedHash: old?.lastSyncedHash,
            remoteEtag: old?.remoteEtag,
            matterId: document.matterId,
            syncState: document.deleted
                ? SyncState.deleted
                : hash == old?.lastSyncedHash
                ? SyncState.synced
                : SyncState.pendingUpload,
          ),
        );
      } on FormatException {
        continue;
      }
    }
    await _index.replaceResults(results);
  }

  Future<String> writeConflictCopy(
    String id,
    String contents, {
    required String remoteEtag,
    required String localHash,
  }) async {
    final remoteHash = hashMarkdown(contents);
    final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final path =
        'vault/conflicts/$safeId.conflict-${remoteHash.substring(7)}.md';
    return _withWriteLock(() async {
      final indexed = await _index.findResult(id);
      final source = indexed == null ? null : await _vault.read(indexed.mdPath);
      if (indexed == null ||
          source == null ||
          hashMarkdown(source) != localHash) {
        throw StateError('本地成果在登记冲突前已变化：$id');
      }
      final previousConflict = await _index.findConflict(id);
      var conflictLocalHash = localHash;
      if (previousConflict?.remoteHash != remoteHash) {
        final document = _codec.decode(source);
        final registered = document.copyWith(
          revision: document.revision + 1,
          updatedAt: DateTime.now(),
        );
        await _commitAndIndex(registered);
        final registeredSource = await _vault.read(registered.markdownPath);
        if (registeredSource == null) {
          throw StateError('冲突版本提交后文件缺失：$id');
        }
        conflictLocalHash = hashMarkdown(registeredSource);
      }
      final existing = await _vault.read(path);
      if (existing != null && hashMarkdown(existing) != remoteHash) {
        throw StateError('冲突副本路径内容不匹配：$id');
      }
      if (existing == null) await _vault.write(path, contents);
      if (previousConflict != null && previousConflict.copyPath != path) {
        await _vault.delete(previousConflict.copyPath);
      }
      await _index.upsertConflict(
        SyncConflictRecord(
          resultId: id,
          remoteHash: remoteHash,
          remoteEtag: remoteEtag,
          localHash: conflictLocalHash,
          copyPath: path,
          createdAt: DateTime.now(),
        ),
      );
      return path;
    });
  }

  Future<List<SyncConflictRecord>> listConflicts() => _index.listConflicts();

  Future<SyncConflictRecord?> findConflict(String id) =>
      _index.findConflict(id);

  Future<void> removeConflict(String id, String path) =>
      _withWriteLock(() async {
        await _index.removeConflict(id);
        await _vault.delete(path);
      });

  Future<String?> readManagedResult(String id) => _vault.exclusive(() async {
    final indexed = await _index.findResult(id);
    return indexed == null ? null : _vault.read(indexed.mdPath);
  });

  Future<void> acknowledgeSynced({
    required String id,
    required String expectedLocalHash,
    required String remoteEtag,
  }) => _withWriteLock(() async {
    final indexed = await _index.findResult(id);
    if (indexed == null) throw StateError('本地成果已不存在：$id');
    final source = await _vault.read(indexed.mdPath);
    if (source == null || hashMarkdown(source) != expectedLocalHash) {
      throw StateError('本地成果在同步期间已变化：$id');
    }
    await _index.upsertResult(
      indexed.copyWith(
        localHash: expectedLocalHash,
        lastSyncedHash: expectedLocalHash,
        remoteEtag: remoteEtag,
        syncState: SyncState.synced,
      ),
    );
  });

  Future<void> importRemote({
    required SyncRemoteObject remote,
    required String? expectedLocalHash,
  }) => _withWriteLock(() async {
    await _recoverPendingTransactions();
    final document = _codec.decode(remote.content);
    final old = await _index.findResult(document.id);
    final current = old == null ? null : await _vault.read(old.mdPath);
    final currentHash = current == null ? null : hashMarkdown(current);
    if (currentHash != expectedLocalHash) {
      throw StateError('本地成果在导入远端前已变化：${document.id}');
    }
    final imported = document;
    await _commitAndIndex(
      imported,
      rawContents: remote.content,
      syncBaseline: _SyncBaseline(remote.hash, remote.etag),
      allowRevisionReplacement: true,
    );
  });

  Future<List<String>> listConflictFiles() async {
    final files = await _vault.exclusive(_vault.listMarkdownFiles);
    return files
        .where((path) => path.startsWith('vault/conflicts/'))
        .toList(growable: false);
  }

  Future<String?> readRaw(String path) =>
      _vault.exclusive(() => _vault.read(path));

  Future<void> writeRaw(String path, String contents) =>
      _vault.exclusive(() => _vault.write(path, contents));

  Future<void> deleteRaw(String path) =>
      _vault.exclusive(() => _vault.delete(path));

  Future<void> resolveConflictUsingRemote(String conflictPath) async {
    final source = await readRaw(conflictPath);
    if (source == null) {
      return;
    }
    final remote = _codec.decode(source);
    final local = await readDocument(remote.id);
    final resolved = remote.copyWith(
      originDevice: deviceId,
      revision: (local?.revision ?? remote.revision) + 1,
      createdAt: local?.createdAt ?? remote.createdAt,
      updatedAt: DateTime.now(),
    );
    await _writeAndIndex(resolved);
    await deleteRaw(conflictPath);
  }

  Future<void> keepLocalConflict(String conflictPath) async {
    await deleteRaw(conflictPath);
  }

  Future<String> describeVaultRoot() => _vault.describeRoot();

  String hashMarkdown(String contents) {
    return 'sha256:${sha256.convert(utf8.encode(contents))}';
  }

  Future<void> _writeAndIndex(ResultDocument document) async {
    return _withWriteLock(() async {
      await _recoverPendingTransactions();
      await _commitAndIndex(document);
    });
  }

  Future<T> _withWriteLock<T>(Future<T> Function() operation) {
    final previousWrite = _writeTail;
    final finished = Completer<void>();
    _writeTail = finished.future;
    return () async {
      await previousWrite;
      try {
        return await _vault.exclusive(operation);
      } finally {
        finished.complete();
      }
    }();
  }

  Future<void> _commitAndIndex(
    ResultDocument document, {
    IdempotentOperation? operation,
    String? rawContents,
    _SyncBaseline? syncBaseline,
    bool allowRevisionReplacement = false,
  }) async {
    if (!_isSafeResultId(document.id) ||
        document.markdownPath !=
            'vault/${document.type.directory}/${document.id}.md') {
      throw StateError('成果 ID 或目标路径不合法：${document.id}');
    }
    final old = await _index.findResult(document.id);
    if (old == null && document.revision != 1 && !allowRevisionReplacement) {
      throw StateError('成果不存在或版本已过期，拒绝覆盖：${document.id}');
    }
    if (old != null &&
        !allowRevisionReplacement &&
        document.revision != old.revision + 1) {
      throw StateError('成果版本已变化，拒绝覆盖：${document.id}');
    }

    final markdown = rawContents ?? _codec.encode(document);
    if (syncBaseline != null && syncBaseline.hash != hashMarkdown(markdown)) {
      throw StateError('同步基线 hash 与提交内容不一致：${document.id}');
    }
    final parsedMarkdown = _codec.decode(markdown);
    if (parsedMarkdown.id != document.id ||
        parsedMarkdown.markdownPath != document.markdownPath ||
        parsedMarkdown.revision != document.revision) {
      throw StateError('成果内容与提交元数据不一致：${document.id}');
    }
    final previousMarkdown = old == null ? null : await _vault.read(old.mdPath);
    if (old != null && previousMarkdown == null) {
      throw StateError('成果文件缺失，拒绝覆盖：${document.id}');
    }
    if (old != null && hashMarkdown(previousMarkdown!) != old.localHash) {
      throw StateError('成果文件已在应用外修改，请重新加载后再保存：${document.id}');
    }
    if (old == null && await _vault.read(document.markdownPath) != null) {
      throw StateError('成果文件已存在但索引缺失，拒绝覆盖：${document.id}');
    }

    final operationId = const Uuid().v4().replaceAll('-', '');
    final transactionRoot = 'vault/.local-transactions';
    final stagedPath = '$transactionRoot/$operationId.new.md';
    final previousPath = '$transactionRoot/$operationId.old.md';
    final journalPath = '$transactionRoot/$operationId.journal.md';
    final nextHash = hashMarkdown(markdown);
    final oldHash = old?.localHash;
    if (previousMarkdown != null) {
      await _vault.write(previousPath, previousMarkdown);
      if (hashMarkdown((await _vault.read(previousPath)) ?? '') != oldHash) {
        throw StateError('成果恢复副本校验失败：${document.id}');
      }
    }
    await _vault.write(stagedPath, markdown);
    if (hashMarkdown((await _vault.read(stagedPath)) ?? '') != nextHash) {
      throw StateError('成果暂存内容校验失败：${document.id}');
    }
    await _vault.write(
      journalPath,
      jsonEncode({
        'schema_version': 1,
        'operation_id': operationId,
        'result_id': document.id,
        'target_path': document.markdownPath,
        'previous_target_path': old?.mdPath,
        'old_hash': oldHash,
        'new_hash': nextHash,
        'expected_revision': old?.revision,
        'idempotency_key': operation?.key,
        'payload_hash': operation?.payloadHash,
        'last_synced_hash': syncBaseline?.hash,
        'remote_etag': syncBaseline?.etag,
      }),
    );

    await _vault.write(document.markdownPath, markdown);
    final committed = await _vault.read(document.markdownPath);
    if (committed == null || hashMarkdown(committed) != nextHash) {
      throw StateError('成果文件提交校验失败：${document.id}');
    }
    await _indexDocument(document, old, nextHash, syncBaseline: syncBaseline);
    if (operation != null) {
      await _index.upsertOperation(
        operation.copyWith(
          state: OperationState.resultCommitted,
          updatedAt: DateTime.now(),
        ),
      );
      await _index.upsertOperation(
        operation.copyWith(
          state: OperationState.completed,
          updatedAt: DateTime.now(),
        ),
      );
    }
    if (old != null && old.mdPath != document.markdownPath) {
      await _vault.delete(old.mdPath);
    }
    await _cleanupTransaction(stagedPath, previousPath, journalPath);
  }

  Future<void> _recoverPendingTransactions() async {
    final files = await _vault.listMarkdownFiles();
    final journals = files
        .where(
          (path) =>
              path.startsWith('vault/.local-transactions/') &&
              path.endsWith('.journal.md'),
        )
        .toList(growable: false);
    for (final journalPath in journals) {
      final source = await _vault.read(journalPath);
      if (source == null) {
        continue;
      }
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic> || decoded['schema_version'] != 1) {
        throw StateError('本地成果提交日志损坏：$journalPath');
      }
      final operationId = decoded['operation_id'];
      final resultId = decoded['result_id'];
      final targetPath = decoded['target_path'];
      final previousTarget = decoded['previous_target_path'];
      final expectedHash = decoded['new_hash'];
      final oldHash = decoded['old_hash'];
      final expectedRevision = decoded['expected_revision'];
      final idempotencyKey = decoded['idempotency_key'];
      final payloadHash = decoded['payload_hash'];
      final syncedHash = decoded['last_synced_hash'];
      final remoteEtag = decoded['remote_etag'];
      if (operationId is! String ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(operationId) ||
          resultId is! String ||
          !_isSafeResultId(resultId) ||
          targetPath is! String ||
          expectedHash is! String ||
          (previousTarget != null && previousTarget is! String) ||
          (oldHash != null && oldHash is! String) ||
          (expectedRevision != null && expectedRevision is! int) ||
          (idempotencyKey != null && idempotencyKey is! String) ||
          (payloadHash != null && payloadHash is! String) ||
          (syncedHash != null && syncedHash is! String) ||
          (remoteEtag != null && remoteEtag is! String) ||
          ((syncedHash == null) != (remoteEtag == null)) ||
          !_isManagedResultPath(targetPath, resultId) ||
          (previousTarget is String &&
              !_isManagedResultPath(previousTarget, resultId))) {
        throw StateError('本地成果提交日志不合法：$journalPath');
      }
      if (journalPath != 'vault/.local-transactions/$operationId.journal.md') {
        throw StateError('本地成果提交日志路径无效：$journalPath');
      }

      final target = await _vault.read(targetPath);
      final targetHash = target == null ? null : hashMarkdown(target);
      final stagedPath = 'vault/.local-transactions/$operationId.new.md';
      final backupPath = 'vault/.local-transactions/$operationId.old.md';
      final staged = await _vault.read(stagedPath);
      final backup = await _vault.read(backupPath);
      final stagedIsValid =
          staged != null && hashMarkdown(staged) == expectedHash;
      if (targetHash != expectedHash && stagedIsValid) {
        final targetIsOld = oldHash == null
            ? target == null
            : targetHash == oldHash ||
                  (target == null &&
                      backup != null &&
                      hashMarkdown(backup) == oldHash);
        if (!targetIsOld) {
          throw StateError('成果在恢复期间又发生变化，保留提交日志：$resultId');
        }
        await _vault.write(targetPath, staged);
        final repaired = await _vault.read(targetPath);
        if (repaired == null || hashMarkdown(repaired) != expectedHash) {
          throw StateError('恢复成果文件校验失败：$resultId');
        }
      }

      final committed = await _vault.read(targetPath);
      if (committed == null || hashMarkdown(committed) != expectedHash) {
        final previousPath = previousTarget is String
            ? previousTarget
            : targetPath;
        if (oldHash != null && targetHash == oldHash) {
          await _cleanupTransaction(stagedPath, backupPath, journalPath);
          continue;
        }
        if (oldHash == null && targetHash == null) {
          await _cleanupTransaction(stagedPath, backupPath, journalPath);
          continue;
        }
        if (oldHash != null &&
            backup != null &&
            hashMarkdown(backup) == oldHash &&
            (targetHash == null || targetHash == oldHash)) {
          if (targetHash == null) {
            await _vault.write(previousPath, backup);
          }
          await _cleanupTransaction(stagedPath, backupPath, journalPath);
          continue;
        }
        throw StateError('成果新旧版本均无法校验，保留恢复材料：$resultId');
      }

      final document = _codec.decode(committed);
      if (document.id != resultId ||
          document.markdownPath != targetPath ||
          hashMarkdown(_codec.encode(document)) != expectedHash) {
        throw StateError('已提交成果身份或内容校验失败：$resultId');
      }

      final old = await _index.findResult(resultId);
      if (expectedRevision is int &&
          old != null &&
          old.revision != expectedRevision &&
          old.revision != document.revision) {
        throw StateError('成果索引 revision 与提交日志不匹配，保留恢复材料：$resultId');
      }
      if (expectedRevision == null &&
          old != null &&
          old.revision != document.revision) {
        throw StateError('新建成果 ID 已被索引占用，拒绝恢复：$resultId');
      }
      if (old == null
          ? expectedRevision != null
          : old.revision != expectedRevision &&
                old.revision != document.revision) {
        throw StateError('成果索引版本与提交日志不匹配，保留恢复材料：$resultId');
      }
      await _indexDocument(
        document,
        old,
        expectedHash,
        syncBaseline: syncedHash is String && remoteEtag is String
            ? _SyncBaseline(syncedHash, remoteEtag)
            : null,
      );
      if (idempotencyKey is String && payloadHash is String) {
        final operation = await _index.findOperation(idempotencyKey);
        if (operation == null ||
            operation.resultId != resultId ||
            operation.payloadHash != payloadHash ||
            payloadHash != _idempotencyPayloadHash(document)) {
          throw StateError('成果操作账本与提交日志不匹配：$resultId');
        }
        await _index.upsertOperation(
          operation.copyWith(
            state: OperationState.resultCommitted,
            updatedAt: DateTime.now(),
          ),
        );
        await _index.upsertOperation(
          operation.copyWith(
            state: OperationState.completed,
            updatedAt: DateTime.now(),
          ),
        );
      }
      if (previousTarget is String && previousTarget != targetPath) {
        await _vault.delete(previousTarget);
      }
      await _cleanupTransaction(
        stagedPath,
        'vault/.local-transactions/$operationId.old.md',
        journalPath,
      );
    }

    final remainingFiles = await _vault.listMarkdownFiles();
    for (final path in remainingFiles.where(
      (path) =>
          path.startsWith('vault/.local-transactions/') &&
          (path.endsWith('.new.md') || path.endsWith('.old.md')),
    )) {
      await _vault.delete(path);
    }
  }

  Future<void> _indexDocument(
    ResultDocument document,
    IndexedResult? old,
    String hash, {
    _SyncBaseline? syncBaseline,
  }) async {
    final record = IndexedResult(
      id: document.id,
      type: document.type,
      title: document.title,
      status: document.status,
      revision: document.revision,
      updatedAt: document.updatedAt,
      deleted: document.deleted,
      mdPath: document.markdownPath,
      localHash: hash,
      lastSyncedHash: syncBaseline?.hash ?? old?.lastSyncedHash,
      remoteEtag: syncBaseline?.etag ?? old?.remoteEtag,
      matterId: document.matterId,
      syncState: document.deleted
          ? SyncState.deleted
          : hash == (syncBaseline?.hash ?? old?.lastSyncedHash)
          ? SyncState.synced
          : SyncState.pendingUpload,
    );
    await _index.upsertResult(record);
  }

  Future<void> _cleanupTransaction(
    String stagedPath,
    String previousPath,
    String journalPath,
  ) async {
    await _vault.delete(stagedPath);
    await _vault.delete(previousPath);
    await _vault.delete(journalPath);
  }

  bool _isManagedMarkdown(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.startsWith('vault/matters/') ||
        normalized.startsWith('vault/todos/') ||
        normalized.startsWith('vault/calendar/') ||
        normalized.startsWith('vault/knowledge/');
  }

  bool _isSafeResultId(String id) {
    return id.length <= 128 && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);
  }

  bool _isManagedResultPath(String path, String id) {
    return ResultType.values.any(
      (type) => path == 'vault/${type.directory}/$id.md',
    );
  }

  bool _sameLogicalContent(ResultDocument left, ResultDocument right) {
    bool sameList(List<String> a, List<String> b) {
      if (a.length != b.length) {
        return false;
      }
      for (var index = 0; index < a.length; index++) {
        if (a[index] != b[index]) {
          return false;
        }
      }
      return true;
    }

    return left.id == right.id &&
        left.type == right.type &&
        left.title == right.title &&
        left.status == right.status &&
        left.body == right.body &&
        left.deleted == right.deleted &&
        left.done == right.done &&
        left.due == right.due &&
        left.matterId == right.matterId &&
        left.start == right.start &&
        left.end == right.end &&
        left.allDay == right.allDay &&
        left.recurrence == right.recurrence &&
        sameList(left.tags, right.tags) &&
        sameList(left.links, right.links) &&
        sameList(left.sourceEventIds, right.sourceEventIds) &&
        sameList(left.sourceHashes, right.sourceHashes);
  }

  String _idempotencyPayloadHash(ResultDocument document) {
    final payload = jsonEncode({
      'type': document.type.wireName,
      'title': document.title,
      'status': document.status.wireName,
      'body': document.body,
      'deleted': document.deleted,
      'done': document.done,
      'due': document.due?.toUtc().toIso8601String(),
      'matter': document.matterId,
      'start': document.start?.toUtc().toIso8601String(),
      'end': document.end?.toUtc().toIso8601String(),
      'all_day': document.allDay,
      'recurrence': document.recurrence,
      'tags': document.tags,
      'links': document.links,
      'source_event_ids': document.sourceEventIds,
      'source_hashes': document.sourceHashes,
    });
    return 'sha256:${sha256.convert(utf8.encode(payload))}';
  }

  String _newId(ResultType type, DateTime timestamp, {String? idempotencyKey}) {
    final prefix = switch (type) {
      ResultType.matter => 'mt',
      ResultType.todo => 'td',
      ResultType.event => 'ev',
      ResultType.knowledge => 'kn',
    };
    if (idempotencyKey != null) {
      final stable = sha256
          .convert(utf8.encode(idempotencyKey))
          .toString()
          .substring(0, 24);
      return '${prefix}_op_$stable';
    }
    final date =
        '${timestamp.year}${timestamp.month.toString().padLeft(2, '0')}${timestamp.day.toString().padLeft(2, '0')}';
    final random = const Uuid()
        .v4()
        .replaceAll('-', '')
        .substring(0, 8)
        .toLowerCase();
    return '${prefix}_${date}_$random';
  }

  List<String> _deduplicate(List<String> values) {
    final seen = <String>{};
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && seen.add(value))
        .toList(growable: false);
  }
}

class _SyncBaseline {
  const _SyncBaseline(this.hash, this.etag);

  final String hash;
  final String etag;
}
