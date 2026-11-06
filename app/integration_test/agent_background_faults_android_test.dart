// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_ai_inbox/services/agent_background_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const scenario = String.fromEnvironment('E2E_AGENT_FAULT');

  testWidgets('Android background fault: $scenario', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('background fault harness'))),
      ),
    );
    final service = AgentBackgroundService.instance;

    await tester.runAsync(() async {
      await service.initialize();
      switch (scenario) {
        case 'notification_denied':
          final permission = await service.requestNotificationPermission();
          expect(
            permission.state,
            AgentBackgroundState.notificationPermissionDenied,
          );
          final started = await service.startTask(
            taskId: 'fault_notification_denied',
            title: '通知拒绝测试',
            text: '不应启动 foreground service',
          );
          expect(
            started.state,
            AgentBackgroundState.notificationPermissionDenied,
          );
          _pass(scenario);
          return;
        case 'activity_recreate':
          await _start(service, scenario);
          print('AGENT_FAULT_READY|$scenario');
          await Future<void>.delayed(const Duration(seconds: 8));
          final status = await service.refreshStatus();
          expect(status.state, AgentBackgroundState.running);
          expect(status.taskId, 'fault_activity_recreate');
          expect(status.activityAttached, isTrue);
          await service.completeTask(taskId: 'fault_$scenario');
          _pass('A31_ACTIVITY_RECREATE');
          return;
        case 'service_interrupted':
          await _start(service, scenario);
          print('AGENT_FAULT_READY|$scenario');
          final status = await _waitForStatus(
            service,
            (value) =>
                value.state == AgentBackgroundState.paused &&
                value.failureCode == 'service_interrupted',
          );
          expect(status.state, AgentBackgroundState.paused);
          _pass('A33_SERVICE_INTERRUPTED');
          return;
        case 'timeout':
          await _start(service, scenario);
          print('AGENT_FAULT_READY|$scenario');
          final status = await _waitForStatus(
            service,
            (value) =>
                value.state == AgentBackgroundState.paused &&
                value.failureCode == 'data_sync_timeout',
          );
          expect(status.state, AgentBackgroundState.paused);
          _pass('A33_TIMEOUT');
          return;
        case 'pause_command':
          await _start(service, scenario);
          print('AGENT_FAULT_READY|$scenario');
          final status = await _waitForStatus(
            service,
            (value) => value.state == AgentBackgroundState.paused,
          );
          expect(status.state, AgentBackgroundState.paused);
          _pass('A33_PAUSE');
          return;
        case 'cancel_command':
          await _start(service, scenario);
          print('AGENT_FAULT_READY|$scenario');
          final status = await _waitForStatus(
            service,
            (value) => value.state == AgentBackgroundState.cancelled,
          );
          expect(status.state, AgentBackgroundState.cancelled);
          _pass('A33_CANCEL');
          return;
        case 'explicit_close':
          await _start(service, scenario);
          print('AGENT_FAULT_READY|$scenario');
          await Future<void>.delayed(const Duration(seconds: 60));
          fail('explicit-close process unexpectedly survived');
        default:
          fail('Unknown E2E_AGENT_FAULT value: $scenario');
      }
    });
  });
}

Future<void> _start(AgentBackgroundService service, String suffix) async {
  final permission = await service.requestNotificationPermission();
  if (permission.state == AgentBackgroundState.notificationPermissionDenied) {
    fail('notification permission must be granted before $suffix');
  }
  final taskId = 'fault_$suffix';
  final started = await service.startTask(
    taskId: taskId,
    title: '原生后台故障注入',
    text: '等待故障触发',
    progress: 0.1,
  );
  expect(started.state, AgentBackgroundState.running);
  await service.updateTask(
    taskId: taskId,
    title: '原生后台故障注入',
    text: '故障注入已就绪',
    progress: 0.2,
  );
}

Future<AgentBackgroundSnapshot> _waitForStatus(
  AgentBackgroundService service,
  bool Function(AgentBackgroundSnapshot snapshot) predicate,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final status = await service.refreshStatus();
    if (predicate(status)) return status;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('background status did not reach the expected state');
}

void _pass(String name) {
  print('AGENT_FAULT_RESULT|$name|passed');
}
