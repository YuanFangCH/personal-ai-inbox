import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../core/models.dart';
import '../core/table_markdown_codec.dart';
import '../core/table_models.dart';
import 'index_database.dart';
import 'vault_store.dart';

/// Markdown is authoritative; this repository owns the table paths and their
/// rebuildable SQLite projection.
class TableRepository {
  TableRepository({
    required VaultStore vault,
    required IndexDatabase index,
    TableMarkdownCodec codec = const TableMarkdownCodec(),
    this.deviceId = 'local',
  }) : _vault = vault,
       _index = index,
       _codec = codec;

  static const defaultTables = <(String, TableRole, String)>[
    ('tb_default_todo', TableRole.inboxTodo, '待办'),
    ('tb_default_schedule', TableRole.inboxSchedule, '日程'),
    ('tb_default_event', TableRole.inboxEvent, '事件'),
  ];

  static const _uuid = Uuid();
  final VaultStore _vault;
  final IndexDatabase _index;
  final TableMarkdownCodec _codec;
  final String deviceId;

  Future<void> initialize() async {
    await _vault.initialize();
    await ensureDefaultTables();
    await rebuildIndex();
  }

  Future<void> ensureDefaultTables() async {
    await _vault.exclusive(() async {
      for (final (id, role, title) in defaultTables) {
        final path = tablePath(id);
        final source = await _vault.read(path);
        if (source == null) {
          final now = DateTime.now();
          final table = TableDocument(
            id: id,
            role: role,
            title: title,
            revision: 1,
            createdAt: now,
            updatedAt: now,
            body: '',
          );
          await _writeAndIndexTable(table, previous: null);
          continue;
        }
        final table = _codec.decodeTable(source);
        if (table.id != id || table.role != role || table.deleted) {
          throw StateError('默认表角色或身份冲突：$id');
        }
      }
    });
  }

  Future<IndexRebuildReport> rebuildIndex() async {
    final diagnostics = <IndexRebuildDiagnostic>[];
    final validTableIds = <String>{};
    final invalidTableIds = <String>{};
    final validEntryIds = <String>{};
    final invalidEntryIds = <String>{};
    final pendingEntries = <(TableEntryDocument, String, String)>[];
    var scanned = 0;
    var indexed = 0;
    final paths = await _vault.exclusive(_vault.listMarkdownFiles);
    for (final path in paths) {
      if (!path.startsWith('vault/tables/') &&
          !path.startsWith('vault/items/')) {
        continue;
      }
      scanned++;
      try {
        await _vault.exclusive(() async {
          final source = await _vault.read(path);
          if (source == null) return;
          if (path.startsWith('vault/tables/')) {
            final table = _codec.decodeTable(source);
            if (path != tablePath(table.id)) {
              throw const FormatException('表文件路径和 ID 不一致');
            }
            await _index.upsertTable(_indexTable(table, source));
            validTableIds.add(table.id);
            indexed++;
          } else {
            final entry = _codec.decodeEntry(source);
            if (path != entryPath(entry.id)) {
              throw const FormatException('内容文件路径和 ID 不一致');
            }
            pendingEntries.add((entry, source, path));
          }
        });
      } on Object catch (error) {
        final filename = path.split('/').last;
        final id = filename.endsWith('.md')
            ? filename.substring(0, filename.length - 3)
            : '';
        if (path.startsWith('vault/tables/')) {
          invalidTableIds.add(id);
        } else {
          invalidEntryIds.add(id);
        }
        diagnostics.add(IndexRebuildDiagnostic(path: path, message: '$error'));
      }
    }
    for (final (entry, source, path) in pendingEntries) {
      final owner = invalidTableIds.contains(entry.tableId)
          ? null
          : await _index.findTable(entry.tableId);
      if (owner == null || owner.deleted) {
        invalidEntryIds.add(entry.id);
        diagnostics.add(
          IndexRebuildDiagnostic(path: path, message: '所属表缺失、无效或已删除；未写入内容索引'),
        );
        continue;
      }
      await _index.upsertTableEntry(_indexEntry(entry, source));
      validEntryIds.add(entry.id);
      indexed++;
    }
    for (final row in await _index.listTables(includeDeleted: true)) {
      if (!validTableIds.contains(row.id) &&
          !invalidTableIds.contains(row.id)) {
        await _index.removeTable(row.id);
      }
    }
    for (final row in await _index.listTableEntries(includeDeleted: true)) {
      if (!validEntryIds.contains(row.id) &&
          !invalidEntryIds.contains(row.id)) {
        await _index.removeTableEntry(row.id);
      }
    }
    return IndexRebuildReport(
      scanned: scanned,
      indexed: indexed,
      diagnostics: List.unmodifiable(diagnostics),
    );
  }

  Future<List<TableDocument>> listTables({bool includeDeleted = false}) async {
    final rows = await _index.listTables(includeDeleted: includeDeleted);
    final tables = <TableDocument>[];
    for (final row in rows) {
      final table = await readTable(row.id);
      if (table != null && (includeDeleted || !table.deleted)) {
        tables.add(table);
      }
    }
    return List.unmodifiable(tables);
  }

  Future<List<TableDocument>> searchTables({
    required String query,
    int offset = 0,
    int limit = 50,
  }) async {
    final rows = await _index.searchTables(
      query: query,
      offset: offset,
      limit: limit,
    );
    final tables = <TableDocument>[];
    for (final row in rows) {
      final table = await readTable(row.id);
      if (table != null && !table.deleted) tables.add(table);
    }
    return List.unmodifiable(tables);
  }

  Future<TableDocument?> readTable(String id) =>
      _vault.exclusive(() => _readTableUnlocked(id));

  Future<TableDocument?> _readTableUnlocked(String id) async {
    final source = await _vault.read(tablePath(id));
    if (source == null) return null;
    final table = _codec.decodeTable(source);
    if (table.id != id) {
      throw const FormatException('Table path and ID mismatch');
    }
    return table;
  }

  Future<TableDocument> createTable({
    required String title,
    String body = '',
  }) async {
    final now = DateTime.now();
    final table = TableDocument(
      id: 'tb_${_uuid.v4()}',
      role: TableRole.custom,
      title: title,
      revision: 1,
      createdAt: now,
      updatedAt: now,
      body: body,
    );
    await _vault.exclusive(() async {
      if (await _vault.read(tablePath(table.id)) != null) {
        throw StateError('表 ID 已存在：${table.id}');
      }
      await _writeAndIndexTable(table, previous: null);
    });
    return table;
  }

  Future<TableDocument> updateTable(
    TableDocument proposed, {
    required int expectedRevision,
  }) async => _vault.exclusive(() async {
    final path = tablePath(proposed.id);
    final source = await _vault.read(path);
    if (source == null) throw StateError('表不存在：${proposed.id}');
    final current = _codec.decodeTable(source);
    _checkRevision(current.revision, expectedRevision);
    if (current.role != proposed.role) {
      throw StateError('不能修改表的默认角色');
    }
    for (final row in await _index.listTableEntries(tableId: current.id)) {
      final entrySource = await _vault.read(entryPath(row.id));
      if (entrySource == null) continue;
      final entry = _codec.decodeEntry(entrySource);
      _codec.encodeEntry(entry, fields: proposed.fields);
    }
    final updated = proposed.copyWith(
      revision: current.revision + 1,
      updatedAt: DateTime.now(),
    );
    await _writeAndIndexTable(updated, previous: source);
    return updated;
  });

  Future<List<TableEntryDocument>> listEntries({
    String? tableId,
    TableContentType? type,
    bool includeDeleted = false,
  }) async {
    final rows = await _index.listTableEntries(
      tableId: tableId,
      type: type,
      includeDeleted: includeDeleted,
    );
    final entries = <TableEntryDocument>[];
    for (final row in rows) {
      final entry = await readEntry(row.id);
      if (entry != null && (includeDeleted || !entry.deleted)) {
        entries.add(entry);
      }
    }
    return List.unmodifiable(entries);
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
  }) async {
    final rows = await _index.searchTableEntries(
      query: query,
      tableId: tableId,
      type: type,
      from: from,
      through: through,
      fieldFilters: fieldFilters,
      offset: offset,
      limit: limit,
    );
    final entries = <TableEntryDocument>[];
    for (final row in rows) {
      final entry = await readEntry(row.id);
      if (entry != null && !entry.deleted) entries.add(entry);
    }
    return List.unmodifiable(entries);
  }

  Future<TableEntryDocument?> readEntry(String id) async {
    final source = await _vault.exclusive(() => _vault.read(entryPath(id)));
    if (source == null) return null;
    final entry = _codec.decodeEntry(source);
    if (entry.id != id) {
      throw const FormatException('Entry path and ID mismatch');
    }
    return entry;
  }

  Future<TableEntryDocument> createEntry(TableEntryDocument entry) async =>
      _vault.exclusive(() async {
        if (await _vault.read(entryPath(entry.id)) != null) {
          throw StateError('内容 ID 已存在：${entry.id}');
        }
        await _requireWritableTableUnlocked(entry.tableId);
        final table = await _readTableUnlocked(entry.tableId);
        if (table == null) throw StateError('所属表不存在：${entry.tableId}');
        final source = _codec.encodeEntry(entry, fields: table.fields);
        await _writeAndIndexEntry(entry, source, previous: null);
        return entry;
      });

  Future<TableEntryDocument> updateEntry(
    TableEntryDocument proposed, {
    required int expectedRevision,
  }) async => _vault.exclusive(() async {
    final path = entryPath(proposed.id);
    final previous = await _vault.read(path);
    if (previous == null) throw StateError('内容不存在：${proposed.id}');
    final current = _codec.decodeEntry(previous);
    _checkRevision(current.revision, expectedRevision);
    await _requireWritableTableUnlocked(proposed.tableId);
    final table = await _readTableUnlocked(proposed.tableId);
    if (table == null) throw StateError('所属表不存在：${proposed.tableId}');
    final updated = proposed.copyWith(
      revision: current.revision + 1,
      updatedAt: DateTime.now(),
    );
    final source = _codec.encodeEntry(updated, fields: table.fields);
    await _writeAndIndexEntry(updated, source, previous: previous);
    return updated;
  });

  Future<TableEntryDocument> moveEntry({
    required String id,
    required String tableId,
    required int expectedRevision,
  }) async {
    final current = await readEntry(id);
    if (current == null) throw StateError('内容不存在：$id');
    return updateEntry(
      current.copyWith(tableId: tableId),
      expectedRevision: expectedRevision,
    );
  }

  Future<void> _requireWritableTableUnlocked(String id) async {
    final table = await _readTableUnlocked(id);
    if (table == null || table.deleted) throw StateError('表不存在或已删除：$id');
  }

  Future<void> _writeAndIndexTable(
    TableDocument table, {
    required String? previous,
  }) async {
    final path = tablePath(table.id);
    final encoded = _codec.encodeTable(table);
    await _vault.write(path, encoded);
    try {
      await _index.upsertTable(_indexTable(table, encoded));
    } catch (_) {
      if (previous == null) {
        await _vault.delete(path);
      } else {
        await _vault.write(path, previous);
      }
      rethrow;
    }
  }

  Future<void> _writeAndIndexEntry(
    TableEntryDocument entry,
    String encoded, {
    required String? previous,
  }) async {
    final path = entryPath(entry.id);
    await _vault.write(path, encoded);
    try {
      await _index.upsertTableEntry(_indexEntry(entry, encoded));
    } catch (_) {
      if (previous == null) {
        await _vault.delete(path);
      } else {
        await _vault.write(path, previous);
      }
      rethrow;
    }
  }

  IndexedTable _indexTable(TableDocument table, String source) => IndexedTable(
    id: table.id,
    role: table.role,
    title: table.title,
    revision: table.revision,
    updatedAt: table.updatedAt.toUtc(),
    deleted: table.deleted,
    mdPath: tablePath(table.id),
    localHash: _hash(source),
    searchText: '${table.title} ${table.body}'.toLowerCase(),
  );

  IndexedTableEntry _indexEntry(TableEntryDocument entry, String source) {
    final businessAt = switch (entry.type) {
      TableContentType.note => null,
      TableContentType.todo => entry.due,
      TableContentType.schedule => entry.start,
      TableContentType.event => entry.occurredAt,
    };
    final values = jsonEncode(entry.customValues);
    return IndexedTableEntry(
      id: entry.id,
      type: entry.type,
      tableId: entry.tableId,
      title: entry.title,
      revision: entry.revision,
      updatedAt: entry.updatedAt.toUtc(),
      businessAt: businessAt?.toUtc(),
      done: entry.done,
      deleted: entry.deleted,
      mdPath: entryPath(entry.id),
      localHash: _hash(source),
      searchText: '${entry.title} ${entry.body} ${entry.tags.join(' ')} $values'
          .toLowerCase(),
      customValuesJson: values,
    );
  }

  String _hash(String source) => sha256.convert(utf8.encode(source)).toString();

  void _checkRevision(int current, int expected) {
    if (current != expected) {
      throw StateError('版本冲突：期望 $expected，实际 $current');
    }
  }

  static String tablePath(String id) => 'vault/tables/$id.md';
  static String entryPath(String id) => 'vault/items/$id.md';
}
