import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/core/agent_usage.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/io_vault_store.dart';
import 'package:personal_ai_inbox/data/sqlite_conversation_store.dart';
import 'package:personal_ai_inbox/data/sqlite_index_database.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/data/settings_service.dart';
import 'package:personal_ai_inbox/modules/capture/capture_workflow.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_background_control.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_task_store.dart';
import 'package:personal_ai_inbox/modules/conversation/auto_record_processor.dart';
import 'package:personal_ai_inbox/modules/conversation/conversation_workspace.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';
import 'package:personal_ai_inbox/services/chat_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'test_support.dart';

void main() {
  test('keeps the prior transcript when saving a compacted task checkpoint fails', () async {
    final conversationStore = _SummaryObservingConversationStore();
    final taskStore = _FailAfterSummaryTaskStore(conversationStore);
    var requests = 0;
    final harness = await _WorkspaceHarness.create(
      conversationStore: conversationStore,
      taskStore: taskStore,
      agentLoopPolicy: const ChatAgentLoopPolicy(maxRequestContextChars: 5000),
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          requests++;
          await body.bytesToString();
          return _streamResponse({
            'choices': [
              {
                'delta': {'content': '收到并继续处理。'},
              },
            ],
          });
        }),
      ),
    );
    addTearDown(harness.close);
    final conversation = await harness.workspace.createConversation();
    final timestamp = DateTime(2026, 11, 5, 10);
    for (var index = 0; index < 5; index++) {
      await harness.chatRepository.saveMessage(
        ChatMessage(
          id: 'old_user_$index',
          conversationId: conversation.id,
          role: ChatRole.user,
          content: '早期事实 $index：${'保留上下文。' * 6}',
          status: ChatMessageStatus.complete,
          createdAt: timestamp.add(Duration(minutes: index * 2)),
          updatedAt: timestamp.add(Duration(minutes: index * 2)),
        ),
      );
      await harness.chatRepository.saveMessage(
        ChatMessage(
          id: 'old_assistant_$index',
          conversationId: conversation.id,
          role: ChatRole.assistant,
          content: '此前已经确认的进展 ${'核对完成。' * 500}',
          status: ChatMessageStatus.complete,
          createdAt: timestamp.add(Duration(minutes: index * 2 + 1)),
          updatedAt: timestamp.add(Duration(minutes: index * 2 + 1)),
        ),
      );
    }

    await harness.workspace.sendChatMessage(
      conversation.id,
      text: '继续当前任务并保留早期事实。',
    );

    final assistant = harness.workspace
        .messagesFor(conversation.id)
        .lastWhere((message) => message.role == ChatRole.assistant);
    final persisted = (await harness.chatRepository.findMessage(assistant.id))!;
    expect(
      taskStore.failureInjected,
      isTrue,
      reason:
          'requests=$requests, summaryWrites=${conversationStore.summaryWriteCount}, '
          'assistantStatus=${assistant.status}, error=${assistant.error}',
    );
    expect(conversationStore.summaryWriteCount, greaterThan(0));
    expect(requests, 0);
    expect(assistant.status, ChatMessageStatus.failed);
    expect(assistant.toolTranscript.any(_containsLocalSummary), isFalse);
    expect(persisted.toolTranscript.any(_containsLocalSummary), isFalse);
    expect(
      (await harness.chatRepository.findGeneration(assistant.id))?.status,
      GenerationStatus.failed,
    );
  });

  test(
    'ModelClient emits terminal for a closed continuation SSE body',
    () async {
      var bodyClosed = false;
      final client = ModelClient(
        client: MockClient.streaming((request, body) async {
          await body.toBytes();
          final response = StreamController<List<int>>();
          scheduleMicrotask(() async {
            for (final line in _completedContinuationEvents()) {
              await Future<void>.delayed(const Duration(milliseconds: 80));
              response.add(utf8.encode(line));
            }
            unawaited(response.close());
            bodyClosed = true;
          });
          return http.StreamedResponse(
            response.stream,
            200,
            headers: const {'content-type': 'text/event-stream'},
          );
        }),
      );

      final deltas = await client
          .streamChat(
            messages: const [ChatRequestMessage(role: 'user', text: '续问')],
            configuration: const ModelConfiguration(
              baseUrl: 'https://model.test',
              model: 'test-model',
              apiKey: 'test-key',
            ),
            now: DateTime(2026, 11, 5),
          )
          .toList()
          .timeout(const Duration(seconds: 2));

      expect(deltas.last.termination, ChatStreamTermination.completed);
      expect(bodyClosed, isTrue, reason: 'fixture body producer must close');
    },
  );

  test(
    'live workspace settles a new turn after stopping an open SSE turn',
    () async {
      final firstResponseCancelled = Completer<void>();
      final firstResponse = StreamController<List<int>>(
        onCancel: () {
          if (!firstResponseCancelled.isCompleted) {
            firstResponseCancelled.complete();
          }
        },
      );
      final secondResponseBodyClosed = Completer<void>();
      var requestCount = 0;
      final client = ModelClient(
        client: MockClient.streaming((request, body) async {
          await body.toBytes();
          requestCount++;
          if (requestCount == 1) {
            return http.StreamedResponse(
              firstResponse.stream,
              200,
              headers: const {'content-type': 'text/event-stream'},
            );
          }
          final response = StreamController<List<int>>();
          scheduleMicrotask(() async {
            for (final line in _completedContinuationEvents()) {
              await Future<void>.delayed(const Duration(milliseconds: 80));
              response.add(utf8.encode(line));
            }
            unawaited(response.close());
            if (!secondResponseBodyClosed.isCompleted) {
              secondResponseBodyClosed.complete();
            }
          });
          return http.StreamedResponse(
            response.stream,
            200,
            headers: const {'content-type': 'text/event-stream'},
          );
        }),
      );
      final harness = await _WorkspaceHarness.create(modelClient: client);
      addTearDown(() async {
        await harness.close();
        await firstResponse.close();
      });
      final conversation = await harness.workspace.createConversation();

      final firstSend = harness.workspace.sendChatMessage(
        conversation.id,
        text: '第一轮未完成的问题',
      );
      await _waitFor(() => requestCount == 1);
      firstResponse.add(_sseContent('第一轮已输出片段'));
      await _waitFor(
        () =>
            harness.workspace.messagesFor(conversation.id).last.content ==
            '第一轮已输出片段',
      );
      expect(firstResponse.isClosed, isFalse, reason: '首段出现时 SSE 仍应保持打开。');
      final stopWatch = Stopwatch()..start();
      await harness.workspace
          .cancelGeneration(conversationId: conversation.id)
          .timeout(const Duration(seconds: 1));
      stopWatch.stop();
      expect(stopWatch.elapsed, lessThanOrEqualTo(const Duration(seconds: 1)));
      await firstSend.timeout(const Duration(seconds: 1));
      await firstResponseCancelled.future.timeout(const Duration(seconds: 1));
      final interrupted = harness.workspace.messagesFor(conversation.id).last;
      expect(interrupted.status, ChatMessageStatus.interrupted);

      final secondSend = harness.workspace.sendChatMessage(
        conversation.id,
        text: '继续处理剩余内容',
      );
      await _waitFor(() => requestCount == 2);
      await secondResponseBodyClosed.future.timeout(const Duration(seconds: 2));
      try {
        await secondSend.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        final assistant = harness.workspace.messagesFor(conversation.id).last;
        final generation = await harness.chatRepository.findGeneration(
          assistant.id,
        );
        fail(
          'workspace failed to settle after body onDone; '
          'bodyClosed=${secondResponseBodyClosed.isCompleted}, '
          'generating=${harness.workspace.isChatGenerating}, '
          'status=${assistant.status}, content=${assistant.content}, '
          'generation=${generation?.status}',
        );
      }

      final messages = harness.workspace.messagesFor(conversation.id);
      expect(messages.where((message) => message.isUser), hasLength(2));
      expect(messages.last.status, ChatMessageStatus.complete);
      expect(messages.last.content, _continuationReply);
      expect(requestCount, 2);
    },
  );

  test(
    'restart continues the original generation with its persisted receipt',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'secretary-agent-process-recovery-',
      );
      addTearDown(() => root.delete(recursive: true));
      late IoVaultStore vault;
      late SqliteIndexDatabase index;
      late SqliteConversationStore chats;
      late VaultAgentTaskStore tasks;
      final attachments = MemoryAttachmentStore();
      var requests = 0;
      late AppRuntime runtime;
      Future<AppRuntime> boot() async {
        vault = IoVaultStore.at(Directory('${root.path}/vault'));
        index = SqliteIndexDatabase('${root.path}/index.sqlite');
        await index.open();
        chats = SqliteConversationStore('${root.path}/conversations.sqlite');
        tasks = VaultAgentTaskStore(vault);
        return AppRuntime.bootstrap(
          vaultOverride: vault,
          indexOverride: index,
          conversationStoreOverride: chats,
          attachmentStoreOverride: attachments,
          agentTaskStore: tasks,
          settingsOverride: FakeSettingsService(modelKey: 'recovery'),
          modelClient: ModelClient(
            client: MockClient.streaming((request, body) async {
              requests++;
              final payload = jsonDecode(await body.bytesToString()) as Map;
              final messages = (payload['messages'] as List).cast<Map>();
              if (requests == 1) {
                final table = runtime.tables.tables.singleWhere(
                  (t) => t.role == TableRole.inboxEvent,
                );
                return _streamResponse({
                  'choices': [
                    {
                      'delta': {
                        'tool_calls': [
                          {
                            'index': 0,
                            'id': 'original_call',
                            'function': {
                              'name': 'content_create',
                              'arguments': jsonEncode({
                                'table_id': table.id,
                                'type': 'note',
                                'title': '唯一内容',
                                'body': '原文',
                                'idempotency_key': 'restart-original',
                              }),
                            },
                          },
                        ],
                      },
                    },
                  ],
                });
              }
              expect(messages.where((m) => m['role'] == 'tool'), hasLength(1));
              if (requests == 2) {
                return http.StreamedResponse(
                  Stream.value(utf8.encode('{}')),
                  401,
                );
              }
              return _streamResponse({
                'choices': [
                  {
                    'delta': {'content': '从原回执继续完成'},
                  },
                ],
              });
            }),
          ),
        );
      }

      runtime = await boot();
      final conversation = await runtime.conversations.createConversation();
      await runtime.conversations.sendChatMessage(
        conversation.id,
        text: '保存一份',
      );
      final original = runtime.conversations.messagesFor(conversation.id).last;
      expect(original.status, ChatMessageStatus.failed);
      expect(
        runtime.tables.entries.where((e) => e.title == '唯一内容'),
        hasLength(1),
      );
      expect(original.toolTranscript, hasLength(2));
      final generationBeforeRestart = (await chats.findGeneration(
        original.id,
      ))!;
      final receiptBeforeRestart =
          generationBeforeRestart.toolCalls.single['completed_receipt_json'];
      await runtime.shutdown();

      final v2Checkpoint = jsonDecode(
        (await vault.read(AgentTaskCheckpoint.storagePath))!,
      ) as Map<String, dynamic>;
      final originalCheckpointTurn =
          (v2Checkpoint['turns'] as List).single as Map;
      final originalTaskId = originalCheckpointTurn['task_id'];
      v2Checkpoint['schema_version'] = 1;
      v2Checkpoint.remove('run_usage');
      v2Checkpoint.remove('active_run_id');
      for (final rawTurn in v2Checkpoint['turns'] as List) {
        (rawTurn as Map).remove('run_id');
      }
      final legacyCheckpoint = jsonEncode(v2Checkpoint);
      await vault.write(AgentTaskCheckpoint.storagePath, legacyCheckpoint);

      runtime = await boot();
      addTearDown(runtime.shutdown);
      expect(requests, 2, reason: 'startup must not replay network requests');
      expect(
        await vault.read('${AgentTaskCheckpoint.storagePath}.v1.backup'),
        legacyCheckpoint,
      );
      final upgradedCheckpoint = jsonDecode(
        (await vault.read(AgentTaskCheckpoint.storagePath))!,
      ) as Map<String, dynamic>;
      expect(
        upgradedCheckpoint['schema_version'],
        AgentTaskCheckpoint.currentSchemaVersion,
      );
      final upgradedTurn = (upgradedCheckpoint['turns'] as List).single as Map;
      expect(upgradedTurn['task_id'], originalTaskId);
      expect(upgradedTurn['assistant_message_id'], original.id);
      expect(runtime.conversations.agentUsage.usedRequests, 2);
      final recoveredBeforeResume = (await chats.findMessage(original.id))!;
      expect(recoveredBeforeResume.toolTranscript, original.toolTranscript);
      final generationAfterUpgrade = await chats.findGeneration(original.id);
      expect(generationAfterUpgrade?.assistantMessageId, original.id);
      expect(
        generationAfterUpgrade?.toolCalls.single['completed_receipt_json'],
        receiptBeforeRestart,
      );
      await runtime.conversations.resumeTasks(approveUncertainEffects: true);
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while ((runtime.conversations.hasPendingChatTurns ||
              runtime.conversations.isChatGenerating ||
              requests < 3) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final messages = runtime.conversations.messagesFor(conversation.id);
      expect(messages.where((m) => !m.isUser), hasLength(1));
      expect(messages.last.id, original.id);
      expect(messages.last.status, ChatMessageStatus.complete);
      expect(requests, 3);
      expect(
        runtime.tables.entries.where((e) => e.title == '唯一内容'),
        hasLength(1),
      );
      expect(runtime.conversations.agentUsage.usedRequests, 3);
    },
  );
  test('setAiPolicy persists the selected action policy', () async {
    final harness = await _WorkspaceHarness.create();
    addTearDown(harness.close);
    final conversation = await harness.workspace.createConversation();
    final policy = AiPolicy.forPreset(AiPolicyPreset.fullAccess);

    await harness.workspace.setAiPolicy(conversation.id, policy);

    final remembered = harness.workspace.findConversation(conversation.id);
    final persisted = await harness.chatRepository.findConversation(
      conversation.id,
    );
    expect(remembered?.aiPolicy?.preset, AiPolicyPreset.fullAccess);
    expect(persisted?.aiPolicy?.preset, AiPolicyPreset.fullAccess);
    expect(
      remembered?.aiPolicy?.decisionFor(AiPermissionAction.tableDelete),
      AiPolicyDecision.allow,
    );
  });

  test(
    'runtime creates conversations from the effective default policy',
    () async {
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(
          defaultAiPolicy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
        ),
      );
      addTearDown(runtime.shutdown);

      final conversation = await runtime.conversations.createConversation();

      expect(conversation.aiPolicy?.preset, AiPolicyPreset.fullAccess);
      expect(
        conversation.effectiveAiPolicy.decisionFor(
          AiPermissionAction.tableDelete,
        ),
        AiPolicyDecision.allow,
      );
    },
  );

  test(
    'memory bootstrap does not initialize the Android background channel',
    () async {
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(),
      );
      addTearDown(runtime.shutdown);

      expect(runtime.backgroundAgent, isA<DisabledAgentBackgroundControl>());
      expect(runtime.conversations.taskStore, isA<MemoryAgentTaskStore>());
    },
  );

  test(
    'invalid task checkpoint fails before module writes or background startup',
    () async {
      final vault = MemoryVaultStore();
      final index = MemoryIndexDatabase();
      final background = _CountingBackgroundControl();
      const invalidCheckpoint = '{"schema_version":99}';
      await vault.write(AgentTaskCheckpoint.storagePath, invalidCheckpoint);

      await expectLater(
        AppRuntime.bootstrap(
          vaultOverride: vault,
          indexOverride: index,
          settingsOverride: FakeSettingsService(),
          agentTaskStore: VaultAgentTaskStore(vault),
          agentBackground: background,
        ),
        throwsFormatException,
      );

      final startupEffects = <String>[
        if (background.initializeCount != 0)
          'background initialize count=${background.initializeCount}',
        if ((await index.listTables()).isNotEmpty)
          'tables initialized=${(await index.listTables()).length}',
        if (vault.files.keys.any(
          (path) => path != AgentTaskCheckpoint.storagePath,
        ))
          'unexpected vault files=${vault.files.keys.join(',')}',
      ];
      expect(startupEffects, isEmpty);
      expect(
        await vault.read(AgentTaskCheckpoint.storagePath),
        invalidCheckpoint,
      );
      expect(
        await vault.read('${AgentTaskCheckpoint.storagePath}.v1.backup'),
        isNull,
      );
    },
  );

  test('missing checkpoint with legacy backup fails before module or background startup', () async {
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    final background = _CountingBackgroundControl();
    final legacy = AgentTaskCheckpoint(
      usage: const AgentUsage(usedRequests: 17),
      turns: const [
        AgentTurnCheckpoint(
          taskId: 'task-in-backup',
          conversationId: 'conversation-in-backup',
          userMessageId: 'user-in-backup',
          assistantMessageId: 'assistant-in-backup',
          kind: AgentTurnQueueKind.conversation,
          status: AgentTurnCheckpointStatus.paused,
          sequence: 4,
        ),
      ],
    ).toJson();
    legacy['schema_version'] = 1;
    legacy.remove('run_budgets');
    legacy.remove('active_budget_run_id');
    ((legacy['turns'] as List).single as Map).remove('budget_run_id');
    final legacyBackup = jsonEncode(legacy);
    final backupPath = '${AgentTaskCheckpoint.storagePath}.v1.backup';
    await vault.write(backupPath, legacyBackup);
    AppRuntime? unexpectedRuntime;
    Object? startupError;

    try {
      unexpectedRuntime = await AppRuntime.bootstrap(
        vaultOverride: vault,
        indexOverride: index,
        settingsOverride: FakeSettingsService(),
        agentTaskStore: VaultAgentTaskStore(vault),
        agentBackground: background,
      );
    } on Object catch (error) {
      startupError = error;
    }
    await unexpectedRuntime?.shutdown();

    expect(startupError, isA<StateError>());
    expect(background.initializeCount, 0);
    expect(await index.listTables(), isEmpty);
    expect(await vault.read(AgentTaskCheckpoint.storagePath), isNull);
    expect(await vault.read(backupPath), legacyBackup);
  });

  test(
    'shutdown records checkpoint failure and still completes cleanup',
    () async {
      final store = _FailingAgentTaskStore();
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(),
        agentTaskStore: store,
      );
      store.failSave = true;

      await runtime.shutdown().timeout(const Duration(seconds: 2));

      expect(
        runtime.conversations.shutdownError,
        contains('checkpoint write failed'),
      );
      expect(runtime.shutdownError, contains('checkpoint write failed'));
    },
  );

  test('cancel interrupts preparation before the network starts', () async {
    final settings = _DelayedSettingsService();
    var requests = 0;
    final harness = await _WorkspaceHarness.create(
      settings: settings,
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          requests++;
          await body.toBytes();
          return http.StreamedResponse(
            Stream.value(utf8.encode('data: [DONE]\n\n')),
            200,
          );
        }),
      ),
    );
    addTearDown(harness.close);
    final conversation = await harness.workspace.createConversation();

    final sending = harness.workspace.sendChatMessage(
      conversation.id,
      text: '准备阶段停止',
    );
    await settings.started.future.timeout(const Duration(seconds: 1));
    await harness.workspace.cancelGeneration().timeout(
      const Duration(seconds: 1),
    );
    await sending.timeout(const Duration(seconds: 1));

    expect(requests, 0);
    final assistant = harness.workspace.messagesFor(conversation.id).last;
    expect(assistant.status, ChatMessageStatus.interrupted);
    expect(assistant.error, contains('没有继续派发新的工具'));
    final generation = await harness.chatRepository.findGeneration(
      assistant.id,
    );
    expect(generation?.status, GenerationStatus.interrupted);
    if (!settings.release.isCompleted) {
      settings.release.complete(settings.settings);
    }
  });

  test('batches stream UI updates and merges text persistence', () async {
    final response = StreamController<List<int>>();
    var requests = 0;
    final harness = await _WorkspaceHarness.create(
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          requests++;
          return http.StreamedResponse(response.stream, 200);
        }),
      ),
    );
    addTearDown(harness.close);
    final conversation = await harness.workspace.createConversation();
    var notifications = 0;
    harness.workspace.addListener(() => notifications++);

    final sending = harness.workspace.sendChatMessage(
      conversation.id,
      text: '流式合批',
    );
    await _waitFor(() => harness.workspace.isChatGenerating);
    expect(requests, 1);
    final notificationBaseline = notifications;
    const chunks = 'abcdefghijklmnopqrst';
    for (final character in chunks.split('')) {
      response.add(
        utf8.encode(
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': character},
              },
            ],
          })}\n\n',
        ),
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 180));
    final assistantId = harness.workspace.messagesFor(conversation.id).last.id;
    final beforePersistence = await harness.chatRepository.findMessage(
      assistantId,
    );
    expect(beforePersistence?.content, isEmpty);
    expect(notifications - notificationBaseline, lessThan(chunks.length / 2));

    await Future<void>.delayed(const Duration(milliseconds: 500));
    final afterPersistence = await harness.chatRepository.findMessage(
      assistantId,
    );
    expect(afterPersistence?.content, chunks);

    response.add(utf8.encode('data: [DONE]\n\n'));
    await response.close();
    await sending.timeout(const Duration(seconds: 2));
    expect(
      harness.workspace.messagesFor(conversation.id).last.status,
      ChatMessageStatus.complete,
    );
  });

  test('turns an empty stream ending into a visible failure', () async {
    final harness = await _WorkspaceHarness.create(
      modelClient: ModelClient(
        client: MockClient.streaming(
          (request, body) async => http.StreamedResponse(
            Stream.value(utf8.encode('data: [DONE]\n\n')),
            200,
          ),
        ),
      ),
    );
    addTearDown(harness.close);
    final conversation = await harness.workspace.createConversation();

    await harness.workspace.sendChatMessage(conversation.id, text: '返回空内容');

    final assistant = harness.workspace.messagesFor(conversation.id).last;
    expect(assistant.status, ChatMessageStatus.failed);
    expect(assistant.error, contains('空回复'));
    final generation = await harness.chatRepository.findGeneration(
      assistant.id,
    );
    expect(generation?.status, GenerationStatus.failed);
  });

  test(
    'startup interrupts a requesting generation without replaying HTTP',
    () async {
      final chats = MemoryConversationStore();
      final timestamp = DateTime(2026, 11, 5, 9);
      const conversationId = 'cnv_requesting_recovery';
      const assistantId = 'msg_requesting_recovery_assistant';
      await chats.upsertConversation(
        Conversation(
          id: conversationId,
          title: '恢复中断请求',
          createdAt: timestamp,
          updatedAt: timestamp,
          autoTitle: false,
        ),
      );
      await chats.upsertMessage(
        ChatMessage(
          id: 'msg_requesting_recovery_user',
          conversationId: conversationId,
          role: ChatRole.user,
          content: '不要自动重发',
          status: ChatMessageStatus.complete,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
      await chats.upsertMessage(
        ChatMessage(
          id: assistantId,
          conversationId: conversationId,
          role: ChatRole.assistant,
          content: '部分流内容',
          status: ChatMessageStatus.streaming,
          createdAt: timestamp.add(const Duration(seconds: 1)),
          updatedAt: timestamp.add(const Duration(seconds: 1)),
        ),
      );
      await chats.upsertGeneration(
        GenerationRun(
          assistantMessageId: assistantId,
          conversationId: conversationId,
          userMessageId: 'msg_requesting_recovery_user',
          status: GenerationStatus.requesting,
          responseText: '部分流内容',
          toolCalls: const [],
          createdAt: timestamp.add(const Duration(seconds: 1)),
          updatedAt: timestamp.add(const Duration(seconds: 1)),
        ),
      );
      var requests = 0;

      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        conversationStoreOverride: chats,
        settingsOverride: FakeSettingsService(modelKey: 'recovery'),
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            requests++;
            await body.toBytes();
            return http.StreamedResponse(
              Stream.value(utf8.encode('data: [DONE]\n\n')),
              200,
            );
          }),
        ),
      );
      addTearDown(runtime.shutdown);

      expect(requests, 0);
      expect(
        (await chats.findGeneration(assistantId))?.status,
        GenerationStatus.interrupted,
      );
      expect(
        (await chats.findMessage(assistantId))?.status,
        ChatMessageStatus.interrupted,
      );
    },
  );

  test('persists each action receipt and skips it during recovery', () async {
    var requests = 0;
    final harness = await _WorkspaceHarness.create(
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          requests++;
          await body.toBytes();
          return http.StreamedResponse(
            Stream.value(utf8.encode('data: [DONE]\n\n')),
            200,
          );
        }),
      ),
    );
    addTearDown(harness.close);
    final conversation = await harness.workspace.createConversation(
      policy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
    );
    final now = DateTime(2026, 11, 3, 12);
    final user = ChatMessage(
      id: 'msg_tool_user',
      conversationId: conversation.id,
      role: ChatRole.user,
      content: '记录提交材料',
      status: ChatMessageStatus.complete,
      createdAt: now,
      updatedAt: now,
    );
    final assistant = ChatMessage(
      id: 'msg_tool_assistant',
      conversationId: conversation.id,
      role: ChatRole.assistant,
      content: '',
      status: ChatMessageStatus.streaming,
      createdAt: now.add(const Duration(seconds: 1)),
      updatedAt: now.add(const Duration(seconds: 1)),
    );
    await harness.chatRepository.saveMessage(user);
    await harness.chatRepository.saveMessage(assistant);
    await harness.chatRepository.saveGeneration(
      GenerationRun(
        assistantMessageId: assistant.id,
        conversationId: conversation.id,
        userMessageId: user.id,
        status: GenerationStatus.requesting,
        responseText: '',
        toolCalls: const [],
        createdAt: assistant.createdAt,
        updatedAt: assistant.updatedAt,
      ),
    );
    final call = ChatWriteToolCall(
      turnId: assistant.id,
      conversationId: conversation.id,
      round: 1,
      index: 0,
      callId: 'call_write_once',
      name: 'create_result',
      wireName: 'create_result',
      rawArguments: jsonEncode({
        'type': 'todo',
        'title': '提交材料',
        'body': '周五前提交',
        'confidence': 0.95,
        'sensitive': false,
      }),
      arguments: const {},
    );

    final firstReceipt = await harness.workspace.executeWriteTool(call);
    final secondReceipt = await harness.workspace.executeWriteTool(call);
    expect(firstReceipt.succeeded, isTrue);
    expect(secondReceipt.succeeded, isTrue);
    expect(harness.results.documents, hasLength(1));

    final afterAction = await harness.chatRepository.findMessage(assistant.id);
    expect(afterAction?.actions, hasLength(1));
    final generation = await harness.chatRepository.findGeneration(
      assistant.id,
    );
    expect(generation?.toolCalls, hasLength(1));
    expect(generation?.toolCalls.single['completed_action_json'], isNotEmpty);
    expect(
      generation?.toolCalls.single['completed_receipt_json'],
      contains('succeeded'),
    );

    await harness.chatRepository.saveGeneration(
      generation!.copyWith(
        status: GenerationStatus.responseReady,
        responseText: '已记录。',
      ),
    );
    await harness.chatRepository.saveMessage(
      afterAction!.copyWith(
        status: ChatMessageStatus.streaming,
        updatedAt: DateTime.now(),
      ),
    );
    await harness.workspace.initialize();

    expect(harness.results.documents, hasLength(1));
    final recovered = await harness.chatRepository.findMessage(assistant.id);
    expect(recovered?.status, ChatMessageStatus.complete);
    expect(recovered?.actions, hasLength(1));
    expect(
      (await harness.chatRepository.findGeneration(assistant.id))?.status,
      GenerationStatus.completed,
    );
    expect(requests, 0);
  });

  test(
    'full access applies global knowledge through the tool callback',
    () async {
      final harness = await _WorkspaceHarness.create();
      addTearDown(harness.close);
      final conversation = await harness.workspace.createConversation(
        policy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
      );
      final now = DateTime(2026, 11, 3, 13);
      final user = ChatMessage(
        id: 'msg_global_user',
        conversationId: conversation.id,
        role: ChatRole.user,
        content: '记住本学期第十八周结束',
        status: ChatMessageStatus.complete,
        createdAt: now,
        updatedAt: now,
      );
      final assistant = ChatMessage(
        id: 'msg_global_assistant',
        conversationId: conversation.id,
        role: ChatRole.assistant,
        content: '',
        status: ChatMessageStatus.streaming,
        createdAt: now.add(const Duration(seconds: 1)),
        updatedAt: now.add(const Duration(seconds: 1)),
      );
      await harness.chatRepository.saveMessage(user);
      await harness.chatRepository.saveMessage(assistant);
      await harness.chatRepository.saveGeneration(
        GenerationRun(
          assistantMessageId: assistant.id,
          conversationId: conversation.id,
          userMessageId: user.id,
          status: GenerationStatus.requesting,
          responseText: '',
          toolCalls: const [],
          createdAt: assistant.createdAt,
          updatedAt: assistant.updatedAt,
        ),
      );
      final call = ChatWriteToolCall(
        turnId: assistant.id,
        conversationId: conversation.id,
        round: 1,
        index: 0,
        callId: 'call_global_once',
        name: 'propose_global_knowledge_change',
        wireName: 'propose_global_knowledge_change',
        rawArguments: jsonEncode({
          'operation': 'create',
          'target_id': null,
          'expected_revision': null,
          'proposal': {
            'title': '2026 秋季学期',
            'body': '本学期第十八周结束。',
            'facts': {'end_week': 18},
          },
        }),
        arguments: const {},
      );

      final firstReceipt = await harness.workspace.executeWriteTool(call);
      final secondReceipt = await harness.workspace.executeWriteTool(call);

      expect(firstReceipt.succeeded, isTrue);
      expect(secondReceipt.succeeded, isTrue);
      expect(harness.results.documents, hasLength(1));
      expect(harness.results.documents.single.isGlobalKnowledge, isTrue);
      final generation = await harness.chatRepository.findGeneration(
        assistant.id,
      );
      expect(
        generation?.toolCalls.single['completed_receipt_json'],
        contains('全局知识已创建'),
      );
    },
  );

  test(
    'full access does not silently approve a pre-existing pending candidate',
    () async {
      final harness = await _WorkspaceHarness.create();
      addTearDown(harness.close);
      final conversation = await harness.workspace.createConversation(
        policy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
      );
      final now = DateTime(2026, 11, 3, 14);
      final user = ChatMessage(
        id: 'msg_old_pending_user',
        conversationId: conversation.id,
        role: ChatRole.user,
        content: '旧模式等待确认的知识',
        status: ChatMessageStatus.complete,
        createdAt: now,
        updatedAt: now,
      );
      final assistant = ChatMessage(
        id: 'msg_old_pending_assistant',
        conversationId: conversation.id,
        role: ChatRole.assistant,
        content: '',
        status: ChatMessageStatus.streaming,
        createdAt: now.add(const Duration(seconds: 1)),
        updatedAt: now.add(const Duration(seconds: 1)),
      );
      await harness.chatRepository.saveMessage(user);
      await harness.chatRepository.saveMessage(assistant);
      await harness.chatRepository.saveGeneration(
        GenerationRun(
          assistantMessageId: assistant.id,
          conversationId: conversation.id,
          userMessageId: user.id,
          status: GenerationStatus.requesting,
          responseText: '',
          toolCalls: const [],
          createdAt: assistant.createdAt,
          updatedAt: assistant.updatedAt,
        ),
      );
      final proposal = {
        'title': '待人工确认的旧候选',
        'body': '不能因当前策略变为完全权限而静默批准。',
        'facts': {'source': 'legacy-pending'},
      };
      final oldCandidate = await harness.results.proposeGlobalKnowledgeChange(
        operation: GlobalKnowledgeOperation.create,
        proposal: proposal,
        sourceConversationId: conversation.id,
        sourceMessageId: user.id,
      );
      expect(oldCandidate.status, GlobalKnowledgeCandidateStatus.pending);

      final call = ChatWriteToolCall(
        turnId: assistant.id,
        conversationId: conversation.id,
        round: 1,
        index: 0,
        callId: 'call_old_pending_retry',
        name: 'propose_global_knowledge_change',
        wireName: 'propose_global_knowledge_change',
        rawArguments: jsonEncode({
          'operation': 'create',
          'target_id': null,
          'expected_revision': null,
          'proposal': proposal,
        }),
        arguments: const {},
      );

      final receipt = await harness.workspace.executeWriteTool(call);
      expect(receipt.outcome, ChatWriteToolOutcome.waitingConfirmation);
      expect(harness.results.documents, isEmpty);
      expect(
        harness.results.globalKnowledgeCandidates.single.status,
        GlobalKnowledgeCandidateStatus.pending,
      );
    },
  );

  test(
    'runtime executes a table write before requesting the final answer',
    () async {
      late final AppRuntime runtime;
      final store = MemoryConversationStore();
      var requests = 0;
      runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        conversationStoreOverride: store,
        attachmentStoreOverride: MemoryAttachmentStore(),
        settingsOverride: FakeSettingsService(modelKey: 'runtime-callback'),
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            requests++;
            final payload =
                jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            final messages = (payload['messages'] as List).cast<Map>();
            if (!messages.any((message) => message['role'] == 'tool')) {
              final table = runtime.tables.tables.singleWhere(
                (item) => item.role == TableRole.inboxEvent,
              );
              return _streamResponse({
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_runtime_write',
                          'function': {
                            'name': 'content_create',
                            'arguments': jsonEncode({
                              'table_id': table.id,
                              'type': 'note',
                              'title': 'Agent 回执',
                              'body': '工具执行后才请求最终答复。',
                              'idempotency_key': 'runtime-callback-write',
                            }),
                          },
                        },
                      ],
                    },
                  },
                ],
              });
            }
            return _streamResponse({
              'choices': [
                {
                  'delta': {'content': '已写入并核对。'},
                },
              ],
            });
          }),
        ),
      );
      addTearDown(runtime.shutdown);
      final conversation = await runtime.conversations.createConversation();

      await runtime.conversations.sendChatMessage(
        conversation.id,
        text: '记录 Agent 回执',
      );

      expect(requests, 2);
      expect(
        runtime.tables.entries
            .singleWhere((entry) => entry.title == 'Agent 回执')
            .body,
        '工具执行后才请求最终答复。',
      );
      final assistant = runtime.conversations.messagesFor(conversation.id).last;
      expect(assistant.status, ChatMessageStatus.complete);
      expect(assistant.content, '已写入并核对。');
      expect(
        assistant.tableActions.single.status,
        TableChatActionStatus.applied,
      );
      expect(assistant.tableActions, hasLength(1));
      final generation = await store.findGeneration(assistant.id);
      expect(generation?.toolCalls.single['completed_action_json'], isNotEmpty);
    },
  );

  test(
    'sharing the same schedule change again reuses its event receipt',
    () async {
      late final AppRuntime runtime;
      var requests = 0;
      final noticeTime = DateTime.parse('2026-11-05T09:00:00+08:00');
      final changedStart = DateTime.parse('2026-11-12T14:00:00+08:00');
      final laterNoticeTime = DateTime.parse('2026-11-06T09:00:00+08:00');
      final laterChangedStart = DateTime.parse('2026-11-13T14:00:00+08:00');
      runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        conversationStoreOverride: MemoryConversationStore(),
        attachmentStoreOverride: MemoryAttachmentStore(),
        settingsOverride: FakeSettingsService(modelKey: 'runtime-schedule'),
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            requests++;
            await body.bytesToString();
            if (requests.isOdd) {
              final isLaterNotice = requests > 3;
              final schedule = runtime.tables.entries.singleWhere(
                (entry) => entry.id == 'schedule_exam',
              );
              return _streamResponse({
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_schedule_$requests',
                          'function': {
                            'name': 'schedule_change',
                            'arguments': jsonEncode({
                              'schedule_id': schedule.id,
                              'if_revision': schedule.revision,
                              'event_title': isLaterNotice
                                  ? '老师再次调整期中考试时间'
                                  : '老师调整了期中考试时间',
                              'event_body': isLaterNotice
                                  ? '考试改至下周五下午。'
                                  : '考试改至下周四下午。',
                              'event_occurred_at':
                                  (isLaterNotice ? laterNoticeTime : noticeTime)
                                      .toIso8601String(),
                              'new_start':
                                  (isLaterNotice
                                          ? laterChangedStart
                                          : changedStart)
                                      .toIso8601String(),
                              'new_end': null,
                              'idempotency_key': 'model-generated-$requests',
                            }),
                          },
                        },
                      ],
                    },
                  },
                ],
              });
            }
            return _streamResponse({
              'choices': [
                {
                  'delta': {'content': '已核对改期通知。'},
                },
              ],
            });
          }),
        ),
      );
      addTearDown(runtime.shutdown);
      final scheduleTable = runtime.tables.tables.singleWhere(
        (table) => table.role == TableRole.inboxSchedule,
      );
      await runtime.tables.createEntry(
        TableEntryDocument(
          id: 'schedule_exam',
          type: TableContentType.schedule,
          tableId: scheduleTable.id,
          title: '期中考试',
          revision: 1,
          createdAt: noticeTime,
          updatedAt: noticeTime,
          body: '',
          start: DateTime.parse('2026-11-10T09:00:00+08:00'),
        ),
      );
      final conversation = await runtime.conversations.createConversation(
        policy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
      );

      await runtime.conversations.sendChatMessage(
        conversation.id,
        text: '处理老师发来的期中考试改期通知。',
      );
      final firstAssistant = runtime.conversations
          .messagesFor(conversation.id)
          .lastWhere((message) => message.role == ChatRole.assistant);
      await runtime.conversations.sendChatMessage(
        conversation.id,
        text: '再处理一次同一条改期通知，确认没有重复。',
      );
      final assistants = runtime.conversations
          .messagesFor(conversation.id)
          .where((message) => message.role == ChatRole.assistant)
          .toList();
      final secondAssistant = assistants.last;

      expect(requests, 4);
      expect(firstAssistant.id, isNot(secondAssistant.id));
      expect(
        firstAssistant.tableActions.single.status,
        TableChatActionStatus.applied,
      );
      expect(
        secondAssistant.tableActions.single.status,
        TableChatActionStatus.applied,
      );
      expect(
        secondAssistant.tableActions.single.relatedEntryId,
        firstAssistant.tableActions.single.relatedEntryId,
      );
      final updatedSchedule = await runtime.tables.readEntry('schedule_exam');
      expect(updatedSchedule!.revision, 2, reason: '重复分享不应再次改写日程。');
      expect(updatedSchedule.start!.isAtSameMomentAs(changedStart), isTrue);
      expect(
        runtime.tables.entries
            .where((entry) => entry.type == TableContentType.event)
            .where(
              (entry) => entry.affects.any(
                (change) => change.scheduleId == 'schedule_exam',
              ),
            ),
        hasLength(1),
      );

      await runtime.conversations.sendChatMessage(
        conversation.id,
        text: '再处理第二条后来收到的改期通知。',
      );
      final laterAssistant = runtime.conversations
          .messagesFor(conversation.id)
          .lastWhere((message) => message.role == ChatRole.assistant);
      final finalSchedule = await runtime.tables.readEntry('schedule_exam');
      expect(requests, 6);
      expect(
        laterAssistant.tableActions.single.status,
        TableChatActionStatus.applied,
      );
      expect(finalSchedule!.revision, 3);
      expect(finalSchedule.start!.isAtSameMomentAs(laterChangedStart), isTrue);
      expect(
        runtime.tables.entries
            .where((entry) => entry.type == TableContentType.event)
            .where(
              (entry) => entry.affects.any(
                (change) => change.scheduleId == 'schedule_exam',
              ),
            ),
        hasLength(2),
      );
    },
  );
}

List<String> _completedContinuationEvents() {
  const text = _continuationReply;
  return [
    for (var index = 0; index < text.length; index += 6)
      _sseContentEvent(
        text.substring(
          index,
          index + 6 > text.length ? text.length : index + 6,
        ),
      ),
    'data: [DONE]\n\n',
  ];
}

const _continuationReply = '这是一段足够长的生成内容，用于验证用户停止本轮后仍能继续提问。';

List<int> _sseContent(String text) => utf8.encode(_sseContentEvent(text));

String _sseContentEvent(String text) =>
    'data: ${jsonEncode({
      'choices': [
        {
          'delta': {'content': text},
        },
      ],
    })}\n\n';

http.StreamedResponse _streamResponse(Map<String, dynamic> event) {
  final body = ['data: ${jsonEncode(event)}\n\n', 'data: [DONE]\n\n'];
  return http.StreamedResponse(
    Stream.fromIterable(body.map(utf8.encode)),
    200,
    headers: const {'content-type': 'text/event-stream'},
  );
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not reached before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _DelayedSettingsService extends SettingsService {
  final started = Completer<void>();
  final release = Completer<AppSettings>();
  final settings = const AppSettings(
    deviceId: 'delayed-settings',
    themeMode: ThemePreference.light,
    modelBaseUrl: 'https://api.deepseek.com',
    modelName: 'deepseek-flash',
    hasModelKey: true,
    showCompletedTodos: false,
    calendarMonthDetailed: true,
  );

  @override
  Future<AppSettings> load() {
    if (!started.isCompleted) started.complete();
    return release.future;
  }

  @override
  Future<String?> readModelKey() async => 'test-key';
}

class _FailingAgentTaskStore implements AgentTaskStore {
  bool failSave = false;

  @override
  Future<AgentTaskCheckpoint> preflight() => load();

  @override
  Future<AgentTaskCheckpoint> load() async => const AgentTaskCheckpoint();

  @override
  Future<void> save(AgentTaskCheckpoint checkpoint) async {
    if (failSave) throw StateError('checkpoint write failed');
  }
}

class _SummaryObservingConversationStore extends MemoryConversationStore {
  int summaryWriteCount = 0;

  @override
  Future<void> upsertMessage(ChatMessage message) async {
    if (message.toolTranscript.any(_containsLocalSummary)) {
      summaryWriteCount++;
    }
    await super.upsertMessage(message);
  }
}

class _FailAfterSummaryTaskStore extends MemoryAgentTaskStore {
  _FailAfterSummaryTaskStore(this.conversationStore);

  final _SummaryObservingConversationStore conversationStore;
  bool failureInjected = false;

  @override
  Future<void> save(AgentTaskCheckpoint checkpoint) async {
    if (!failureInjected && conversationStore.summaryWriteCount > 0) {
      failureInjected = true;
      throw StateError('simulated task checkpoint write failure');
    }
    await super.save(checkpoint);
  }
}

bool _containsLocalSummary(Map<String, dynamic> item) =>
    item['role'] == 'system' && '${item['content']}'.contains('本地安全前缀摘要');

class _CountingBackgroundControl extends DisabledAgentBackgroundControl {
  int initializeCount = 0;

  @override
  Future<void> initialize() async {
    initializeCount++;
  }
}

class _WorkspaceHarness {
  _WorkspaceHarness({
    required this.chatRepository,
    required this.results,
    required this.workspace,
  });

  final ChatRepository chatRepository;
  final ResultLibrary results;
  final ConversationWorkspace workspace;

  static Future<_WorkspaceHarness> create({
    SettingsService? settings,
    ModelClient? modelClient,
    MemoryConversationStore? conversationStore,
    AgentTaskStore? taskStore,
    ChatAgentLoopPolicy agentLoopPolicy = const ChatAgentLoopPolicy(),
  }) async {
    final settingsService =
        settings ?? FakeSettingsService(modelKey: 'test-key');
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    final repository = ResultRepository(
      vault: vault,
      index: index,
      deviceId: 'workspace-agent-test',
    );
    await repository.initialize();
    final results = ResultLibrary(repository: repository);
    await results.initialize();
    final capture = CaptureWorkflow(
      repository: repository,
      results: results,
      indexDatabase: index,
      captureService: CaptureService(
        settings: settingsService,
        parser: const DeterministicParser(),
        modelClient: modelClient,
      ),
    );
    await capture.initialize();
    final chatRepository = ChatRepository(
      store: conversationStore ?? MemoryConversationStore(),
      attachments: MemoryAttachmentStore(),
    );
    await chatRepository.initialize();
    final workspace = ConversationWorkspace(
      repository: chatRepository,
      results: results,
      chatService: ChatService(
        settings: settingsService,
        repository: chatRepository,
        modelClient: modelClient,
        agentLoopPolicy: agentLoopPolicy,
      ),
      autoRecordProcessor: AutoRecordProcessor(
        chatRepository: chatRepository,
        results: results,
        captures: capture,
        deviceId: () => repository.deviceId,
      ),
      defaultPolicy: () => AiPolicy.forPreset(AiPolicyPreset.standard),
      taskStore: taskStore,
    );
    await workspace.initialize();
    return _WorkspaceHarness(
      chatRepository: chatRepository,
      results: results,
      workspace: workspace,
    );
  }

  Future<void> close() async {
    await workspace.shutdown();
    await chatRepository.close();
  }
}
