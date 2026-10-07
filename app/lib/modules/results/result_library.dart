import 'package:flutter/foundation.dart';

import '../../core/models.dart';
import '../../data/result_repository.dart';

/// Application-layer-only access owned by modules that coordinate results.
///
/// UI code must use [ResultLibrary] and its immutable snapshots instead of
/// importing or calling this interface.
abstract interface class ResultLibraryInternal {
  Future<List<String>> listConflictFiles();

  Future<String?> readRaw(String path);

  Future<void> writeRaw(String path, String contents);

  Future<void> deleteRaw(String path);
}

/// Returns the application-layer access surface for [library].
///
/// This is intentionally a free function instead of a public getter on
/// [ResultLibrary], keeping raw storage behavior out of the UI-facing class.
ResultLibraryInternal resultLibraryInternal(ResultLibrary library) {
  return library._internal;
}

/// Deep application module for the Markdown-backed result library.
///
/// The module owns the immutable read model visible to the rest of the app.
/// Markdown parsing, SQLite indexing, revision handling, tombstones and raw
/// conflict files remain behind [ResultRepository].
class ResultLibrary extends ChangeNotifier {
  ResultLibrary({required ResultRepository repository})
    : _repository = repository,
      _internal = _ResultLibraryInternal(repository);

  final ResultRepository _repository;
  final ResultLibraryInternal _internal;

  List<ResultDocument> _documents = const [];
  List<ResultDocument> _canonicalDocuments = const [];
  List<ResultDocument> _draftDocuments = const [];
  List<ResultDocument> _todos = const [];
  List<ResultDocument> _events = const [];
  List<ResultDocument> _matters = const [];
  List<ResultDocument> _knowledge = const [];
  String _vaultRoot = '';

  List<ResultDocument> get documents => _documents;

  List<ResultDocument> get canonicalDocuments => _canonicalDocuments;

  List<ResultDocument> get draftDocuments => _draftDocuments;

  List<ResultDocument> get todos => _todos;

  List<ResultDocument> get events => _events;

  List<ResultDocument> get matters => _matters;

  List<ResultDocument> get knowledge => _knowledge;

  String get vaultRoot => _vaultRoot;

  ResultDocument? findDocument(String id) {
    for (final document in _documents) {
      if (document.id == id) {
        return document;
      }
    }
    return null;
  }

  Future<void> initialize() async {
    await _repository.initialize();
    await refresh();
  }

  Future<void> refresh() async {
    final documents = await _repository.listDocuments(includeDeleted: false);
    final frozen = List<ResultDocument>.unmodifiable(
      documents.map(_freezeDocument),
    );
    final canonical = List<ResultDocument>.unmodifiable(
      frozen.where((document) => document.status == ResultStatus.canonical),
    );

    _documents = frozen;
    _canonicalDocuments = canonical;
    _draftDocuments = List<ResultDocument>.unmodifiable(
      frozen.where((document) => document.status == ResultStatus.draft),
    );
    _todos = List<ResultDocument>.unmodifiable(
      canonical.where((document) => document.type == ResultType.todo),
    );
    _events = List<ResultDocument>.unmodifiable(
      canonical.where((document) => document.type == ResultType.event),
    );
    _matters = List<ResultDocument>.unmodifiable(
      canonical.where((document) => document.type == ResultType.matter),
    );
    _knowledge = List<ResultDocument>.unmodifiable(
      canonical.where((document) => document.type == ResultType.knowledge),
    );
    _vaultRoot = await _repository.describeVaultRoot();
    notifyListeners();
  }

  Future<ResultDocument> createManual({
    required ResultType type,
    required String title,
    String body = '',
    ResultStatus status = ResultStatus.canonical,
    DateTime? due,
    String? matterId,
    DateTime? start,
    DateTime? end,
    bool allDay = false,
    String? recurrence,
    List<String> tags = const [],
  }) async {
    final document = await _repository.create(
      type: type,
      title: title,
      body: body,
      status: status,
      due: due,
      matterId: matterId,
      start: start,
      end: end,
      allDay: allDay,
      recurrence: recurrence,
      tags: tags,
    );
    await refresh();
    return document;
  }

  Future<void> saveDocument(ResultDocument document) async {
    await _repository.save(document);
    await refresh();
  }

  Future<void> toggleTodo(ResultDocument document, bool done) async {
    await _repository.markTodo(document, done);
    await refresh();
  }

  Future<void> deleteDocument(String id) async {
    await _repository.delete(id);
    await refresh();
  }

  /// Creates a canonical result from a captured or model-produced candidate.
  ///
  /// This is an application-layer capability for capture and auto-record
  /// coordinators. UI code should use [createManual] instead.
  Future<ResultDocument> createFromCandidate(
    ClassificationCandidate candidate,
  ) async {
    final document = await _repository.create(
      type: candidate.type,
      title: candidate.title,
      body: candidate.summary,
      status: ResultStatus.canonical,
      tags: candidate.tags,
      due: candidate.type == ResultType.todo ? candidate.due : null,
      start: candidate.type == ResultType.event ? candidate.start : null,
      end: candidate.type == ResultType.event ? candidate.end : null,
      allDay: candidate.allDay,
      recurrence: candidate.recurrence,
    );
    await refresh();
    return document;
  }

  Future<void> rebuildIndex() async {
    await _repository.rebuildIndex();
    await refresh();
  }

  ResultDocument _freezeDocument(ResultDocument document) {
    return document.copyWith(
      tags: List<String>.unmodifiable(document.tags),
      links: List<String>.unmodifiable(document.links),
      sourceEventIds: List<String>.unmodifiable(document.sourceEventIds),
      sourceHashes: List<String>.unmodifiable(document.sourceHashes),
    );
  }
}

class _ResultLibraryInternal implements ResultLibraryInternal {
  _ResultLibraryInternal(this._repository);

  final ResultRepository _repository;

  @override
  Future<List<String>> listConflictFiles() => _repository.listConflictFiles();

  @override
  Future<String?> readRaw(String path) => _repository.readRaw(path);

  @override
  Future<void> writeRaw(String path, String contents) {
    return _repository.writeRaw(path, contents);
  }

  @override
  Future<void> deleteRaw(String path) => _repository.deleteRaw(path);
}
