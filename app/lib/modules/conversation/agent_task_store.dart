import 'dart:convert';

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

class AgentBudgetCheckpoint {
  const AgentBudgetCheckpoint({
    this.usedRequests = 0,
    this.usedActiveMillis = 0,
    this.grantedRequests = 240,
    this.grantedActiveMillis = Duration.millisecondsPerHour * 2,
  });

  final int usedRequests;
  final int usedActiveMillis;
  final int grantedRequests;
  final int grantedActiveMillis;

  Duration get usedActive => Duration(milliseconds: usedActiveMillis);

  Duration get grantedActive => Duration(milliseconds: grantedActiveMillis);

  Duration get remainingActive {
    final remainingMilliseconds = grantedActiveMillis - usedActiveMillis;
    return Duration(
      milliseconds: remainingMilliseconds > 0 ? remainingMilliseconds : 0,
    );
  }

  int get remainingRequests {
    final remaining = grantedRequests - usedRequests;
    return remaining > 0 ? remaining : 0;
  }

  bool get exhausted =>
      remainingRequests <= 0 || remainingActive <= Duration.zero;

  AgentBudgetCheckpoint copyWith({
    int? usedRequests,
    int? usedActiveMillis,
    int? grantedRequests,
    int? grantedActiveMillis,
  }) => AgentBudgetCheckpoint(
    usedRequests: usedRequests ?? this.usedRequests,
    usedActiveMillis: usedActiveMillis ?? this.usedActiveMillis,
    grantedRequests: grantedRequests ?? this.grantedRequests,
    grantedActiveMillis: grantedActiveMillis ?? this.grantedActiveMillis,
  );

  Map<String, Object?> toJson() => {
    'used_requests': usedRequests,
    'used_active_ms': usedActiveMillis,
    'granted_requests': grantedRequests,
    'granted_active_ms': grantedActiveMillis,
  };

  static AgentBudgetCheckpoint fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Agent 预算必须是对象');
    int read(String key) {
      final raw = value[key];
      if (raw is! int || raw < 0) {
        throw FormatException('Agent 预算字段 $key 类型错误');
      }
      return raw;
    }

    return AgentBudgetCheckpoint(
      usedRequests: read('used_requests'),
      usedActiveMillis: read('used_active_ms'),
      grantedRequests: read('granted_requests'),
      grantedActiveMillis: read('granted_active_ms'),
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
    this.budgetRunId,
  });

  final String taskId;
  final String? budgetRunId;
  String get effectiveBudgetRunId => budgetRunId ?? taskId;
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
    budgetRunId: budgetRunId,
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
    'budget_run_id': effectiveBudgetRunId,
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
      budgetRunId: value['budget_run_id'] == null
          ? null
          : requiredString('budget_run_id'),
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
    this.budget = const AgentBudgetCheckpoint(),
    this.turns = const [],
    this.runBudgets = const {},
    this.activeBudgetRunId,
  });

  static const currentSchemaVersion = 2;
  static const storagePath = '.local/agent-task-checkpoint.json';

  final AgentBudgetCheckpoint budget;
  final Map<String, AgentBudgetCheckpoint> runBudgets;
  final String? activeBudgetRunId;
  final List<AgentTurnCheckpoint> turns;

  bool get needsReview =>
      turns.any((turn) => turn.status == AgentTurnCheckpointStatus.needsReview);

  Map<String, Object?> toJson() => {
    'schema_version': currentSchemaVersion,
    'budget': budget.toJson(),
    'run_budgets': runBudgets.map(
      (id, budget) => MapEntry(id, budget.toJson()),
    ),
    if (activeBudgetRunId != null) 'active_budget_run_id': activeBudgetRunId,
    'turns': turns.map((turn) => turn.toJson()).toList(growable: false),
  };

  static AgentTaskCheckpoint fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Agent 任务检查点必须是对象');
    final version = value['schema_version'];
    if (version != 1 && version != currentSchemaVersion) {
      throw FormatException('不支持 Agent 任务检查点版本：$version');
    }
    final rawTurns = value['turns'];
    if (rawTurns is! List) throw const FormatException('Agent turns 必须是列表');
    final turns =
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
    final budget = AgentBudgetCheckpoint.fromJson(value['budget']);
    final rawBudgets = value['run_budgets'];
    if (version == 2 && rawBudgets is! Map) {
      throw const FormatException('任务预算必须是对象');
    }
    final budgets = version == 1
        ? <String, AgentBudgetCheckpoint>{
            if (turns.isNotEmpty) 'legacy': budget,
          }
        : Map<String, AgentBudgetCheckpoint>.fromEntries(
            (rawBudgets as Map).entries.map((entry) {
              if (entry.key is! String || (entry.key as String).isEmpty) {
                throw const FormatException('任务预算ID无效');
              }
              return MapEntry(
                entry.key as String,
                AgentBudgetCheckpoint.fromJson(entry.value),
              );
            }),
          );
    final activeRunId = version == 1
        ? (turns.isEmpty ? null : 'legacy')
        : value['active_budget_run_id'];
    if (activeRunId != null &&
        (activeRunId is! String || !budgets.containsKey(activeRunId))) {
      throw const FormatException('当前任务预算引用无效');
    }
    if (version == 2 &&
        turns.any((turn) => !budgets.containsKey(turn.effectiveBudgetRunId))) {
      throw const FormatException('任务预算缺失');
    }
    return AgentTaskCheckpoint(
      budget: budget,
      runBudgets: Map.unmodifiable(budgets),
      activeBudgetRunId: activeRunId as String?,
      turns: List.unmodifiable(turns),
    );
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
      if (decoded is Map && decoded['schema_version'] == 1) {
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
        if ((decoded as Map)['schema_version'] == 1) {
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
