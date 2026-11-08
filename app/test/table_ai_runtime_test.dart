import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/ai_policy.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/table_repository.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_task_store.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'test_support.dart';

void main() {
  test(
    'full access changes an inbox target through the model tool path',
    () async {
      var modelRequestCount = 0;
      late final String sourceTableId;
      late final String targetTableId;
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(modelKey: 'inbox-target-agent'),
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            final payload =
                jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            modelRequestCount++;
            if (modelRequestCount > 1) {
              final toolReply = (payload['messages'] as List)
                  .whereType<Map>()
                  .lastWhere((message) => message['role'] == 'tool');
              expect(toolReply['content'], contains('"status":"succeeded"'));
              return _stream({
                'choices': [
                  {
                    'delta': {'content': '已调整待办收纳目标。'},
                  },
                ],
              }, finish: 'stop');
            }
            return _stream({
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_assign_inbox_todo',
                        'function': {
                          'name': 'table_propose',
                          'arguments': jsonEncode({
                            'operation': 'assign_inbox_target',
                            'table_id': targetTableId,
                            'expected_revision': 0,
                            'payload': {
                              'kind': 'todo',
                              'expected_current_table_id': sourceTableId,
                            },
                            'idempotency_key': 'assign-inbox-todo',
                          }),
                        },
                      },
                    ],
                  },
                },
              ],
            }, finish: 'tool_calls');
          }),
        ),
      );
      addTearDown(runtime.shutdown);
      sourceTableId = runtime.tables.inboxAssignments.targetFor(
        InboxAssignmentKind.todo,
      )!;
      final target = await runtime.tables.createTable(title: '任务中心');
      targetTableId = target.id;
      final conversation = await runtime.conversations.createConversation();
      await runtime.conversations.setAiPolicy(
        conversation.id,
        AiPolicy.forPreset(AiPolicyPreset.fullAccess),
      );

      await runtime.conversations.sendChatMessage(
        conversation.id,
        text: '把待办收纳目标改为任务中心',
      );

      expect(
        runtime.tables.inboxAssignments.targetFor(InboxAssignmentKind.todo),
        target.id,
      );
      final assistant = runtime.conversations.messagesFor(conversation.id).last;
      expect(
        assistant.tableActions.single.status,
        TableChatActionStatus.applied,
      );
      expect(assistant.content, contains('已调整待办收纳目标'));
      expect(modelRequestCount, 2);
    },
  );

  test(
    'standard inbox target change waits for explicit confirmation',
    () async {
      var modelRequestCount = 0;
      late final String sourceTableId;
      late final int assignmentRevision;
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(modelKey: 'inbox-target-ask'),
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            final payload =
                jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            modelRequestCount++;
            if (modelRequestCount > 1) {
              final toolReply = (payload['messages'] as List)
                  .whereType<Map>()
                  .lastWhere((message) => message['role'] == 'tool');
              expect(
                toolReply['content'],
                contains('"status":"waitingConfirmation"'),
              );
              return _stream({
                'choices': [
                  {
                    'delta': {'content': '待办收纳目标已提出，等待确认。'},
                  },
                ],
              }, finish: 'stop');
            }
            return _stream({
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_clear_inbox_todo',
                        'function': {
                          'name': 'table_propose',
                          'arguments': jsonEncode({
                            'operation': 'assign_inbox_target',
                            'table_id': null,
                            'expected_revision': assignmentRevision,
                            'payload': {
                              'kind': 'todo',
                              'expected_current_table_id': sourceTableId,
                            },
                            'idempotency_key': 'clear-inbox-todo',
                          }),
                        },
                      },
                    ],
                  },
                },
              ],
            }, finish: 'tool_calls');
          }),
        ),
      );
      addTearDown(runtime.shutdown);
      final before = await runtime.tables.readInboxAssignments();
      sourceTableId = before.targetFor(InboxAssignmentKind.todo)!;
      assignmentRevision = before.revision;
      final conversation = await runtime.conversations.createConversation();
      await runtime.conversations.setAiPolicy(
        conversation.id,
        AiPolicy.forPreset(AiPolicyPreset.standard),
      );

      await runtime.conversations.sendChatMessage(
        conversation.id,
        text: '清除待办收纳目标',
      );

      final assistant = runtime.conversations.messagesFor(conversation.id).last;
      final pending = assistant.tableActions.single;
      expect(pending.status, TableChatActionStatus.pendingConfirmation);
      expect(
        runtime.tables.inboxAssignments.targetFor(InboxAssignmentKind.todo),
        sourceTableId,
      );
      expect(await runtime.tables.pendingInboxAssignmentOperationId(), isNull);
      expect(modelRequestCount, 2);

      await runtime.conversations.confirmTableStructureAction(pending.id);
      final confirmed = runtime.conversations.messagesFor(conversation.id).last;
      expect(
        confirmed.tableActions.single.status,
        TableChatActionStatus.applied,
      );
      expect(
        runtime.tables.inboxAssignments.targetFor(InboxAssignmentKind.todo),
        isNull,
      );
      expect(await runtime.tables.pendingInboxAssignmentOperationId(), isNull);
    },
  );

  test('explicit task resume restores an inbox receipt after a committed write crash', () async {
    final store = _GateAppliedInboxActionStore();
    final vault = MemoryVaultStore();
    final taskStore = VaultAgentTaskStore(vault);
    var modelRequestCount = 0;
    late final String sourceTableId;
    late final String targetTableId;
    final firstRuntime = await AppRuntime.bootstrap(
      vaultOverride: vault,
      indexOverride: MemoryIndexDatabase(),
      conversationStoreOverride: store,
      agentTaskStore: taskStore,
      settingsOverride: FakeSettingsService(modelKey: 'inbox-crash-recovery'),
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          final payload =
              jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
          modelRequestCount++;
          if (modelRequestCount > 1) {
            final toolReply = (payload['messages'] as List)
                .whereType<Map>()
                .lastWhere((message) => message['role'] == 'tool');
            expect(toolReply['content'], contains('"status":"succeeded"'));
            return _stream({
              'choices': [
                {
                  'delta': {'content': '收纳调整已提交。'},
                },
              ],
            }, finish: 'stop');
          }
          return _stream({
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_crash_assign_inbox',
                      'function': {
                        'name': 'table_propose',
                        'arguments': jsonEncode({
                          'operation': 'assign_inbox_target',
                          'table_id': targetTableId,
                          'expected_revision': 0,
                          'payload': {
                            'kind': 'todo',
                            'expected_current_table_id': sourceTableId,
                          },
                          'idempotency_key': 'crash-recovery-assignment',
                        }),
                      },
                    },
                  ],
                },
              },
            ],
          }, finish: 'tool_calls');
        }),
      ),
    );
    AppRuntime? secondRuntime;
    var recoveryModelRequestCount = 0;
    addTearDown(() async {
      store.releaseFirstAppliedActionSave();
      await secondRuntime?.shutdown();
      await firstRuntime.shutdown();
    });
    sourceTableId = firstRuntime.tables.inboxAssignments.targetFor(
      InboxAssignmentKind.todo,
    )!;
    final target = await firstRuntime.tables.createTable(title: '恢复后目标');
    targetTableId = target.id;
    final conversation = await firstRuntime.conversations.createConversation();
    await firstRuntime.conversations.setAiPolicy(
      conversation.id,
      AiPolicy.forPreset(AiPolicyPreset.fullAccess),
    );

    final firstSend = firstRuntime.conversations.sendChatMessage(
      conversation.id,
      text: '调整待办收纳目标',
    );

    await store.appliedInboxActionSaveAttempted.future.timeout(
      const Duration(seconds: 2),
    );
    expect(
      firstRuntime.tables.inboxAssignments.targetFor(InboxAssignmentKind.todo),
      target.id,
    );
    final pendingOperationId = await firstRuntime.tables
        .pendingInboxAssignmentOperationId();
    expect(pendingOperationId, isNotNull);
    final firstAssistantId = (await store.listMessages(conversation.id))
        .singleWhere((message) => message.role == ChatRole.assistant)
        .id;
    final persistedIntent = await store.findMessage(firstAssistantId);
    expect(persistedIntent!.toolTranscript, isNotEmpty);
    expect(
      (await store.findGeneration(firstAssistantId))?.status,
      GenerationStatus.requesting,
      reason: 'force-stop occurred before tool receipt persistence',
    );

    final recovered = await AppRuntime.bootstrap(
      vaultOverride: vault,
      indexOverride: MemoryIndexDatabase(),
      conversationStoreOverride: store,
      agentTaskStore: VaultAgentTaskStore(vault),
      settingsOverride: FakeSettingsService(modelKey: 'inbox-crash-recovery'),
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          await body.bytesToString();
          recoveryModelRequestCount++;
          return _stream({
            'choices': [
              {
                'delta': {'content': '恢复后的回复。'},
              },
            ],
          }, finish: 'stop');
        }),
      ),
    );
    secondRuntime = recovered;
    await recovered.conversations.openConversation(conversation.id);

    var recoveredAssistant = recovered.conversations
        .messagesFor(conversation.id)
        .singleWhere((message) => message.id == firstAssistantId);
    expect(recoveredAssistant.status, ChatMessageStatus.interrupted);
    expect(recoveredAssistant.tableActions, isEmpty);
    expect(
      (await store.findGeneration(firstAssistantId))?.status,
      GenerationStatus.interrupted,
    );
    expect(
      await recovered.tables.pendingInboxAssignmentOperationId(),
      pendingOperationId,
    );
    expect(recovered.conversations.hasTasksNeedingReview, isTrue);

    await recovered.conversations.resumeTasks(approveUncertainEffects: true);
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while ((recovered.conversations.hasPendingChatTurns ||
            recovered.conversations.isChatGenerating ||
            recoveryModelRequestCount == 0) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    recoveredAssistant = recovered.conversations
        .messagesFor(conversation.id)
        .singleWhere((message) => message.id == firstAssistantId);
    expect(
      recoveredAssistant.tableActions.single.status,
      TableChatActionStatus.applied,
    );
    expect(recoveredAssistant.tableActions.single.id, pendingOperationId);
    expect(
      recovered.tables.inboxAssignments.targetFor(InboxAssignmentKind.todo),
      target.id,
    );
    expect(await recovered.tables.pendingInboxAssignmentOperationId(), isNull);
    expect(recoveryModelRequestCount, 1);
    store.releaseFirstAppliedActionSave();
    await firstSend.timeout(const Duration(seconds: 2));
    expect(
      (await store.findGeneration(firstAssistantId))?.status,
      GenerationStatus.completed,
    );
    expect((await recovered.tables.readInboxAssignments()).revision, 1);
  });

  test(
    'third-state assignment journal opens in visible read-only review',
    () async {
      final vault = MemoryVaultStore();
      final seedIndex = MemoryIndexDatabase();
      await seedIndex.open();
      final seed = TableRepository(vault: vault, index: seedIndex);
      await seed.initialize();
      final source = (await seed.inboxAssignments()).targetFor(
        InboxAssignmentKind.todo,
      )!;
      final target = await seed.createTable(title: '预期目标');
      final external = await seed.createTable(title: '外部目标');
      final beforeRaw = (await vault.read(
        TableRepository.inboxAssignmentsPath,
      ))!;
      final before = jsonDecode(beforeRaw) as Map<String, dynamic>;
      final beforeAssignments = Map<String, dynamic>.from(
        before['assignments'] as Map,
      );
      final afterAssignments = Map<String, dynamic>.from(beforeAssignments)
        ..['todo'] = target.id;
      final after = jsonEncode({
        ...before,
        'revision': (before['revision'] as int) + 1,
        'assignments': afterAssignments,
      });
      final externalAssignments = Map<String, dynamic>.from(beforeAssignments)
        ..['todo'] = external.id;
      final externalState = jsonEncode({
        ...before,
        'revision': (before['revision'] as int) + 2,
        'assignments': externalAssignments,
      });
      await vault.write(TableRepository.inboxAssignmentsPath, externalState);
      await vault.write(
        TableRepository.writeJournalPath,
        jsonEncode({
          'schema_version': 2,
          'kind': 'inbox_assignments',
          'operation_id': 'act_uncertain_inbox',
          'request_signature': 'uncertain-signature',
          'before': beforeRaw,
          'after': after,
          'receipt': {
            'operation_id': 'act_uncertain_inbox',
            'kind': InboxAssignmentKind.todo.wireName,
            'previous_table_id': source,
            'table_id': target.id,
            'previous_revision': before['revision'],
            'revision': (before['revision'] as int) + 1,
          },
        }),
      );
      final savedJournal = await vault.read(TableRepository.writeJournalPath);
      AppRuntime? runtime;
      addTearDown(() => runtime?.shutdown());

      runtime = await AppRuntime.bootstrap(
        vaultOverride: vault,
        indexOverride: MemoryIndexDatabase(),
        conversationStoreOverride: MemoryConversationStore(),
        settingsOverride: FakeSettingsService(modelKey: 'third-state-review'),
      );

      expect(runtime.tables.inboxAssignmentNeedsReview, isTrue);
      expect(runtime.tables.tables, isNotEmpty);
      expect(
        (await runtime.tables.readInboxAssignments()).targetFor(
          InboxAssignmentKind.todo,
        ),
        external.id,
      );
      await expectLater(
        runtime.tables.createTable(title: '核对期间禁止写入'),
        throwsStateError,
      );
      expect(await vault.read(TableRepository.writeJournalPath), savedJournal);
      expect(
        await vault.read(TableRepository.inboxAssignmentsPath),
        externalState,
      );
    },
  );

  test(
    'startup recovery never replays legacy result writes in table mode',
    () async {
      final store = MemoryConversationStore();
      final now = DateTime.now();
      const conversationId = 'cnv_legacy_pending_recovery';
      const userMessageId = 'msg_legacy_pending_user';
      const assistantMessageId = 'msg_legacy_pending_assistant';
      await store.upsertConversation(
        Conversation(
          id: conversationId,
          title: '旧格式待恢复会话',
          createdAt: now,
          updatedAt: now,
          autoTitle: false,
        ),
      );
      await store.upsertMessage(
        ChatMessage(
          id: userMessageId,
          conversationId: conversationId,
          role: ChatRole.user,
          content: '帮我创建待办',
          status: ChatMessageStatus.complete,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await store.upsertMessage(
        ChatMessage(
          id: assistantMessageId,
          conversationId: conversationId,
          role: ChatRole.assistant,
          content: '',
          status: ChatMessageStatus.streaming,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await store.upsertGeneration(
        GenerationRun(
          assistantMessageId: assistantMessageId,
          conversationId: conversationId,
          userMessageId: userMessageId,
          status: GenerationStatus.responseReady,
          responseText: '已记录旧格式待办',
          toolCalls: [
            {
              'index': '0',
              'id': 'call_legacy_pending',
              'name': 'create_result',
              'arguments': jsonEncode({
                'type': 'todo',
                'title': '不得回放为旧待办',
                'body': '迁移后的会话恢复必须使用表格式工具。',
                'confidence': 0.99,
                'sensitive': false,
                'due': now.add(const Duration(days: 2)).toIso8601String(),
              }),
            },
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );

      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        conversationStoreOverride: store,
        attachmentStoreOverride: MemoryAttachmentStore(),
        settingsOverride: FakeSettingsService(deviceId: 'legacy-recovery'),
      );
      addTearDown(runtime.shutdown);

      expect(runtime.results.documents, isEmpty);
      expect(runtime.tables.entries, isEmpty);
      await runtime.conversations.openConversation(conversationId);
      final recovered = runtime.conversations
          .messagesFor(conversationId)
          .singleWhere((message) => message.id == assistantMessageId);
      expect(recovered.status, ChatMessageStatus.complete);
      expect(recovered.actions, isEmpty);
    },
  );

  test(
    'complete model response applies table content without confirmation',
    () async {
      late final AppRuntime runtime;
      var modelRequestCount = 0;
      runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(modelKey: 'table-ai-test'),
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            final payload =
                jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            modelRequestCount++;
            if (modelRequestCount > 1) {
              final messages = payload['messages'] as List;
              final toolReplies = messages
                  .whereType<Map>()
                  .where((message) => message['role'] == 'tool')
                  .toList();
              expect(toolReplies, isNotEmpty);
              expect(
                toolReplies.last['content'],
                contains('"status":"succeeded"'),
              );
              return _stream({
                'choices': [
                  {
                    'delta': {'content': '已记录考试范围。'},
                  },
                ],
              }, finish: 'stop');
            }
            final names = (payload['tools'] as List)
                .map((tool) => (tool as Map)['function']['name'])
                .toSet();
            expect(names, contains('content_create'));
            expect(names, contains('table_propose'));
            expect(names, isNot(contains('create_result')));
            return _stream({
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_create_table_note',
                        'function': {
                          'name': 'content_create',
                          'arguments': jsonEncode({
                            'table_id': runtime.tables.tables
                                .singleWhere(
                                  (table) => table.role == TableRole.inboxEvent,
                                )
                                .id,
                            'type': 'note',
                            'title': '考试范围',
                            'body': '第三章到第五章',
                            'idempotency_key': 'create-exam-note',
                          }),
                        },
                      },
                    ],
                  },
                },
              ],
            }, finish: 'tool_calls');
          }),
        ),
      );
      addTearDown(runtime.shutdown);
      final conversation = await runtime.conversations.createConversation();
      await runtime.conversations.sendChatMessage(
        conversation.id,
        text: '把考试范围记下来',
      );

      final entry = runtime.tables.entries.singleWhere(
        (item) => item.title == '考试范围',
      );
      expect(entry.type, TableContentType.note);
      expect(
        entry.tableId,
        runtime.tables.tables
            .singleWhere((table) => table.role == TableRole.inboxEvent)
            .id,
      );
      expect(entry.body, '第三章到第五章');
      final assistant = runtime.conversations.messagesFor(conversation.id).last;
      expect(assistant.status, ChatMessageStatus.complete);
      expect(assistant.content, contains('已记录考试范围'));
      expect(modelRequestCount, 2);
      expect(
        assistant.tableActions.single.status,
        TableChatActionStatus.applied,
      );
      expect(assistant.actions, isEmpty);
    },
  );

  test(
    'model table structure call waits, then confirms through the workspace',
    () async {
      var modelRequestCount = 0;
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(
          modelKey: 'table-structure-ai-test',
        ),
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            final payload =
                jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            modelRequestCount++;
            if (modelRequestCount > 1) {
              final messages = payload['messages'] as List;
              final toolReplies = messages
                  .whereType<Map>()
                  .where((message) => message['role'] == 'tool')
                  .toList();
              expect(toolReplies, isNotEmpty);
              expect(
                toolReplies.last['content'],
                contains(
                  modelRequestCount == 2
                      ? '"status":"waitingConfirmation"'
                      : '"status":"succeeded"',
                ),
              );
              return _stream({
                'choices': [
                  {
                    'delta': {'content': '已提出课程安排表，等待你确认。'},
                  },
                ],
              }, finish: 'stop');
            }
            return _stream({
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_propose_table',
                        'function': {
                          'name': 'table_propose',
                          'arguments': jsonEncode({
                            'operation': 'create',
                            'payload': {'title': '课程安排'},
                            'idempotency_key': 'propose-course-table',
                          }),
                        },
                      },
                    ],
                  },
                },
              ],
            }, finish: 'tool_calls');
          }),
        ),
      );
      addTearDown(runtime.shutdown);
      final conversation = await runtime.conversations.createConversation();
      await runtime.conversations.sendChatMessage(
        conversation.id,
        text: '新建课程安排表',
      );
      final assistant = runtime.conversations.messagesFor(conversation.id).last;
      final proposal = assistant.tableActions.single;
      expect(assistant.content, contains('等待你确认'));
      expect(modelRequestCount, 2);
      expect(proposal.status, TableChatActionStatus.pendingConfirmation);
      expect(
        runtime.tables.tables.any((table) => table.title == '课程安排'),
        isFalse,
      );

      await runtime.conversations.setAiPolicy(
        conversation.id,
        AiPolicy.forPreset(AiPolicyPreset.fullAccess),
      );
      final afterPolicyChange = runtime.conversations
          .messagesFor(conversation.id)
          .last
          .tableActions
          .single;
      expect(
        afterPolicyChange.status,
        TableChatActionStatus.pendingConfirmation,
      );
      expect(
        runtime.tables.tables.any((table) => table.title == '课程安排'),
        isFalse,
      );

      await runtime.conversations.confirmTableStructureAction(proposal.id);
      expect(
        runtime.tables.tables.any((table) => table.title == '课程安排'),
        isTrue,
      );
      expect(
        runtime.conversations
            .messagesFor(conversation.id)
            .last
            .tableActions
            .single
            .status,
        TableChatActionStatus.applied,
      );
    },
  );

  test('response-ready confirmation recovery preserves and resumes the original turn', () async {
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    final chats = MemoryConversationStore();
    final attachments = MemoryAttachmentStore();
    final tasks = MemoryAgentTaskStore();
    var modelRequestCount = 0;
    final thirdRequestStarted = Completer<void>();
    final modelClient = ModelClient(
      client: MockClient.streaming((request, body) async {
        final payload =
            jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
        modelRequestCount++;
        if (modelRequestCount == 1) {
          return _stream({
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_recover_confirmation',
                      'function': {
                        'name': 'table_propose',
                        'arguments': jsonEncode({
                          'operation': 'create',
                          'payload': {'title': '恢复后确认的表'},
                          'idempotency_key': 'recover-confirmation',
                        }),
                      },
                    },
                  ],
                },
              },
            ],
          }, finish: 'tool_calls');
        }
        final toolReply = (payload['messages'] as List)
            .whereType<Map>()
            .lastWhere((message) => message['role'] == 'tool');
        if (modelRequestCount == 2) {
          expect(toolReply['content'], contains('waitingConfirmation'));
        } else {
          expect(modelRequestCount, 3);
          expect(toolReply['content'], contains('succeeded'));
          if (!thirdRequestStarted.isCompleted) {
            thirdRequestStarted.complete();
          }
        }
        return _stream({
          'choices': [
            {
              'delta': {
                'content': modelRequestCount == 2
                    ? '表结构操作等待确认。'
                    : '已确认并继续完成原任务。',
              },
            },
          ],
        }, finish: 'stop');
      }),
    );
    Future<AppRuntime> boot() => AppRuntime.bootstrap(
      vaultOverride: vault,
      indexOverride: index,
      conversationStoreOverride: chats,
      attachmentStoreOverride: attachments,
      agentTaskStore: tasks,
      settingsOverride: FakeSettingsService(
        modelKey: 'response-ready-confirmation-recovery',
      ),
      modelClient: modelClient,
    );

    var runtime = await boot();
    final conversation = await runtime.conversations.createConversation(
      policy: AiPolicy.forPreset(AiPolicyPreset.standard),
    );
    await runtime.conversations.sendChatMessage(
      conversation.id,
      text: '新建一个恢复测试表',
    );
    final originalAssistant = runtime.conversations
        .messagesFor(conversation.id)
        .last;
    final proposal = originalAssistant.tableActions.single;
    expect(proposal.status, TableChatActionStatus.pendingConfirmation);
    expect(modelRequestCount, 2);
    final originalTask = tasks.checkpoint.turns.singleWhere(
      (turn) => turn.assistantMessageId == originalAssistant.id,
    );
    expect(originalTask.status, AgentTurnCheckpointStatus.waitingInput);
    final waitingBudget = tasks
        .checkpoint
        .runUsage[originalTask.effectiveRunId]!
        .usedActiveMillis;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      tasks.checkpoint.runUsage[originalTask.effectiveRunId]!.usedActiveMillis,
      waitingBudget,
      reason: 'waiting for user confirmation does not consume active time',
    );
    expect(
      modelRequestCount,
      2,
      reason: 'waiting for user confirmation dispatches no model request',
    );
    final responseReady = (await chats.findGeneration(originalAssistant.id))!;
    expect(
      responseReady.toolCalls.single['completed_receipt_json'],
      contains('waitingConfirmation'),
    );
    await runtime.shutdown();

    await chats.upsertMessage(
      originalAssistant.copyWith(status: ChatMessageStatus.streaming),
    );
    await chats.upsertGeneration(
      responseReady.copyWith(status: GenerationStatus.responseReady),
    );
    tasks.checkpoint = AgentTaskCheckpoint(
      usage: tasks.checkpoint.usage,
      runUsage: tasks.checkpoint.runUsage,
      activeRunId: tasks.checkpoint.activeRunId,
      turns: [originalTask.copyWith(status: AgentTurnCheckpointStatus.running)],
    );

    runtime = await boot();
    addTearDown(runtime.shutdown);
    expect(modelRequestCount, 2, reason: 'startup must not issue HTTP');
    expect(tasks.checkpoint.turns.single.taskId, originalTask.taskId);
    expect(
      tasks.checkpoint.turns.single.status,
      AgentTurnCheckpointStatus.waitingInput,
    );
    expect(
      runtime.conversations.tasksNeedingAction.single.awaitingInput,
      isTrue,
    );
    expect(runtime.conversations.hasPendingChatTurns, isTrue);

    await runtime.conversations.openConversation(conversation.id);
    final recoveredAssistant = runtime.conversations
        .messagesFor(conversation.id)
        .singleWhere((message) => message.id == originalAssistant.id);
    final recoveredProposal = recoveredAssistant.tableActions.single;
    expect(recoveredProposal.status, TableChatActionStatus.pendingConfirmation);
    await runtime.conversations.confirmTableStructureAction(
      recoveredProposal.id,
    );
    await thirdRequestStarted.future.timeout(const Duration(seconds: 5));
    expect(modelRequestCount, 3);
    await _waitForCondition(() => tasks.checkpoint.turns.isEmpty);
    expect(
      runtime.tables.tables.any((table) => table.title == '恢复后确认的表'),
      isTrue,
    );
    expect(
      runtime.conversations
          .messagesFor(conversation.id)
          .singleWhere((message) => message.id == originalAssistant.id)
          .status,
      ChatMessageStatus.complete,
    );
  });

  test('injected legacy result tool cannot bypass table mode', () async {
    var modelRequestCount = 0;
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      settingsOverride: FakeSettingsService(modelKey: 'legacy-tool-denial'),
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          final payload =
              jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
          modelRequestCount++;
          if (modelRequestCount > 1) {
            final messages = payload['messages'] as List;
            final toolReplies = messages
                .whereType<Map>()
                .where((message) => message['role'] == 'tool')
                .toList();
            expect(toolReplies, isNotEmpty);
            expect(toolReplies.last['content'], contains('旧成果工具已停用'));
            return _stream({
              'choices': [
                {
                  'delta': {'content': '旧成果工具已被拒绝。'},
                },
              ],
            }, finish: 'stop');
          }
          return _stream({
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_legacy_create',
                      'function': {
                        'name': 'create_result',
                        'arguments': jsonEncode({
                          'type': 'knowledge',
                          'title': '旧工具写入',
                          'body': '不得写入旧成果库',
                          'confidence': 1,
                          'sensitive': false,
                        }),
                      },
                    },
                  ],
                },
              },
            ],
          }, finish: 'tool_calls');
        }),
      ),
    );
    addTearDown(runtime.shutdown);
    final conversation = await runtime.conversations.createConversation();
    await runtime.conversations.sendChatMessage(
      conversation.id,
      text: '测试旧工具拒绝',
    );
    expect(runtime.results.documents, isEmpty);
    expect(runtime.tables.entries, isEmpty);
    expect(
      runtime.conversations.messagesFor(conversation.id).last.actions,
      isEmpty,
    );
    expect(
      runtime.conversations.messagesFor(conversation.id).last.tableActions,
      isEmpty,
    );
    expect(
      runtime.conversations.messagesFor(conversation.id).last.content,
      contains('旧成果工具已被拒绝'),
    );
    expect(modelRequestCount, 2);
  });
}

http.StreamedResponse _stream(Map<String, dynamic> event, {String? finish}) {
  final choices = (event['choices'] as List)
      .map((choice) => Map<String, dynamic>.from(choice as Map))
      .toList();
  if (finish != null) choices.first['finish_reason'] = finish;
  return http.StreamedResponse(
    Stream.fromIterable([
      utf8.encode('data: ${jsonEncode({...event, 'choices': choices})}\n\n'),
      utf8.encode('data: [DONE]\n\n'),
    ]),
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}

Future<void> _waitForCondition(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition was not reached');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _GateAppliedInboxActionStore extends MemoryConversationStore {
  final appliedInboxActionSaveAttempted = Completer<void>();
  final _releaseFirstAppliedActionSave = Completer<void>();
  bool _blockedFirstAppliedActionSave = false;

  void releaseFirstAppliedActionSave() {
    if (!_releaseFirstAppliedActionSave.isCompleted) {
      _releaseFirstAppliedActionSave.complete();
    }
  }

  @override
  Future<void> upsertMessage(ChatMessage message) async {
    final isAppliedInboxAction = message.tableActions.any(
      (action) =>
          action.operation == 'table.assign_inbox_target' &&
          action.status == TableChatActionStatus.applied,
    );
    if (isAppliedInboxAction && !_blockedFirstAppliedActionSave) {
      _blockedFirstAppliedActionSave = true;
      if (!appliedInboxActionSaveAttempted.isCompleted) {
        appliedInboxActionSaveAttempted.complete();
      }
      await _releaseFirstAppliedActionSave.future;
    }
    await super.upsertMessage(message);
  }
}
