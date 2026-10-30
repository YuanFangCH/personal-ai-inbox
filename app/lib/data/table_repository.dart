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
    DateTime Function()? clock,
  }) : _vault = vault,
       _index = index,
       _codec = codec,
       _clock = clock ?? DateTime.now;

  static const defaultTables = <(String, TableRole, String)>[
    ('tb_default_todo', TableRole.inboxTodo, '待办'),
    ('tb_default_schedule', TableRole.inboxSchedule, '日程'),
    ('tb_default_event', TableRole.inboxEvent, '事件'),
  ];

  static const _uuid = Uuid();
  static const entryUndoWindow = Duration(minutes: 10);
  static const tableRecoveryWindow = Duration(days: 30);
  final VaultStore _vault;
  final IndexDatabase _index;
  final TableMarkdownCodec _codec;
  final DateTime Function() _clock;
  final String deviceId;

  Future<void> initialize() async {
    await _vault.initialize();
    await _resumeRecoveryBatches();
    await ensureDefaultTables();
    await rebuildIndex();
    await _expireRecoveryBatches(_clock());
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

  Future<TableDocument?> readTable(String id) => _vault.exclusive(() {
    _validateId(id);
    return _readTableUnlocked(id);
  });

  Future<TableDocument?> _readTableUnlocked(String id) async {
    final source = await _vault.read(tablePath(id));
    if (source == null) return null;
    final table = _codec.decodeTable(source);
    if (table.id != id) {
      throw const FormatException('Table path and ID mismatch');
    }
    return table;
  }

  Future<TableEntryDocument?> _readEntryUnlocked(String id) async {
    final source = await _vault.read(entryPath(id));
    if (source == null) return null;
    final entry = _codec.decodeEntry(source);
    if (entry.id != id) {
      throw const FormatException('Entry path and ID mismatch');
    }
    return entry;
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
    _validateId(proposed.id);
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
    _validateId(id);
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
        _validateId(entry.id);
        _validateId(entry.tableId);
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
    _validateId(proposed.id);
    _validateId(proposed.tableId);
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
    Map<String, String> fieldMapping = const {},
    Map<String, Map<String, String>> optionMapping = const {},
  }) => _vault.exclusive(() async {
    _validateId(id);
    _validateId(tableId);
    final path = entryPath(id);
    final previous = await _vault.read(path);
    if (previous == null) throw StateError('内容不存在：$id');
    final current = _codec.decodeEntry(previous);
    _checkRevision(current.revision, expectedRevision);
    if (current.deleted) throw StateError('内容已删除：$id');
    final source = await _readTableUnlocked(current.tableId);
    if (source == null || source.deleted) {
      throw StateError('源表不存在或已删除：${current.tableId}');
    }
    await _requireWritableTableUnlocked(tableId);
    final target = await _readTableUnlocked(tableId);
    if (target == null) throw StateError('目标表不存在：$tableId');
    final targetFields = {for (final field in target.fields) field.id: field};
    final sourceFields = {for (final field in source.fields) field.id: field};
    final values = <String, Object?>{};
    final assignedFields = <String>{};
    for (final value in current.customValues.entries) {
      if (value.value == null) continue;
      final sourceField = sourceFields[value.key];
      final targetFieldId = fieldMapping[value.key] ?? value.key;
      final targetField = targetFields[targetFieldId];
      if (sourceField == null || targetField == null) {
        throw StateError(
          '目标表缺少有值字段“${sourceField?.name ?? value.key}”，移动前需处理字段映射。',
        );
      }
      if (sourceField.type != targetField.type) {
        throw StateError('字段“${sourceField.name}”类型不兼容，不能移动此内容。');
      }
      if (!assignedFields.add(targetFieldId)) {
        throw StateError('多个源字段映射到了同一目标字段“${targetField.name}”。');
      }
      final optionIds = optionMapping[value.key] ?? const <String, String>{};
      final mappedValue = switch (sourceField.type) {
        CustomFieldType.singleSelect => optionIds[value.value] ?? value.value,
        CustomFieldType.multiSelect =>
          (value.value as List<Object?>)
              .map((optionId) => optionIds[optionId] ?? optionId)
              .toList(growable: false),
        _ => value.value,
      };
      values[targetFieldId] = mappedValue;
    }
    final moved = current.copyWith(
      tableId: tableId,
      revision: current.revision + 1,
      updatedAt: DateTime.now(),
      customValues: values,
    );
    final encoded = _codec.encodeEntry(moved, fields: target.fields);
    await _writeAndIndexEntry(moved, encoded, previous: previous);
    return moved;
  });

  Future<ScheduleChangeResult> changeScheduleFromEvent({
    required String scheduleId,
    required int expectedRevision,
    required DateTime start,
    DateTime? end,
    required String eventTitle,
    required String eventBody,
    required String idempotencyKey,
    DateTime? now,
  }) => _vault.exclusive(() async {
    _validateId(scheduleId);
    final timestamp = (now ?? _clock()).toLocal();
    final batchId = _recoveryId(idempotencyKey);
    final prior = await _index.findTableRecoveryBatch(batchId);
    if (prior != null) {
      final objects = _recoveryObjects(prior).toList();
      if (prior.scope != TableRecoveryScope.scheduleChange ||
          objects.length != 2 ||
          !objects.any((object) => object['id'] == scheduleId)) {
        throw StateError('日程修改幂等键已用于其他操作');
      }
      final schedule = await _readEntryUnlocked(scheduleId);
      final eventId =
          objects.firstWhere((object) => object['id'] != scheduleId)['id']
              as String;
      final event = await _readEntryUnlocked(eventId);
      if (schedule == null || event == null) {
        throw StateError('日程修改账本对应的内容缺失：$batchId');
      }
      return ScheduleChangeResult(
        batch: prior,
        schedule: schedule,
        event: event,
      );
    }
    if (eventTitle.trim().isEmpty) {
      throw ArgumentError.value(eventTitle, 'eventTitle');
    }
    if (end != null && !end.isAfter(start)) {
      throw ArgumentError('日程结束时间必须晚于开始时间');
    }
    final schedulePath = entryPath(scheduleId);
    final scheduleSource = await _vault.read(schedulePath);
    if (scheduleSource == null) throw StateError('日程不存在：$scheduleId');
    final schedule = _codec.decodeEntry(scheduleSource);
    _checkRevision(schedule.revision, expectedRevision);
    if (schedule.type != TableContentType.schedule || schedule.deleted) {
      throw StateError('目标不是有效日程：$scheduleId');
    }
    final table = await _readTableUnlocked(schedule.tableId);
    if (table == null || table.deleted) {
      throw StateError('日程所属表不存在或已删除：${schedule.tableId}');
    }
    final updatedSchedule = schedule.copyWith(
      revision: schedule.revision + 1,
      updatedAt: timestamp,
      start: start,
      end: end,
    );
    final eventId = 'ev_${_uuid.v4().replaceAll('-', '')}';
    final event = TableEntryDocument(
      id: eventId,
      type: TableContentType.event,
      tableId: schedule.tableId,
      title: eventTitle.trim(),
      revision: 1,
      createdAt: timestamp,
      updatedAt: timestamp,
      body: eventBody,
      occurredAt: timestamp,
      affects: [
        ScheduleChange(scheduleId: scheduleId, summary: eventTitle.trim()),
      ],
    );
    final eventTombstone = event.copyWith(revision: 2, deleted: true);
    final batch = await _prepareDeleteBatch(
      id: batchId,
      scope: TableRecoveryScope.scheduleChange,
      tableId: schedule.tableId,
      createdAt: timestamp,
      lifetime: entryUndoWindow,
      objects: [
        _RecoveryObject(
          kind: 'entry',
          id: scheduleId,
          sourcePath: schedulePath,
          before: scheduleSource,
          deleted: _codec.encodeEntry(updatedSchedule, fields: table.fields),
          deleteTarget: false,
        ),
        _RecoveryObject(
          kind: 'entry',
          id: eventId,
          sourcePath: entryPath(eventId),
          before: _codec.encodeEntry(eventTombstone, fields: table.fields),
          deleted: _codec.encodeEntry(event, fields: table.fields),
          existsBefore: false,
          deleteTarget: false,
        ),
      ],
    );
    final updated = await _readEntryUnlocked(scheduleId);
    final createdEvent = await _readEntryUnlocked(eventId);
    if (updated == null || createdEvent == null) {
      throw StateError('日程修改已提交但读取回执失败：$batchId');
    }
    return ScheduleChangeResult(
      batch: batch,
      schedule: updated,
      event: createdEvent,
    );
  });

  Future<TableRecoveryBatch> _prepareDeleteBatch({
    required String id,
    required TableRecoveryScope scope,
    required String tableId,
    required DateTime createdAt,
    required Duration lifetime,
    required List<_RecoveryObject> objects,
    Map<String, Object?> metadata = const {},
  }) async {
    if (await _index.findTableRecoveryBatch(id) != null) {
      throw StateError('删除批次已存在：$id');
    }
    final descriptors = <Map<String, Object?>>[];
    final materialPaths = <String>[];
    final materialRoot = 'vault/recycle-bin/$id';
    try {
      for (final object in objects) {
        final beforePath = '$materialRoot/before_${object.id}.md';
        final deletedPath = '$materialRoot/deleted_${object.id}.md';
        await _vault.write(beforePath, object.before);
        materialPaths.add(beforePath);
        await _vault.write(deletedPath, object.deleted);
        materialPaths.add(deletedPath);
        descriptors.add({
          'kind': object.kind,
          'id': object.id,
          'source_path': object.sourcePath,
          'before_path': beforePath,
          'deleted_path': deletedPath,
          'before_hash': _hash(object.before),
          'deleted_hash': _hash(object.deleted),
          'delete_target': object.deleteTarget,
          'exists_before': object.existsBefore,
        });
      }
    } catch (_) {
      for (final path in materialPaths) {
        await _vault.delete(path);
      }
      rethrow;
    }
    final batch = TableRecoveryBatch(
      id: id,
      scope: scope,
      tableId: tableId,
      status: TableRecoveryStatus.prepared,
      createdAt: createdAt,
      expiresAt: createdAt.add(lifetime),
      manifestJson: jsonEncode({...metadata, 'objects': descriptors}),
    );
    try {
      await _index.upsertTableRecoveryBatch(batch);
    } catch (_) {
      for (final path in materialPaths) {
        await _vault.delete(path);
      }
      rethrow;
    }
    await _applyPreparedDelete(batch);
    return (await _index.findTableRecoveryBatch(id))!;
  }

  Future<void> _applyPreparedDelete(TableRecoveryBatch batch) async {
    for (final object in _recoveryObjects(batch)) {
      final desired = await _vault.read(object['deleted_path'] as String);
      if (desired == null || _hash(desired) != object['deleted_hash']) {
        throw StateError('回收站删除前像缺失或校验失败：${object['id']}');
      }
      final sourcePath = object['source_path'] as String;
      final current = await _vault.read(sourcePath);
      if (current != null && _hash(current) == object['deleted_hash']) {
        await _indexRecoveredObject(object, current);
        continue;
      }
      if (object['exists_before'] == true &&
          (current == null || _hash(current) != object['before_hash'])) {
        await _index.upsertTableRecoveryBatch(
          batch.copyWith(
            status: TableRecoveryStatus.failed,
            error: '删除目标版本已变化，前像已保留：${object['id']}',
          ),
        );
        throw StateError('删除目标版本已变化，前像已保留：${object['id']}');
      }
      if (object['exists_before'] == false && current != null) {
        await _index.upsertTableRecoveryBatch(
          batch.copyWith(
            status: TableRecoveryStatus.failed,
            error: '新增对象 ID 已被占用：${object['id']}',
          ),
        );
        throw StateError('新增对象 ID 已被占用：${object['id']}');
      }
      await _vault.write(sourcePath, desired);
      await _indexRecoveredObject(object, desired);
    }
    await _index.upsertTableRecoveryBatch(
      batch.copyWith(status: TableRecoveryStatus.active, error: null),
    );
  }

  Future<TableRecoveryBatch> _prepareRestore(
    TableRecoveryBatch batch,
    DateTime restoredAt,
  ) async {
    final objects = _recoveryObjects(batch).toList()
      ..sort((left, right) {
        final leftIsTable = left['kind'] == 'table';
        final rightIsTable = right['kind'] == 'table';
        return leftIsTable == rightIsTable ? 0 : (leftIsTable ? -1 : 1);
      });
    TableDocument? restoredTable;
    final updatedObjects = <Map<String, Object?>>[];
    for (final object in objects) {
      final beforePath = object['before_path'] as String;
      final deletedPath = object['deleted_path'] as String;
      final sourcePath = object['source_path'] as String;
      final before = await _vault.read(beforePath);
      final deleted = await _vault.read(deletedPath);
      final current = await _vault.read(sourcePath);
      if (before == null ||
          deleted == null ||
          current == null ||
          _hash(before) != object['before_hash'] ||
          _hash(deleted) != object['deleted_hash'] ||
          _hash(current) != object['deleted_hash']) {
        throw StateError('恢复目标或前像已变化，保留回收批次：${object['id']}');
      }
      final restoredPath = '$beforePath.restored';
      String restoredMarkdown;
      if (object['kind'] == 'table') {
        final original = _codec.decodeTable(before);
        final tombstone = _codec.decodeTable(deleted);
        restoredTable = original.copyWith(
          revision: tombstone.revision + 1,
          updatedAt: restoredAt,
          deleted: false,
        );
        restoredMarkdown = _codec.encodeTable(restoredTable);
      } else {
        final original = _codec.decodeEntry(before);
        final tombstone = _codec.decodeEntry(deleted);
        final table = restoredTable?.id == original.tableId
            ? restoredTable
            : await _readTableUnlocked(original.tableId);
        if (table == null) throw StateError('恢复目标表缺失：${original.tableId}');
        restoredMarkdown = _codec.encodeEntry(
          original.copyWith(
            revision: tombstone.revision + 1,
            updatedAt: restoredAt,
            deleted: batch.scope == TableRecoveryScope.entry
                ? false
                : original.deleted,
          ),
          fields: table.fields,
        );
      }
      await _vault.write(restoredPath, restoredMarkdown);
      updatedObjects.add({
        ...object,
        'restored_path': restoredPath,
        'restored_hash': _hash(restoredMarkdown),
      });
    }
    final pending = batch.copyWith(
      status: TableRecoveryStatus.restoring,
      manifestJson: jsonEncode({
        ...Map<String, dynamic>.from(jsonDecode(batch.manifestJson) as Map),
        'objects': updatedObjects,
      }),
      error: null,
    );
    await _index.upsertTableRecoveryBatch(pending);
    return pending;
  }

  Future<TableRecoveryBatch> _applyPreparedRestore(
    TableRecoveryBatch batch,
  ) async {
    for (final object in _recoveryObjects(batch)) {
      final path = object['source_path'] as String;
      final current = await _vault.read(path);
      if (current == null) throw StateError('恢复目标文件缺失：${object['id']}');
      final currentHash = _hash(current);
      final restoredHash = object['restored_hash'] as String?;
      if (restoredHash == null) {
        throw StateError('恢复批次缺少目标版本：${batch.id}');
      }
      if (currentHash == restoredHash) {
        await _indexRecoveredObject(object, current);
        continue;
      }
      if (currentHash != object['deleted_hash']) {
        await _index.upsertTableRecoveryBatch(
          batch.copyWith(
            status: TableRecoveryStatus.failed,
            error: '恢复目标已被其他操作修改，保留回收材料：${object['id']}',
          ),
        );
        throw StateError('恢复目标已被其他操作修改，保留回收材料：${object['id']}');
      }
      final restored = await _vault.read(object['restored_path'] as String);
      if (restored == null || currentHash == restoredHash) {
        throw StateError('恢复前像缺失：${object['id']}');
      }
      if (_hash(restored) != restoredHash) {
        throw StateError('恢复前像校验失败：${object['id']}');
      }
      await _vault.write(path, restored);
      await _indexRecoveredObject(object, restored);
    }
    final restoredBatch = batch.copyWith(
      status: TableRecoveryStatus.restored,
      error: null,
    );
    await _index.upsertTableRecoveryBatch(restoredBatch);
    return restoredBatch;
  }

  Iterable<Map<String, dynamic>> _recoveryObjects(TableRecoveryBatch batch) {
    final manifest = jsonDecode(batch.manifestJson);
    if (manifest is! Map || manifest['objects'] is! List) {
      throw StateError('回收批次清单损坏：${batch.id}');
    }
    for (final raw in manifest['objects'] as List) {
      if (raw is! Map ||
          raw['id'] is! String ||
          raw['kind'] is! String ||
          raw['source_path'] is! String ||
          raw['before_path'] is! String ||
          raw['deleted_path'] is! String ||
          raw['before_hash'] is! String ||
          raw['deleted_hash'] is! String ||
          raw['delete_target'] is! bool ||
          raw['exists_before'] is! bool) {
        throw StateError('回收批次对象描述损坏：${batch.id}');
      }
    }
    return (manifest['objects'] as List).cast<Map>().map(
      (item) => Map<String, dynamic>.from(item),
    );
  }

  List<String> _manifestIds(TableRecoveryBatch batch) =>
      _recoveryObjects(batch).map((object) => object['id'] as String).toList();

  String _recoveryId(String? idempotencyKey) {
    if (idempotencyKey == null) return 'rb_${_uuid.v4()}';
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(idempotencyKey)) {
      throw ArgumentError.value(idempotencyKey, 'idempotencyKey');
    }
    return 'rb_$idempotencyKey';
  }

  void _validateId(String id) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id');
    }
  }

  Future<void> _indexRecoveredObject(
    Map<String, dynamic> object,
    String source,
  ) async {
    if (object['kind'] == 'table') {
      await _index.upsertTable(_indexTable(_codec.decodeTable(source), source));
    } else if (object['kind'] == 'entry') {
      await _index.upsertTableEntry(
        _indexEntry(_codec.decodeEntry(source), source),
      );
    } else {
      throw FormatException(
        'Unsupported recovery object kind: ${object['kind']}',
      );
    }
  }

  Future<void> _expireBatch(TableRecoveryBatch batch, DateTime now) async {
    final objects = _recoveryObjects(batch).toList();
    if (batch.status == TableRecoveryStatus.active) {
      objects.sort((left, right) {
        final leftIsTable = left['kind'] == 'table';
        final rightIsTable = right['kind'] == 'table';
        return leftIsTable == rightIsTable ? 0 : (leftIsTable ? 1 : -1);
      });
      for (final object in objects) {
        if (object['delete_target'] == false) continue;
        final path = object['source_path'] as String;
        final current = await _vault.read(path);
        if (current == null || _hash(current) != object['deleted_hash']) {
          final failed = batch.copyWith(
            status: TableRecoveryStatus.failed,
            error: '到期清理发现目标版本变化；原恢复材料已保留。',
          );
          await _index.upsertTableRecoveryBatch(failed);
          return;
        }
        String hardTombstone;
        if (object['kind'] == 'table') {
          final table = _codec.decodeTable(current);
          hardTombstone = _codec.encodeTable(
            table.copyWith(
              revision: table.revision + 1,
              updatedAt: now,
              body: '',
              fields: const [],
            ),
          );
        } else {
          final entry = _codec.decodeEntry(current);
          final owner = await _readTableUnlocked(entry.tableId);
          if (owner == null) throw StateError('过期清理找不到内容所属表：${entry.id}');
          hardTombstone = _codec.encodeEntry(
            entry.copyWith(
              revision: entry.revision + 1,
              updatedAt: now,
              body: '',
              tags: const [],
              links: const [],
              customValues: const {},
              affects: const [],
            ),
            fields: owner.fields,
          );
        }
        await _vault.write(path, hardTombstone);
        await _indexRecoveredObject(object, hardTombstone);
      }
    }
    for (final object in objects) {
      await _vault.delete(object['before_path'] as String);
      await _vault.delete(object['deleted_path'] as String);
      final restoredPath = object['restored_path'];
      if (restoredPath is String) await _vault.delete(restoredPath);
    }
    await _index.upsertTableRecoveryBatch(
      batch.copyWith(status: TableRecoveryStatus.expired, error: null),
    );
  }

  Future<TableRecoveryBatch> deleteEntry({
    required String id,
    required int expectedRevision,
    String? idempotencyKey,
    DateTime? now,
  }) => _vault.exclusive(() async {
    _validateId(id);
    final currentBatchId = _recoveryId(idempotencyKey);
    final prior = await _index.findTableRecoveryBatch(currentBatchId);
    if (prior != null) {
      if (prior.scope != TableRecoveryScope.entry ||
          !_manifestIds(prior).contains(id)) {
        throw StateError('删除幂等键已用于其他内容');
      }
      return prior;
    }
    final path = entryPath(id);
    final source = await _vault.read(path);
    if (source == null) throw StateError('内容不存在：$id');
    final entry = _codec.decodeEntry(source);
    _checkRevision(entry.revision, expectedRevision);
    if (entry.deleted) throw StateError('内容已删除：$id');
    final timestamp = (now ?? _clock()).toLocal();
    final table = await _readTableUnlocked(entry.tableId);
    if (table == null) throw StateError('所属表不存在：${entry.tableId}');
    final deleted = entry.copyWith(
      revision: entry.revision + 1,
      updatedAt: timestamp,
      deleted: true,
    );
    final deletedMarkdown = _codec.encodeEntry(deleted, fields: table.fields);
    final objects = <_RecoveryObject>[
      _RecoveryObject(
        kind: 'entry',
        id: id,
        sourcePath: path,
        before: source,
        deleted: deletedMarkdown,
      ),
    ];
    if (entry.type == TableContentType.schedule) {
      for (final row in await _index.listTableEntries(
        type: TableContentType.event,
      )) {
        final eventPath = entryPath(row.id);
        final eventSource = await _vault.read(eventPath);
        if (eventSource == null) continue;
        final event = _codec.decodeEntry(eventSource);
        final affects = event.affects
            .where((link) => link.scheduleId != entry.id)
            .toList(growable: false);
        if (affects.length == event.affects.length) continue;
        final eventTable = await _readTableUnlocked(event.tableId);
        if (eventTable == null || eventTable.deleted) {
          throw StateError('事件所属表缺失或已删除：${event.id}');
        }
        final updatedEvent = event.copyWith(
          revision: event.revision + 1,
          updatedAt: timestamp,
          affects: affects,
        );
        objects.add(
          _RecoveryObject(
            kind: 'entry',
            id: event.id,
            sourcePath: eventPath,
            before: eventSource,
            deleted: _codec.encodeEntry(
              updatedEvent,
              fields: eventTable.fields,
            ),
            deleteTarget: false,
          ),
        );
      }
    }
    return _prepareDeleteBatch(
      id: currentBatchId,
      scope: TableRecoveryScope.entry,
      tableId: entry.tableId,
      createdAt: timestamp,
      lifetime: entryUndoWindow,
      objects: objects,
    );
  });

  Future<TableRecoveryBatch> deleteTable({
    required String id,
    required int expectedRevision,
    String? idempotencyKey,
    DateTime? now,
  }) => _vault.exclusive(() async {
    _validateId(id);
    final currentBatchId = _recoveryId(idempotencyKey);
    final prior = await _index.findTableRecoveryBatch(currentBatchId);
    if (prior != null) {
      if (prior.scope != TableRecoveryScope.table || prior.tableId != id) {
        throw StateError('删除幂等键已用于其他表');
      }
      return prior;
    }
    final tablePathValue = tablePath(id);
    final tableSource = await _vault.read(tablePathValue);
    if (tableSource == null) throw StateError('表不存在：$id');
    final table = _codec.decodeTable(tableSource);
    _checkRevision(table.revision, expectedRevision);
    if (table.role != TableRole.custom) throw StateError('默认表禁止删除：$id');
    if (table.deleted) throw StateError('表已删除：$id');
    final timestamp = (now ?? _clock()).toLocal();
    final objects = <_RecoveryObject>[];
    final affectedScheduleIds = <String>{};
    final deletedTable = table.copyWith(
      revision: table.revision + 1,
      updatedAt: timestamp,
      deleted: true,
    );
    objects.add(
      _RecoveryObject(
        kind: 'table',
        id: table.id,
        sourcePath: tablePathValue,
        before: tableSource,
        deleted: _codec.encodeTable(deletedTable),
      ),
    );
    for (final row in await _index.listTableEntries(
      tableId: table.id,
      includeDeleted: true,
    )) {
      final path = entryPath(row.id);
      final source = await _vault.read(path);
      if (source == null) {
        throw StateError('表内内容缺失，停止删除以避免不完整恢复：${row.id}');
      }
      final entry = _codec.decodeEntry(source);
      if (entry.tableId != table.id) {
        throw StateError('内容归属在删除期间已变化：${entry.id}');
      }
      if (entry.type == TableContentType.schedule && !entry.deleted) {
        affectedScheduleIds.add(entry.id);
      }
      final deleted = entry.copyWith(
        revision: entry.revision + 1,
        updatedAt: timestamp,
        deleted: true,
      );
      objects.add(
        _RecoveryObject(
          kind: 'entry',
          id: entry.id,
          sourcePath: path,
          before: source,
          deleted: _codec.encodeEntry(deleted, fields: table.fields),
        ),
      );
    }
    if (affectedScheduleIds.isNotEmpty) {
      for (final row in await _index.listTableEntries(
        type: TableContentType.event,
      )) {
        if (row.tableId == table.id) continue;
        final path = entryPath(row.id);
        final source = await _vault.read(path);
        if (source == null) continue;
        final event = _codec.decodeEntry(source);
        final affects = event.affects
            .where((link) => !affectedScheduleIds.contains(link.scheduleId))
            .toList(growable: false);
        if (affects.length == event.affects.length) continue;
        final eventTable = await _readTableUnlocked(event.tableId);
        if (eventTable == null || eventTable.deleted) {
          throw StateError('事件所属表缺失或已删除：${event.id}');
        }
        final updated = event.copyWith(
          revision: event.revision + 1,
          updatedAt: timestamp,
          affects: affects,
        );
        objects.add(
          _RecoveryObject(
            kind: 'entry',
            id: event.id,
            sourcePath: path,
            before: source,
            deleted: _codec.encodeEntry(updated, fields: eventTable.fields),
            deleteTarget: false,
          ),
        );
      }
    }
    return _prepareDeleteBatch(
      id: currentBatchId,
      scope: TableRecoveryScope.table,
      tableId: table.id,
      createdAt: timestamp,
      lifetime: tableRecoveryWindow,
      objects: objects,
    );
  });

  Future<List<TableRecoveryBatch>> recoveryBatches() async =>
      (await _index.listTableRecoveryBatches(activeOnly: true))
          .where(
            (batch) =>
                batch.scope == TableRecoveryScope.entry ||
                batch.scope == TableRecoveryScope.table,
          )
          .toList(growable: false);

  Future<TableRecoveryPreview?> previewDeletedTable(String batchId) =>
      _vault.exclusive(() async {
        final batch = await _index.findTableRecoveryBatch(batchId);
        if (batch == null ||
            batch.scope != TableRecoveryScope.table ||
            batch.status != TableRecoveryStatus.active) {
          return null;
        }
        final manifest = jsonDecode(batch.manifestJson) as Map<String, dynamic>;
        final objects = manifest['objects'] as List<dynamic>;
        final tableObject = objects
            .whereType<Map<String, dynamic>>()
            .firstWhere((object) => object['kind'] == 'table');
        final tableSource = await _vault.read(
          tableObject['before_path'] as String,
        );
        if (tableSource == null) {
          throw StateError('回收站缺少表快照：$batchId');
        }
        final table = _codec.decodeTable(tableSource);
        final entries = <TableEntryDocument>[];
        for (final object in objects.whereType<Map<String, dynamic>>()) {
          if (object['kind'] != 'entry' || object['delete_target'] == false) {
            continue;
          }
          final source = await _vault.read(object['before_path'] as String);
          if (source == null) {
            throw StateError('回收站缺少内容快照：${object['id']}');
          }
          entries.add(_codec.decodeEntry(source));
        }
        return TableRecoveryPreview(
          table: table,
          entries: List.unmodifiable(entries),
        );
      });

  Future<List<TableRecoveryBatch>> fieldChangeRecoveryBatches({
    String? tableId,
  }) async => (await _index.listTableRecoveryBatches(activeOnly: true))
      .where(
        (batch) =>
            batch.scope == TableRecoveryScope.fieldChange &&
            (tableId == null || batch.tableId == tableId),
      )
      .toList(growable: false);

  Future<TableRecoveryBatch> removeTableField({
    required String tableId,
    required String fieldId,
    required int expectedRevision,
    String? idempotencyKey,
    DateTime? now,
  }) => _vault.exclusive(() async {
    _validateId(tableId);
    _validateId(fieldId);
    final operationKey =
        idempotencyKey ??
        'remove-field-${_hash('$tableId|$fieldId|$expectedRevision').substring(0, 32)}';
    final batchId = _recoveryId(operationKey);
    final prior = await _index.findTableRecoveryBatch(batchId);
    if (prior != null) {
      final decoded = jsonDecode(prior.manifestJson);
      final operation = decoded is Map ? decoded['operation'] : null;
      if (prior.scope != TableRecoveryScope.fieldChange ||
          prior.tableId != tableId ||
          operation is! Map ||
          operation['field_id'] != fieldId) {
        throw StateError('字段删除幂等键已用于其他结构变更');
      }
      return prior;
    }
    final activeBatches = await _index.listTableRecoveryBatches(
      activeOnly: true,
    );
    if (activeBatches.any((batch) => batch.tableId == tableId)) {
      throw StateError('该表有未完成的恢复/日程联动批次，请先恢复或等待到期。');
    }
    final tablePathValue = tablePath(tableId);
    final tableSource = await _vault.read(tablePathValue);
    if (tableSource == null) throw StateError('表不存在：$tableId');
    final table = _codec.decodeTable(tableSource);
    _checkRevision(table.revision, expectedRevision);
    if (table.deleted) throw StateError('表已删除：$tableId');
    TableFieldDefinition? field;
    for (final candidate in table.fields) {
      if (candidate.id == fieldId) field = candidate;
    }
    if (field == null) throw StateError('字段不存在：$fieldId');
    final timestamp = (now ?? _clock()).toLocal();
    final remainingFields = table.fields
        .where((candidate) => candidate.id != fieldId)
        .toList(growable: false);
    final updatedTable = table.copyWith(
      revision: table.revision + 1,
      updatedAt: timestamp,
      fields: remainingFields,
    );
    final objects = <_RecoveryObject>[
      _RecoveryObject(
        kind: 'table',
        id: table.id,
        sourcePath: tablePathValue,
        before: tableSource,
        deleted: _codec.encodeTable(updatedTable),
        deleteTarget: false,
      ),
    ];
    for (final row in await _index.listTableEntries(
      tableId: tableId,
      includeDeleted: true,
    )) {
      final path = entryPath(row.id);
      final source = await _vault.read(path);
      if (source == null) {
        throw StateError('字段影响内容缺失，停止删除以避免丢值：${row.id}');
      }
      final entry = _codec.decodeEntry(source);
      if (entry.tableId != tableId) {
        throw StateError('字段影响内容归属已变化：${entry.id}');
      }
      if (!entry.customValues.containsKey(fieldId)) continue;
      final values = Map<String, Object?>.of(entry.customValues)
        ..remove(fieldId);
      final updatedEntry = entry.copyWith(
        revision: entry.revision + 1,
        updatedAt: timestamp,
        customValues: values,
      );
      objects.add(
        _RecoveryObject(
          kind: 'entry',
          id: entry.id,
          sourcePath: path,
          before: source,
          deleted: _codec.encodeEntry(updatedEntry, fields: remainingFields),
          deleteTarget: false,
        ),
      );
    }
    return _prepareDeleteBatch(
      id: batchId,
      scope: TableRecoveryScope.fieldChange,
      tableId: tableId,
      createdAt: timestamp,
      lifetime: tableRecoveryWindow,
      objects: objects,
      metadata: {
        'operation': {
          'kind': 'remove_field',
          'field_id': field.id,
          'field_name': field.name,
        },
      },
    );
  });

  Future<void> purgeExpiredRecoveryBatches({DateTime? now}) =>
      _expireRecoveryBatches((now ?? _clock()).toLocal());

  Future<TableRecoveryBatch> restoreRecoveryBatch(String id, {DateTime? now}) =>
      _vault.exclusive(() async {
        var batch = await _index.findTableRecoveryBatch(id);
        if (batch == null) throw StateError('恢复批次不存在：$id');
        final timestamp = (now ?? _clock()).toLocal();
        if (!timestamp.isBefore(batch.expiresAt)) {
          await _expireBatch(batch, timestamp);
          throw StateError('恢复期限已过：$id');
        }
        if (batch.status == TableRecoveryStatus.restored) return batch;
        if (batch.status == TableRecoveryStatus.expired ||
            batch.status == TableRecoveryStatus.failed) {
          throw StateError('恢复批次不可恢复：${batch.status.name}');
        }
        if (batch.status == TableRecoveryStatus.prepared) {
          await _applyPreparedDelete(batch);
          batch = (await _index.findTableRecoveryBatch(id))!;
        }
        if (batch.status == TableRecoveryStatus.active) {
          batch = await _prepareRestore(batch, timestamp);
        }
        return _applyPreparedRestore(batch);
      });

  Future<void> _resumeRecoveryBatches() async {
    for (final batch in await _index.listTableRecoveryBatches(
      activeOnly: true,
    )) {
      await _vault.exclusive(() async {
        final current = await _index.findTableRecoveryBatch(batch.id);
        if (current == null) return;
        if (current.status == TableRecoveryStatus.prepared) {
          await _applyPreparedDelete(current);
        } else if (current.status == TableRecoveryStatus.restoring) {
          await _applyPreparedRestore(current);
        }
      });
    }
  }

  Future<void> _expireRecoveryBatches(DateTime now) async {
    final batches = await _index.listTableRecoveryBatches();
    for (final batch in batches) {
      if ((batch.status == TableRecoveryStatus.prepared ||
              batch.status == TableRecoveryStatus.restoring) ||
          now.isBefore(batch.expiresAt) ||
          batch.status == TableRecoveryStatus.expired ||
          batch.status == TableRecoveryStatus.failed) {
        continue;
      }
      await _vault.exclusive(() => _expireBatch(batch, now));
    }
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

class _RecoveryObject {
  const _RecoveryObject({
    required this.kind,
    required this.id,
    required this.sourcePath,
    required this.before,
    required this.deleted,
    this.deleteTarget = true,
    this.existsBefore = true,
  });

  final String kind;
  final String id;
  final String sourcePath;
  final String before;
  final String deleted;
  final bool deleteTarget;
  final bool existsBefore;
}

class ScheduleChangeResult {
  const ScheduleChangeResult({
    required this.batch,
    required this.schedule,
    required this.event,
  });

  final TableRecoveryBatch batch;
  final TableEntryDocument schedule;
  final TableEntryDocument event;
}
