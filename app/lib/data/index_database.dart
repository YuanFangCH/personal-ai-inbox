import '../core/models.dart';
import '../core/table_models.dart';

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
    bool globalKnowledgeOnly = false,
  });

  Future<IndexedResult?> findResult(String id);

  Future<void> replaceResults(List<IndexedResult> results);

  Future<void> upsertTable(IndexedTable table);

  Future<void> removeTable(String id);

  Future<IndexedTable?> findTable(String id);

  Future<List<IndexedTable>> listTables({bool includeDeleted = false});

  Future<List<IndexedTable>> searchTables({
    required String query,
    required int limit,
    required int offset,
    bool includeDeleted = false,
  });

  Future<void> upsertTableEntry(IndexedTableEntry entry);

  Future<void> removeTableEntry(String id);

  Future<IndexedTableEntry?> findTableEntry(String id);

  Future<List<IndexedTableEntry>> listTableEntries({
    String? tableId,
    TableContentType? type,
    bool includeDeleted = false,
  });

  Future<List<IndexedTableEntry>> searchTableEntries({
    required String query,
    required int limit,
    required int offset,
    String? tableId,
    TableContentType? type,
    DateTime? from,
    DateTime? through,
    Map<String, Object?> fieldFilters = const {},
    bool includeDeleted = false,
  });

  Future<void> upsertTableRecoveryBatch(TableRecoveryBatch batch);

  Future<TableRecoveryBatch?> findTableRecoveryBatch(String id);

  Future<List<TableRecoveryBatch>> listTableRecoveryBatches({
    bool activeOnly = false,
  });

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

class IndexedTable {
  const IndexedTable({
    required this.id,
    required this.role,
    required this.title,
    required this.revision,
    required this.updatedAt,
    required this.deleted,
    required this.mdPath,
    required this.localHash,
    required this.searchText,
  });

  final String id;
  final TableRole role;
  final String title;
  final int revision;
  final DateTime updatedAt;
  final bool deleted;
  final String mdPath;
  final String localHash;
  final String searchText;
}

class IndexedTableEntry {
  const IndexedTableEntry({
    required this.id,
    required this.type,
    required this.tableId,
    required this.title,
    required this.revision,
    required this.updatedAt,
    required this.deleted,
    required this.mdPath,
    required this.localHash,
    required this.searchText,
    required this.customValuesJson,
    this.businessAt,
    this.done = false,
  });

  final String id;
  final TableContentType type;
  final String tableId;
  final String title;
  final int revision;
  final DateTime updatedAt;
  final DateTime? businessAt;
  final bool done;
  final bool deleted;
  final String mdPath;
  final String localHash;
  final String searchText;
  final String customValuesJson;
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
