import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/services/agent_background_service.dart';

void main() {
  test('starts and updates exactly one active background writer', () async {
    final transport = _FakeBackgroundTransport();
    final service = AgentBackgroundService(
      transport: transport,
      platformSupported: true,
    );
    await service.initialize();

    final first = await service.startTask(
      taskId: 'task_1',
      title: '检查资料',
      text: '正在读取第 1 页',
      progress: 0.25,
    );
    expect(first.state, AgentBackgroundState.running);
    expect(first.keepsRuntimeAlive, isTrue);
    expect(transport.calls.last.$1, 'start');
    expect(transport.calls.last.$2['taskId'], 'task_1');

    final busy = await service.startTask(
      taskId: 'task_2',
      title: '另一个任务',
      text: '不应启动',
    );
    expect(busy.state, AgentBackgroundState.busy);
    expect(busy.taskId, 'task_1');

    final updated = await service.updateTask(
      taskId: 'task_1',
      title: '检查资料',
      text: '正在读取第 2 页',
      progress: 0.5,
    );
    expect(updated.state, AgentBackgroundState.running);
    expect(transport.calls.last.$1, 'update');
    expect(transport.calls.last.$2['progress'], 0.5);
  });

  test('native pause and cancel actions become agent commands', () async {
    final transport = _FakeBackgroundTransport();
    final service = AgentBackgroundService(
      transport: transport,
      platformSupported: true,
    );
    await service.initialize();
    await service.startTask(taskId: 'task_pause', title: '长任务', text: '运行中');
    final commands = <AgentBackgroundCommand>[];
    final subscription = service.commands.listen(commands.add);

    await transport.deliver('pauseRequested', {
      'taskId': 'task_pause',
      'reason': '通知暂停',
    });
    expect(service.snapshot.state, AgentBackgroundState.paused);
    expect(service.snapshot.keepsRuntimeAlive, isFalse);

    await transport.deliver('cancelRequested', {
      'taskId': 'task_pause',
      'reason': '通知取消',
    });
    expect(service.snapshot.state, AgentBackgroundState.cancelled);
    expect(commands.map((command) => command.type), [
      AgentBackgroundCommandType.pause,
      AgentBackgroundCommandType.cancel,
    ]);

    await subscription.cancel();
  });

  test('native service stop pauses only its matching running task', () async {
    final transport = _FakeBackgroundTransport();
    final service = AgentBackgroundService(
      transport: transport,
      platformSupported: true,
    );
    await service.initialize();
    final commands = <AgentBackgroundCommand>[];
    final subscription = service.commands.listen(commands.add);

    await service.startTask(
      taskId: 'task_interrupted',
      title: '长任务',
      text: '运行中',
    );
    final mismatchAck = await transport.deliver('serviceStopped', {
      'state': 'paused',
      'taskId': 'another_task',
      'message': '旧服务退出',
      'code': 'service_interrupted',
    });
    expect(mismatchAck, {
      'state': 'running',
      'taskId': 'task_interrupted',
      'message': '运行中',
      'notificationPermissionGranted': true,
      'event': 'serviceStopped',
      'eventTaskId': 'another_task',
      'currentTaskId': 'task_interrupted',
      'taskIdMatched': false,
    });
    final interruptionAck = await transport.deliver('serviceStopped', {
      'state': 'paused',
      'taskId': 'task_interrupted',
      'message': '系统终止服务',
      'code': 'service_interrupted',
    });
    expect(interruptionAck, {
      'state': 'paused',
      'taskId': 'task_interrupted',
      'message': '系统终止服务',
      'failureCode': 'service_interrupted',
      'event': 'serviceStopped',
      'eventTaskId': 'task_interrupted',
      'currentTaskId': 'task_interrupted',
      'taskIdMatched': true,
    });

    await service.startTask(taskId: 'task_timeout', title: '长任务', text: '运行中');
    await transport.deliver('serviceStopped', {
      'state': 'paused',
      'taskId': 'task_timeout',
      'message': '系统时间限制',
      'code': 'data_sync_timeout',
    });

    await service.startTask(
      taskId: 'task_cancelled',
      title: '长任务',
      text: '运行中',
    );
    await transport.deliver('serviceStopped', {
      'state': 'cancelled',
      'taskId': 'task_cancelled',
      'message': '用户取消任务',
      'code': 'user_cancelled',
    });

    await service.startTask(taskId: 'task_shutdown', title: '长任务', text: '运行中');
    await transport.deliver('serviceStopped', {
      'state': 'idle',
      'taskId': 'task_shutdown',
      'message': '应用正常关闭',
    });

    await service.startTask(
      taskId: 'task_completed',
      title: '长任务',
      text: '运行中',
    );
    await transport.deliver('serviceStopped', {
      'state': 'completed',
      'taskId': 'task_completed',
      'message': '正常完成',
    });
    await Future<void>.delayed(Duration.zero);

    expect(commands, hasLength(2));
    expect(
      commands.map((command) => command.type),
      everyElement(AgentBackgroundCommandType.pause),
    );
    expect(commands.map((command) => command.taskId), [
      'task_interrupted',
      'task_timeout',
    ]);
    expect(commands.first.reason, '系统终止服务');
    expect(commands.last.reason, '系统时间限制');
    expect(service.snapshot.state, AgentBackgroundState.completed);
    await subscription.cancel();
  });

  test(
    'notification denial is visible and does not claim a running task',
    () async {
      final transport = _FakeBackgroundTransport(
        responder: (method, arguments) async {
          if (method == 'getStatus') {
            return {'state': 'idle', 'notificationPermissionGranted': false};
          }
          return {
            'state': 'notification_permission_denied',
            'taskId': arguments['taskId'],
            'message': '通知权限被拒绝。',
            'notificationPermissionGranted': false,
            'failureCode': 'notification_permission_denied',
          };
        },
      );
      final service = AgentBackgroundService(
        transport: transport,
        platformSupported: true,
      );
      await service.initialize();

      final result = await service.startTask(
        taskId: 'task_denied',
        title: '检查',
        text: '不应启动服务',
      );

      expect(result.state, AgentBackgroundState.notificationPermissionDenied);
      expect(result.notificationPermissionGranted, isFalse);
      expect(result.keepsRuntimeAlive, isFalse);
    },
  );

  test('permission request publishes its result even when refresh returns stored task state', () async {
    final transport = _FakeBackgroundTransport(
      responder: (method, arguments) async {
        if (method == 'getStatus') {
          return {
            'state': 'service_start_restricted',
            'failureCode': 'foreground_service_start_not_allowed',
            'notificationPermissionGranted': false,
          };
        }
        return {
          'state': 'notification_permission_denied',
          'message': '通知权限被拒绝。',
          'notificationPermissionGranted': false,
          'failureCode': 'notification_permission_denied',
        };
      },
    );
    final service = AgentBackgroundService(
      transport: transport,
      platformSupported: true,
    );
    await service.initialize();

    final permission = await service.requestNotificationPermission();

    expect(permission.state, AgentBackgroundState.notificationPermissionDenied);
    expect(
      service.snapshot.state,
      AgentBackgroundState.notificationPermissionDenied,
    );
    expect(permission.notificationPermissionGranted, isFalse);

    final refreshed = await service.refreshStatus();
    expect(refreshed.state, AgentBackgroundState.serviceRestricted);
    expect(refreshed.notificationPermissionGranted, isFalse);
  });

  test(
    'service start restrictions are mapped to an explicit failure',
    () async {
      final transport = _FakeBackgroundTransport(
        responder: (method, arguments) async {
          if (method == 'getStatus') return {'state': 'idle'};
          throw PlatformException(
            code: 'foreground_service_start_not_allowed',
            message: '当前状态不允许启动前台服务。',
          );
        },
      );
      final service = AgentBackgroundService(
        transport: transport,
        platformSupported: true,
      );
      await service.initialize();

      final result = await service.startTask(
        taskId: 'task_restricted',
        title: '检查',
        text: '启动失败',
      );

      expect(result.state, AgentBackgroundState.serviceRestricted);
      expect(result.failureCode, 'foreground_service_start_not_allowed');
    },
  );

  test(
    'native service restriction remains visible and pauses the matching task',
    () async {
      final transport = _FakeBackgroundTransport(
        responder: (method, arguments) async {
          if (method == 'getStatus') return {'state': 'idle'};
          return {
            'state': 'service_start_restricted',
            'taskId': arguments['taskId'],
            'message': '系统限制启动前台服务；任务已保存为暂停。',
            'failureCode': 'foreground_service_start_not_allowed',
          };
        },
      );
      final service = AgentBackgroundService(
        transport: transport,
        platformSupported: true,
      );
      await service.initialize();
      final commands = <AgentBackgroundCommand>[];
      final subscription = service.commands.listen(commands.add);

      final snapshot = await service.startTask(
        taskId: 'task_service_restricted',
        title: '受限服务任务',
        text: '前台服务启动失败',
      );
      await Future<void>.delayed(Duration.zero);

      expect(snapshot.state, AgentBackgroundState.serviceRestricted);
      expect(snapshot.taskId, 'task_service_restricted');
      expect(snapshot.failureCode, 'foreground_service_start_not_allowed');
      expect(snapshot.keepsRuntimeAlive, isFalse);
      expect(commands, hasLength(1));
      expect(commands.single.type, AgentBackgroundCommandType.pause);
      expect(commands.single.taskId, 'task_service_restricted');

      final beforePause = transport.calls.length;
      final paused = await service.pauseTask(taskId: 'task_service_restricted');
      expect(paused.state, AgentBackgroundState.serviceRestricted);
      expect(paused.failureCode, 'foreground_service_start_not_allowed');
      expect(transport.calls, hasLength(beforePause));
      await subscription.cancel();
    },
  );

  test(
    'async service restriction updates status before pausing only its task',
    () async {
      final transport = _FakeBackgroundTransport();
      final service = AgentBackgroundService(
        transport: transport,
        platformSupported: true,
      );
      await service.initialize();
      await service.startTask(
        taskId: 'task_async_restriction',
        title: '受限服务任务',
        text: '运行中',
      );
      final observedStates = <AgentBackgroundState>[];
      final commands = <AgentBackgroundCommand>[];
      final subscription = service.commands.listen((command) {
        observedStates.add(service.snapshot.state);
        commands.add(command);
      });

      await transport.deliver('serviceStopped', {
        'state': 'service_start_restricted',
        'taskId': 'task_async_restriction',
        'message': '系统限制前台服务启动。',
        'code': 'foreground_service_start_not_allowed',
      });
      await transport.deliver('serviceStopped', {
        'state': 'service_start_restricted',
        'taskId': 'different_task',
        'message': '不应影响当前任务。',
        'code': 'foreground_service_start_not_allowed',
      });
      await Future<void>.delayed(Duration.zero);

      expect(service.snapshot.state, AgentBackgroundState.serviceRestricted);
      expect(service.snapshot.taskId, 'task_async_restriction');
      expect(commands, hasLength(1));
      expect(commands.single.taskId, 'task_async_restriction');
      expect(observedStates, [AgentBackgroundState.serviceRestricted]);
      await subscription.cancel();
    },
  );

  test(
    'restriction callback racing start result emits one pause command',
    () async {
      late final _FakeBackgroundTransport transport;
      transport = _FakeBackgroundTransport(
        responder: (method, arguments) async {
          if (method == 'getStatus') return {'state': 'idle'};
          if (method == 'start') {
            await transport.deliver('serviceStopped', {
              'state': 'service_start_restricted',
              'taskId': arguments['taskId'],
              'message': '系统异步拒绝启动前台服务。',
              'code': 'foreground_service_start_not_allowed',
            });
            return {'state': 'running', 'taskId': arguments['taskId']};
          }
          return {'state': 'idle'};
        },
      );
      final service = AgentBackgroundService(
        transport: transport,
        platformSupported: true,
      );
      await service.initialize();
      final commands = <AgentBackgroundCommand>[];
      final subscription = service.commands.listen(commands.add);

      final snapshot = await service.startTask(
        taskId: 'task_start_race',
        title: '受限服务任务',
        text: '正在启动',
      );
      await Future<void>.delayed(Duration.zero);

      expect(snapshot.state, AgentBackgroundState.serviceRestricted);
      expect(snapshot.taskId, 'task_start_race');
      expect(commands, hasLength(1));
      expect(commands.single.taskId, 'task_start_race');
      await subscription.cancel();
    },
  );

  test(
    'a cancelled task cannot be restarted with the same stable ID',
    () async {
      final transport = _FakeBackgroundTransport();
      final service = AgentBackgroundService(
        transport: transport,
        platformSupported: true,
      );
      await service.initialize();
      await service.startTask(
        taskId: 'task_terminal',
        title: '长任务',
        text: '运行中',
      );
      await service.cancelTask(taskId: 'task_terminal');
      final callsBeforeRestart = transport.calls.length;

      final restarted = await service.startTask(
        taskId: 'task_terminal',
        title: '长任务',
        text: '不应复活',
      );

      expect(restarted.state, AgentBackgroundState.cancelled);
      expect(restarted.failureCode, 'terminal_task');
      expect(transport.calls, hasLength(callsBeforeRestart));
    },
  );
}

class _FakeBackgroundTransport implements AgentBackgroundTransport {
  _FakeBackgroundTransport({this.responder});

  final Future<Object?> Function(String method, Map<String, Object?> arguments)?
  responder;
  final List<(String, Map<String, Object?>)> calls = [];
  Future<Object?> Function(MethodCall call)? _handler;

  @override
  void setMethodCallHandler(
    Future<Object?> Function(MethodCall call)? handler,
  ) {
    _handler = handler;
  }

  @override
  Future<Object?> invokeMethod(
    String method,
    Map<String, Object?> arguments,
  ) async {
    calls.add((method, Map.unmodifiable(arguments)));
    final custom = responder;
    if (custom != null) return custom(method, arguments);
    return switch (method) {
      'getStatus' => {'state': 'idle'},
      'start' || 'update' => {
        'state': 'running',
        'taskId': arguments['taskId'],
        'message': '运行中',
        'notificationPermissionGranted': true,
      },
      'pause' => {
        'state': 'paused',
        'taskId': arguments['taskId'],
        'message': '已暂停',
      },
      'complete' => {'state': 'completed', 'taskId': arguments['taskId']},
      'cancel' => {
        'state': 'cancelled',
        'taskId': arguments['taskId'],
        'failureCode': 'user_cancelled',
      },
      _ => {'state': 'idle'},
    };
  }

  Future<Object?> deliver(String method, Map<String, Object?> arguments) {
    final handler = _handler;
    if (handler == null) throw StateError('No background method handler.');
    return handler(MethodCall(method, arguments));
  }
}
