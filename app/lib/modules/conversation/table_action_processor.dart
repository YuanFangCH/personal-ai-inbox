import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/ai_policy.dart';
import '../../core/chat_models.dart';
import '../../core/models.dart';
import '../../core/table_models.dart';
import '../../data/chat_repository.dart';
import '../../data/table_repository.dart';
import '../tables/table_library.dart';
import 'auto_record_processor.dart';
import 'content_duplicate_policy.dart';
import 'content_intake.dart';

/// Applies table content calls after the model has completed its full reply.
/// Table-structure calls are stored as pending chat actions for button review.
class TableActionProcessor {
  TableActionProcessor({
    required ChatRepository chatRepository,
    required TableLibrary tables,
    SemanticDuplicateDecisionSource? semanticDuplicateDecisionSource,
    AiPolicy Function(Conversation conversation)? policyResolver,
  }) : _chatRepository = chatRepository,
       _tables = tables,
       _contentIntake = ContentIntake(
         tables: tables,
         semanticDecisionSource: semanticDuplicateDecisionSource,
       ),
       _policyResolver =
           policyResolver ?? ((conversation) => conversation.effectiveAiPolicy);

  final ChatRepository _chatRepository;
  final TableLibrary _tables;
  final ContentIntake _contentIntake;
  final AiPolicy Function(Conversation conversation) _policyResolver;

  Future<void> acknowledgeInboxAssignmentOperation(
    TableChatAction action,
  ) async {
    final proposal = action.proposal;
    if (action.operation != 'table.assign_inbox_target' ||
        action.status != TableChatActionStatus.applied ||
        proposal['operation'] != 'assign_inbox_target') {
      throw StateError('收纳目标回执缺少已应用的原始操作。');
    }
    final payload = _objectMap(proposal['payload']);
    final kind = InboxAssignmentKind.parse(_requiredString(payload, 'kind'));
    final expectedRevision = _requiredInt(proposal, 'expected_revision');
    final expectedPrevious = _optionalString(
      payload,
      'expected_current_table_id',
    );
    final tableId = _optionalString(proposal, 'table_id');
    await _tables.acknowledgeInboxAssignmentOperation(
      operationId: action.id,
      kind: kind,
      expectedRevision: expectedRevision,
      expectedPreviousTableId: expectedPrevious,
      tableId: tableId,
    );
  }

  Future<void> reconcileInboxAssignmentJournal() async {
    final operationId = await _tables.pendingInboxAssignmentOperationId();
    if (operationId == null) return;
    final found = await _chatRepository.findTableChatAction(operationId);
    if (found?.$2.status == TableChatActionStatus.applied) {
      await acknowledgeInboxAssignmentOperation(found!.$2);
    }
  }

  Future<List<TableChatAction>> processToolCalls(
    String assistantMessageId,
    List<ToolCallAccumulator> calls, {
    DateTime? completedAt,
  }) async {
    final assistant = await _chatRepository.findMessage(assistantMessageId);
    if (assistant == null) return const [];
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
          'conversation:$assistantMessageId:${call.index ?? call.id ?? calls.indexOf(call)}';
      final actionId =
          'act_${sha256.convert(utf8.encode(stableKey)).toString().substring(0, 24)}';
      final String fingerprint;
      try {
        fingerprint = sha256
            .convert(
              utf8.encode(
                jsonEncode([
                  name,
                  _canonicalRequestValue(_decode(call.arguments.toString())),
                ]),
              ),
            )
            .toString();
      } on FormatException {
        actions.add(_failed(actionId, name, createdAt, '工具参数不是有效 JSON 对象。'));
        continue;
      }
      final legacyKey =
          'conversation:$sourceUserMessageId:${call.index ?? call.id ?? calls.indexOf(call)}';
      final legacyId =
          'act_${sha256.convert(utf8.encode(legacyKey)).toString().substring(0, 24)}';
      final existing =
          await _chatRepository.findTableChatAction(actionId) ??
          await _chatRepository.findTableChatAction(legacyId);
      if (existing != null) {
        final previous = existing.$2;
        actions.add(
          previous.operation == name &&
                  previous.requestFingerprint == fingerprint
              ? previous
              : _failed(
                  actionId,
                  name,
                  createdAt,
                  '此操作位置已有不同或无法核对的执行记录，请核对后重新发起。',
                ),
        );
        continue;
      }
      final conversation = await _chatRepository.findConversation(
        assistant.conversationId,
      );
      final effectivePolicy = conversation == null
          ? AiPolicy.forPreset(AiPolicyPreset.readOnly)
          : _policyResolver(conversation);
      final payload = _decode(call.arguments.toString());
      final permission =
          name == 'table.propose' &&
              payload['operation'] == 'assign_inbox_target'
          ? await _inboxAssignmentPermission(
              payload,
              effectivePolicy,
              operationId: actionId,
            )
          : _permissionFor(name, payload, effectivePolicy);
      if (permission == AiPolicyDecision.deny) {
        actions.add(_failed(actionId, name, createdAt, '当前会话权限不允许此操作。'));
        continue;
      }
      if (permission == AiPolicyDecision.ask && name != 'table.propose') {
        actions.add(_failed(actionId, name, createdAt, '此操作需要用户确认后才能执行。'));
        continue;
      }
      try {
        var action = switch (name) {
          'content.create' => await _create(
            actionId,
            payload,
            createdAt,
            conversationId: assistant.conversationId,
            sourceUserMessageId: sourceUserMessageId,
          ),
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
        if (name == 'table.propose' && permission == AiPolicyDecision.allow) {
          action = await _confirmStructureUnchecked(
            action,
            authorizationGuard: payload['operation'] == 'assign_inbox_target'
                ? () => _inboxAssignmentPolicyGuard(
                    assistant.conversationId,
                    payload,
                    requireAllow: true,
                  )
                : null,
          );
        }
        actions.add(action.copyWith(requestFingerprint: fingerprint));
      } on Object catch (error) {
        actions.add(_failed(actionId, name, createdAt, _errorMessage(error)));
      }
    }
    return List.unmodifiable(actions);
  }

  Object? _canonicalRequestValue(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonicalRequestValue(value[key])};
    }
    if (value is List) return value.map(_canonicalRequestValue).toList();
    return value;
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

  AiPolicyDecision _permissionFor(
    String name,
    Map<String, dynamic> payload,
    AiPolicy policy,
  ) {
    switch (name) {
      case 'content.create':
        final tableId = _optionalString(payload, 'table_id');
        return policy.decisionFor(
          AiPermissionAction.contentCreate,
          tableIds: [?tableId],
        );
      case 'table.body.update':
        final tableId = _optionalString(payload, 'table_id');
        return policy.decisionFor(
          AiPermissionAction.tableBodyUpdate,
          tableIds: [?tableId],
        );
      case 'content.update':
        final id = _optionalString(payload, 'id');
        final tableId = id == null
            ? null
            : _tables.entries
                  .where((entry) => entry.id == id)
                  .firstOrNull
                  ?.tableId;
        return policy.decisionFor(
          AiPermissionAction.contentUpdate,
          tableIds: [?tableId],
        );
      case 'content.move':
        final id = _optionalString(payload, 'id');
        final sourceTableId = id == null
            ? null
            : _tables.entries
                  .where((entry) => entry.id == id)
                  .firstOrNull
                  ?.tableId;
        final targetTableId = _optionalString(payload, 'to_table_id');
        return policy.decisionFor(
          AiPermissionAction.contentMove,
          tableIds: [?sourceTableId, ?targetTableId],
        );
      case 'content.delete':
        final id = _optionalString(payload, 'id');
        final tableId = id == null
            ? null
            : _tables.entries
                  .where((entry) => entry.id == id)
                  .firstOrNull
                  ?.tableId;
        return policy.decisionFor(
          AiPermissionAction.contentDelete,
          tableIds: [?tableId],
        );
      case 'schedule.change':
        final scheduleId = _optionalString(payload, 'schedule_id');
        final tableId = scheduleId == null
            ? null
            : _tables.entries
                  .where((entry) => entry.id == scheduleId)
                  .firstOrNull
                  ?.tableId;
        return _combinePolicyDecisions([
          policy.decisionFor(
            AiPermissionAction.contentCreate,
            tableIds: [?tableId],
          ),
          policy.decisionFor(
            AiPermissionAction.contentUpdate,
            tableIds: [?tableId],
          ),
        ]);
      case 'table.propose':
        final action = switch (payload['operation']) {
          'create' => AiPermissionAction.tableCreate,
          'rename' => AiPermissionAction.tableUpdate,
          'delete' => AiPermissionAction.tableDelete,
          'upsert_field' || 'delete_field' => AiPermissionAction.fieldAdjust,
          'assign_inbox_target' => AiPermissionAction.inboxTargetAdjust,
          _ => null,
        };
        if (action == null) return AiPolicyDecision.deny;
        return policy.decisionFor(
          action,
          tableIds: [
            ?_optionalString(payload, 'table_id'),
            if (payload['operation'] == 'assign_inbox_target')
              ?_optionalString(
                _objectMap(payload['payload']),
                'expected_current_table_id',
              ),
          ],
        );
      default:
        return AiPolicyDecision.deny;
    }
  }

  Future<AiPolicyDecision> _inboxAssignmentPermission(
    Map<String, dynamic> proposal,
    AiPolicy policy, {
    required String operationId,
  }) async {
    try {
      final rawPayload = _objectMap(proposal['payload']);
      if (!_inboxAssignmentTargetValuesAreValid(proposal, rawPayload)) {
        return AiPolicyDecision.deny;
      }
      final kind = InboxAssignmentKind.parse(
        _requiredString(rawPayload, 'kind'),
      );
      final expectedRevision = _requiredInt(proposal, 'expected_revision');
      final expectedPrevious = _optionalString(
        rawPayload,
        'expected_current_table_id',
      );
      final targetTableId = _optionalString(proposal, 'table_id');
      if (!_inboxAssignmentPolicyAllows(proposal, policy)) {
        return AiPolicyDecision.deny;
      }
      final tableIds = <String>{?expectedPrevious, ?targetTableId};
      for (final tableId in tableIds) {
        final table = await _tables.readTable(tableId);
        if (table == null || table.deleted) return AiPolicyDecision.deny;
      }
      final committed = await _tables.committedInboxAssignmentReceipt(
        operationId: operationId,
        kind: kind,
        expectedRevision: expectedRevision,
        expectedPreviousTableId: expectedPrevious,
        tableId: targetTableId,
      );
      final decision = policy.decisionFor(
        AiPermissionAction.inboxTargetAdjust,
        tableIds: tableIds,
      );
      if (committed != null) return decision;
      final current = await _tables.readInboxAssignments();
      if (current.revision != expectedRevision ||
          current.targetFor(kind) != expectedPrevious) {
        return AiPolicyDecision.deny;
      }
      return decision;
    } on Object {
      return AiPolicyDecision.deny;
    }
  }

  bool _inboxAssignmentPolicyAllows(
    Map<String, dynamic> proposal,
    AiPolicy policy,
  ) {
    final payload = _objectMap(proposal['payload']);
    if (!_inboxAssignmentTargetValuesAreValid(proposal, payload)) return false;
    final expectedPrevious = _optionalString(
      payload,
      'expected_current_table_id',
    );
    final targetTableId = _optionalString(proposal, 'table_id');
    final tableIds = <String>{?expectedPrevious, ?targetTableId};
    if (tableIds.any((id) => !policy.tableScope.covers(id))) return false;
    return policy.decisionFor(
          AiPermissionAction.inboxTargetAdjust,
          tableIds: tableIds,
        ) !=
        AiPolicyDecision.deny;
  }

  bool _inboxAssignmentTargetValuesAreValid(
    Map<String, dynamic> proposal,
    Map<String, dynamic> payload,
  ) =>
      (proposal['table_id'] == null || proposal['table_id'] is String) &&
      (payload['expected_current_table_id'] == null ||
          payload['expected_current_table_id'] is String);

  Future<bool> _inboxAssignmentPolicyGuard(
    String conversationId,
    Map<String, dynamic> proposal, {
    required bool requireAllow,
  }) async {
    final conversation = await _chatRepository.findConversation(conversationId);
    if (conversation == null) return false;
    final rawPayload = _objectMap(proposal['payload']);
    final policy = _policyResolver(conversation);
    final tableIds = <String>{
      ?_optionalString(rawPayload, 'expected_current_table_id'),
      ?_optionalString(proposal, 'table_id'),
    };
    final decision = policy.decisionFor(
      AiPermissionAction.inboxTargetAdjust,
      tableIds: tableIds,
    );
    if (tableIds.any((id) => !policy.tableScope.covers(id))) return false;
    return requireAllow
        ? decision == AiPolicyDecision.allow
        : decision != AiPolicyDecision.deny;
  }

  AiPolicyDecision _combinePolicyDecisions(
    Iterable<AiPolicyDecision> decisions,
  ) {
    final values = decisions.toList(growable: false);
    if (values.contains(AiPolicyDecision.deny)) return AiPolicyDecision.deny;
    if (values.contains(AiPolicyDecision.ask)) return AiPolicyDecision.ask;
    return AiPolicyDecision.allow;
  }

  String? _optionalString(Map<String, dynamic> value, String key) =>
      value[key] is String ? value[key] as String : null;

  Future<TableChatAction> _create(
    String actionId,
    Map<String, dynamic> payload,
    DateTime createdAt, {
    required String conversationId,
    required String sourceUserMessageId,
    String? intakeOperationId,
    bool persistAuthorizationConflict = true,
  }) async {
    _requireKeys(payload, const {
      'table_id',
      'type',
      'title',
      'body',
      'tags',
      'due',
      'start',
      'end',
      'all_day',
      'recurrence',
      'occurred_at',
      'done',
      'custom_values',
      'idempotency_key',
    });
    final tableId = _requiredString(payload, 'table_id');
    _requireTable(tableId);
    final type = _parseType(payload['type']);
    final title = _requiredString(payload, 'title').trim();
    if (title.isEmpty) throw StateError('标题不能为空。');
    final body = _string(payload, 'body', fallback: '');
    final tags = _stringList(payload['tags']);
    final due = _date(payload['due']);
    final start = _date(payload['start']);
    final end = _date(payload['end']);
    final occurredAt = _date(payload['occurred_at']);
    if (payload['all_day'] != null && payload['all_day'] is! bool) {
      throw StateError('all_day 必须是布尔值。');
    }
    if (payload['done'] != null && payload['done'] is! bool) {
      throw StateError('done 必须是布尔值。');
    }
    if (payload['recurrence'] != null && payload['recurrence'] is! String) {
      throw StateError('recurrence 必须是文本。');
    }
    final allDay = payload['all_day'] == true;
    final recurrence = payload['recurrence'] as String?;
    if (type == TableContentType.schedule && start == null) {
      throw StateError('日程必须提供开始时间。');
    }
    if (start != null && end != null && !end.isAfter(start)) {
      throw StateError('结束时间必须晚于开始时间。');
    }
    final values = _objectMap(payload['custom_values']);
    final idempotencyKey = _requiredString(payload, 'idempotency_key').trim();
    if (idempotencyKey.isEmpty) throw StateError('幂等键不能为空。');
    final evidence = contentObjectEvidenceKey(
      type: type,
      title: title,
      due: due,
      start: start,
      end: end,
      occurredAt: occurredAt,
      allDay: allDay,
      recurrence: recurrence,
      customValues: values,
    );
    final request = ContentIntakeRequest(
      operationId: intakeOperationId ?? 'legacy:$actionId',
      tableId: tableId,
      type: type,
      title: title,
      body: body,
      identity: ContentBusinessIdentity(evidence: [evidence]),
      tags: tags,
      due: due,
      done: payload['done'] == true,
      start: start,
      end: end,
      allDay: allDay,
      recurrence: recurrence,
      occurredAt: occurredAt,
      customValues: values,
      sourceRefs: [
        'conversation:$conversationId',
        'message:$sourceUserMessageId',
        'idempotency:$idempotencyKey',
      ],
      requestedEntryId: 'nt_${actionId.substring(4)}',
    );
    final preparation = await _contentIntake.prepare(request);
    final currentConversation = await _chatRepository.findConversation(
      conversationId,
    );
    final policy = currentConversation == null
        ? AiPolicy.forPreset(AiPolicyPreset.readOnly)
        : _policyResolver(currentConversation);
    if (preparation.outcome == ContentIntakeOutcome.augmented) {
      final targetId = preparation.targetId;
      final target = targetId == null
          ? null
          : await _tables.readEntry(targetId);
      if (target == null) throw StateError('自动补充目标不存在。');
      final decision = policy.decisionFor(
        AiPermissionAction.contentUpdate,
        tableIds: [target.tableId],
      );
      if (decision != AiPolicyDecision.allow) {
        if (intakeOperationId != null) {
          return TableChatAction(
            id: actionId,
            operation: 'content.create',
            title: title,
            status: TableChatActionStatus.pendingRetry,
            createdAt: createdAt,
            tableId: tableId,
            entryType: type.name,
            message: '当前授权已变化；没有写入。原始内容和操作编号仍待执行。',
            proposal: Map<String, Object?>.from(payload),
            requestFingerprint: null,
            intakeCoverageChecked:
                preparation.coverage.semanticCandidatesChecked,
            intakeCoverageTotal: preparation.coverage.semanticCandidatesTotal,
            intakeCoverageComplete:
                preparation.coverage.semanticComparisonComplete,
            retryableIntake: true,
            intakeRetryOperationId: intakeOperationId,
            intakeRetryPending: true,
          );
        }
        return _failed(
          actionId,
          'content.create',
          createdAt,
          decision == AiPolicyDecision.deny
              ? '当前会话没有自动补充既有内容的修改权限。'
              : '自动补充既有内容需要用户确认。',
        );
      }
    }
    final result = await _contentIntake.commit(
      preparation,
      now: createdAt,
      persistAuthorizationConflict: persistAuthorizationConflict,
      authorizationGuard: (authorization) async {
        final current = await _chatRepository.findConversation(conversationId);
        if (current == null) return false;
        final currentPolicy = _policyResolver(current);
        if (currentPolicy.decisionFor(
              AiPermissionAction.contentCreate,
              tableIds: [tableId],
            ) !=
            AiPolicyDecision.allow) {
          return false;
        }
        final action = authorization.kind == ContentIntakeWriteKind.create
            ? AiPermissionAction.contentCreate
            : AiPermissionAction.contentUpdate;
        return currentPolicy.decisionFor(
              action,
              tableIds: [authorization.tableId],
            ) ==
            AiPolicyDecision.allow;
      },
    );
    final receiptConversation = await _chatRepository.findConversation(
      conversationId,
    );
    final receiptEntry = result.entry;
    if (receiptConversation == null ||
        (receiptEntry != null &&
            !_policyResolver(receiptConversation).tableScope
                .covers(receiptEntry.tableId))) {
      return _failed(
        actionId,
        'content.create',
        createdAt,
        '当前授权范围不足以返回接收结果，请调整权限后核对。',
      );
    }
    return _actionForIntake(
      actionId,
      result,
      createdAt,
      tableId: tableId,
      type: type,
      proposal: payload,
      retryOperationId: persistAuthorizationConflict ? null : intakeOperationId,
    );
  }

  TableChatAction _actionForIntake(
    String actionId,
    ContentIntakeResult result,
    DateTime createdAt, {
    required String tableId,
    required TableContentType type,
    required Map<String, dynamic> proposal,
    String? retryOperationId,
  }) {
    final entry = result.entry;
    if (result.outcome == ContentIntakeOutcome.conflict) {
      final incomplete = !result.coverage.semanticComparisonComplete;
      final authorizationFailed =
          retryOperationId != null &&
          (result.reason?.contains('授权') == true ||
              result.reason?.contains('权限') == true);
      if (incomplete || authorizationFailed) {
        return TableChatAction(
          id: actionId,
          operation: 'content.create',
          title: proposal['title']?.toString() ?? '未完成的内容接收',
          status: authorizationFailed
              ? TableChatActionStatus.pendingRetry
              : TableChatActionStatus.failed,
          createdAt: createdAt,
          tableId: tableId,
          entryType: type.name,
          message: authorizationFailed
              ? '${result.reason ?? '授权已变化，写入未执行。'} '
                    '重新授权后可继续同一扫描；操作编号尚未结算。'
              : '${result.reason ?? '查重覆盖不足，尚未写入。'} '
                    '已检查 ${result.coverage.semanticCandidatesChecked}/'
                    '${result.coverage.semanticCandidatesTotal} 个语义候选，'
                    '仍有 ${result.coverage.semanticCandidatesRemaining} 个未检查；'
                    '原始接收内容已保留，可在权限和额度允许后重新扫描。',
          proposal: Map<String, Object?>.from(proposal),
          intakeCoverageChecked: result.coverage.semanticCandidatesChecked,
          intakeCoverageTotal: result.coverage.semanticCandidatesTotal,
          intakeCoverageComplete: result.coverage.semanticComparisonComplete,
          retryableIntake: true,
          intakeRetryOperationId: retryOperationId,
          intakeRetryPending: authorizationFailed,
        );
      }
      return _failed(
        actionId,
        'content.create',
        createdAt,
        result.reason ?? '同一业务对象存在冲突，尚不能写入。',
      );
    }
    if (entry == null) {
      return _failed(actionId, 'content.create', createdAt, '内容接收没有返回实际结果。');
    }
    final table = _requireTable(entry.tableId);
    final message = switch (result.outcome) {
      ContentIntakeOutcome.created => '已新建内容。',
      ContentIntakeOutcome.reused => '已复用已有内容，没有创建重复记录。',
      ContentIntakeOutcome.augmented => '已补充到既有内容，没有创建重复记录。',
      ContentIntakeOutcome.conflict => '',
    };
    return _applied(
      actionId,
      'content.create',
      createdAt,
      entry.title,
      table,
      entry: entry,
      undoUntil: result.outcome == ContentIntakeOutcome.created
          ? createdAt.add(TableRepository.entryUndoWindow)
          : null,
      message: message,
    );
  }

  Future<TableChatAction> retryIncompleteIntake(
    TableChatAction action, {
    required String operationId,
  }) async {
    if (!action.retryableIntake || action.operation != 'content.create') {
      throw StateError('该操作没有待重扫的内容接收意图。');
    }
    final located = await _chatRepository.findTableChatAction(action.id);
    if (located == null ||
        located.$2.requestFingerprint != action.requestFingerprint) {
      throw StateError('待重扫意图已变化，请刷新后再试。');
    }
    final (message, storedAction) = located;
    final conversation = await _chatRepository.findConversation(
      message.conversationId,
    );
    final payload = Map<String, dynamic>.from(storedAction.proposal);
    final policy = conversation == null
        ? AiPolicy.forPreset(AiPolicyPreset.readOnly)
        : _policyResolver(conversation);
    if (_permissionFor('content.create', payload, policy) !=
        AiPolicyDecision.allow) {
      return storedAction.copyWith(
        status: TableChatActionStatus.pendingRetry,
        intakeRetryPending: true,
        message: '当前会话授权尚未允许重新扫描；待接收意图与扫描 ID 已保留。',
      );
    }
    final messages = await _chatRepository.listMessages(message.conversationId);
    var sourceUserMessageId = message.id;
    for (final candidate in messages) {
      if (candidate.role == ChatRole.user &&
          !candidate.createdAt.isAfter(message.createdAt)) {
        sourceUserMessageId = candidate.id;
      }
    }
    try {
      final result = await _create(
        storedAction.id,
        payload,
        DateTime.now(),
        conversationId: message.conversationId,
        sourceUserMessageId: sourceUserMessageId,
        intakeOperationId: operationId,
        persistAuthorizationConflict: false,
      );
      return result.copyWith(
        requestFingerprint: storedAction.requestFingerprint,
        intakeRetryAttempt: storedAction.intakeRetryAttempt,
        intakeRetryOperationId: operationId,
        intakeRetryPending: result.intakeRetryPending,
      );
    } on Object catch (error) {
      return storedAction.copyWith(
        status: TableChatActionStatus.pendingRetry,
        intakeRetryOperationId: operationId,
        intakeRetryPending: true,
        message: '重新扫描尚未完成，原始意图与扫描 ID 已保留：${_errorMessage(error)}',
      );
    }
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
    final eventTitle = _requiredString(payload, 'event_title');
    final eventBody = _string(payload, 'event_body', fallback: '');
    final eventOccurredAt = _date(payload['event_occurred_at']);
    if (eventOccurredAt == null) {
      throw StateError('改期通知缺少有效的原始发生时间。');
    }
    final eventIdentity = sha256
        .convert(
          utf8.encode(
            jsonEncode([scheduleId, eventOccurredAt.toUtc().toIso8601String()]),
          ),
        )
        .toString();
    final result = await _tables.changeScheduleFromEvent(
      scheduleId: scheduleId,
      expectedRevision: expected,
      start: start,
      end: _date(payload['new_end']),
      eventTitle: eventTitle,
      eventBody: eventBody,
      eventOccurredAt: eventOccurredAt,
      idempotencyKey: 'schedule-change-$eventIdentity',
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
      'assign_inbox_target',
    };
    if (!allowed.contains(operation)) throw StateError('表结构操作类型无效。');
    final data = _objectMap(payload['payload']);
    final tableId = payload['table_id'] as String?;
    final table = tableId == null ? null : _requireTable(tableId);
    final revision = (payload['expected_revision'] as num?)?.toInt();
    if (operation != 'create' && revision == null) {
      throw StateError('表结构操作缺少预期版本。');
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
    final located = await _chatRepository.findTableChatAction(action.id);
    if (located == null) {
      return action.copyWith(
        status: TableChatActionStatus.failed,
        message: '找不到此结构候选所属的会话，未执行。',
      );
    }
    final conversation = await _chatRepository.findConversation(
      located.$1.conversationId,
    );
    if (conversation == null) {
      return action.copyWith(
        status: TableChatActionStatus.failed,
        message: '会话已不存在，未执行结构变更。',
      );
    }
    final decision = action.proposal['operation'] == 'assign_inbox_target'
        ? await _inboxAssignmentPermission(
            Map<String, dynamic>.from(action.proposal),
            _policyResolver(conversation),
            operationId: action.id,
          )
        : _permissionFor(
            'table.propose',
            Map<String, dynamic>.from(action.proposal),
            _policyResolver(conversation),
          );
    if (decision == AiPolicyDecision.deny) {
      return action.copyWith(
        status: TableChatActionStatus.failed,
        message: '当前会话权限不允许此结构变更。',
      );
    }
    return _confirmStructureUnchecked(
      action,
      authorizationGuard: action.proposal['operation'] == 'assign_inbox_target'
          ? () => _inboxAssignmentPolicyGuard(
              located.$1.conversationId,
              Map<String, dynamic>.from(action.proposal),
              requireAllow: false,
            )
          : null,
    );
  }

  Future<TableChatAction> _confirmStructureUnchecked(
    TableChatAction action, {
    Future<bool> Function()? authorizationGuard,
  }) async {
    final proposal = action.proposal;
    final operation = proposal['operation'] as String? ?? '';
    final payload = _objectMap(proposal['payload']);
    final tableId = proposal['table_id'] as String?;
    final expected = (proposal['expected_revision'] as num?)?.toInt();
    try {
      if (operation == 'assign_inbox_target') {
        final rawPayload = _objectMap(proposal['payload']);
        final kind = InboxAssignmentKind.parse(
          _requiredString(rawPayload, 'kind'),
        );
        final receipt = await _tables.assignInboxTargetForOperation(
          operationId: action.id,
          kind: kind,
          expectedRevision: expected!,
          expectedPreviousTableId: _optionalString(
            rawPayload,
            'expected_current_table_id',
          ),
          tableId: tableId,
          authorizationGuard: authorizationGuard,
        );
        return action.copyWith(
          status: TableChatActionStatus.applied,
          message: receipt.previousTableId == receipt.tableId
              ? '收纳目标没有变化。'
              : receipt.tableId == null
              ? '已清除该收纳目标。'
              : '收纳目标已调整。',
        );
      }
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
    } on InboxAssignmentAuthorizationDeferred {
      return action.copyWith(
        status: TableChatActionStatus.pendingConfirmation,
        message: '当前授权已变化；没有修改收纳目标。该操作仍待再次确认。',
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
    if (!action.canUndo) {
      throw StateError('内容恢复时限已过或恢复批次缺失。');
    }
    if (batchId != null) {
      await _tables.restoreRecoveryBatch(batchId);
      return;
    }
    if (action.operation == 'content.create' && action.entryId != null) {
      final entry = await _tables.readEntry(action.entryId!);
      if (entry == null || entry.deleted) return;
      await _tables.deleteEntry(
        id: entry.id,
        expectedRevision: entry.revision,
        idempotencyKey: 'undo_${action.id}',
      );
      return;
    }
    throw StateError('此表操作不支持撤销。');
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
      case 'assign_inbox_target':
        final kind = InboxAssignmentKind.parse(
          _requiredString(payload, 'kind'),
        );
        final previousTableId = _optionalString(
          payload,
          'expected_current_table_id',
        );
        return {
          'operation': operation,
          'table_id': table?.id,
          'expected_revision': revision,
          'payload': {
            'kind': kind.wireName,
            'expected_current_table_id': previousTableId,
          },
          'title': '调整${kind.wireName}收纳目标',
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
