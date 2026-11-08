import 'dart:convert';

import '../../core/agent_usage.dart';
import '../../data/vault_store.dart';

enum AgentTurnQueueKind {
  conversation('conversation'),
  steering('steering');

  const AgentTurnQueueKind(this.wireName);

  final String wireName;

  static AgentTurnQueueKind parse(String value) {
    return AgentTurnQueueKind.values.firstWhere(
      (kind) => kind.wireName == value,
      orElse: () => throw FormatException('未知 Agent turn 队列类型：$value'),
    );
  }
}

enum AgentTurnCheckpointStatus {
  queued('queued'),
  running('running'),
  paused('paused'),
  waitingInput('waiting_input'),
  needsReview('needs_review');

  const AgentTurnCheckpointStatus(this.wireName);

  final String wireName;

  static AgentTurnCheckpointStatus parse(String value) {
    return AgentTurnCheckpointStatus.values.firstWhere(
      (status) => status.wireName == value,
      orElse: () => throw FormatException('未知 Agent turn 状态：$value'),
    );
  }
}

class AgentTurnCheckpoint {
  const AgentTurnCheckpoint({
    required this.taskId,
    required this.conversationId,
    required this.userMessageId,
    required this.kind,
    required this.status,
    required this.sequence,
    this.assistantMessageId,
    this.thinkingEnabled = false,
    this.excludedMessageIds = const {},
    this.runId,
  });

  final String taskId;
  final String? runId;
  String get effectiveRunId => runId ?? taskId;
  final String conversationId;
  final String userMessageId;
  final AgentTurnQueueKind kind;
  final AgentTurnCheckpointStatus status;
  final int sequence;
  final String? assistantMessageId;
  final bool thinkingEnabled;
  final Set<String> excludedMessageIds;

  AgentTurnCheckpoint copyWith({
    AgentTurnQueueKind? kind,
    AgentTurnCheckpointStatus? status,
    String? assistantMessageId,
  }) => AgentTurnCheckpoint(
    taskId: taskId,
    runId: runId,
    conversationId: conversationId,
    userMessageId: userMessageId,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    sequence: sequence,
    assistantMessageId: assistantMessageId ?? this.assistantMessageId,
    thinkingEnabled: thinkingEnabled,
    excludedMessageIds: excludedMessageIds,
  );

  Map<String, Object?> toJson() => {
    'task_id': taskId,
    'run_id': effectiveRunId,
    'conversation_id': conversationId,
    'user_message_id': userMessageId,
    'kind': kind.wireName,
    'status': status.wireName,
    'sequence': sequence,
    if (assistantMessageId != null) 'assistant_message_id': assistantMessageId,
    'thinking_enabled': thinkingEnabled,
    'excluded_message_ids': excludedMessageIds.toList(growable: false),
  };

  static AgentTurnCheckpoint fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Agent turn 必须是对象');
    String requiredString(String key) {
      final raw = value[key];
      if (raw is! String || raw.trim().isEmpty) {
        throw FormatException('Agent turn 字段 $key 类型错误');
      }
      return raw;
    }

    final sequence = value['sequence'];
    final rawExcluded = value['excluded_message_ids'] ?? const [];
    if (sequence is! int ||
        sequence < 0 ||
        rawExcluded is! List ||
        rawExcluded.any((id) => id is! String)) {
      throw const FormatException('Agent turn 序号或排除消息格式错误');
    }
    return AgentTurnCheckpoint(
      taskId: requiredString('task_id'),
      runId: switch (value['run_id'] ?? value['budget_run_id']) {
        null => null,
        final raw when raw is String && raw.trim().isNotEmpty => raw,
        _ => throw const FormatException('Agent turn 字段 run_id 类型错误'),
      },
      conversationId: requiredString('conversation_id'),
      userMessageId: requiredString('user_message_id'),
      kind: AgentTurnQueueKind.parse(requiredString('kind')),
      status: AgentTurnCheckpointStatus.parse(requiredString('status')),
      sequence: sequence,
      assistantMessageId: value['assistant_message_id'] is String
          ? value['assistant_message_id'] as String
          : null,
      thinkingEnabled: value['thinking_enabled'] == true,
      excludedMessageIds: Set.unmodifiable(rawExcluded.cast<String>()),
    );
  }
}

class AgentTaskCheckpoint {
  const AgentTaskCheckpoint({
    this.usage = const AgentUsage(),
    this.turns = const [],
    this.runUsage = const {},
    this.activeRunId,
  });

  static const currentSchemaVersion = 3;
  static const storagePath = '.local/agent-task-checkpoint.json';

  final AgentUsage usage;
  final Map<String, AgentUsage> runUsage;
  final String? activeRunId;
  final List<AgentTurnCheckpoint> turns;

  bool get needsReview =>
      turns.any((turn) => turn.status == AgentTurnCheckpointStatus.needsReview);

  Map<String, Object?> toJson() => {
    'schema_version': currentSchemaVersion,
    'usage': usage.toJson(),
    'run_usage': runUsage.map((id, usage) => MapEntry(id, usage.toJson())),
    if (activeRunId != null) 'active_run_id': activeRunId,
    'turns': turns.map((turn) => turn.toJson()).toList(growable: false),
  };

  static AgentTaskCheckpoint fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Agent 任务检查点必须是对象');
    final version = value['schema_version'];
    if (version != 1 && version != 2 && version != currentSchemaVersion) {
      throw FormatException('不支持 Agent 任务检查点版本：$version');
    }
    final rawTurns = value['turns'];
    if (rawTurns is! List) throw const FormatException('Agent turns 必须是列表');
    var turns =
        rawTurns
            .map(
              (raw) => AgentTurnCheckpoint.fromJson(
                version == 1 && raw is Map
                    ? {...raw, 'budget_run_id': 'legacy'}
                    : raw,
              ),
            )
            .toList()
          ..sort((left, right) => left.sequence.compareTo(right.sequence));
    final taskIds = <String>{};
    for (final turn in turns) {
      if (!taskIds.add(turn.taskId)) {
        throw FormatException('Agent turn taskId 重复：${turn.taskId}');
      }
    }
    final legacy = version != currentSchemaVersion;
    final rawUsage = legacy
        ? value['budget'] ?? value['usage']
        : value['usage'];
    final usage = _usageFromJson(rawUsage);
    final rawRunUsage = legacy ? value['run_budgets'] : value['run_usage'];
    if (!legacy && rawRunUsage is! Map) {
      throw const FormatException('任务用量必须是对象');
    }
    final runUsage = version == 1
        ? <String, AgentUsage>{if (turns.isNotEmpty) 'legacy': usage}
        : Map<String, AgentUsage>.fromEntries(
            (rawRunUsage as Map).entries.map((entry) {
              if (entry.key is! String || (entry.key as String).isEmpty) {
                throw const FormatException('任务用量 ID 无效');
              }
              return MapEntry(entry.key as String, _usageFromJson(entry.value));
            }),
          );
    final activeRunId = version == 1
        ? (turns.isEmpty ? null : 'legacy')
        : value[legacy ? 'active_budget_run_id' : 'active_run_id'];
    if (activeRunId != null &&
        (activeRunId is! String || !runUsage.containsKey(activeRunId))) {
      throw const FormatException('当前任务用量引用无效');
    }
    if (version != 1 &&
        turns.any((turn) => !runUsage.containsKey(turn.effectiveRunId))) {
      throw const FormatException('任务用量缺失');
    }
    if (legacy && _legacyBudgetExhausted(value['budget'])) {
      turns = [
        for (final turn in turns)
          turn.status == AgentTurnCheckpointStatus.paused
              ? turn.copyWith(status: AgentTurnCheckpointStatus.queued)
              : turn,
      ];
    }
    return AgentTaskCheckpoint(
      usage: usage,
      runUsage: Map.unmodifiable(runUsage),
      activeRunId: activeRunId as String?,
      turns: List.unmodifiable(turns),
    );
  }

  static AgentUsage _usageFromJson(Object? value) {
    if (value is! Map) throw const FormatException('Agent 用量必须是对象');
    final requests = value['used_requests'];
    final activeMillis = value['used_active_ms'];
    final toolCalls = value['used_tool_calls'] ?? 0;
    if (requests is! int ||
        requests < 0 ||
        activeMillis is! int ||
        activeMillis < 0 ||
        toolCalls is! int ||
        toolCalls < 0) {
      throw const FormatException('Agent 用量字段类型错误');
    }
    return AgentUsage(
      usedRequests: requests,
      usedActiveMillis: activeMillis,
      usedToolCalls: toolCalls,
    );
  }

  static bool _legacyBudgetExhausted(Object? value) {
    if (value is! Map) return false;
    final usedRequests = value['used_requests'];
    final grantedRequests = value['granted_requests'];
    final usedActive = value['used_active_ms'];
    final grantedActive = value['granted_active_ms'];
    if (usedRequests is! int ||
        grantedRequests is! int ||
        usedActive is! int ||
        grantedActive is! int) {
      return false;
    }
    return usedRequests >= grantedRequests || usedActive >= grantedActive;
  }
}

abstract interface class AgentTaskStore {
  /// Validates persisted task state before application modules or background
  /// execution are initialized. Valid v1 state is upgraded before startup.
  Future<AgentTaskCheckpoint> preflight();

  Future<AgentTaskCheckpoint> load();

  Future<void> save(AgentTaskCheckpoint checkpoint);
}

class MemoryAgentTaskStore implements AgentTaskStore {
  AgentTaskCheckpoint checkpoint = const AgentTaskCheckpoint();
  int saveCount = 0;

  @override
  Future<AgentTaskCheckpoint> preflight() => load();

  @override
  Future<AgentTaskCheckpoint> load() async => checkpoint;

  @override
  Future<void> save(AgentTaskCheckpoint checkpoint) async {
    this.checkpoint = checkpoint;
    saveCount++;
  }
}

class VaultAgentTaskStore implements AgentTaskStore {
  VaultAgentTaskStore(
    this._vault, {
    this.relativePath = AgentTaskCheckpoint.storagePath,
  });

  final VaultStore _vault;
  final String relativePath;
  AgentTaskCheckpoint? _preflightedCheckpoint;

  @override
  Future<AgentTaskCheckpoint> preflight() async {
    _preflightedCheckpoint = null;
    final checkpoint = await _vault.exclusive(() async {
      final raw = await _readPrimaryOrFailOnRecoverySidecar();
      if (raw == null) return const AgentTaskCheckpoint();
      if (raw.trim().isEmpty) {
        throw const FormatException('Agent 任务检查点为空或损坏');
      }
      final decoded = jsonDecode(raw);
      final checkpoint = AgentTaskCheckpoint.fromJson(decoded);
      if (decoded is Map &&
          decoded['schema_version'] !=
              AgentTaskCheckpoint.currentSchemaVersion) {
        await _preserveLegacySource(raw);
        final upgraded = const JsonEncoder.withIndent('  ')
            .convert(checkpoint.toJson());
        try {
          await _vault.write(relativePath, upgraded);
        } on Object catch (error, stackTrace) {
          await _vault.write(relativePath, raw);
          Error.throwWithStackTrace(error, stackTrace);
        }
      }
      return checkpoint;
    });
    _preflightedCheckpoint = checkpoint;
    return checkpoint;
  }

  @override
  Future<AgentTaskCheckpoint> load() async {
    final preflighted = _preflightedCheckpoint;
    if (preflighted != null) {
      _preflightedCheckpoint = null;
      return preflighted;
    }
    return _loadPersisted();
  }

  Future<AgentTaskCheckpoint> _loadPersisted() async {
    return _vault.exclusive(() async {
      final raw = await _readPrimaryOrFailOnRecoverySidecar();
      if (raw == null) return const AgentTaskCheckpoint();
      if (raw.trim().isEmpty) {
        throw const FormatException('Agent 任务检查点为空或损坏');
      }
      final decoded = jsonDecode(raw);
      return AgentTaskCheckpoint.fromJson(decoded);
    });
  }

  @override
  Future<void> save(AgentTaskCheckpoint checkpoint) {
    _preflightedCheckpoint = null;
    final contents = const JsonEncoder.withIndent('  ')
        .convert(checkpoint.toJson());
    return _vault.exclusive(() async {
      final previous = await _readPrimaryOrFailOnRecoverySidecar();
      if (previous != null) {
        final decoded = jsonDecode(previous);
        // Refuse to replace corrupt or newer state and retain the original v1
        // snapshot before the first upgrade write.
        AgentTaskCheckpoint.fromJson(decoded);
        if ((decoded as Map)['schema_version'] !=
            AgentTaskCheckpoint.currentSchemaVersion) {
          await _preserveLegacySource(previous);
        }
      }
      try {
        await _vault.write(relativePath, contents);
      } on Object catch (error, stackTrace) {
        if (previous != null) await _vault.write(relativePath, previous);
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
  }

  Future<void> _preserveLegacySource(String source) async {
    final backupPath = '$relativePath.v1.backup';
    final existingBackup = await _vault.read(backupPath);
    if (existingBackup == null) {
      await _vault.write(backupPath, source);
    } else if (existingBackup != source) {
      throw StateError('Agent v1 备份与待升级检查点不一致；保留两份文件并停止启动。');
    }
  }

  Future<String?> _readPrimaryOrFailOnRecoverySidecar() async {
    final primary = await _vault.read(relativePath);
    if (primary != null) return primary;
    for (final suffix in const ['.tmp', '.restore.tmp', '.v1.backup']) {
      if (await _vault.read('$relativePath$suffix') != null) {
        throw StateError('Agent 任务检查点缺失但恢复侧文件存在；保留原文件并停止启动。');
      }
    }
    return null;
  }
}
