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
    _tables = List.unmodifiable(await _repository.listTables());
    _entries = List.unmodifiable(
      await _repository.listEntries(tableId: tableId),
    );
    notifyListeners();
  }

  Future<List<TableDocument>> searchTables({
    required String query,
    int offset = 0,
    int limit = 50,
  }) => _repository.searchTables(query: query, offset: offset, limit: limit);

  Future<TableDocument> createTable({
    required String title,
    String body = '',
  }) async {
    final table = await _repository.createTable(title: title, body: body);
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

  Future<TableEntryDocument> createEntry(TableEntryDocument entry) async {
    final created = await _repository.createEntry(entry);
    await refresh(tableId: entry.tableId);
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
    await refresh(tableId: updated.tableId);
    return updated;
  }

  Future<TableEntryDocument> moveEntry({
    required String id,
    required String tableId,
    required int expectedRevision,
  }) async {
    final moved = await _repository.moveEntry(
      id: id,
      tableId: tableId,
      expectedRevision: expectedRevision,
    );
    await refresh(tableId: tableId);
    return moved;
  }

  Future<List<TableEntryDocument>> searchEntries({
    required String query,
    String? tableId,
    TableContentType? type,
    DateTime? from,
    DateTime? through,
    int offset = 0,
    int limit = 50,
  }) => _repository.searchEntries(
    query: query,
    tableId: tableId,
    type: type,
    from: from,
    through: through,
    offset: offset,
    limit: limit,
  );
}
