import 'package:flutter/foundation.dart';

import '../../core/table_models.dart';
import '../../data/table_repository.dart';

/// Immutable UI-facing snapshots for notebook tables and their entries.
/// Writes always pass through [TableRepository].
class TableLibrary extends ChangeNotifier {
  TableLibrary({required TableRepository repository})
    : _repository = repository;

  final TableRepository _repository;
  List<TableDocument> _tables = const [];
  List<TableEntryDocument> _entries = const [];

  List<TableDocument> get tables => _tables;
  List<TableEntryDocument> get entries => _entries;

  TableDocument? findTable(String id) {
    for (final table in _tables) {
      if (table.id == id) return table;
    }
    return null;
  }

  Future<void> initialize() async {
    await _repository.initialize();
    await refresh();
  }

  Future<void> refresh({String? tableId}) async {
    await _repository.purgeExpiredRecoveryBatches();
    _tables = List.unmodifiable(await _repository.listTables());
    _entries = List.unmodifiable(
      await _repository.listEntries(tableId: tableId),
    );
    notifyListeners();
  }

  Future<List<TableRecoveryBatch>> recoveryBatches() =>
      _repository.recoveryBatches();

  Future<TableRecoveryPreview?> previewDeletedTable(String batchId) =>
      _repository.previewDeletedTable(batchId);

  Future<List<TableRecoveryBatch>> fieldChangeRecoveryBatches({
    String? tableId,
  }) => _repository.fieldChangeRecoveryBatches(tableId: tableId);

  Future<List<TableDocument>> searchTables({
    required String query,
    int offset = 0,
    int limit = 50,
  }) => _repository.searchTables(query: query, offset: offset, limit: limit);

  Future<TableDocument> createTable({
    String? id,
    required String title,
    String body = '',
  }) async {
    final table = await _repository.createTable(
      id: id,
      title: title,
      body: body,
    );
    await refresh();
    return table;
  }

  Future<TableDocument> updateTable(
    TableDocument table, {
    required int expectedRevision,
  }) async {
    final updated = await _repository.updateTable(
      table,
      expectedRevision: expectedRevision,
    );
    await refresh();
    return updated;
  }

  Future<TableRecoveryBatch> removeTableField({
    required String tableId,
    required String fieldId,
    required int expectedRevision,
    String? idempotencyKey,
    DateTime? now,
  }) async {
    final batch = await _repository.removeTableField(
      tableId: tableId,
      fieldId: fieldId,
      expectedRevision: expectedRevision,
      idempotencyKey: idempotencyKey,
      now: now,
    );
    await refresh();
    return batch;
  }

  Future<TableEntryDocument> createEntry(TableEntryDocument entry) async {
    final created = await _repository.createEntry(entry);
    await refresh();
    return created;
  }

  Future<TableEntryDocument> updateEntry(
    TableEntryDocument entry, {
    required int expectedRevision,
  }) async {
    final updated = await _repository.updateEntry(
      entry,
      expectedRevision: expectedRevision,
    );
    await refresh();
    return updated;
  }

  Future<TableEntryDocument> moveEntry({
    required String id,
    required String tableId,
    required int expectedRevision,
    Map<String, String> fieldMapping = const {},
    Map<String, Map<String, String>> optionMapping = const {},
  }) async {
    final moved = await _repository.moveEntry(
      id: id,
      tableId: tableId,
      expectedRevision: expectedRevision,
      fieldMapping: fieldMapping,
      optionMapping: optionMapping,
    );
    await refresh();
    return moved;
  }

  Future<ScheduleChangeResult> changeScheduleFromEvent({
    required String scheduleId,
    required int expectedRevision,
    required DateTime start,
    DateTime? end,
    required String eventTitle,
    required String eventBody,
    required String idempotencyKey,
    DateTime? eventOccurredAt,
    DateTime? now,
  }) async {
    final result = await _repository.changeScheduleFromEvent(
      scheduleId: scheduleId,
      expectedRevision: expectedRevision,
      start: start,
      end: end,
      eventTitle: eventTitle,
      eventBody: eventBody,
      idempotencyKey: idempotencyKey,
      eventOccurredAt: eventOccurredAt,
      now: now,
    );
    await refresh();
    return result;
  }

  Future<List<TableEntryDocument>> searchEntries({
    required String query,
    String? tableId,
    TableContentType? type,
    DateTime? from,
    DateTime? through,
    Map<String, Object?> fieldFilters = const {},
    int offset = 0,
    int limit = 50,
  }) => _repository.searchEntries(
    query: query,
    tableId: tableId,
    type: type,
    from: from,
    through: through,
    fieldFilters: fieldFilters,
    offset: offset,
    limit: limit,
  );

  Future<TableEntryDocument?> readEntry(String id) => _repository.readEntry(id);

  Future<TableRecoveryBatch> deleteEntry({
    required String id,
    required int expectedRevision,
    String? idempotencyKey,
    DateTime? now,
  }) async {
    final batch = await _repository.deleteEntry(
      id: id,
      expectedRevision: expectedRevision,
      idempotencyKey: idempotencyKey,
      now: now,
    );
    await refresh();
    return batch;
  }

  Future<TableRecoveryBatch> deleteTable({
    required String id,
    required int expectedRevision,
    String? idempotencyKey,
    DateTime? now,
  }) async {
    final batch = await _repository.deleteTable(
      id: id,
      expectedRevision: expectedRevision,
      idempotencyKey: idempotencyKey,
      now: now,
    );
    await refresh();
    return batch;
  }

  Future<TableRecoveryBatch> restoreRecoveryBatch(
    String id, {
    DateTime? now,
  }) async {
    final batch = await _repository.restoreRecoveryBatch(id, now: now);
    await refresh();
    return batch;
  }
}
