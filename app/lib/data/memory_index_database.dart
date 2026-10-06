import '../core/models.dart';
import 'index_database.dart';

class MemoryIndexDatabase implements IndexDatabase {
  final Map<String, IndexedResult> _results = {};
  final Map<String, CaptureRecord> _captures = {};

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
}
