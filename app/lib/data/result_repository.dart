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

  Future<void> initialize() async {
    await _vault.initialize();
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

  Future<ResultDocument?> readDocument(String id) async {
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
  }) async {
    final timestamp = createdAt ?? DateTime.now();
    final id = _newId(type, timestamp);
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
    await _writeAndIndex(document);
    return document;
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

  Future<void> updateIndex(IndexedResult result) => _index.upsertResult(result);

  Future<void> rebuildIndex() async {
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

  Future<void> writeConflictCopy(String id, String contents) async {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '');
    final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    await _vault.write(
      'vault/conflicts/$safeId.conflict-$timestamp.md',
      contents,
    );
  }

  Future<List<String>> listConflictFiles() async {
    final files = await _vault.listMarkdownFiles();
    return files
        .where((path) => path.startsWith('vault/conflicts/'))
        .toList(growable: false);
  }

  Future<String?> readRaw(String path) => _vault.read(path);

  Future<void> writeRaw(String path, String contents) =>
      _vault.write(path, contents);

  Future<void> deleteRaw(String path) => _vault.delete(path);

  Future<void> resolveConflictUsingRemote(String conflictPath) async {
    final source = await _vault.read(conflictPath);
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
    await _vault.delete(conflictPath);
  }

  Future<void> keepLocalConflict(String conflictPath) async {
    await _vault.delete(conflictPath);
  }

  Future<String> describeVaultRoot() => _vault.describeRoot();

  String hashMarkdown(String contents) {
    return 'sha256:${sha256.convert(utf8.encode(contents))}';
  }

  Future<void> _writeAndIndex(ResultDocument document) async {
    final old = await _index.findResult(document.id);
    if (old != null && old.mdPath != document.markdownPath) {
      await _vault.delete(old.mdPath);
    }
    final markdown = _codec.encode(document);
    await _vault.write(document.markdownPath, markdown);
    final hash = hashMarkdown(markdown);
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
      lastSyncedHash: old?.lastSyncedHash,
      remoteEtag: old?.remoteEtag,
      matterId: document.matterId,
      syncState: document.deleted
          ? SyncState.deleted
          : hash == old?.lastSyncedHash
          ? SyncState.synced
          : SyncState.pendingUpload,
    );
    await _index.upsertResult(record);
  }

  bool _isManagedMarkdown(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.startsWith('vault/matters/') ||
        normalized.startsWith('vault/todos/') ||
        normalized.startsWith('vault/calendar/') ||
        normalized.startsWith('vault/knowledge/');
  }

  String _newId(ResultType type, DateTime timestamp) {
    final prefix = switch (type) {
      ResultType.matter => 'mt',
      ResultType.todo => 'td',
      ResultType.event => 'ev',
      ResultType.knowledge => 'kn',
    };
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
