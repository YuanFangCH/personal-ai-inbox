import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/chat_models.dart';
import '../../core/models.dart';
import '../../data/chat_repository.dart';
import '../capture/capture_workflow.dart';
import '../results/result_library.dart';

/// Applies the guarded auto-record rules after a complete model stream.
///
/// This module only creates new results. It never updates or deletes an
/// existing result, and it routes uncertain candidates into the review queue.
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
    List<ToolCallAccumulator> calls,
  ) async {
    final actions = <AutoRecordAction>[];
    for (final call in calls) {
      if (call.name != 'create_result' || call.arguments.isEmpty) {
        continue;
      }
      final action = await _process(
        assistantMessageId,
        call.arguments.toString(),
      );
      if (action != null) {
        actions.add(action);
      }
    }
    return actions;
  }

  Future<AutoRecordAction?> _process(
    String assistantMessageId,
    String rawArguments,
  ) async {
    final actionId = _chatRepository.newActionId();
    final createdAt = DateTime.now();
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
    final confidence = (payload['confidence'] as num?)?.toDouble() ?? 0;
    final sensitive = payload['sensitive'] == true;
    final recurrence = payload['recurrence']?.toString().trim() ?? '';
    final due = _parseDate(payload['due']);
    final start = _parseDate(payload['start']);
    final end = _parseDate(payload['end']);
    final allDay = payload['all_day'] == true;
    final tags = _stringList(payload['tags']);
    final candidateAt = type == ResultType.event ? start : due;

    String? reviewReason;
    if (title.isEmpty || body.isEmpty) {
      reviewReason = '标题或正文为空';
    } else if (confidence < 0.85) {
      reviewReason = '置信度低于 85%';
    } else if (sensitive) {
      reviewReason = '敏感内容需要人工确认';
    } else if (recurrence.isNotEmpty) {
      reviewReason = '重复规则需要人工确认';
    } else if (type == ResultType.event && start == null) {
      reviewReason = '事件缺少开始时间';
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
        id: 'cap_${const Uuid().v4()}',
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

    final document = await _results.createManual(
      type: type,
      title: title,
      body: body,
      status: ResultStatus.canonical,
      tags: tags,
      due: type == ResultType.todo ? due : null,
      start: type == ResultType.event ? start : null,
      end: type == ResultType.event ? end : null,
      allDay: allDay,
    );
    return AutoRecordAction(
      id: actionId,
      type: type,
      title: document.title,
      status: AutoRecordStatus.created,
      createdAt: createdAt,
      resultId: document.id,
      undoUntil: createdAt.add(const Duration(minutes: 10)),
    );
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
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}
