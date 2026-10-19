import '../core/models.dart';

abstract interface class IndexDatabase {
  Future<void> open();

  Future<void> close();

  Future<void> upsertResult(IndexedResult result);

  Future<void> removeResult(String id);

  Future<List<IndexedResult>> listResults();

  Future<List<IndexedResult>> searchResults({
    required String query,
    required int limit,
    required int offset,
    ResultType? type,
  });

  Future<IndexedResult?> findResult(String id);

  Future<void> replaceResults(List<IndexedResult> results);

  Future<void> insertCapture(CaptureRecord capture);

  Future<void> updateCapture(CaptureRecord capture);

  Future<List<CaptureRecord>> listCaptures({bool reviewOnly = false});

  Future<void> deleteCapture(String id);

  Future<void> clear();

  Future<IdempotentOperation?> findOperation(String key);

  Future<void> upsertOperation(IdempotentOperation operation);

  Future<List<IdempotentOperation>> listIncompleteOperations();

  Future<ReversibleResultAction?> findReversibleAction(String id);

  Future<List<ReversibleResultAction>> listReversibleActions();

  Future<void> upsertReversibleAction(ReversibleResultAction action);

  Future<void> removeReversibleAction(String id);

  Future<GlobalKnowledgeCandidate?> findGlobalKnowledgeCandidate(String id);

  Future<List<GlobalKnowledgeCandidate>> listGlobalKnowledgeCandidates();

  Future<void> upsertGlobalKnowledgeCandidate(
    GlobalKnowledgeCandidate candidate,
  );

  Future<SyncConflictRecord?> findConflict(String resultId);

  Future<void> upsertConflict(SyncConflictRecord conflict);

  Future<void> removeConflict(String resultId);

  Future<List<SyncConflictRecord>> listConflicts();
}

enum OperationState {
  prepared('prepared'),
  resultCommitted('resultCommitted'),
  completed('completed');

  const OperationState(this.wireName);

  final String wireName;
}

class IdempotentOperation {
  const IdempotentOperation({
    required this.key,
    required this.resultId,
    required this.payloadHash,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
  });

  final String key;
  final String resultId;
  final String payloadHash;
  final OperationState state;
  final DateTime createdAt;
  final DateTime updatedAt;

  IdempotentOperation copyWith({OperationState? state, DateTime? updatedAt}) {
    return IdempotentOperation(
      key: key,
      resultId: resultId,
      payloadHash: payloadHash,
      state: state ?? this.state,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class SyncConflictRecord {
  const SyncConflictRecord({
    required this.resultId,
    required this.remoteHash,
    required this.remoteEtag,
    required this.localHash,
    required this.copyPath,
    required this.createdAt,
  });

  final String resultId;
  final String remoteHash;
  final String remoteEtag;
  final String localHash;
  final String copyPath;
  final DateTime createdAt;
}
