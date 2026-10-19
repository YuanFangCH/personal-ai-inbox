import '../core/models.dart';
import 'index_database.dart';

class MemoryIndexDatabase implements IndexDatabase {
  final Map<String, IndexedResult> _results = {};
  final Map<String, CaptureRecord> _captures = {};
  final Map<String, IdempotentOperation> _operations = {};
  final Map<String, SyncConflictRecord> _conflicts = {};
  final Map<String, ReversibleResultAction> _reversibleActions = {};

  @override
  Future<void> open() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> upsertResult(IndexedResult result) async {
    _results[result.id] = result;
  }

  @override
  Future<void> removeResult(String id) async {
    _results.remove(id);
  }

  @override
  Future<List<IndexedResult>> listResults() async {
    return _results.values.toList(growable: false);
  }

  @override
  Future<List<IndexedResult>> searchResults({
    required String query,
    required int limit,
    required int offset,
    ResultType? type,
  }) async {
    final normalized = query.trim().toLowerCase();
    final matches =
        _results.values
            .where(
              (result) =>
                  !result.deleted &&
                  result.status == ResultStatus.canonical &&
                  (type == null || result.type == type) &&
                  (normalized.isEmpty ||
                      result.searchText.contains(normalized)),
            )
            .toList()
          ..sort((left, right) {
            final byTime = right.updatedAt.compareTo(left.updatedAt);
            return byTime != 0 ? byTime : left.id.compareTo(right.id);
          });
    if (offset >= matches.length) return const [];
    return matches.skip(offset).take(limit).toList(growable: false);
  }

  @override
  Future<IndexedResult?> findResult(String id) async => _results[id];

  @override
  Future<void> replaceResults(List<IndexedResult> results) async {
    _results
      ..clear()
      ..addEntries(results.map((result) => MapEntry(result.id, result)));
  }

  @override
  Future<void> insertCapture(CaptureRecord capture) async {
    _captures[capture.id] = capture;
  }

  @override
  Future<void> updateCapture(CaptureRecord capture) async {
    _captures[capture.id] = capture;
  }

  @override
  Future<List<CaptureRecord>> listCaptures({bool reviewOnly = false}) async {
    final values = _captures.values.where(
      (capture) => !reviewOnly || capture.status == CaptureStatus.needsReview,
    );
    return values.toList(growable: false);
  }

  @override
  Future<void> deleteCapture(String id) async {
    _captures.remove(id);
  }

  @override
  Future<void> clear() async {
    _results.clear();
    _captures.clear();
  }

  @override
  Future<IdempotentOperation?> findOperation(String key) async =>
      _operations[key];

  @override
  Future<void> upsertOperation(IdempotentOperation operation) async {
    _operations[operation.key] = operation;
  }

  @override
  Future<List<IdempotentOperation>> listIncompleteOperations() async {
    return _operations.values
        .where((operation) => operation.state != OperationState.completed)
        .toList(growable: false);
  }

  @override
  Future<ReversibleResultAction?> findReversibleAction(String id) async =>
      _reversibleActions[id];

  @override
  Future<List<ReversibleResultAction>> listReversibleActions() async =>
      _reversibleActions.values.toList(growable: false);

  @override
  Future<void> upsertReversibleAction(ReversibleResultAction action) async {
    _reversibleActions[action.id] = action;
  }

  @override
  Future<void> removeReversibleAction(String id) async {
    _reversibleActions.remove(id);
  }

  @override
  Future<SyncConflictRecord?> findConflict(String resultId) async =>
      _conflicts[resultId];

  @override
  Future<void> upsertConflict(SyncConflictRecord conflict) async {
    _conflicts[conflict.resultId] = conflict;
  }

  @override
  Future<void> removeConflict(String resultId) async {
    _conflicts.remove(resultId);
  }

  @override
  Future<List<SyncConflictRecord>> listConflicts() async =>
      _conflicts.values.toList(growable: false);
}
