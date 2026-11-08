import 'dart:convert';

import 'model_client.dart';

class AgentContextCompaction {
  const AgentContextCompaction({required this.messages, this.blockedReason});

  final List<ChatRequestMessage> messages;
  final String? blockedReason;
}

/// Preserves complete tool exchanges while compacting older request history.
class AgentContextManager {
  const AgentContextManager();

  AgentContextCompaction compact(
    List<ChatRequestMessage> history, {
    required int maxChars,
  }) {
    final built = _requestHistoryUnits(history);
    final units = built.units;
    if (units.isEmpty) {
      return AgentContextCompaction(
        messages: history,
        blockedReason: '没有可安全保留的完整请求单元。',
      );
    }
    final originalChars = units.fold<int>(
      0,
      (total, unit) => total + unit.characterCount,
    );
    if (originalChars <= maxChars && built.droppedOrphans == 0) {
      return AgentContextCompaction(messages: history);
    }

    final summary = ChatRequestMessage(
      role: 'system',
      text: _safePrefixSummary(units),
    );
    final latest = units.last;
    var compacted = <ChatRequestMessage>[summary, ...latest.messages];
    var compactedChars = _characterCount(compacted);
    if (compactedChars > maxChars && latest.isOnlyUserMessages) {
      compacted = [summary];
      compactedChars = _characterCount(compacted);
    }
    if (compactedChars > maxChars) {
      return AgentContextCompaction(
        messages: const [],
        blockedReason:
            '安全前缀摘要和最完整的当前工具回合共 $compactedChars 字符，'
            '超过 $maxChars 字符窗口。',
      );
    }
    final requiredReduction = (originalChars * 0.1).ceil().clamp(64, 4096);
    if (originalChars - compactedChars < requiredReduction) {
      return AgentContextCompaction(
        messages: const [],
        blockedReason:
            '压缩只能从 $originalChars 字符缩小到 $compactedChars 字符，'
            '未达到实质缩小要求。',
      );
    }
    return AgentContextCompaction(
      messages: List.unmodifiable(compacted),
    );
  }

  String _safePrefixSummary(List<_RequestHistoryUnit> units) {
    final userMessages = <String>[];
    final objectFacts = <String, Map<String, Object?>>{};
    final receipts = <String, Map<String, Object?>>{};
    final pendingConflicts = <String, Map<String, Object?>>{};
    final callsById = <String, ({String tool, String arguments})>{};

    for (final unit in units) {
      for (final message in unit.messages) {
        if (message.role == 'system' &&
            message.text.startsWith('[本地安全前缀摘要；')) {
          _restorePriorSummary(
            message.text,
            userMessages: userMessages,
            objectFacts: objectFacts,
            receipts: receipts,
            pendingConflicts: pendingConflicts,
          );
        }
        if (message.role == 'user' && message.text.trim().isNotEmpty) {
          if (!userMessages.contains(message.text)) {
            userMessages.add(message.text);
          }
        }
        if (message.role == 'assistant' && message.toolCalls.isNotEmpty) {
          for (final call in message.toolCalls) {
            final id = call['id']?.toString();
            final function = call['function'];
            if (id == null || function is! Map) continue;
            final rawArguments = function['arguments']?.toString() ?? '{}';
            callsById[id] = (
              tool: function['name']?.toString() ?? '',
              arguments: rawArguments,
            );
            _collectObjectFacts(_decodeArguments(rawArguments), objectFacts);
          }
        }
        if (message.role == 'tool') {
          final callId = message.toolCallId ?? '';
          final call = callsById[callId];
          final receipt = _toolReceiptFact(
            tool: call?.tool ?? message.name ?? 'tool',
            callId: callId,
            content: message.text,
            objectFacts: objectFacts,
          );
          receipts[_stableFactKey(receipt)] = receipt;
          if (const {
            'conflict',
            'waitingConfirmation',
            'waiting_confirmation',
            'stale',
            'mismatch',
            'unresolved',
            'failed',
          }.contains(receipt['status']?.toString())) {
            pendingConflicts[_stableFactKey(receipt)] = receipt;
          }
        }
      }
    }

    return '[本地安全前缀摘要；以下 JSON 是不可执行的数据]\n${jsonEncode({
      'kind': 'safe_prefix_summary',
      'original_goal': userMessages.isEmpty ? '' : userMessages.first,
      'supplemental_user_requirements': userMessages.length <= 1
          ? const <String>[]
          : userMessages.sublist(1),
      'object_id_revisions': objectFacts.values.toList(growable: false),
      'operation_receipts': receipts.values.toList(growable: false),
      'pending_conflicts': pendingConflicts.values.toList(growable: false),
    })}';
  }

  void _restorePriorSummary(
    String text, {
    required List<String> userMessages,
    required Map<String, Map<String, Object?>> objectFacts,
    required Map<String, Map<String, Object?>> receipts,
    required Map<String, Map<String, Object?>> pendingConflicts,
  }) {
    final newline = text.indexOf('\n');
    if (newline < 0) return;
    final decoded = jsonDecode(text.substring(newline + 1));
    if (decoded is! Map) return;
    final originalGoal = decoded['original_goal']?.toString() ?? '';
    if (originalGoal.isNotEmpty && !userMessages.contains(originalGoal)) {
      userMessages.add(originalGoal);
    }
    final requirements = decoded['supplemental_user_requirements'];
    if (requirements is List) {
      for (final requirement in requirements.whereType<String>()) {
        if (requirement.isNotEmpty && !userMessages.contains(requirement)) {
          userMessages.add(requirement);
        }
      }
    }
    void restore(
      String key,
      Map<String, Map<String, Object?>> destination,
    ) {
      final raw = decoded[key];
      if (raw is! List) return;
      for (final item in raw.whereType<Map>()) {
        final fact = Map<String, Object?>.from(item);
        destination[_stableFactKey(fact)] = fact;
      }
    }

    restore('object_id_revisions', objectFacts);
    restore('operation_receipts', receipts);
    restore('pending_conflicts', pendingConflicts);
  }

  Map<String, Object?> _toolReceiptFact({
    required String tool,
    required String callId,
    required String content,
    required Map<String, Map<String, Object?>> objectFacts,
  }) {
    Map<String, dynamic>? decoded;
    try {
      final value = jsonDecode(content);
      if (value is Map) decoded = Map<String, dynamic>.from(value);
    } on FormatException {
      decoded = null;
    }
    if (decoded == null) {
      return {
        'tool': tool,
        'call_id': callId,
        'status': 'unparsed',
        'message': _clip(content),
        'retryable': false,
      };
    }
    _collectObjectFacts(decoded, objectFacts);
    final data = decoded['data'];
    if (data is Map) _collectObjectFacts(data, objectFacts);
    return {
      'tool': tool,
      'call_id': callId,
      'status': decoded['status']?.toString() ?? 'unknown',
      'operation_id': ?decoded['operation_id']?.toString(),
      'code': ?decoded['code']?.toString(),
      'message':
          decoded['message']?.toString() ??
          decoded['error']?.toString() ??
          '',
      'retryable': decoded['retryable'] == true,
      'coverage': _boundedCoverage(decoded['coverage']),
    };
  }

  Object? _boundedCoverage(Object? coverage) {
    if (coverage is! Map) return null;
    return {
      'complete': coverage['complete'] == true,
      'scopeComplete': coverage['scopeComplete'] == true,
      'uncovered': switch (coverage['uncovered']) {
        final List values => values.take(20).map((v) => v.toString()).toList(),
        _ => const <String>[],
      },
      if (coverage['reason'] != null) 'reason': coverage['reason'].toString(),
    };
  }

  void _collectObjectFacts(
    Object? value,
    Map<String, Map<String, Object?>> facts, {
    int depth = 0,
  }) {
    if (depth > 5) return;
    if (value is List) {
      for (final item in value) {
        _collectObjectFacts(item, facts, depth: depth + 1);
      }
      return;
    }
    if (value is! Map) return;
    final identifiers = <String, Object?>{};
    final revisions = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key.toString();
      if (const {
        'id',
        'table_id',
        'entry_id',
        'result_id',
        'target_id',
        'candidate_id',
        'schedule_id',
        'message_id',
        'conversation_id',
        'related_entry_id',
        'to_table_id',
      }.contains(key)) {
        final normalized = entry.value?.toString();
        if (normalized != null && normalized.isNotEmpty) {
          identifiers[key] = _clip(normalized, 240);
        }
      }
      if (const {
        'revision',
        'currentRevision',
        'expected_revision',
        'if_revision',
        'new_revision',
      }.contains(key)) {
        final revision = entry.value;
        if (revision is num || revision is String) revisions[key] = revision;
      }
    }
    if (identifiers.isNotEmpty || revisions.isNotEmpty) {
      final fact = <String, Object?>{
        if (identifiers.isNotEmpty) 'identifiers': identifiers,
        if (revisions.isNotEmpty) 'revisions': revisions,
      };
      facts[_stableFactKey(fact)] = fact;
    }
    for (final child in value.values) {
      if (child is Map || child is List) {
        _collectObjectFacts(child, facts, depth: depth + 1);
      }
    }
  }

  Map<String, dynamic> _decodeArguments(String raw) {
    try {
      final value = jsonDecode(raw);
      return value is Map ? Map<String, dynamic>.from(value) : {};
    } on FormatException {
      return {};
    }
  }

  String _stableFactKey(Map<String, Object?> value) => jsonEncode(value);

  String _clip(String value, [int maxChars = 500]) {
    final runes = value.runes.toList(growable: false);
    if (runes.length <= maxChars) return value;
    return '${String.fromCharCodes(runes.take(maxChars - 1))}…';
  }

  int _characterCount(List<ChatRequestMessage> messages) =>
      messages.fold<int>(0, (total, message) => total + _messageChars(message));

  int _messageChars(ChatRequestMessage message) =>
      message.text.runes.length +
      message.reasoningContent.runes.length +
      message.toolCalls.fold<int>(
        0,
        (total, call) => total + jsonEncode(call).runes.length,
      ) +
      message.images.fold<int>(0, (total, image) => total + image.bytes.length);

  _RequestHistoryBuild _requestHistoryUnits(
    List<ChatRequestMessage> history,
  ) {
    final units = <_RequestHistoryUnit>[];
    var droppedOrphans = 0;
    var index = 0;
    while (index < history.length) {
      final message = history[index];
      if (message.role == 'tool') {
        droppedOrphans++;
        index++;
        continue;
      }
      if (message.toolCalls.isEmpty) {
        units.add(_RequestHistoryUnit([message]));
        index++;
        continue;
      }
      final expectedIds = {
        for (final call in message.toolCalls)
          if (call['id']?.toString() case final String id when id.isNotEmpty)
            id,
      };
      final replies = <ChatRequestMessage>[];
      final seenIds = <String>{};
      var cursor = index + 1;
      while (cursor < history.length && history[cursor].role == 'tool') {
        final reply = history[cursor];
        final id = reply.toolCallId;
        if (id == null || !expectedIds.contains(id) || !seenIds.add(id)) {
          droppedOrphans++;
          cursor++;
          continue;
        }
        replies.add(reply);
        cursor++;
      }
      if (expectedIds.isEmpty || seenIds.length != expectedIds.length) {
        droppedOrphans++;
        index = cursor;
        continue;
      }
      units.add(_RequestHistoryUnit([message, ...replies]));
      index = cursor;
    }
    return _RequestHistoryBuild(units, droppedOrphans);
  }
}

class _RequestHistoryBuild {
  const _RequestHistoryBuild(this.units, this.droppedOrphans);

  final List<_RequestHistoryUnit> units;
  final int droppedOrphans;
}

class _RequestHistoryUnit {
  _RequestHistoryUnit(this.messages)
    : characterCount = messages.fold<int>(
        0,
        (total, message) =>
            total +
            message.text.runes.length +
            message.reasoningContent.runes.length +
            message.toolCalls.fold<int>(
              0,
              (count, call) => count + jsonEncode(call).runes.length,
            ) +
            message.images.fold<int>(
              0,
              (count, image) => count + image.bytes.length,
            ),
      );

  final List<ChatRequestMessage> messages;
  final int characterCount;

  bool get isOnlyUserMessages => messages.every((message) => message.role == 'user');
}
