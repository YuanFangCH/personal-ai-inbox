import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AgentBackgroundState {
  unsupported,
  idle,
  running,
  paused,
  completed,
  cancelled,
  notificationPermissionDenied,
  serviceRestricted,
  activityUnavailable,
  busy,
  failed,
}

extension AgentBackgroundStateLifetime on AgentBackgroundState {
  bool get keepsRuntimeAlive => this == AgentBackgroundState.running;

  bool get isTerminal =>
      this == AgentBackgroundState.completed ||
      this == AgentBackgroundState.cancelled;
}

enum AgentBackgroundCommandType { pause, cancel }

class AgentBackgroundCommand {
  const AgentBackgroundCommand({
    required this.type,
    required this.taskId,
    this.reason,
  });

  final AgentBackgroundCommandType type;
  final String taskId;
  final String? reason;
}

class AgentBackgroundSnapshot {
  const AgentBackgroundSnapshot({
    required this.state,
    this.taskId,
    this.message,
    this.notificationPermissionGranted,
    this.activityAttached,
    this.failureCode,
  });

  const AgentBackgroundSnapshot.initial()
    : state = AgentBackgroundState.idle,
      taskId = null,
      message = null,
      notificationPermissionGranted = null,
      activityAttached = null,
      failureCode = null;

  final AgentBackgroundState state;
  final String? taskId;
  final String? message;
  final bool? notificationPermissionGranted;
  final bool? activityAttached;
  final String? failureCode;

  bool get keepsRuntimeAlive => state.keepsRuntimeAlive;
}

abstract interface class AgentBackgroundTransport {
  void setMethodCallHandler(Future<Object?> Function(MethodCall call)? handler);

  Future<Object?> invokeMethod(String method, Map<String, Object?> arguments);
}

abstract interface class AgentBackgroundPort {
  ValueListenable<AgentBackgroundSnapshot> get status;
  Stream<AgentBackgroundCommand> get commands;

  Future<void> initialize();
}

class AgentBackgroundLifecycleGate {
  AgentBackgroundLifecycleGate({
    required this.backgroundAgent,
    required this.shutdownRuntime,
    this.shutdownGracePeriod = const Duration(seconds: 2),
  }) : assert(!shutdownGracePeriod.isNegative);

  final AgentBackgroundPort backgroundAgent;
  final Future<void> Function() shutdownRuntime;
  final Duration shutdownGracePeriod;
  bool _scheduled = false;
  bool _shutdownStarted = false;
  int _scheduleGeneration = 0;
  VoidCallback? _statusListener;
  Timer? _shutdownTimer;

  Future<void> scheduleShutdown() async {
    if (_scheduled || _shutdownStarted) return;
    _scheduled = true;
    final generation = ++_scheduleGeneration;
    await backgroundAgent.initialize();
    if (!_scheduled || generation != _scheduleGeneration) return;
    _waitForTaskToStop(generation);
  }

  void cancelShutdown() {
    if (!_scheduled || _shutdownStarted) return;
    _scheduled = false;
    _scheduleGeneration++;
    _shutdownTimer?.cancel();
    _shutdownTimer = null;
    final listener = _statusListener;
    if (listener != null) {
      backgroundAgent.status.removeListener(listener);
      _statusListener = null;
    }
  }

  void _deferShutdown(int generation) {
    if (!_scheduled || generation != _scheduleGeneration) return;
    _shutdownTimer?.cancel();
    _shutdownTimer = Timer(shutdownGracePeriod, () {
      _shutdownTimer = null;
      if (!_scheduled || generation != _scheduleGeneration) return;
      if (backgroundAgent.status.value.keepsRuntimeAlive) {
        _waitForTaskToStop(generation);
        return;
      }
      _scheduled = false;
      _shutdownStarted = true;
      unawaited(shutdownRuntime());
    });
  }

  void _waitForTaskToStop(int generation) {
    if (!_scheduled || generation != _scheduleGeneration) return;
    if (!backgroundAgent.status.value.keepsRuntimeAlive) {
      _deferShutdown(generation);
      return;
    }
    if (_statusListener != null) return;
    void onStatusChanged() {
      if (!_scheduled ||
          generation != _scheduleGeneration ||
          backgroundAgent.status.value.keepsRuntimeAlive) {
        return;
      }
      backgroundAgent.status.removeListener(onStatusChanged);
      _statusListener = null;
      _deferShutdown(generation);
    }

    _statusListener = onStatusChanged;
    backgroundAgent.status.addListener(onStatusChanged);
  }
}

class MethodChannelAgentBackgroundTransport
    implements AgentBackgroundTransport {
  const MethodChannelAgentBackgroundTransport();

  static const _channel = MethodChannel(
    'com.yuanfang.aitext.personal_ai_inbox/background_agent',
  );

  @override
  void setMethodCallHandler(
    Future<Object?> Function(MethodCall call)? handler,
  ) {
    _channel.setMethodCallHandler(handler);
  }

  @override
  Future<Object?> invokeMethod(String method, Map<String, Object?> arguments) {
    return _channel.invokeMethod<Object?>(method, arguments);
  }
}

class AgentBackgroundService implements AgentBackgroundPort {
  AgentBackgroundService({
    AgentBackgroundTransport transport =
        const MethodChannelAgentBackgroundTransport(),
    bool? platformSupported,
  }) : _transport = transport,
       _platformSupported =
           platformSupported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    _status.value = AgentBackgroundSnapshot(
      state: _platformSupported
          ? AgentBackgroundState.idle
          : AgentBackgroundState.unsupported,
      message: _platformSupported ? null : '当前平台不支持 Android 前台任务。',
    );
  }

  static final AgentBackgroundService instance = AgentBackgroundService();

  final AgentBackgroundTransport _transport;
  final bool _platformSupported;
  final ValueNotifier<AgentBackgroundSnapshot> _status =
      ValueNotifier<AgentBackgroundSnapshot>(
        const AgentBackgroundSnapshot.initial(),
      );
  final StreamController<AgentBackgroundCommand> _commands =
      StreamController<AgentBackgroundCommand>.broadcast();
  final Set<String> _terminalTaskIds = {};
  final Set<String> _pauseCommandsEmitted = {};
  bool _initialized = false;

  @override
  ValueListenable<AgentBackgroundSnapshot> get status => _status;

  @override
  Stream<AgentBackgroundCommand> get commands => _commands.stream;

  AgentBackgroundSnapshot get snapshot => _status.value;

  Future<AgentBackgroundSnapshot> refreshStatus() async {
    await initialize();
    return _refreshStatus();
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!_platformSupported) return;
    _transport.setMethodCallHandler(_handleNativeCall);
    await _refreshStatus();
  }

  Future<AgentBackgroundSnapshot> requestNotificationPermission() async {
    await initialize();
    return _invoke('requestNotificationPermission', const {});
  }

  Future<AgentBackgroundSnapshot> startTask({
    required String taskId,
    required String title,
    required String text,
    double? progress,
  }) async {
    await initialize();
    if (!_platformSupported) return _status.value;
    if (taskId.trim().isEmpty) {
      return _setFailure(
        AgentBackgroundState.failed,
        'task_missing',
        '后台任务缺少稳定 ID。',
      );
    }
    if (_terminalTaskIds.contains(taskId)) {
      return _setSnapshot(
        AgentBackgroundSnapshot(
          state: AgentBackgroundState.cancelled,
          taskId: taskId,
          message: '该任务已由用户主动结束，不会自动恢复。',
          failureCode: 'terminal_task',
        ),
      );
    }
    final current = _status.value;
    if (current.keepsRuntimeAlive &&
        current.taskId != null &&
        current.taskId != taskId) {
      return _setSnapshot(
        AgentBackgroundSnapshot(
          state: AgentBackgroundState.busy,
          taskId: current.taskId,
          message: '已有另一个 Agent 任务正在使用唯一写入运行时。',
          failureCode: 'writer_busy',
        ),
      );
    }
    _pauseCommandsEmitted.remove(taskId);
    final snapshot = await _invoke('start', {
      'taskId': taskId,
      'title': title,
      'text': text,
      'progress': ?progress,
    });
    if (snapshot.state == AgentBackgroundState.serviceRestricted &&
        snapshot.taskId == taskId) {
      _emitPauseCommand(taskId, snapshot.message);
    }
    return snapshot;
  }

  Future<AgentBackgroundSnapshot> updateTask({
    required String taskId,
    required String title,
    required String text,
    double? progress,
  }) async {
    await initialize();
    return _invoke('update', {
      'taskId': taskId,
      'title': title,
      'text': text,
      'progress': ?progress,
    });
  }

  Future<AgentBackgroundSnapshot> pauseTask({
    required String taskId,
    String reason = '用户暂停了后台任务。',
  }) async {
    await initialize();
    final current = _status.value;
    if (current.state == AgentBackgroundState.serviceRestricted &&
        current.taskId == taskId) {
      return current;
    }
    if (current.state == AgentBackgroundState.paused &&
        current.taskId == taskId) {
      return current;
    }
    return _invoke('pause', {'taskId': taskId, 'reason': reason});
  }

  Future<AgentBackgroundSnapshot> completeTask({
    required String taskId,
    String message = '后台任务已完成。',
  }) async {
    await initialize();
    _terminalTaskIds.add(taskId);
    return _invoke('complete', {'taskId': taskId, 'message': message});
  }

  Future<AgentBackgroundSnapshot> cancelTask({
    required String taskId,
    String reason = '用户取消了后台任务。',
  }) async {
    await initialize();
    _terminalTaskIds.add(taskId);
    return _invoke('cancel', {'taskId': taskId, 'reason': reason});
  }

  Future<AgentBackgroundSnapshot> _refreshStatus() async {
    if (!_platformSupported) return _status.value;
    return _invoke('getStatus', const {});
  }

  Future<AgentBackgroundSnapshot> _invoke(
    String method,
    Map<String, Object?> arguments,
  ) async {
    if (!_platformSupported) return _status.value;
    try {
      final raw = await _transport.invokeMethod(method, arguments);
      if (raw is! Map) {
        return _setFailure(
          AgentBackgroundState.failed,
          'invalid_native_response',
          'Android 后台服务返回了无法识别的状态。',
        );
      }
      final snapshot = _snapshotFromMap(Map<String, Object?>.from(raw));
      final current = _status.value;
      if (method == 'start' &&
          current.state == AgentBackgroundState.serviceRestricted &&
          current.taskId == snapshot.taskId) {
        return current;
      }
      if (snapshot.state.isTerminal && snapshot.taskId != null) {
        _terminalTaskIds.add(snapshot.taskId!);
      }
      return _setSnapshot(snapshot);
    } on MissingPluginException {
      return _setFailure(
        AgentBackgroundState.unsupported,
        'channel_unavailable',
        'Android 后台服务尚未安装。',
      );
    } on PlatformException catch (error) {
      final state = switch (error.code) {
        'foreground_service_start_not_allowed' ||
        'foreground_service_restricted' =>
          AgentBackgroundState.serviceRestricted,
        'activity_unavailable' => AgentBackgroundState.activityUnavailable,
        _ => AgentBackgroundState.failed,
      };
      return _setFailure(state, error.code, error.message ?? '后台服务调用失败。');
    } on Object {
      return _setFailure(
        AgentBackgroundState.failed,
        'background_channel_failed',
        'Android 后台服务调用失败。',
      );
    }
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    final arguments = call.arguments is Map
        ? Map<String, Object?>.from(call.arguments as Map)
        : const <String, Object?>{};
    final taskId = arguments['taskId']?.toString() ?? '';
    final reason = arguments['reason']?.toString();
    switch (call.method) {
      case 'pauseRequested':
        final snapshot = _setSnapshot(
          AgentBackgroundSnapshot(
            state: AgentBackgroundState.paused,
            taskId: taskId,
            message: reason ?? '用户从通知暂停了后台任务。',
          ),
        );
        _emitCommand(
          AgentBackgroundCommand(
            type: AgentBackgroundCommandType.pause,
            taskId: taskId,
            reason: reason,
          ),
        );
        return _snapshotMap(snapshot);
      case 'cancelRequested':
        _terminalTaskIds.add(taskId);
        final snapshot = _setSnapshot(
          AgentBackgroundSnapshot(
            state: AgentBackgroundState.cancelled,
            taskId: taskId,
            message: reason ?? '用户从通知取消了后台任务。',
            failureCode: 'user_cancelled',
          ),
        );
        _emitCommand(
          AgentBackgroundCommand(
            type: AgentBackgroundCommandType.cancel,
            taskId: taskId,
            reason: reason,
          ),
        );
        return _snapshotMap(snapshot);
      case 'serviceStopped':
        final state = _parseState(arguments['state']);
        final failureCode = arguments['code']?.toString();
        final current = _status.value;
        if (current.taskId != null && current.taskId != taskId) {
          return _serviceStoppedAcknowledgement(
            current,
            eventTaskId: taskId,
            currentTaskId: current.taskId,
          );
        }
        final shouldPauseWorkspace =
            taskId.isNotEmpty &&
            current.state == AgentBackgroundState.running &&
            current.taskId == taskId &&
            ((state == AgentBackgroundState.paused &&
                    (failureCode == 'service_interrupted' ||
                        failureCode == 'data_sync_timeout')) ||
                (state == AgentBackgroundState.serviceRestricted &&
                    failureCode == 'foreground_service_start_not_allowed'));
        final snapshot = _setSnapshot(
          AgentBackgroundSnapshot(
            state: state,
            taskId: taskId.isEmpty ? null : taskId,
            message: arguments['message']?.toString(),
            failureCode: failureCode,
          ),
        );
        if (shouldPauseWorkspace) {
          _emitPauseCommand(taskId, snapshot.message);
        }
        return _serviceStoppedAcknowledgement(
          snapshot,
          eventTaskId: taskId,
          currentTaskId: current.taskId,
        );
      case 'status':
        return _snapshotMap(_setSnapshot(_snapshotFromMap(arguments)));
      default:
        throw MissingPluginException('Unknown native background callback.');
    }
  }

  void _emitCommand(AgentBackgroundCommand command) {
    if (command.taskId.isNotEmpty && !_commands.isClosed) {
      _commands.add(command);
    }
  }

  void _emitPauseCommand(String taskId, String? reason) {
    if (_pauseCommandsEmitted.add(taskId)) {
      _emitCommand(
        AgentBackgroundCommand(
          type: AgentBackgroundCommandType.pause,
          taskId: taskId,
          reason: reason,
        ),
      );
    }
  }

  AgentBackgroundSnapshot _setFailure(
    AgentBackgroundState state,
    String code,
    String message,
  ) {
    return _setSnapshot(
      AgentBackgroundSnapshot(
        state: state,
        message: message,
        failureCode: code,
      ),
    );
  }

  AgentBackgroundSnapshot _setSnapshot(AgentBackgroundSnapshot snapshot) {
    _status.value = snapshot;
    return snapshot;
  }

  AgentBackgroundSnapshot _snapshotFromMap(Map<String, Object?> value) {
    return AgentBackgroundSnapshot(
      state: _parseState(value['state']),
      taskId: value['taskId']?.toString(),
      message: value['message']?.toString(),
      notificationPermissionGranted:
          value['notificationPermissionGranted'] as bool?,
      activityAttached: value['activityAttached'] as bool?,
      failureCode: value['failureCode']?.toString(),
    );
  }

  AgentBackgroundState _parseState(Object? value) {
    return switch (value?.toString()) {
      'running' => AgentBackgroundState.running,
      'paused' => AgentBackgroundState.paused,
      'completed' => AgentBackgroundState.completed,
      'cancelled' => AgentBackgroundState.cancelled,
      'notification_permission_denied' =>
        AgentBackgroundState.notificationPermissionDenied,
      'service_start_restricted' => AgentBackgroundState.serviceRestricted,
      'activity_unavailable' => AgentBackgroundState.activityUnavailable,
      'busy' => AgentBackgroundState.busy,
      'failed' => AgentBackgroundState.failed,
      'idle' || null => AgentBackgroundState.idle,
      _ => AgentBackgroundState.failed,
    };
  }

  Map<String, Object?> _snapshotMap(AgentBackgroundSnapshot snapshot) => {
    'state': switch (snapshot.state) {
      AgentBackgroundState.notificationPermissionDenied =>
        'notification_permission_denied',
      AgentBackgroundState.serviceRestricted => 'service_start_restricted',
      AgentBackgroundState.activityUnavailable => 'activity_unavailable',
      _ => snapshot.state.name,
    },
    if (snapshot.taskId != null) 'taskId': snapshot.taskId,
    if (snapshot.message != null) 'message': snapshot.message,
    if (snapshot.notificationPermissionGranted != null)
      'notificationPermissionGranted': snapshot.notificationPermissionGranted,
    if (snapshot.activityAttached != null)
      'activityAttached': snapshot.activityAttached,
    if (snapshot.failureCode != null) 'failureCode': snapshot.failureCode,
  };

  Map<String, Object?> _serviceStoppedAcknowledgement(
    AgentBackgroundSnapshot snapshot, {
    required String eventTaskId,
    required String? currentTaskId,
  }) => {
    ..._snapshotMap(snapshot),
    'event': 'serviceStopped',
    'eventTaskId': eventTaskId,
    'currentTaskId': ?currentTaskId,
    'taskIdMatched': currentTaskId == eventTaskId,
  };
}
