import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/chat_models.dart';
import '../../core/models.dart';
import '../../core/table_models.dart';
import '../../data/chat_repository.dart';
import '../tables/table_library.dart';
import 'auto_record_processor.dart';

/// Applies table content calls after the model has completed its full reply.
/// Table-structure calls are stored as pending chat actions for button review.
class TableActionProcessor {
  TableActionProcessor({
    required ChatRepository chatRepository,
    required TableLibrary tables,
  }) : _chatRepository = chatRepository,
       _tables = tables;

  final ChatRepository _chatRepository;
  final TableLibrary _tables;

  Future<List<TableChatAction>> processToolCalls(
    String assistantMessageId,
    List<ToolCallAccumulator> calls, {
    DateTime? completedAt,
  }) async {
    final assistant = await _chatRepository.findMessage(assistantMessageId);
    if (assistant == null) return const [];
    final conversation = await _chatRepository.findConversation(
      assistant.conversationId,
    );
    final permissions =
        conversation?.aiPermissions ??
        const AiPermissions(read: false, create: false, modifyDelete: false);
    final messages = await _chatRepository.listMessages(
      assistant.conversationId,
    );
    var sourceUserMessageId = assistantMessageId;
    for (final message in messages) {
      if (message.role == ChatRole.user &&
          !message.createdAt.isAfter(assistant.createdAt)) {
        sourceUserMessageId = message.id;
      }
    }
    final createdAt = completedAt ?? assistant.createdAt;
    final actions = <TableChatAction>[];
    for (final call in calls) {
      final name = call.name;
      if (name == null || !_isTableTool(name) || call.arguments.isEmpty) {
        continue;
      }
      final stableKey =
          'conversation:$sourceUserMessageId:${call.index ?? call.id ?? calls.indexOf(call)}';
      final actionId =
          'act_${sha256.convert(utf8.encode(stableKey)).toString().substring(0, 24)}';
      final existing = await _chatRepository.findTableChatAction(actionId);
      if (existing != null) {
        actions.add(existing.$2);
        continue;
      }
      final payload = _decode(call.arguments.toString());
      final permission = _permissionFor(name, permissions);
      final proposedOperation = name == 'table.propose'
          ? payload['operation']
          : null;
      final structurePermission = proposedOperation == 'create'
          ? permissions.create
          : permissions.modifyDelete;
      if (!permission || (name == 'table.propose' && !structurePermission)) {
        actions.add(_failed(actionId, name, createdAt, '当前会话权限不允许此操作。'));
        continue;
      }
      try {
        final action = switch (name) {
          'content.create' => await _create(actionId, payload, createdAt),
          'table.body.update' => await _updateTableBody(
            actionId,
            payload,
            createdAt,
          ),
          'content.update' => await _update(actionId, payload, createdAt),
          'content.move' => await _move(actionId, payload, createdAt),
          'content.delete' => await _delete(actionId, payload, createdAt),
          'schedule.change' => await _changeSchedule(
            actionId,
            payload,
            createdAt,
          ),
          'table.propose' => await _propose(actionId, payload, createdAt),
          _ => _failed(actionId, name, createdAt, '未知表操作。'),
        };
        actions.add(action);
      } on Object catch (error) {
        actions.add(_failed(actionId, name, createdAt, _errorMessage(error)));
      }
    }
    return List.unmodifiable(actions);
  }

  bool _isTableTool(String name) => const {
    'content.create',
    'table.body.update',
    'content.update',
    'content.move',
    'content.delete',
    'schedule.change',
    'table.propose',
  }.contains(name);

  bool _permissionFor(String name, AiPermissions permissions) => switch (name) {
    'content.create' => permissions.create,
    'table.body.update' => permissions.modifyDelete,
    'content.update' ||
    'content.move' ||
    'content.delete' => permissions.modifyDelete,
    'schedule.change' => permissions.create && permissions.modifyDelete,
    'table.propose' => permissions.create || permissions.modifyDelete,
    _ => false,
  };

  Future<TableChatAction> _create(
    String actionId,
    Map<String, dynamic> payload,
    DateTime createdAt,
  ) async {
    _requireKeys(payload, const {
      'table_id',
      'type',
      'title',
      'body',
      'tags',
      'due',
      'start',
      'end',
      'occurred_at',
      'done',
      'custom_values',
      'idempotency_key',
    });
    final tableId = _requiredString(payload, 'table_id');
    final table = _requireTable(tableId);
    final type = _parseType(payload['type']);
    final title = _requiredString(payload, 'title').trim();
    if (title.isEmpty) throw StateError('标题不能为空。');
    final body = _string(payload, 'body', fallback: '');
    final tags = _stringList(payload['tags']);
    final due = _date(payload['due']);
    final start = _date(payload['start']);
    final end = _date(payload['end']);
    final occurredAt = _date(payload['occurred_at']);
    if (type == TableContentType.schedule && start == null) {
      throw StateError('日程必须提供开始时间。');
    }
    if (start != null && end != null && !end.isAfter(start)) {
      throw StateError('结束时间必须晚于开始时间。');
    }
    final values = _objectMap(payload['custom_values']);
    final entryId = 'nt_${actionId.substring(4)}';
    final existing = await _tables.readEntry(entryId);
    if (existing != null) {
      if (_sameCreatedEntry(
        existing,
        tableId: tableId,
        type: type,
        title: title,
        body: body,
        due: due,
        start: start,
        end: end,
        occurredAt: occurredAt,
        tags: tags,
        done: payload['done'] == true,
        customValues: values,
      )) {
        return _applied(
          actionId,
          'content.create',
          createdAt,
          title,
          table,
          entry: existing,
          message: '重放时已找到相同内容。',
        );
      }
      throw StateError('稳定内容 ID 已被其他内容使用。');
    }
    final now = createdAt;
    final entry = await _tables.createEntry(
      TableEntryDocument(
        id: entryId,
        type: type,
        tableId: tableId,
        title: title,
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: body,
        tags: tags,
        due: due,
        done: payload['done'] == true,
        start: start,
        end: end,
        occurredAt: occurredAt,
        customValues: values,
      ),
    );
    return _applied(
      actionId,
      'content.create',
      createdAt,
      title,
      table,
      entry: entry,
    );
  }

  Future<TableChatAction> _updateTableBody(
    String actionId,
    Map<String, dynamic> payload,
    DateTime createdAt,
  ) async {
    _requireKeys(payload, const {
      'table_id',
      'if_revision',
      'body',
      'idempotency_key',
    });
    final tableId = _requiredString(payload, 'table_id');
    final expected = _requiredInt(payload, 'if_revision');
    final body = _requiredString(payload, 'body');
    final table = _requireTable(tableId);
    if (table.revision == expected + 1 && table.body == body) {
      return _applied(
        actionId,
        'table.body.update',
        createdAt,
        table.title,
        table,
        message: '重放时已找到相同表正文。',
      );
    }
    if (table.revision != expected) throw StateError('表版本已变化，请重新读取。');
    final saved = await _tables.updateTable(
      table.copyWith(body: body),
      expectedRevision: expected,
    );
    return _applied(
      actionId,
      'table.body.update',
      createdAt,
      saved.title,
      saved,
    );
  }

  Future<TableChatAction> _update(
    String actionId,
    Map<String, dynamic> payload,
    DateTime createdAt,
  ) async {
    _requireKeys(payload, const {
      'id',
      'if_revision',
      'changes',
      'idempotency_key',
    });
    final id = _requiredString(payload, 'id');
    final expected = _requiredInt(payload, 'if_revision');
    final changes = _objectMap(payload['changes']);
    _requireKeys(changes, const {
      'title',
      'body',
      'due',
      'start',
      'end',
      'occurred_at',
      'done',
      'custom_values',
      'tags',
    });
    final entry = await _tables.readEntry(id);
    if (entry == null || entry.deleted) throw StateError('内容不存在或已删除。');
    final table = _requireTable(entry.tableId);
    final title = changes['title'] as String? ?? entry.title;
    final body = changes['body'] as String? ?? entry.body;
    final updated = entry.copyWith(
      title: title,
      body: body,
      due: changes.containsKey('due') ? _date(changes['due']) : entry.due,
      start: changes.containsKey('start')
          ? _date(changes['start'])
          : entry.start,
      end: changes.containsKey('end') ? _date(changes['end']) : entry.end,
      occurredAt: changes.containsKey('occurred_at')
          ? _date(changes['occurred_at'])
          : entry.occurredAt,
      done: changes['done'] as bool? ?? entry.done,
      customValues: changes.containsKey('custom_values')
          ? _objectMap(changes['custom_values'])
          : entry.customValues,
      tags: changes.containsKey('tags')
          ? _stringList(changes['tags'])
          : entry.tags,
    );
    if (entry.revision == expected + 1 && _sameEntryState(entry, updated)) {
      return _applied(
        actionId,
        'content.update',
        createdAt,
        title,
        table,
        entry: entry,
        message: '重放时已找到相同更新。',
      );
    }
    if (entry.revision != expected) throw StateError('内容版本已变化，请重新读取。');
    final saved = await _tables.updateEntry(
      updated,
      expectedRevision: expected,
    );
    return _applied(
      actionId,
      'content.update',
      createdAt,
      saved.title,
      table,
      entry: saved,
    );
  }

  Future<TableChatAction> _move(
    String actionId,
    Map<String, dynamic> payload,
    DateTime createdAt,
  ) async {
    _requireKeys(payload, const {
      'id',
      'if_revision',
      'to_table_id',
      'field_mapping',
      'option_mapping',
      'idempotency_key',
    });
    final id = _requiredString(payload, 'id');
    final expected = _requiredInt(payload, 'if_revision');
    final targetId = _requiredString(payload, 'to_table_id');
    final target = _requireTable(targetId);
    final fieldMapping = _stringMap(payload['field_mapping']);
    final optionMapping = _nestedStringMap(payload['option_mapping']);
    var entry = await _tables.readEntry(id);
    if (entry == null || entry.deleted) throw StateError('待移动内容不存在。');
    if (entry.tableId == targetId && entry.revision == expected + 1) {
      return _applied(
        actionId,
        'content.move',
        createdAt,
        entry.title,
        target,
        entry: entry,
        message: '重放时已在目标表。',
      );
    }
    if (entry.revision != expected) throw StateError('内容版本已变化，请重新读取。');
    entry = await _tables.moveEntry(
      id: id,
      tableId: targetId,
      expectedRevision: expected,
      fieldMapping: fieldMapping,
      optionMapping: optionMapping,
    );
    return _applied(
      actionId,
      'content.move',
      createdAt,
      entry.title,
      target,
      entry: entry,
    );
  }

  Future<TableChatAction> _delete(
    String actionId,
    Map<String, dynamic> payload,
    DateTime createdAt,
  ) async {
    _requireKeys(payload, const {'id', 'if_revision', 'idempotency_key'});
    final id = _requiredString(payload, 'id');
    final expected = _requiredInt(payload, 'if_revision');
    final entry = await _tables.readEntry(id);
    if (entry == null) throw StateError('内容不存在。');
    final table = _requireTable(entry.tableId);
    final batch = await _tables.deleteEntry(
      id: id,
      expectedRevision: expected,
      idempotencyKey: actionId,
      now: createdAt,
    );
    return _applied(
      actionId,
      'content.delete',
      createdAt,
      entry.title,
      table,
      entry: entry,
      recoveryBatchId: batch.id,
      undoUntil: batch.expiresAt,
    );
  }

  Future<TableChatAction> _changeSchedule(
    String actionId,
    Map<String, dynamic> payload,
    DateTime createdAt,
  ) async {
    _requireKeys(payload, const {
      'schedule_id',
      'if_revision',
      'event_title',
      'event_body',
      'event_occurred_at',
      'new_start',
      'new_end',
      'idempotency_key',
    });
    final scheduleId = _requiredString(payload, 'schedule_id');
    final expected = _requiredInt(payload, 'if_revision');
    final start = _date(payload['new_start']);
    if (start == null) throw StateError('新日程必须提供开始时间。');
    final result = await _tables.changeScheduleFromEvent(
      scheduleId: scheduleId,
      expectedRevision: expected,
      start: start,
      end: _date(payload['new_end']),
      eventTitle: _requiredString(payload, 'event_title'),
      eventBody: _string(payload, 'event_body', fallback: ''),
      eventOccurredAt: _date(payload['event_occurred_at']) ?? createdAt,
      idempotencyKey: actionId,
      now: createdAt,
    );
    return TableChatAction(
      id: actionId,
      operation: 'schedule.change',
      title: result.schedule.title,
      status: TableChatActionStatus.applied,
      createdAt: createdAt,
      tableId: result.schedule.tableId,
      tableTitle: _requireTable(result.schedule.tableId).title,
      entryId: result.schedule.id,
      relatedEntryId: result.event.id,
      entryType: TableContentType.schedule.name,
      message: '通知事件已保留并更新原日程。',
      recoveryBatchId: result.batch.id,
      undoUntil: result.batch.expiresAt,
    );
  }

  Future<TableChatAction> _propose(
    String actionId,
    Map<String, dynamic> payload,
    DateTime createdAt,
  ) async {
    _requireKeys(payload, const {
      'operation',
      'table_id',
      'expected_revision',
      'payload',
      'idempotency_key',
    });
    final operation = _requiredString(payload, 'operation');
    const allowed = {
      'create',
      'rename',
      'delete',
      'upsert_field',
      'delete_field',
    };
    if (!allowed.contains(operation)) throw StateError('表结构操作类型无效。');
    final data = _objectMap(payload['payload']);
    final tableId = payload['table_id'] as String?;
    final table = tableId == null ? null : _requireTable(tableId);
    final revision = (payload['expected_revision'] as num?)?.toInt();
    if (operation != 'create' && revision == null) {
      throw StateError('表结构操作缺少预期版本。');
    }
    if (operation == 'delete' && table?.role != TableRole.custom) {
      throw StateError('默认表禁止删除。');
    }
    final proposal = _normalizeProposal(
      actionId,
      operation,
      table,
      data,
      revision,
    );
    return TableChatAction(
      id: actionId,
      operation: 'table.$operation',
      title: proposal['title'] as String,
      status: TableChatActionStatus.pendingConfirmation,
      createdAt: createdAt,
      tableId: proposal['table_id'] as String?,
      tableTitle: table?.title ?? proposal['title'] as String?,
      expectedRevision: proposal['expected_revision'] as int?,
      proposal: proposal,
      message: '此操作尚未执行，需要你在这里确认。',
    );
  }

  Future<TableChatAction> confirmStructure(TableChatAction action) async {
    if (action.status != TableChatActionStatus.pendingConfirmation) {
      return action;
    }
    final proposal = action.proposal;
    final operation = proposal['operation'] as String? ?? '';
    final payload = _objectMap(proposal['payload']);
    final tableId = proposal['table_id'] as String?;
    final expected = (proposal['expected_revision'] as num?)?.toInt();
    try {
      if (operation == 'create') {
        final id = _requiredString(proposal, 'table_id');
        final title = _requiredString(payload, 'title');
        final existing = _tables.findTable(id);
        if (existing != null) {
          if (existing.role == TableRole.custom && existing.title == title) {
            return action.copyWith(
              status: TableChatActionStatus.applied,
              message: '该表已创建。',
            );
          }
          return action.copyWith(
            status: TableChatActionStatus.stale,
            message: '目标表 ID 已对应其他表，请重新提出。',
          );
        }
        await _tables.createTable(id: id, title: title);
        return action.copyWith(
          status: TableChatActionStatus.applied,
          message: '已创建表。',
        );
      }

      if (tableId == null || expected == null) {
        return action.copyWith(
          status: TableChatActionStatus.failed,
          message: '结构候选缺少表 ID 或预期版本。',
        );
      }
      final table = _tables.findTable(tableId);
      if (operation == 'delete') {
        final batch = await _tables.deleteTable(
          id: tableId,
          expectedRevision: expected,
          idempotencyKey: action.id,
        );
        return action.copyWith(
          status: TableChatActionStatus.applied,
          message: '表及内容已移入回收站，可在 30 天内恢复。',
          recoveryBatchId: batch.id,
          undoUntil: batch.expiresAt,
        );
      }
      if (table == null || table.deleted) {
        return action.copyWith(
          status: TableChatActionStatus.stale,
          message: '目标表已不存在，请重新读取表列表后提出变更。',
        );
      }
      if (table.revision != expected) {
        if (table.revision == expected + 1 &&
            _structureAlreadyApplied(operation, payload, table)) {
          return action.copyWith(
            status: TableChatActionStatus.applied,
            message: '该表结构变更已执行。',
          );
        }
        return action.copyWith(
          status: TableChatActionStatus.stale,
          message: '表已在确认前发生变化。请重新读取并提出新的结构候选。',
        );
      }

      switch (operation) {
        case 'rename':
          await _tables.updateTable(
            table.copyWith(title: _requiredString(payload, 'name')),
            expectedRevision: expected,
          );
        case 'upsert_field':
          final field = _fieldFromProposal(payload);
          final fields = [...table.fields];
          final index = fields.indexWhere((item) => item.id == field.id);
          if (index < 0) {
            fields.add(field);
          } else {
            fields[index] = field;
          }
          await _tables.updateTable(
            table.copyWith(fields: fields),
            expectedRevision: expected,
          );
        case 'delete_field':
          final batch = await _tables.removeTableField(
            tableId: table.id,
            fieldId: _requiredString(payload, 'field_id'),
            expectedRevision: expected,
            idempotencyKey: action.id,
          );
          return action.copyWith(
            status: TableChatActionStatus.applied,
            message: '字段已删除，30 天内可撤销。',
            recoveryBatchId: batch.id,
            undoUntil: batch.expiresAt,
          );
        default:
          return action.copyWith(
            status: TableChatActionStatus.failed,
            message: '不支持的表结构操作。',
          );
      }
      return action.copyWith(
        status: TableChatActionStatus.applied,
        message: '表结构已更新。',
      );
    } on Object catch (error) {
      return action.copyWith(
        status: TableChatActionStatus.failed,
        message: _errorMessage(error),
      );
    }
  }

  TableChatAction rejectStructure(TableChatAction action) => action.copyWith(
    status: TableChatActionStatus.rejected,
    message: '已拒绝，未修改表结构。',
  );

  Future<void> undoDelete(TableChatAction action) async {
    final batchId = action.recoveryBatchId;
    if (batchId == null || !action.canUndo) {
      throw StateError('内容恢复时限已过或恢复批次缺失。');
    }
    await _tables.restoreRecoveryBatch(batchId);
  }

  Map<String, Object?> _normalizeProposal(
    String actionId,
    String operation,
    TableDocument? table,
    Map<String, Object?> payload,
    int? revision,
  ) {
    final digest = sha256.convert(utf8.encode(actionId)).toString();
    switch (operation) {
      case 'create':
        final title = _requiredString(payload, 'title').trim();
        if (title.isEmpty) throw StateError('表名不能为空。');
        return {
          'operation': operation,
          'table_id': 'tb_ai_${digest.substring(0, 24)}',
          'expected_revision': null,
          'payload': {'title': title},
          'title': title,
        };
      case 'rename':
        final name = _requiredString(payload, 'name').trim();
        if (name.isEmpty) throw StateError('表名不能为空。');
        return {
          'operation': operation,
          'table_id': table!.id,
          'expected_revision': revision ?? table.revision,
          'payload': {'name': name},
          'title': name,
        };
      case 'delete':
        return {
          'operation': operation,
          'table_id': table!.id,
          'expected_revision': revision ?? table.revision,
          'payload': {
            'content_count': _tables.entries
                .where((entry) => entry.tableId == table.id)
                .length,
          },
          'title': table.title,
        };
      case 'upsert_field':
        final raw = _objectMap(payload['field'] ?? payload);
        final name = _requiredString(raw, 'name').trim();
        final type = _requiredString(raw, 'type');
        if (!CustomFieldType.values.any((value) => value.name == type)) {
          throw StateError('字段类型无效。');
        }
        final fieldId =
            raw['id'] as String? ?? 'fld_ai_${digest.substring(0, 20)}';
        final options = (raw['options'] as List? ?? const [])
            .asMap()
            .entries
            .map((item) {
              final option = _objectMap(item.value);
              return {
                'id':
                    option['id'] as String? ??
                    'opt_ai_${digest.substring(0, 16)}_${item.key}',
                'label': _requiredString(option, 'label').trim(),
              };
            })
            .toList(growable: false);
        return {
          'operation': operation,
          'table_id': table!.id,
          'expected_revision': revision ?? table.revision,
          'payload': {
            'field': {
              'id': fieldId,
              'name': name,
              'type': type,
              'options': options,
              'required': raw['required'] == true,
            },
          },
          'title': name,
        };
      case 'delete_field':
        final fieldId = _requiredString(payload, 'field_id');
        final field = table!.fields
            .where((item) => item.id == fieldId)
            .firstOrNull;
        if (field == null) throw StateError('字段不存在。');
        return {
          'operation': operation,
          'table_id': table.id,
          'expected_revision': revision ?? table.revision,
          'payload': {
            'field_id': fieldId,
            'value_count': _tables.entries
                .where(
                  (entry) =>
                      entry.tableId == table.id &&
                      entry.customValues.containsKey(fieldId),
                )
                .length,
          },
          'title': field.name,
        };
      default:
        throw StateError('不支持的表结构操作。');
    }
  }

  TableFieldDefinition _fieldFromProposal(Map<String, dynamic> payload) {
    final field = _objectMap(payload['field']);
    final type = CustomFieldType.values
        .where((value) => value.name == field['type'])
        .firstOrNull;
    if (type == null) throw StateError('字段类型无效。');
    final options = (field['options'] as List? ?? const [])
        .map((value) {
          final option = _objectMap(value);
          return TableFieldOption(
            id: _requiredString(option, 'id'),
            label: _requiredString(option, 'label'),
          );
        })
        .toList(growable: false);
    return TableFieldDefinition(
      id: _requiredString(field, 'id'),
      name: _requiredString(field, 'name'),
      type: type,
      options: options,
      required: field['required'] == true,
    );
  }

  bool _structureAlreadyApplied(
    String operation,
    Map<String, dynamic> payload,
    TableDocument table,
  ) {
    switch (operation) {
      case 'rename':
        return table.title == payload['name'];
      case 'upsert_field':
        final field = _fieldFromProposal(payload);
        final proposedOptions = jsonEncode([
          for (final option in field.options)
            {'id': option.id, 'label': option.label},
        ]);
        return table.fields.any(
          (item) =>
              item.id == field.id &&
              item.name == field.name &&
              item.type == field.type &&
              jsonEncode([
                    for (final option in item.options)
                      {'id': option.id, 'label': option.label},
                  ]) ==
                  proposedOptions,
        );
      case 'delete_field':
        return !table.fields.any((item) => item.id == payload['field_id']);
      default:
        return false;
    }
  }

  TableDocument _requireTable(String id) {
    final table = _tables.findTable(id);
    if (table == null || table.deleted) throw StateError('表不存在或已删除：$id');
    return table;
  }

  TableChatAction _applied(
    String id,
    String operation,
    DateTime createdAt,
    String title,
    TableDocument table, {
    TableEntryDocument? entry,
    String? recoveryBatchId,
    DateTime? undoUntil,
    String? message,
  }) => TableChatAction(
    id: id,
    operation: operation,
    title: title,
    status: TableChatActionStatus.applied,
    createdAt: createdAt,
    tableId: table.id,
    tableTitle: table.title,
    entryId: entry?.id,
    entryType: entry?.type.name,
    recoveryBatchId: recoveryBatchId,
    undoUntil: undoUntil,
    message: message,
  );

  TableChatAction _failed(
    String id,
    String operation,
    DateTime createdAt,
    String message,
  ) => TableChatAction(
    id: id,
    operation: operation,
    title: '表内操作未执行',
    status: TableChatActionStatus.failed,
    createdAt: createdAt,
    message: message,
  );

  Map<String, dynamic> _decode(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map) throw const FormatException('工具参数必须是对象。');
    return Map<String, dynamic>.from(decoded);
  }

  void _requireKeys(Map<String, dynamic> value, Set<String> allowed) {
    final unknown = value.keys.where((key) => !allowed.contains(key));
    if (unknown.isNotEmpty) throw StateError('包含不支持字段：${unknown.join('、')}');
  }

  String _requiredString(
    Map<String, dynamic> value,
    String key, {
    String? fallback,
  }) {
    final result = value[key];
    if (result is String) return result;
    if (fallback != null) return fallback;
    throw StateError('缺少文本字段：$key');
  }

  String _string(
    Map<String, dynamic> value,
    String key, {
    required String fallback,
  }) => value[key] is String ? value[key] as String : fallback;

  int _requiredInt(Map<String, dynamic> value, String key) {
    final result = value[key];
    if (result is num) return result.toInt();
    throw StateError('缺少版本字段：$key');
  }

  DateTime? _date(Object? value) {
    if (value == null) return null;
    if (value is! String) throw StateError('日期时间必须为 ISO 文本。');
    final date = DateTime.tryParse(value);
    if (date == null) throw StateError('日期时间格式无效。');
    return date;
  }

  TableContentType _parseType(Object? value) =>
      TableContentType.values.where((type) => type.name == value).firstOrNull ??
      (throw StateError('表内内容类型无效。'));

  List<String> _stringList(Object? value) {
    if (value == null) return const [];
    if (value is! List || value.any((item) => item is! String)) {
      throw StateError('标签必须是字符串列表。');
    }
    return value.cast<String>();
  }

  Map<String, Object?> _objectMap(Object? value) {
    if (value == null) return const {};
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw StateError('对象字段格式无效。');
    }
    return Map<String, Object?>.from(value);
  }

  Map<String, String> _stringMap(Object? value) => {
    for (final item in _objectMap(value).entries)
      if (item.value is String) item.key: item.value as String,
  };

  Map<String, Map<String, String>> _nestedStringMap(Object? value) => {
    for (final entry in _objectMap(value).entries)
      if (entry.value is Map) entry.key: _stringMap(entry.value),
  };

  bool _sameCreatedEntry(
    TableEntryDocument entry, {
    required String tableId,
    required TableContentType type,
    required String title,
    required String body,
    required DateTime? due,
    required DateTime? start,
    required DateTime? end,
    required DateTime? occurredAt,
    required List<String> tags,
    required bool done,
    required Map<String, Object?> customValues,
  }) =>
      entry.tableId == tableId &&
      entry.type == type &&
      entry.title == title &&
      entry.body == body &&
      entry.due == due &&
      entry.start == start &&
      entry.end == end &&
      entry.occurredAt == occurredAt &&
      entry.done == done &&
      jsonEncode(entry.tags) == jsonEncode(tags) &&
      jsonEncode(entry.customValues) == jsonEncode(customValues);

  bool _sameEntryState(TableEntryDocument left, TableEntryDocument right) =>
      left.title == right.title &&
      left.body == right.body &&
      left.due == right.due &&
      left.start == right.start &&
      left.end == right.end &&
      left.occurredAt == right.occurredAt &&
      left.done == right.done &&
      jsonEncode(left.customValues) == jsonEncode(right.customValues) &&
      jsonEncode(left.tags) == jsonEncode(right.tags);

  String _errorMessage(Object error) =>
      error is StateError ? error.message : error.toString();
}
