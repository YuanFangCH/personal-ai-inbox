import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/chat_models.dart';
import '../../core/models.dart';
import '../../data/chat_repository.dart';
import '../capture/capture_workflow.dart';
import '../results/result_library.dart';

/// Applies permission-checked result actions after a complete model stream.
///
/// New results retain the guarded auto-record rules; modifications and deletes
/// use revision-bound reversible actions and cannot target global knowledge.
class AutoRecordProcessor {
  AutoRecordProcessor({
    required ChatRepository chatRepository,
    required ResultLibrary results,
    required CaptureWorkflow captures,
    required String Function() deviceId,
  }) : _chatRepository = chatRepository,
       _results = results,
       _captures = captures,
       _deviceId = deviceId;

  final ChatRepository _chatRepository;
  final ResultLibrary _results;
  final CaptureWorkflow _captures;
  final String Function() _deviceId;

  Future<List<AutoRecordAction>> processToolCalls(
    String assistantMessageId,
    List<ToolCallAccumulator> calls, {
    DateTime? completedAt,
  }) async {
    final actions = <AutoRecordAction>[];
    final assistant = await _chatRepository.findMessage(assistantMessageId);
    final conversation = assistant == null
        ? null
        : await _chatRepository.findConversation(assistant.conversationId);
    final permissions =
        conversation?.aiPermissions ??
        const AiPermissions(read: false, create: false, modifyDelete: false);
    var sourceUserMessageId = assistantMessageId;
    if (assistant != null) {
      for (final message in await _chatRepository.listMessages(
        assistant.conversationId,
      )) {
        if (message.role == ChatRole.user &&
            !message.createdAt.isAfter(assistant.createdAt)) {
          sourceUserMessageId = message.id;
        }
      }
    }
    final createdAt = completedAt ?? assistant?.createdAt ?? DateTime.now();
    for (final call in calls) {
      if (call.arguments.isEmpty) {
        continue;
      }
      final stableKey =
          'conversation:$sourceUserMessageId:${call.index ?? call.id ?? calls.indexOf(call)}';
      final actionId =
          'act_${sha256.convert(utf8.encode(stableKey)).toString().substring(0, 24)}';
      final existingAction = await _chatRepository.findAutoRecordAction(
        actionId,
      );
      if (existingAction != null) {
        actions.add(existingAction);
        continue;
      }
      final action = switch (call.name) {
        'create_result' =>
          permissions.create
              ? await _process(stableKey, createdAt, call.arguments.toString())
              : _skipped(actionId, createdAt, '当前会话未开启新增权限'),
        'update_result' || 'delete_result' =>
          permissions.modifyDelete
              ? await _processModifyDelete(
                  call.name!,
                  actionId,
                  createdAt,
                  call.arguments.toString(),
                )
              : _skipped(actionId, createdAt, '当前会话未开启修改和删除权限'),
        _ => null,
      };
      if (action != null) {
        actions.add(action);
      }
    }
    return actions;
  }

  Future<AutoRecordAction?> _process(
    String idempotencyKey,
    DateTime createdAt,
    String rawArguments,
  ) async {
    final actionId =
        'act_${sha256.convert(utf8.encode(idempotencyKey)).toString().substring(0, 24)}';
    dynamic decoded;
    try {
      decoded = jsonDecode(rawArguments);
    } on FormatException {
      return _skipped(actionId, createdAt, '模型返回的记录结构无效');
    }
    if (decoded is! Map) {
      return _skipped(actionId, createdAt, '模型返回的记录结构无效');
    }
    final payload = decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final structuralError = _validatePayload(payload);
    if (structuralError != null) {
      return _skipped(actionId, createdAt, structuralError);
    }
    ResultType type;
    try {
      type = ResultType.parse(payload['type'].toString());
    } on FormatException {
      return AutoRecordAction(
        id: actionId,
        type: ResultType.knowledge,
        title: payload['title']?.toString() ?? '无法识别的记录',
        status: AutoRecordStatus.skipped,
        createdAt: createdAt,
        reason: '成果类型无效',
      );
    }
    final title = payload['title']?.toString().trim() ?? '';
    final body = payload['body']?.toString().trim() ?? '';
    final confidence = (payload['confidence'] as num).toDouble();
    final sensitive = payload['sensitive'] == true;
    final recurrence = payload['recurrence']?.toString().trim() ?? '';
    final due = _parseDate(payload['due']);
    final start = _parseDate(payload['start']);
    final end = _parseDate(payload['end']);
    final allDay = payload['all_day'] == true;
    final tags = _stringList(payload['tags']);
    final candidateAt = type == ResultType.event ? start : due;

    final savedAction = await _chatRepository.findAutoRecordAction(actionId);
    if (savedAction != null) {
      if (savedAction.status == AutoRecordStatus.created) {
        final reversibleAction = await _results.reversibleActionForKey(
          actionId,
        );
        final recoveredStatus = switch (reversibleAction?.status) {
          ReversibleActionStatus.applied => AutoRecordStatus.created,
          ReversibleActionStatus.undone => AutoRecordStatus.undone,
          ReversibleActionStatus.expired => AutoRecordStatus.expired,
          ReversibleActionStatus.undoing ||
          ReversibleActionStatus.failed ||
          null => AutoRecordStatus.undoFailed,
          ReversibleActionStatus.prepared => AutoRecordStatus.undoFailed,
        };
        if (recoveredStatus != savedAction.status) {
          return savedAction.copyWith(
            status: recoveredStatus,
            reason: recoveredStatus == AutoRecordStatus.undoFailed
                ? '无法核对当前操作状态，请检查成果库'
                : null,
          );
        }
      }
      return savedAction;
    }
    final previouslyCreated = await _results.findByIdempotencyKey(
      type: type,
      createdAt: createdAt,
      idempotencyKey: idempotencyKey,
    );
    if (previouslyCreated != null) {
      if (!_matchesCandidate(
        previouslyCreated,
        type,
        title,
        body,
        tags,
        due,
        start,
        end,
        allDay,
      )) {
        return _skipped(actionId, createdAt, '同一自动记录请求对应的成果内容不同');
      }
      final action = await _results.reversibleActionForKey(actionId);
      return AutoRecordAction(
        id: actionId,
        type: type,
        title: previouslyCreated.title,
        status: AutoRecordStatus.created,
        createdAt: previouslyCreated.createdAt,
        resultId: previouslyCreated.id,
        undoUntil: action?.undoUntil,
      );
    }

    String? reviewReason;
    if (title.isEmpty || body.isEmpty) {
      reviewReason = '标题或正文为空';
    } else if (confidence < 0.85) {
      reviewReason = '置信度低于 85%';
    } else if (sensitive) {
      reviewReason = '敏感内容需要人工确认';
    } else if (recurrence.isNotEmpty) {
      reviewReason = '重复规则需要人工确认';
    } else if ((type != ResultType.todo && due != null) ||
        (type != ResultType.event &&
            (start != null || end != null || allDay))) {
      reviewReason = '日期字段与成果类型不匹配';
    } else if (_hasInvalidDate(payload, 'due') ||
        _hasInvalidDate(payload, 'start') ||
        _hasInvalidDate(payload, 'end')) {
      reviewReason = '日期格式无效，需要人工确认';
    } else if (type == ResultType.event && start == null) {
      reviewReason = '事件缺少开始时间';
    } else if (type == ResultType.event &&
        end != null &&
        start != null &&
        end.isBefore(start)) {
      reviewReason = '事件结束时间早于开始时间';
    } else if ((start ?? due) != null &&
        (start ?? due)!.isBefore(DateTime.now())) {
      reviewReason = '日期已经过去';
    } else if (await _isDuplicate(type, title, candidateAt)) {
      return AutoRecordAction(
        id: actionId,
        type: type,
        title: title,
        status: AutoRecordStatus.skipped,
        createdAt: createdAt,
        reason: '已存在相同成果',
      );
    }

    if (reviewReason != null) {
      final capture = CaptureRecord(
        id: 'cap_${sha256.convert(utf8.encode(idempotencyKey)).toString().substring(0, 24)}',
        deviceId: _deviceId(),
        capturedAt: createdAt,
        sourceType: CaptureSourceType.text,
        text: body.isEmpty ? title : body,
        status: CaptureStatus.needsReview,
        candidateType: type,
        candidateTitle: title.isEmpty ? '待整理' : title,
        candidateAt: candidateAt,
        confidence: confidence,
        reviewReason: reviewReason,
      );
      await _captures.enqueueReview(capture);
      return AutoRecordAction(
        id: actionId,
        type: type,
        title: capture.candidateTitle!,
        status: AutoRecordStatus.review,
        createdAt: createdAt,
        captureId: capture.id,
        reason: reviewReason,
      );
    }

    final operation = await _results.createManualWithUndo(
      type: type,
      title: title,
      body: body,
      status: ResultStatus.canonical,
      tags: tags,
      due: type == ResultType.todo ? due : null,
      start: type == ResultType.event ? start : null,
      end: type == ResultType.event ? end : null,
      allDay: allDay,
      actionId: actionId,
      idempotencyKey: idempotencyKey,
      createdAt: createdAt,
    );
    final document = operation.document;
    return AutoRecordAction(
      id: actionId,
      type: type,
      title: document.title,
      status: AutoRecordStatus.created,
      createdAt: document.createdAt,
      resultId: document.id,
      undoUntil: operation.action.undoUntil,
    );
  }

  Future<AutoRecordAction?> _processModifyDelete(
    String operation,
    String actionId,
    DateTime createdAt,
    String rawArguments,
  ) async {
    dynamic decoded;
    try {
      decoded = jsonDecode(rawArguments);
    } on FormatException {
      return _skipped(actionId, createdAt, '模型返回的成果操作结构无效');
    }
    if (decoded is! Map) {
      return _skipped(actionId, createdAt, '模型返回的成果操作结构无效');
    }
    final payload = decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    const allowed = {'id', 'expected_revision', 'title', 'body'};
    if (payload.keys.any((key) => !allowed.contains(key)) ||
        (payload['title'] != null && payload['title'] is! String) ||
        (payload['body'] != null && payload['body'] is! String)) {
      return _skipped(actionId, createdAt, '成果操作字段无效');
    }
    final id = payload['id'];
    final expectedRevision = payload['expected_revision'];
    if (id is! String || expectedRevision is! num) {
      return _skipped(actionId, createdAt, '成果操作缺少稳定 ID 或版本');
    }
    final previousAction = await _results.reversibleActionForKey(actionId);
    if (previousAction != null &&
        previousAction.status != ReversibleActionStatus.prepared &&
        previousAction.status != ReversibleActionStatus.failed) {
      final current = await _results.readDocument(id);
      if (current == null) {
        return _skipped(actionId, createdAt, '已提交成果操作缺少当前对象');
      }
      return AutoRecordAction(
        id: actionId,
        type: current.type,
        title: current.title,
        status: switch (previousAction.status) {
          ReversibleActionStatus.undone => AutoRecordStatus.undone,
          ReversibleActionStatus.expired => AutoRecordStatus.expired,
          ReversibleActionStatus.failed => AutoRecordStatus.undoFailed,
          _ => AutoRecordStatus.created,
        },
        createdAt: previousAction.createdAt,
        resultId: id,
        undoUntil: previousAction.undoUntil,
        operation: AutoRecordOperation.values.byName(previousAction.kind.name),
      );
    }
    final document = await _results.readDocument(id);
    if (document == null ||
        document.deleted ||
        document.status != ResultStatus.canonical ||
        document.isGlobalKnowledge ||
        document.revision != expectedRevision.toInt()) {
      return _skipped(actionId, createdAt, '成果已变化或不属于普通成果，请重新读取');
    }
    final expectedHash = await _results.hashManagedDocument(id);
    if (expectedHash == null) {
      return _skipped(actionId, createdAt, '成果文件不可读取');
    }
    try {
      final result = operation == 'delete_result'
          ? await _results.deleteWithUndo(
              id: id,
              expectedRevision: document.revision,
              expectedHash: expectedHash,
              actionId: actionId,
            )
          : await _results.modifyWithUndo(
              document: document.copyWith(
                title: payload['title'] as String? ?? document.title,
                body: payload['body'] as String? ?? document.body,
              ),
              expectedRevision: document.revision,
              expectedHash: expectedHash,
              actionId: actionId,
            );
      return AutoRecordAction(
        id: actionId,
        type: document.type,
        title: result.document.title,
        status: AutoRecordStatus.created,
        createdAt: createdAt,
        resultId: document.id,
        undoUntil: result.action.undoUntil,
        operation: operation == 'delete_result'
            ? AutoRecordOperation.delete
            : AutoRecordOperation.update,
      );
    } on StateError catch (error) {
      return _skipped(actionId, createdAt, error.message);
    }
  }

  AutoRecordAction _skipped(
    String actionId,
    DateTime createdAt,
    String reason,
  ) {
    return AutoRecordAction(
      id: actionId,
      type: ResultType.knowledge,
      title: '无法解析的自动记录',
      status: AutoRecordStatus.skipped,
      createdAt: createdAt,
      reason: reason,
    );
  }

  String? _validatePayload(Map<String, dynamic> payload) {
    const allowed = {
      'type',
      'title',
      'body',
      'tags',
      'confidence',
      'sensitive',
      'due',
      'start',
      'end',
      'all_day',
      'recurrence',
    };
    if (payload.keys.any((key) => !allowed.contains(key))) {
      return '模型返回了未支持的字段';
    }
    if (payload['type'] is! String ||
        payload['title'] is! String ||
        payload['body'] is! String) {
      return '成果类型、标题和正文必须是文本';
    }
    final confidence = payload['confidence'];
    if (confidence is! num ||
        !confidence.isFinite ||
        confidence < 0 ||
        confidence > 1) {
      return '置信度格式无效';
    }
    if (payload['sensitive'] is! bool) {
      return '敏感状态缺失或格式无效';
    }
    if (payload.containsKey('tags') &&
        (payload['tags'] is! List ||
            (payload['tags'] as List).any((value) => value is! String))) {
      return '标签格式无效';
    }
    if (payload.containsKey('all_day') && payload['all_day'] is! bool) {
      return '全天标记格式无效';
    }
    final recurrence = payload['recurrence'];
    if (recurrence != null && recurrence is! String) {
      return '重复规则格式无效';
    }
    for (final field in const ['due', 'start', 'end']) {
      final value = payload[field];
      if (value != null && value is! String) {
        return '$field 日期格式无效';
      }
    }
    return null;
  }

  bool _matchesCandidate(
    ResultDocument existing,
    ResultType type,
    String title,
    String body,
    List<String> tags,
    DateTime? due,
    DateTime? start,
    DateTime? end,
    bool allDay,
  ) {
    final normalizedTags = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet();
    return existing.type == type &&
        existing.title == title &&
        existing.body == body &&
        existing.tags.length == normalizedTags.length &&
        existing.tags.every(normalizedTags.contains) &&
        existing.due == (type == ResultType.todo ? due : null) &&
        existing.start == (type == ResultType.event ? start : null) &&
        existing.end == (type == ResultType.event ? end : null) &&
        existing.allDay == (type == ResultType.event && allDay);
  }

  bool _hasInvalidDate(Map<String, dynamic> payload, String field) {
    final value = payload[field];
    return value is String && DateTime.tryParse(value) == null;
  }

  Future<bool> _isDuplicate(ResultType type, String title, DateTime? at) async {
    final normalized = title.trim().toLowerCase();
    for (final document in _results.documents) {
      if (document.type != type ||
          document.deleted ||
          document.title.trim().toLowerCase() != normalized) {
        continue;
      }
      final existingAt = document.type == ResultType.event
          ? document.start
          : document.type == ResultType.todo
          ? document.due
          : null;
      if (at == null || existingAt == null) {
        return true;
      }
      if (existingAt.difference(at).abs() < const Duration(minutes: 1)) {
        return true;
      }
    }
    return false;
  }

  DateTime? _parseDate(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') {
      return null;
    }
    return DateTime.tryParse(text)?.toLocal();
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}

class ToolCallAccumulator {
  int? index;
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}
