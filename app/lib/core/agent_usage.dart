/// Observable Agent usage that is persisted for recovery and diagnostics.
///
/// Usage never grants or denies execution. The Harness runs until it completes,
/// fails, waits for the user, or is explicitly cancelled.
class AgentUsage {
  const AgentUsage({
    this.usedRequests = 0,
    this.usedActiveMillis = 0,
    this.usedToolCalls = 0,
  });

  final int usedRequests;
  final int usedActiveMillis;
  final int usedToolCalls;

  Duration get usedActive => Duration(milliseconds: usedActiveMillis);

  AgentUsage copyWith({
    int? usedRequests,
    int? usedActiveMillis,
    int? usedToolCalls,
  }) => AgentUsage(
    usedRequests: usedRequests ?? this.usedRequests,
    usedActiveMillis: usedActiveMillis ?? this.usedActiveMillis,
    usedToolCalls: usedToolCalls ?? this.usedToolCalls,
  );

  Map<String, Object?> toJson() => {
    'used_requests': usedRequests,
    'used_active_ms': usedActiveMillis,
    'used_tool_calls': usedToolCalls,
  };

  static AgentUsage fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Agent 用量必须是对象');
    int read(String key) {
      final raw = value[key] ?? 0;
      if (raw is! int || raw < 0) {
        throw FormatException('Agent 用量字段 $key 类型错误');
      }
      return raw;
    }

    return AgentUsage(
      usedRequests: read('used_requests'),
      usedActiveMillis: read('used_active_ms'),
      usedToolCalls: read('used_tool_calls'),
    );
  }
}

/// Runtime usage meter.
///
/// Counters are monotonic for one turn and are checkpointed by the workspace.
class AgentUsageMeter {
  AgentUsageMeter({
    AgentUsage initial = const AgentUsage(),
    Duration Function()? activeElapsedDuration,
  }) : _usedRequests = initial.usedRequests,
       _usedToolCalls = initial.usedToolCalls,
       _initialActive = initial.usedActive,
       _activeElapsedDuration = activeElapsedDuration;

  final Stopwatch _activeClock = Stopwatch();
  final Duration _initialActive;
  final Duration Function()? _activeElapsedDuration;
  int _usedRequests;
  int _usedToolCalls;

  int get requestCount => _usedRequests;
  int get toolCallCount => _usedToolCalls;

  Duration get activeDuration =>
      _initialActive + (_activeElapsedDuration?.call() ?? _activeClock.elapsed);

  AgentUsage snapshot() => AgentUsage(
    usedRequests: _usedRequests,
    usedActiveMillis: activeDuration.inMilliseconds,
    usedToolCalls: _usedToolCalls,
  );

  void beginActivity() {
    if (!_activeClock.isRunning) _activeClock.start();
  }

  void pauseActivity() {
    if (_activeClock.isRunning) _activeClock.stop();
  }

  void recordRequest() {
    _usedRequests++;
  }

  void recordToolCalls([int count = 1]) {
    if (count < 0) throw ArgumentError.value(count, 'count');
    _usedToolCalls += count;
  }

  void sync(AgentUsage usage) {
    if (usage.usedRequests > _usedRequests) {
      _usedRequests = usage.usedRequests;
    }
    if (usage.usedToolCalls > _usedToolCalls) {
      _usedToolCalls = usage.usedToolCalls;
    }
  }
}
