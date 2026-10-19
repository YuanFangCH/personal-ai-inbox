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
  static const defaultUndoWindow = Duration(minutes: 10);
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

  Future<List<ResultDocument>> searchDocuments({
    required String query,
    required ResultType type,
    required int offset,
    int limit = 50,
  }) async {
    final records = await _index.searchResults(
      query: query,
      type: type,
      limit: limit.clamp(1, 50),
      offset: offset < 0 ? 0 : offset,
    );
    final documents = <ResultDocument>[];
    for (final record in records) {
      final document = await _vault.exclusive(() async {
        final source = await _vault.read(record.mdPath);
        if (source == null) return null;
        try {
          final decoded = _codec.decode(source);
          return decoded.id == record.id && !decoded.deleted ? decoded : null;
        } on FormatException {
          return null;
        }
      });
      if (document != null) documents.add(document);
    }
    return List.unmodifiable(documents);
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
    Map<String, Object?> extensionFields = const {},
    DateTime? createdAt,
    String? idempotencyKey,
    String? reversibleActionId,
    String? approvedGlobalCandidateId,
    String? approvedGlobalCandidateDigest,
    Duration undoWindow = defaultUndoWindow,
  }) async {
    return _withWriteLock(() async {
      await _recoverPendingTransactions();
      await _requireGlobalWriteApproval(
        type: type,
        extensionFields: extensionFields,
        candidateId: approvedGlobalCandidateId,
        digest: approvedGlobalCandidateDigest,
        operation: GlobalKnowledgeOperation.create,
      );
      if (reversibleActionId != null && idempotencyKey == null) {
        throw ArgumentError(
          'A reversible result creation requires a stable idempotency key',
        );
      }
      if (idempotencyKey != null && createdAt == null) {
        throw ArgumentError.value(
          null,
          'createdAt',
          'An idempotent create requires a stable creation time',
        );
      }
      final timestamp = createdAt ?? DateTime.now();
      final id = _newId(type, timestamp, idempotencyKey: idempotencyKey);
      if (reversibleActionId != null &&
          !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(reversibleActionId)) {
        throw ArgumentError.value(reversibleActionId, 'reversibleActionId');
      }
      final priorAction = reversibleActionId == null
          ? null
          : await _index.findReversibleAction(reversibleActionId);
      if (priorAction != null && priorAction.resultId != id) {
        throw StateError('撤销动作 ID 已用于其他成果：$reversibleActionId');
      }
      final document = ResultDocument(
        id: id,
        type: type,
        title: title.trim().isEmpty ? type.wireName : title.trim(),
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
        extensionFields: Map.unmodifiable(extensionFields),
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
      if (reversibleActionId != null) {
        final action = _newReversibleAction(
          id: reversibleActionId,
          resultId: id,
          kind: ReversibleActionKind.create,
          document: document,
          markdown: _codec.encode(document),
          previousMarkdown: null,
          undoWindow: undoWindow,
        );
        await _index.upsertReversibleAction(action);
      }
      await _commitAndIndex(
        document,
        operation: operation,
        reversibleActionId: reversibleActionId,
      );
      return document;
    });
  }

  Future<ReversibleResultAction> undoAction(String actionId, {DateTime? now}) {
    return _withWriteLock(() async {
      await _recoverPendingTransactions(now: now ?? DateTime.now());
      final action = await _index.findReversibleAction(actionId);
      if (action?.status == ReversibleActionStatus.expired) {
        throw StateError('操作撤销期限已过：$actionId');
      }
      if (action == null || action.status != ReversibleActionStatus.applied) {
        throw StateError('操作不可撤销或已撤销：$actionId');
      }
      final currentBeforeUndo = await _readDocument(action.resultId);
      final priorDocument = action.previousMarkdown == null
          ? null
          : _codec.decode(action.previousMarkdown!);
      if (currentBeforeUndo?.isGlobalKnowledge == true ||
          priorDocument?.isGlobalKnowledge == true) {
        throw StateError('全局知识的撤销必须先提交并确认新的变更候选：$actionId');
      }
      final timestamp = now ?? DateTime.now();
      if (!action.undoUntil.isAfter(timestamp)) {
        throw StateError('操作撤销期限已过：$actionId');
      }
      final current = await _readExpectedDocument(
        action.resultId,
        expectedRevision: action.expectedRevision,
        expectedHash: action.expectedHash,
        allowDeleted: action.kind == ReversibleActionKind.delete,
      );
      final restored = action.previousMarkdown == null
          ? current.copyWith(
              deleted: true,
              body: '',
              revision: current.revision + 1,
              updatedAt: timestamp,
              due: null,
              start: null,
              end: null,
            )
          : _codec
                .decode(action.previousMarkdown!)
                .copyWith(
                  originDevice: deviceId,
                  revision: current.revision + 1,
                  createdAt: current.createdAt,
                  updatedAt: timestamp,
                );
      final restoreHash = hashMarkdown(_codec.encode(restored));
      final undoing = action.copyWith(
        status: ReversibleActionStatus.undoing,
        undoRevision: restored.revision,
        undoHash: restoreHash,
        error: null,
      );
      await _index.upsertReversibleAction(undoing);
      await _commitAndIndex(
        restored,
        reversibleActionId: actionId,
        reversibleActionStatus: ReversibleActionStatus.undone,
      );
      return (await _index.findReversibleAction(actionId))!;
    });
  }

  Future<ReversibleResultAction?> findReversibleAction(String id) {
    return _withWriteLock(() async {
      await _recoverPendingTransactions();
      return _index.findReversibleAction(id);
    });
  }

  Future<List<ReversibleResultAction>> listReversibleActions() {
    return _withWriteLock(() async {
      await _recoverPendingTransactions();
      return _index.listReversibleActions();
    });
  }

  Future<GlobalKnowledgeCandidate?> findGlobalKnowledgeCandidate(String id) {
    return _index.findGlobalKnowledgeCandidate(id);
  }

  Future<List<GlobalKnowledgeCandidate>> listGlobalKnowledgeCandidates() {
    return _index.listGlobalKnowledgeCandidates();
  }

  Future<GlobalKnowledgeCandidate> saveGlobalKnowledgeCandidate(
    GlobalKnowledgeCandidate candidate,
  ) {
    return _withWriteLock(() async {
      final existing = await _index.findGlobalKnowledgeCandidate(candidate.id);
      if (existing != null && existing.digest != candidate.digest) {
        throw StateError('全局知识候选 ID 已绑定其他内容：${candidate.id}');
      }
      if (existing != null &&
          !_isAllowedCandidateTransition(existing, candidate)) {
        throw StateError(
          '全局知识候选状态不可从 ${existing.status.name} 变为 ${candidate.status.name}',
        );
      }
      await _index.upsertGlobalKnowledgeCandidate(candidate);
      return candidate;
    });
  }

  Future<ResultDocument> save(
    ResultDocument document, {
    bool incrementRevision = true,
  }) async {
    final previous = await readDocument(document.id);
    if (document.isGlobalKnowledge || previous?.isGlobalKnowledge == true) {
      throw StateError('全局知识的新增、修改和删除必须经人工确认候选');
    }
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

  Future<ResultDocument> saveWithUndo({
    required ResultDocument document,
    required int expectedRevision,
    required String expectedHash,
    required String actionId,
    String? approvedGlobalCandidateId,
    String? approvedGlobalCandidateDigest,
    Duration undoWindow = defaultUndoWindow,
  }) {
    return _withWriteLock(() async {
      await _recoverPendingTransactions();
      final retry = await _replayReversibleAction(
        actionId,
        kind: ReversibleActionKind.update,
        expectedRevision: expectedRevision,
      );
      if (retry != null) return retry;
      final current = await _readExpectedDocument(
        document.id,
        expectedRevision: expectedRevision,
        expectedHash: expectedHash,
      );
      if (document.type != current.type || document.deleted) {
        throw StateError('修改不能改变成果类型或墓碑状态：${document.id}');
      }
      await _requireGlobalWriteApproval(
        type: current.type,
        extensionFields: document.extensionFields,
        candidateId: approvedGlobalCandidateId,
        digest: approvedGlobalCandidateDigest,
        operation: GlobalKnowledgeOperation.update,
        target: current,
      );
      final next = document.copyWith(
        originDevice: deviceId,
        revision: current.revision + 1,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
      );
      final previousMarkdown = await _vault.read(current.markdownPath);
      if (previousMarkdown == null) {
        throw StateError('成果文件缺失，拒绝修改：${document.id}');
      }
      await _index.upsertReversibleAction(
        _newReversibleAction(
          id: actionId,
          resultId: next.id,
          kind: ReversibleActionKind.update,
          document: next,
          markdown: _codec.encode(next),
          previousMarkdown: previousMarkdown,
          undoWindow: undoWindow,
        ),
      );
      await _commitAndIndex(next, reversibleActionId: actionId);
      return next;
    });
  }

  Future<ResultDocument> deleteWithUndo({
    required String id,
    required int expectedRevision,
    required String expectedHash,
    required String actionId,
    String? approvedGlobalCandidateId,
    String? approvedGlobalCandidateDigest,
    Duration undoWindow = defaultUndoWindow,
  }) {
    return _withWriteLock(() async {
      await _recoverPendingTransactions();
      final retry = await _replayReversibleAction(
        actionId,
        kind: ReversibleActionKind.delete,
        expectedRevision: expectedRevision,
      );
      if (retry != null) return retry;
      final current = await _readExpectedDocument(
        id,
        expectedRevision: expectedRevision,
        expectedHash: expectedHash,
      );
      await _requireGlobalWriteApproval(
        type: current.type,
        extensionFields: current.extensionFields,
        candidateId: approvedGlobalCandidateId,
        digest: approvedGlobalCandidateDigest,
        operation: GlobalKnowledgeOperation.delete,
        target: current,
      );
      final source = await _vault.read(current.markdownPath);
      if (source == null) throw StateError('成果文件缺失，拒绝删除：$id');
      final tombstone = current.copyWith(
        deleted: true,
        body: '',
        revision: current.revision + 1,
        updatedAt: DateTime.now(),
        due: null,
        start: null,
        end: null,
      );
      await _index.upsertReversibleAction(
        _newReversibleAction(
          id: actionId,
          resultId: id,
          kind: ReversibleActionKind.delete,
          document: tombstone,
          markdown: _codec.encode(tombstone),
          previousMarkdown: source,
          undoWindow: undoWindow,
        ),
      );
      await _commitAndIndex(tombstone, reversibleActionId: actionId);
      return tombstone;
    });
  }

  Future<ResultDocument?> markTodo(ResultDocument document, bool done) async {
    if (document.type != ResultType.todo) {
      return null;
    }
    return save(document.copyWith(done: done));
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

  Future<ResultDocument?> delete(String id) async {
    final document = await readDocument(id);
    if (document == null) {
      return null;
    }
    if (document.isGlobalKnowledge) {
      throw StateError('全局知识的新增、修改和删除必须经人工确认候选');
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
    return tombstone;
  }

  Future<void> _requireGlobalWriteApproval({
    required ResultType type,
    required Map<String, Object?> extensionFields,
    required String? candidateId,
    required String? digest,
    required GlobalKnowledgeOperation operation,
    ResultDocument? target,
  }) async {
    final touchesGlobalKnowledge =
        target?.isGlobalKnowledge == true ||
        extensionFields[globalKnowledgeScopeKey] == globalKnowledgeScopeValue;
    if (!touchesGlobalKnowledge) return;
    if (type != ResultType.knowledge || candidateId == null || digest == null) {
      throw StateError('全局知识的新增、修改和删除必须经人工确认候选');
    }
    final candidate = await _index.findGlobalKnowledgeCandidate(candidateId);
    if (candidate == null ||
        candidate.status != GlobalKnowledgeCandidateStatus.approved ||
        candidate.operation != operation ||
        candidate.digest != digest ||
        (target == null
            ? candidate.targetId != null
            : candidate.targetId != target.id ||
                  candidate.expectedRevision != target.revision ||
                  candidate.expectedHash !=
                      hashMarkdown(
                        (await _vault.read(target.markdownPath))!,
                      ))) {
      throw StateError('全局知识候选尚未确认，或候选与目标版本不匹配');
    }
  }

  bool _isAllowedCandidateTransition(
    GlobalKnowledgeCandidate previous,
    GlobalKnowledgeCandidate next,
  ) {
    if (previous.operation != next.operation ||
        previous.digest != next.digest ||
        previous.targetId != next.targetId ||
        previous.expectedRevision != next.expectedRevision ||
        previous.expectedHash != next.expectedHash ||
        previous.sourceConversationId != next.sourceConversationId ||
        previous.sourceMessageId != next.sourceMessageId ||
        previous.createdAt != next.createdAt ||
        jsonEncode(previous.proposal) != jsonEncode(next.proposal)) {
      return false;
    }
    return switch (previous.status) {
      GlobalKnowledgeCandidateStatus.pending =>
        next.status == GlobalKnowledgeCandidateStatus.pending ||
            next.status == GlobalKnowledgeCandidateStatus.approved ||
            next.status == GlobalKnowledgeCandidateStatus.rejected ||
            next.status == GlobalKnowledgeCandidateStatus.stale,
      GlobalKnowledgeCandidateStatus.approved =>
        next.status == GlobalKnowledgeCandidateStatus.approved ||
            next.status == GlobalKnowledgeCandidateStatus.applied ||
            next.status == GlobalKnowledgeCandidateStatus.stale ||
            next.status == GlobalKnowledgeCandidateStatus.failed,
      _ => next.status == previous.status,
    };
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

  Future<IndexRebuildReport> rebuildIndex() {
    return _withWriteLock(_rebuildIndex);
  }

  Future<IndexRebuildReport> _rebuildIndex() async {
    final previous = {
      for (final entry in await _index.listResults()) entry.id: entry,
    };
    final files = await _vault.listMarkdownFiles();
    final results = <IndexedResult>[];
    final diagnostics = <IndexRebuildDiagnostic>[];
    final firstPathById = <String, String>{};
    final duplicateIds = <String>{};
    var scanned = 0;
    for (final path in files) {
      if (!_isManagedMarkdown(path)) {
        continue;
      }
      scanned++;
      final source = await _vault.read(path);
      if (source == null) {
        diagnostics.add(IndexRebuildDiagnostic(path: path, message: '文件读取失败'));
        continue;
      }
      try {
        final document = _codec.decode(source);
        if (!_isSafeResultId(document.id) ||
            document.markdownPath != path.replaceAll('\\', '/')) {
          diagnostics.add(
            IndexRebuildDiagnostic(path: path, message: '成果身份或标准路径不匹配'),
          );
          continue;
        }
        final firstPath = firstPathById[document.id];
        if (firstPath != null) {
          duplicateIds.add(document.id);
          diagnostics.add(
            IndexRebuildDiagnostic(
              path: firstPath,
              message: '成果 ID 与 $path 重复；两份文件均未写入索引',
            ),
          );
          diagnostics.add(
            IndexRebuildDiagnostic(
              path: path,
              message: '成果 ID 与 $firstPath 重复；两份文件均未写入索引',
            ),
          );
          continue;
        }
        firstPathById[document.id] = path;
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
            searchText: _searchText(document),
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
      } on FormatException catch (error) {
        diagnostics.add(
          IndexRebuildDiagnostic(path: path, message: error.message),
        );
        continue;
      } catch (error) {
        diagnostics.add(
          IndexRebuildDiagnostic(path: path, message: '解析失败：$error'),
        );
        continue;
      }
    }
    results.removeWhere((result) => duplicateIds.contains(result.id));
    final nextById = {for (final result in results) result.id: result};
    for (final old in previous.values) {
      if (!nextById.containsKey(old.id)) await _index.removeResult(old.id);
    }
    for (final result in results) {
      final old = previous[result.id];
      if (old == null || !_sameIndexRecord(old, result)) {
        await _index.upsertResult(result);
      }
    }
    return IndexRebuildReport(
      scanned: scanned,
      indexed: results.length,
      diagnostics: List.unmodifiable(diagnostics),
    );
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

  Future<void> waitForWrites() => _writeTail;

  ReversibleResultAction _newReversibleAction({
    required String id,
    required String resultId,
    required ReversibleActionKind kind,
    required ResultDocument document,
    required String markdown,
    required String? previousMarkdown,
    required Duration undoWindow,
  }) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id');
    }
    if (undoWindow <= Duration.zero) {
      throw ArgumentError.value(undoWindow, 'undoWindow');
    }
    final now = DateTime.now();
    return ReversibleResultAction(
      id: id,
      resultId: resultId,
      kind: kind,
      status: ReversibleActionStatus.prepared,
      expectedRevision: document.revision,
      expectedHash: hashMarkdown(markdown),
      previousMarkdown: previousMarkdown,
      previousHash: previousMarkdown == null
          ? null
          : hashMarkdown(previousMarkdown),
      createdAt: now,
      undoUntil: now.add(undoWindow),
    );
  }

  Future<ResultDocument> _readExpectedDocument(
    String id, {
    required int expectedRevision,
    required String expectedHash,
    bool allowDeleted = false,
  }) async {
    final indexed = await _index.findResult(id);
    if (indexed == null || (indexed.deleted && !allowDeleted)) {
      throw StateError('成果不存在或已删除：$id');
    }
    if (indexed.revision != expectedRevision ||
        indexed.localHash != expectedHash) {
      throw StateError('成果版本已变化，请重新检索后再操作：$id');
    }
    final source = await _vault.read(indexed.mdPath);
    if (source == null || hashMarkdown(source) != expectedHash) {
      throw StateError('成果文件版本与索引不一致，请重新加载后再操作：$id');
    }
    final document = _codec.decode(source);
    if (document.id != id ||
        document.revision != expectedRevision ||
        (document.deleted && !allowDeleted)) {
      throw StateError('成果内容版本已变化，请重新检索后再操作：$id');
    }
    return document;
  }

  Future<ResultDocument?> _replayReversibleAction(
    String actionId, {
    required ReversibleActionKind kind,
    required int expectedRevision,
  }) async {
    final action = await _index.findReversibleAction(actionId);
    if (action == null) return null;
    if (action.kind != kind ||
        action.expectedRevision != expectedRevision + 1) {
      throw StateError('动作 ID 已用于另一项成果操作：$actionId');
    }
    if (action.status != ReversibleActionStatus.applied) {
      throw StateError('动作不可重放：$actionId (${action.status.name})');
    }
    return _readExpectedDocument(
      action.resultId,
      expectedRevision: action.expectedRevision,
      expectedHash: action.expectedHash,
      allowDeleted: kind == ReversibleActionKind.delete,
    );
  }

  Future<void> _commitAndIndex(
    ResultDocument document, {
    IdempotentOperation? operation,
    String? rawContents,
    _SyncBaseline? syncBaseline,
    String? reversibleActionId,
    ReversibleActionStatus reversibleActionStatus =
        ReversibleActionStatus.applied,
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
    final reversibleAction = reversibleActionId == null
        ? null
        : await _index.findReversibleAction(reversibleActionId);
    if (reversibleActionId != null &&
        (reversibleAction == null ||
            reversibleAction.resultId != document.id)) {
      throw StateError('成果撤销账本缺失或目标不一致：$reversibleActionId');
    }
    final nextHash = hashMarkdown(markdown);
    if (reversibleActionStatus == ReversibleActionStatus.undone) {
      if (reversibleAction!.status != ReversibleActionStatus.undoing ||
          reversibleAction.undoRevision != document.revision ||
          reversibleAction.undoHash != nextHash) {
        throw StateError('撤销记录与恢复内容不一致：$reversibleActionId');
      }
    } else if (reversibleAction != null &&
        (reversibleAction.status != ReversibleActionStatus.prepared ||
            reversibleAction.expectedRevision != document.revision ||
            reversibleAction.expectedHash != nextHash)) {
      throw StateError('成果操作记录与提交内容不一致：$reversibleActionId');
    }
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
        'reversible_action_id': reversibleActionId,
        'reversible_action_status': reversibleActionId == null
            ? null
            : reversibleActionStatus.name,
      }),
    );

    await _vault.write(document.markdownPath, markdown);
    final committed = await _vault.read(document.markdownPath);
    if (committed == null || hashMarkdown(committed) != nextHash) {
      throw StateError('成果文件提交校验失败：${document.id}');
    }
    await _indexDocument(document, old, nextHash, syncBaseline: syncBaseline);
    if (reversibleActionId != null) {
      final action = await _index.findReversibleAction(reversibleActionId);
      if (action == null || action.resultId != document.id) {
        throw StateError('成果撤销账本与提交日志不匹配：$reversibleActionId');
      }
      await _index.upsertReversibleAction(
        action.copyWith(
          status: reversibleActionStatus,
          previousMarkdown:
              reversibleActionStatus == ReversibleActionStatus.undone
              ? null
              : action.previousMarkdown,
          previousHash: reversibleActionStatus == ReversibleActionStatus.undone
              ? null
              : action.previousHash,
          undoRevision: reversibleActionStatus == ReversibleActionStatus.undone
              ? null
              : action.undoRevision,
          undoHash: reversibleActionStatus == ReversibleActionStatus.undone
              ? null
              : action.undoHash,
          error: null,
        ),
      );
    }
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

  Future<void> _recoverPendingTransactions({DateTime? now}) async {
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
      final reversibleActionId = decoded['reversible_action_id'];
      final reversibleActionStatus = decoded['reversible_action_status'];
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
          (reversibleActionId != null && reversibleActionId is! String) ||
          (reversibleActionStatus != null &&
              (reversibleActionStatus is! String ||
                  !ReversibleActionStatus.values.any(
                    (status) => status.name == reversibleActionStatus,
                  ))) ||
          ((reversibleActionId == null) != (reversibleActionStatus == null)) ||
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
      if (document.id != resultId || document.markdownPath != targetPath) {
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
      if (reversibleActionId is String && reversibleActionStatus is String) {
        final action = await _index.findReversibleAction(reversibleActionId);
        if (action == null || action.resultId != document.id) {
          throw StateError('恢复时缺少成果操作账本：$reversibleActionId');
        }
        final nextStatus = ReversibleActionStatus.values.byName(
          reversibleActionStatus,
        );
        if (nextStatus == ReversibleActionStatus.undone &&
            (action.status != ReversibleActionStatus.undoing ||
                action.undoRevision != document.revision ||
                action.undoHash != expectedHash)) {
          throw StateError('撤销恢复材料与提交日志不匹配：$reversibleActionId');
        }
        if (nextStatus == ReversibleActionStatus.applied &&
            (action.status != ReversibleActionStatus.prepared ||
                action.expectedRevision != document.revision ||
                action.expectedHash != expectedHash)) {
          throw StateError('成果操作恢复材料与提交日志不匹配：$reversibleActionId');
        }
        await _index.upsertReversibleAction(
          action.copyWith(
            status: nextStatus,
            previousMarkdown: nextStatus == ReversibleActionStatus.undone
                ? null
                : action.previousMarkdown,
            previousHash: nextStatus == ReversibleActionStatus.undone
                ? null
                : action.previousHash,
            undoRevision: nextStatus == ReversibleActionStatus.undone
                ? null
                : action.undoRevision,
            undoHash: nextStatus == ReversibleActionStatus.undone
                ? null
                : action.undoHash,
            error: null,
          ),
        );
      }
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
    await _reconcileReversibleActions(now ?? DateTime.now());
  }

  Future<void> _reconcileReversibleActions(DateTime now) async {
    for (final action in await _index.listReversibleActions()) {
      if (action.status == ReversibleActionStatus.applied) {
        if (!action.undoUntil.isAfter(now)) {
          await _index.upsertReversibleAction(
            action.copyWith(
              status: ReversibleActionStatus.expired,
              previousMarkdown: null,
              previousHash: null,
            ),
          );
          continue;
        }
        final current = await _index.findResult(action.resultId);
        if (current == null ||
            current.revision != action.expectedRevision ||
            current.localHash != action.expectedHash) {
          await _index.upsertReversibleAction(
            action.copyWith(
              status: ReversibleActionStatus.failed,
              previousMarkdown: null,
              previousHash: null,
              error: '成果版本已变化，撤销不可用。',
            ),
          );
        }
        continue;
      }
      if (action.status == ReversibleActionStatus.prepared) {
        final current = await _index.findResult(action.resultId);
        final applied =
            current != null &&
            current.revision == action.expectedRevision &&
            current.localHash == action.expectedHash;
        await _index.upsertReversibleAction(
          action.copyWith(
            status: applied
                ? ReversibleActionStatus.applied
                : ReversibleActionStatus.failed,
            previousMarkdown: applied ? action.previousMarkdown : null,
            previousHash: applied ? action.previousHash : null,
            error: applied ? null : '操作未完成，成果版本未提交。',
          ),
        );
        continue;
      }
      if (action.status == ReversibleActionStatus.undoing) {
        final current = await _index.findResult(action.resultId);
        if (current != null &&
            current.revision == action.undoRevision &&
            current.localHash == action.undoHash) {
          await _index.upsertReversibleAction(
            action.copyWith(
              status: ReversibleActionStatus.undone,
              previousMarkdown: null,
              previousHash: null,
              undoRevision: null,
              undoHash: null,
              error: null,
            ),
          );
        } else if (current != null &&
            current.revision == action.expectedRevision &&
            current.localHash == action.expectedHash) {
          await _index.upsertReversibleAction(
            action.copyWith(
              status: ReversibleActionStatus.applied,
              undoRevision: null,
              undoHash: null,
              error: null,
            ),
          );
        } else {
          await _index.upsertReversibleAction(
            action.copyWith(
              status: ReversibleActionStatus.failed,
              previousMarkdown: null,
              previousHash: null,
              undoRevision: null,
              undoHash: null,
              error: '撤销未完成，当前成果版本已变化。',
            ),
          );
        }
      }
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
      searchText: _searchText(document),
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

  String _searchText(ResultDocument document) => [
    document.title,
    document.body,
    ...document.tags,
  ].join('\n').toLowerCase();

  bool _sameIndexRecord(IndexedResult left, IndexedResult right) =>
      left.id == right.id &&
      left.type == right.type &&
      left.title == right.title &&
      left.status == right.status &&
      left.revision == right.revision &&
      left.updatedAt == right.updatedAt &&
      left.deleted == right.deleted &&
      left.mdPath == right.mdPath &&
      left.localHash == right.localHash &&
      left.lastSyncedHash == right.lastSyncedHash &&
      left.remoteEtag == right.remoteEtag &&
      left.matterId == right.matterId &&
      left.syncState == right.syncState &&
      left.searchText == right.searchText;

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
        jsonEncode(_stableExtensionFields(left.extensionFields)) ==
            jsonEncode(_stableExtensionFields(right.extensionFields)) &&
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
      'extensions': _stableExtensionFields(document.extensionFields),
    });
    return 'sha256:${sha256.convert(utf8.encode(payload))}';
  }

  Map<String, Object?> _stableExtensionFields(Map<String, Object?> fields) => {
    for (final key in fields.keys.toList()..sort())
      key: _stableExtensionValue(fields[key]),
  };

  Object? _stableExtensionValue(Object? value) {
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is List) {
      return value.map(_stableExtensionValue).toList(growable: false);
    }
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _stableExtensionValue(value[key])};
    }
    return value;
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
