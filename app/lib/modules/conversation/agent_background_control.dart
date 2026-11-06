import 'package:flutter/foundation.dart';

import '../../services/agent_background_service.dart';

/// Narrow control surface used by the agent runtime.
///
/// `AgentBackgroundPort` currently exposes only lifecycle status and native
/// commands. This adapter adds the task commands without changing the
/// background service or Android bridge owned by another workstream.
abstract interface class AgentBackgroundControl {
  ValueListenable<AgentBackgroundSnapshot> get status;
  Stream<AgentBackgroundCommand> get commands;

  Future<void> initialize();

  Future<AgentBackgroundSnapshot> requestNotificationPermission();

  Future<AgentBackgroundSnapshot> startTask({
    required String taskId,
    required String title,
    required String text,
    double? progress,
  });

  Future<AgentBackgroundSnapshot> updateTask({
    required String taskId,
    required String title,
    required String text,
    double? progress,
  });

  Future<AgentBackgroundSnapshot> pauseTask({
    required String taskId,
    String reason = '用户暂停了后台任务。',
  });

  Future<AgentBackgroundSnapshot> completeTask({
    required String taskId,
    String message = '后台任务已完成。',
  });

  Future<AgentBackgroundSnapshot> cancelTask({
    required String taskId,
    String reason = '用户取消了后台任务。',
  });
}

class ServiceAgentBackgroundControl implements AgentBackgroundControl {
  ServiceAgentBackgroundControl(this.service);

  final AgentBackgroundService service;

  @override
  ValueListenable<AgentBackgroundSnapshot> get status => service.status;

  @override
  Stream<AgentBackgroundCommand> get commands => service.commands;

  @override
  Future<void> initialize() => service.initialize();

  @override
  Future<AgentBackgroundSnapshot> requestNotificationPermission() =>
      service.requestNotificationPermission();

  @override
  Future<AgentBackgroundSnapshot> startTask({
    required String taskId,
    required String title,
    required String text,
    double? progress,
  }) => service.startTask(
    taskId: taskId,
    title: title,
    text: text,
    progress: progress,
  );

  @override
  Future<AgentBackgroundSnapshot> updateTask({
    required String taskId,
    required String title,
    required String text,
    double? progress,
  }) => service.updateTask(
    taskId: taskId,
    title: title,
    text: text,
    progress: progress,
  );

  @override
  Future<AgentBackgroundSnapshot> pauseTask({
    required String taskId,
    String reason = '用户暂停了后台任务。',
  }) => service.pauseTask(taskId: taskId, reason: reason);

  @override
  Future<AgentBackgroundSnapshot> completeTask({
    required String taskId,
    String message = '后台任务已完成。',
  }) => service.completeTask(taskId: taskId, message: message);

  @override
  Future<AgentBackgroundSnapshot> cancelTask({
    required String taskId,
    String reason = '用户取消了后台任务。',
  }) => service.cancelTask(taskId: taskId, reason: reason);
}

/// Foreground-only default for isolated module tests and unsupported hosts.
class DisabledAgentBackgroundControl implements AgentBackgroundControl {
  DisabledAgentBackgroundControl();

  final ValueNotifier<AgentBackgroundSnapshot> _status =
      ValueNotifier<AgentBackgroundSnapshot>(
        const AgentBackgroundSnapshot(
          state: AgentBackgroundState.unsupported,
          message: '未注入 Android 后台运行适配器。',
        ),
      );

  AgentBackgroundSnapshot get _snapshot => const AgentBackgroundSnapshot(
    state: AgentBackgroundState.unsupported,
    message: '当前仅在前台运行。',
  );

  @override
  ValueListenable<AgentBackgroundSnapshot> get status => _status;

  @override
  Stream<AgentBackgroundCommand> get commands => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<AgentBackgroundSnapshot> requestNotificationPermission() async =>
      _snapshot;

  @override
  Future<AgentBackgroundSnapshot> startTask({
    required String taskId,
    required String title,
    required String text,
    double? progress,
  }) async => _snapshot;

  @override
  Future<AgentBackgroundSnapshot> updateTask({
    required String taskId,
    required String title,
    required String text,
    double? progress,
  }) async => _snapshot;

  @override
  Future<AgentBackgroundSnapshot> pauseTask({
    required String taskId,
    String reason = '用户暂停了后台任务。',
  }) async => _snapshot;

  @override
  Future<AgentBackgroundSnapshot> completeTask({
    required String taskId,
    String message = '后台任务已完成。',
  }) async => _snapshot;

  @override
  Future<AgentBackgroundSnapshot> cancelTask({
    required String taskId,
    String reason = '用户取消了后台任务。',
  }) async => _snapshot;
}
