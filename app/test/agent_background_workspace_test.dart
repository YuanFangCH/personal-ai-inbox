import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/core/ai_policy.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/modules/capture/capture_workflow.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_background_control.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_task_store.dart';
import 'package:personal_ai_inbox/modules/conversation/auto_record_processor.dart';
import 'package:personal_ai_inbox/modules/conversation/conversation_workspace.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';
import 'package:personal_ai_inbox/services/agent_background_service.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';
import 'package:personal_ai_inbox/services/chat_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'test_support.dart';

void main() {
  test('native service interruption keeps its failure reason through workspace settlement', () async {
    final transport = _BackgroundTransport();
    final service = AgentBackgroundService(
      transport: transport,
      platformSupported: true,
    );
    final background = ServiceAgentBackgroundControl(service);
    final taskStore = MemoryAgentTaskStore();
    final responseBody = StreamController<List<int>>();
    var modelRequestCount = 0;
    final settings = FakeSettingsService(
      modelKey: 'background-interruption-test',
    );
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    final resultRepository = ResultRepository(
      vault: vault,
      index: index,
      deviceId: 'background-interruption-test',
    );
    await resultRepository.initialize();
    final results = ResultLibrary(repository: resultRepository);
    await results.initialize();
    final capture = CaptureWorkflow(
      repository: resultRepository,
      results: results,
      indexDatabase: index,
      captureService: CaptureService(
        settings: settings,
        parser: const DeterministicParser(),
        modelClient: ModelClient(
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      ),
    );
    await capture.initialize();
    final conversations = ChatRepository(
      store: MemoryConversationStore(),
      attachments: MemoryAttachmentStore(),
    );
    await conversations.initialize();
    final workspace = ConversationWorkspace(
      repository: conversations,
      results: results,
      chatService: ChatService(
        settings: settings,
        repository: conversations,
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            modelRequestCount++;
            await body.bytesToString();
            return http.StreamedResponse(
              responseBody.stream,
              200,
              headers: const {'content-type': 'text/event-stream'},
            );
          }),
        ),
      ),
      autoRecordProcessor: AutoRecordProcessor(
        chatRepository: conversations,
        results: results,
        captures: capture,
        deviceId: () => resultRepository.deviceId,
      ),
      defaultPolicy: () => AiPolicy.forPreset(AiPolicyPreset.standard),
      backgroundAgent: background,
      taskStore: taskStore,
    );
    await workspace.initialize();

    try {
      final conversation = await workspace.createConversation();
      final sending = workspace.sendChatMessage(
        conversation.id,
        text: '请检查本地资料',
      );
      await _waitFor(() => transport.startedTaskId != null);
      await _waitFor(() => modelRequestCount == 1);
      final taskId = transport.startedTaskId!;

      await transport.deliver('serviceStopped', {
        'state': 'paused',
        'taskId': taskId,
        'message': '前台 dataSync 服务被系统中止，任务已保存为暂停。',
        'code': 'service_interrupted',
      });
      await sending.timeout(const Duration(seconds: 3));
      await _waitFor(
        () => taskStore.checkpoint.turns.any(
          (turn) =>
              turn.assistantMessageId == taskId &&
              turn.status == AgentTurnCheckpointStatus.paused,
        ),
      );

      expect(modelRequestCount, 1);
      expect(service.snapshot.state, AgentBackgroundState.paused);
      expect(service.snapshot.taskId, taskId);
      expect(service.snapshot.failureCode, 'service_interrupted');
      expect(
        taskStore.checkpoint.turns
            .singleWhere((turn) => turn.assistantMessageId == taskId)
            .status,
        AgentTurnCheckpointStatus.paused,
      );
      expect(
        transport.calls.where((call) => call.$1 == 'pause'),
        isEmpty,
        reason: 'service interruption already stopped the native service',
      );
    } finally {
      await responseBody.close();
      await workspace.shutdown();
      await conversations.close();
      await results.shutdown();
      results.dispose();
    }
  });

  test('native service start restriction pauses and checkpoints the production workspace run', () async {
    final transport = _BackgroundTransport();
    transport.pendingStart = Completer<Object?>();
    final service = AgentBackgroundService(
      transport: transport,
      platformSupported: true,
    );
    final background = ServiceAgentBackgroundControl(service);
    final taskStore = MemoryAgentTaskStore();
    final pending = _PendingModelResponse();
    var modelRequestCount = 0;
    final settings = FakeSettingsService(modelKey: 'background-workspace-test');
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    final resultRepository = ResultRepository(
      vault: vault,
      index: index,
      deviceId: 'background-workspace-test',
    );
    await resultRepository.initialize();
    final results = ResultLibrary(repository: resultRepository);
    await results.initialize();
    final capture = CaptureWorkflow(
      repository: resultRepository,
      results: results,
      indexDatabase: index,
      captureService: CaptureService(
        settings: settings,
        parser: const DeterministicParser(),
        modelClient: ModelClient(
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      ),
    );
    await capture.initialize();
    final conversations = ChatRepository(
      store: MemoryConversationStore(),
      attachments: MemoryAttachmentStore(),
    );
    await conversations.initialize();
    final workspace = ConversationWorkspace(
      repository: conversations,
      results: results,
      chatService: ChatService(
        settings: settings,
        repository: conversations,
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            modelRequestCount++;
            await body.bytesToString();
            return pending.response.future;
          }),
        ),
      ),
      autoRecordProcessor: AutoRecordProcessor(
        chatRepository: conversations,
        results: results,
        captures: capture,
        deviceId: () => resultRepository.deviceId,
      ),
      defaultPolicy: () => AiPolicy.forPreset(AiPolicyPreset.standard),
      backgroundAgent: background,
      taskStore: taskStore,
    );
    await workspace.initialize();

    try {
      final conversation = await workspace.createConversation();
      final sending = workspace.sendChatMessage(
        conversation.id,
        text: '请检查本地资料',
      );
      await _waitFor(() => transport.startedTaskId != null);
      final taskId = transport.startedTaskId!;
      await transport.deliver('serviceStopped', {
        'state': 'service_start_restricted',
        'taskId': taskId,
        'message': '系统限制前台服务启动；任务已保存为暂停。',
        'code': 'foreground_service_start_not_allowed',
      });
      transport.pendingStart!.complete({
        'state': 'service_start_restricted',
        'taskId': taskId,
        'message': '系统限制前台服务启动；任务已保存为暂停。',
        'failureCode': 'foreground_service_start_not_allowed',
      });
      await workspace.activeCancellationFuture().timeout(
        const Duration(seconds: 3),
      );
      await sending.timeout(const Duration(seconds: 3));
      await _waitFor(
        () => taskStore.checkpoint.turns.any(
          (turn) =>
              turn.assistantMessageId == taskId &&
              turn.status == AgentTurnCheckpointStatus.paused,
        ),
      );

      expect(
        workspace.messagesFor(conversation.id).last.status,
        ChatMessageStatus.interrupted,
      );
      expect(
        (await conversations.findGeneration(taskId))?.status,
        GenerationStatus.interrupted,
      );
      final checkpoint = taskStore.checkpoint.turns.singleWhere(
        (turn) => turn.assistantMessageId == taskId,
      );
      expect(checkpoint.status, AgentTurnCheckpointStatus.paused);
      expect(checkpoint.assistantMessageId, taskId);
      expect(modelRequestCount, 0);
      expect(service.snapshot.state, AgentBackgroundState.serviceRestricted);
      expect(
        service.snapshot.failureCode,
        'foreground_service_start_not_allowed',
      );
      expect(
        transport.calls.where((call) => call.$1 == 'pause'),
        isEmpty,
        reason: 'restriction already stopped the native service',
      );
    } finally {
      if (!pending.response.isCompleted) {
        pending.response.complete(_emptyResponse());
      }
      await workspace.shutdown();
      await conversations.close();
      await results.shutdown();
      results.dispose();
    }
  });
}

class _BackgroundTransport implements AgentBackgroundTransport {
  Completer<Object?>? pendingStart;

  Future<Object?> Function(MethodCall call)? _handler;
  String? startedTaskId;
  final List<(String, Map<String, Object?>)> calls = [];

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
    if (method == 'start') {
      startedTaskId = arguments['taskId'] as String;
      if (pendingStart != null) return pendingStart!.future;
      return {'state': 'running', 'taskId': arguments['taskId']};
    }
    return switch (method) {
      'getStatus' => {'state': 'idle'},
      'update' => {'state': 'running', 'taskId': arguments['taskId']},
      'pause' => {'state': 'paused', 'taskId': arguments['taskId']},
      'complete' => {'state': 'completed', 'taskId': arguments['taskId']},
      'cancel' => {'state': 'cancelled', 'taskId': arguments['taskId']},
      _ => {'state': 'idle'},
    };
  }

  Future<Object?> deliver(String method, Map<String, Object?> arguments) {
    final handler = _handler;
    if (handler == null) {
      throw StateError('background callback handler is missing');
    }
    return handler(MethodCall(method, arguments));
  }
}

class _PendingModelResponse {
  final Completer<http.StreamedResponse> response =
      Completer<http.StreamedResponse>();
}

http.StreamedResponse _emptyResponse() => http.StreamedResponse(
  Stream<String>.value('data: [DONE]\n\n').transform(utf8.encoder),
  200,
  headers: const {'content-type': 'text/event-stream'},
);

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition timed out');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
