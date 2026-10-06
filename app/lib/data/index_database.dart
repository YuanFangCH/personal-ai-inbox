import '../core/models.dart';

abstract interface class IndexDatabase {
  Future<void> open();

  Future<void> close();

  Future<void> upsertResult(IndexedResult result);

  Future<void> removeResult(String id);

  Future<List<IndexedResult>> listResults();

  Future<IndexedResult?> findResult(String id);

  Future<void> replaceResults(List<IndexedResult> results);

  Future<void> insertCapture(CaptureRecord capture);

  Future<void> updateCapture(CaptureRecord capture);

  Future<List<CaptureRecord>> listCaptures({bool reviewOnly = false});

  Future<void> deleteCapture(String id);

  Future<void> clear();
}
