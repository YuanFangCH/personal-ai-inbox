import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/core/agent_usage.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/ai_policy.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/data/table_repository.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';
import 'package:personal_ai_inbox/modules/tables/table_library.dart';
import 'package:personal_ai_inbox/services/chat_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'test_support.dart';

void main() {
  test(
    'completed ChatService answer does not wait for HTTP body cancellation',
    () async {
      final fixture = await _AgentFixture.create();
      final cancellationStarted = Completer<void>();
      final cancellationGate = Completer<void>();
      final cancellationFinished = Completer<void>();
      final body = StreamController<List<int>>(
        onCancel: () async {
          if (!cancellationStarted.isCompleted) cancellationStarted.complete();
          await cancellationGate.future;
          if (!cancellationFinished.isCompleted) {
            cancellationFinished.complete();
          }
        },
      );
      final service = ChatService(
        settings: FakeSettingsService(modelKey: 'test-key'),
        repository: fixture.chats,
        results: fixture.results,
        tables: fixture.tables,
        modelClient: ModelClient(
          client: MockClient.streaming((request, requestBody) async {
            await requestBody.bytesToString();
            return http.StreamedResponse(body.stream, 200);
          }),
        ),
      );
      addTearDown(() => fixture.close(service));
      final now = DateTime(2026, 11, 5);
      await fixture.chats.saveMessage(
        ChatMessage(
          id: 'msg_cancel_barrier_followup',
          conversationId: fixture.conversationId,
          role: ChatRole.user,
          content: '继续处理剩余内容',
          status: ChatMessageStatus.complete,
          createdAt: now,
          updatedAt: now,
        ),
      );

      try {
        final answerFuture = (await service.streamReply(
          conversationId: fixture.conversationId,
          assistantMessageId: 'msg_cancel_barrier_assistant',
        )).toList();
        body.add(
          utf8.encode(
            'data: {"choices":[{"delta":{"content":"继续问题已完成。"},"finish_reason":"stop"}]}\n\n',
          ),
        );

        await cancellationStarted.future.timeout(const Duration(seconds: 3));
        expect(cancellationFinished.isCompleted, isFalse);
        final answer = await answerFuture.timeout(const Duration(seconds: 3));
        expect(answer.map((delta) => delta.content).join(), '继续问题已完成。');
        expect(answer.last.termination, ChatStreamTermination.completed);
        expect(cancellationFinished.isCompleted, isFalse);
      } finally {
        if (!cancellationGate.isCompleted) cancellationGate.complete();
        if (cancellationStarted.isCompleted) {
          await cancellationFinished.future.timeout(const Duration(seconds: 3));
        }
        await body.close();
      }
    },
  );

  test('global knowledge instructions follow the effective policy', () async {
    final fixture = await _AgentFixture.create();
    final requests = <Map<String, dynamic>>[];
    final service = ChatService(
      settings: FakeSettingsService(modelKey: 'test-key'),
      repository: fixture.chats,
      results: fixture.results,
      tables: fixture.tables,
      modelClient: ModelClient(
        client: MockClient.streaming((_, body) async {
          requests.add(
            jsonDecode(await body.bytesToString()) as Map<String, dynamic>,
          );
          return _textResponse('收到。');
        }),
      ),
    );
    addTearDown(() => fixture.close(service));

    Future<Map<String, dynamic>> sendWith(AiPolicy policy) async {
      await fixture.chats.setAiPolicy(fixture.conversationId, policy);
      await (await service.streamReply(conversationId: fixture.conversationId))
          .toList();
      return requests.last;
    }

    final standard = await sendWith(
      AiPolicy.forPreset(AiPolicyPreset.standard),
    );
    final fullAccess = await sendWith(
      AiPolicy.forPreset(AiPolicyPreset.fullAccess),
    );

    String systemPrompt(Map<String, dynamic> request) =>
        (request['messages'] as List)
            .cast<Map>()
            .firstWhere((message) => message['role'] == 'system')['content']
            .toString();
    Map<String, dynamic> knowledgeTool(Map<String, dynamic> request) =>
        (request['tools'] as List)
            .cast<Map>()
            .map((tool) => Map<String, dynamic>.from(tool))
            .firstWhere(
              (tool) =>
                  (tool['function'] as Map)['name'] ==
                  'propose_global_knowledge_change',
            );

    expect(systemPrompt(standard), contains('逐项确认'));
    expect(systemPrompt(standard), isNot(contains('按当前策略直接生效')));
    expect(
      knowledgeTool(standard)['function']['description'],
      contains('必须由用户逐项确认'),
    );
    expect(systemPrompt(fullAccess), contains('按当前策略直接执行'));
    expect(systemPrompt(fullAccess), contains('向用户报告结果'));
    expect(systemPrompt(fullAccess), contains('设置页完全体模式启动时会重新校验并自动处理'));
    expect(systemPrompt(fullAccess), isNot(contains('全局知识仅能提议')));
    expect(
      knowledgeTool(fullAccess)['function']['description'],
      contains('按当前策略直接执行'),
    );
  });

  test(
    'table structure instructions follow each effective action policy',
    () async {
      final fixture = await _AgentFixture.create();
      final requests = <Map<String, dynamic>>[];
      final service = ChatService(
        settings: FakeSettingsService(modelKey: 'test-key'),
        repository: fixture.chats,
        results: fixture.results,
        tables: fixture.tables,
        modelClient: ModelClient(
          client: MockClient.streaming((_, body) async {
            requests.add(
              jsonDecode(await body.bytesToString()) as Map<String, dynamic>,
            );
            return _textResponse('收到。');
          }),
        ),
      );
      addTearDown(() => fixture.close(service));

      Future<Map<String, dynamic>> sendWith(AiPolicy policy) async {
        await fixture.chats.setAiPolicy(fixture.conversationId, policy);
        await (await service.streamReply(
          conversationId: fixture.conversationId,
        )).toList();
        return requests.last;
      }

      String systemPrompt(Map<String, dynamic> request) =>
          (request['messages'] as List)
              .cast<Map>()
              .firstWhere((message) => message['role'] == 'system')['content']
              .toString();
      Map<String, dynamic>? tableTool(Map<String, dynamic> request) =>
          (request['tools'] as List)
              .cast<Map>()
              .map((tool) => Map<String, dynamic>.from(tool))
              .where(
                (tool) => (tool['function'] as Map)['name'] == 'table_propose',
              )
              .firstOrNull;

      final standard = await sendWith(
        AiPolicy.forPreset(AiPolicyPreset.standard),
      );
      final fullAccess = await sendWith(
        AiPolicy.forPreset(AiPolicyPreset.fullAccess),
      );
      final customMixed = await sendWith(
        AiPolicy.forPreset(AiPolicyPreset.fullAccess)
            .withDecision(
              AiPermissionAction.tableCreate,
              AiPolicyDecision.allow,
            )
            .withDecision(AiPermissionAction.tableUpdate, AiPolicyDecision.ask)
            .withDecision(AiPermissionAction.tableDelete, AiPolicyDecision.deny)
            .withDecision(AiPermissionAction.fieldAdjust, AiPolicyDecision.deny)
            .withDecision(
              AiPermissionAction.inboxTargetAdjust,
              AiPolicyDecision.deny,
            ),
      );
      final customDenied = await sendWith(
        AiPolicy.custom(
          tableScope: AiResourceScope.selected([fixture.table.id]),
          decisions: {
            for (final action in AiPermissionAction.values)
              action: AiPolicyDecision.deny,
            AiPermissionAction.tableRead: AiPolicyDecision.allow,
            AiPermissionAction.contentRead: AiPolicyDecision.allow,
          },
        ),
      );

      final standardTool = tableTool(standard)!;
      expect(systemPrompt(standard), contains('建表：只能提议'));
      expect(systemPrompt(standard), contains('必须由用户在当前对话卡片确认'));
      expect(standardTool['function']['description'], contains('建表：只能提议'));

      final fullAccessTool = tableTool(fullAccess)!;
      expect(systemPrompt(fullAccess), contains('建表：按当前策略允许提交'));
      expect(systemPrompt(fullAccess), contains('根据本地回执报告结果'));
      expect(systemPrompt(fullAccess), contains('本地执行器校验目标表范围'));
      expect(
        fullAccessTool['function']['description'],
        contains('建表：按当前策略允许提交'),
      );

      final customTool = tableTool(customMixed)!;
      final operationEnum =
          ((((customTool['function'] as Map)['parameters'] as Map)['properties']
                      as Map)['operation']
                  as Map)['enum']
              as List;
      expect(operationEnum, contains('create'));
      expect(operationEnum, contains('rename'));
      expect(operationEnum, isNot(contains('delete')));
      expect(operationEnum, isNot(contains('upsert_field')));
      expect(operationEnum, isNot(contains('delete_field')));
      expect(operationEnum, isNot(contains('assign_inbox_target')));
      expect(systemPrompt(customMixed), contains('建表：按当前策略允许提交'));
      expect(systemPrompt(customMixed), contains('改名表：只能提议'));
      expect(systemPrompt(customMixed), contains('删除表：禁止请求或执行'));
      expect(systemPrompt(customMixed), contains('字段调整：禁止请求或执行'));
      expect(customTool['function']['description'], contains('删除表：禁止请求或执行'));

      expect(tableTool(customDenied), isNull);
      expect(systemPrompt(customDenied), contains('建表：禁止请求或执行'));
      expect(systemPrompt(customDenied), isNot(contains('建表：只能提议')));
    },
  );

  test(
    'repeated tool calls get an advisory reminder without pausing',
    () async {
      final fixture = await _AgentFixture.create();
      var requests = 0;
      final service = ChatService(
        settings: FakeSettingsService(modelKey: 'test-key'),
        repository: fixture.chats,
        results: fixture.results,
        tables: fixture.tables,
        modelClient: ModelClient(
          client: MockClient.streaming((_, body) async {
            final payload = jsonDecode(await body.bytesToString()) as Map;
            requests++;
            if (requests == 4) {
              expect(jsonEncode(payload['messages']), contains('连续 3 次'));
              return _textResponse('已收到提醒并完成');
            }
            return _toolCallResponse(
              id: 'repeat_$requests',
              name: 'table_list',
              arguments: {},
            );
          }),
        ),
      );
      addTearDown(() => fixture.close(service));
      final deltas = await (await service.streamReply(
        conversationId: fixture.conversationId,
      )).toList();
      expect(requests, 4);
      expect(deltas.map((d) => d.content).join(), contains('已收到提醒并完成'));
      expect(deltas.last.termination, ChatStreamTermination.completed);
    },
  );

  test('empty response recovery is bounded to one extra request', () async {
    final fixture = await _AgentFixture.create();
    var requests = 0;
    final service = ChatService(
      settings: FakeSettingsService(modelKey: 'test-key'),
      repository: fixture.chats,
      results: fixture.results,
      tables: fixture.tables,
      modelClient: ModelClient(
        client: MockClient.streaming((_, body) async {
          await body.bytesToString();
          requests++;
          return _textResponse('');
        }),
      ),
    );
    addTearDown(() => fixture.close(service));
    final deltas = await (await service.streamReply(
      conversationId: fixture.conversationId,
    )).toList();
    expect(requests, 2);
    expect(deltas.map((d) => d.content).join(), contains('连续返回空答复'));
    expect(deltas.last.termination, ChatStreamTermination.empty);
  });
  test('cancel during intent persistence prevents dispatch', () async {
    final fixture = await _AgentFixture.create();
    var cancelled = false;
    var writes = 0;
    final service = ChatService(
      settings: FakeSettingsService(modelKey: 'test-key'),
      repository: fixture.chats,
      results: fixture.results,
      tables: fixture.tables,
      writeToolExecutor: (_) async {
        writes++;
        return ChatWriteToolReceipt.succeeded(
          operationId: 'bad',
          message: '不应执行',
        );
      },
      modelClient: ModelClient(
        client: MockClient.streaming((_, body) async {
          await body.bytesToString();
          fail('must not send another model request after cancellation');
        }),
      ),
    );
    addTearDown(() => fixture.close(service));
    final deltas = await (await service.streamReply(
      conversationId: fixture.conversationId,
      isCancelled: () => cancelled,
      persistToolTranscript: (_) async {
        cancelled = true;
      },
      resumeToolTranscript: [
        {
          'role': 'assistant',
          'tool_calls': [
            {
              'id': 'pending',
              'function': {'name': 'content_create', 'arguments': '{}'},
            },
          ],
        },
      ],
    )).toList();
    expect(writes, 0);
    expect(deltas.last.termination, ChatStreamTermination.cancelled);
  });
  test(
    'recovers complete pending intent before another model request',
    () async {
      final fixture = await _AgentFixture.create();
      var persistedIntent = false;
      var writes = 0;
      var requests = 0;
      final service = ChatService(
        settings: FakeSettingsService(modelKey: 'test-key'),
        repository: fixture.chats,
        results: fixture.results,
        tables: fixture.tables,
        writeToolExecutor: (call) async {
          expect(persistedIntent, isTrue);
          expect(call.turnId, 'original_assistant');
          expect(call.index, 1);
          writes++;
          return ChatWriteToolReceipt.succeeded(
            operationId: 'original_op',
            message: '已结算',
          );
        },
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            requests++;
            expect(writes, 1);
            final payload = jsonDecode(await body.bytesToString()) as Map;
            final tools = (payload['messages'] as List).where(
              (m) => m['role'] == 'tool',
            );
            expect(tools, hasLength(2));
            return _textResponse('恢复完成');
          }),
        ),
      );
      addTearDown(() => fixture.close(service));
      final deltas = await (await service.streamReply(
        conversationId: fixture.conversationId,
        assistantMessageId: 'original_assistant',
        resumeToolTranscript: [
          {
            'role': 'assistant',
            'tool_calls': [
              {
                'id': 'read',
                'type': 'function',
                'function': {'name': 'table_list', 'arguments': '{}'},
              },
            ],
          },
          {
            'role': 'tool',
            'tool_call_id': 'read',
            'content': '{"status":"ok"}',
          },
          {
            'role': 'assistant',
            'tool_calls': [
              {
                'id': 'write',
                'type': 'function',
                'function': {
                  'name': 'content_create',
                  'arguments': jsonEncode({
                    'table_id': fixture.table.id,
                    'type': 'note',
                    'title': '恢复',
                  }),
                },
              },
            ],
          },
        ],
        persistToolTranscript: (transcript) async {
          persistedIntent = true;
        },
      )).toList();
      expect(requests, 1);
      expect(writes, 1);
      expect(deltas.last.termination, ChatStreamTermination.completed);
    },
  );
  test('completes 100 consecutive ordinary conversation turns', () async {
    final fixture = await _AgentFixture.create();
    var requests = 0;
    final service = ChatService(
      settings: FakeSettingsService(modelKey: 'test-key'),
      repository: fixture.chats,
      results: fixture.results,
      tables: fixture.tables,
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          final payload = jsonDecode(await body.bytesToString()) as Map;
          final messages = (payload['messages'] as List).cast<Map>();
          requests++;
          expect(messages.last['content'], '第 $requests 轮普通对话');
          if (requests > 1) {
            expect(
              messages.any(
                (message) =>
                    message['role'] == 'assistant' &&
                    message['content'] == '第 ${requests - 1} 轮回复',
              ),
              isTrue,
            );
          }
          return _textResponse('第 $requests 轮回复');
        }),
      ),
    );
    try {
      for (var turn = 1; turn <= 100; turn++) {
        final now = DateTime(2026, 11, 4).add(Duration(minutes: turn));
        await fixture.chats.saveMessage(
          ChatMessage(
            id: 'stress_user_$turn',
            conversationId: fixture.conversationId,
            role: ChatRole.user,
            content: '第 $turn 轮普通对话',
            status: ChatMessageStatus.complete,
            createdAt: now,
            updatedAt: now,
          ),
        );
        final deltas = await (await service.streamReply(
          conversationId: fixture.conversationId,
        )).toList();
        final answer = deltas.map((delta) => delta.content).join();
        expect(answer, '第 $turn 轮回复');
        expect(deltas.last.termination, ChatStreamTermination.completed);
        await fixture.chats.saveMessage(
          ChatMessage(
            id: 'stress_assistant_$turn',
            conversationId: fixture.conversationId,
            role: ChatRole.assistant,
            content: answer,
            status: ChatMessageStatus.complete,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      expect(requests, 100);
    } finally {
      await fixture.close(service);
    }
  });

  test(
    'full access exposes complete table tools without revision friction',
    () async {
      final fixture = await _AgentFixture.create();
      await fixture.chats.setAiPolicy(
        fixture.conversationId,
        AiPolicy.forPreset(AiPolicyPreset.fullAccess),
      );
      Map<String, dynamic>? request;
      final service = ChatService(
        settings: FakeSettingsService(modelKey: 'test-key'),
        repository: fixture.chats,
        results: fixture.results,
        tables: fixture.tables,
        modelClient: ModelClient(
          client: MockClient.streaming((_, body) async {
            request =
                jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            return _textResponse('工具面已核对');
          }),
        ),
      );

      await (await service.streamReply(conversationId: fixture.conversationId))
          .toList();

      final tools = (request!['tools'] as List).cast<Map>();
      final byName = {
        for (final tool in tools)
          (tool['function'] as Map)['name']: tool['function'] as Map,
      };
      expect(byName, contains('recovery_list'));
      expect(byName, contains('recovery_preview'));
      expect(byName, contains('recovery_restore'));
      expect(byName, contains('inbox_targets_read'));
      final update = byName['content_update']!;
      final required = ((update['parameters'] as Map)['required'] as List)
          .cast<String>();
      expect(required, isNot(contains('if_revision')));
      expect(required, isNot(contains('idempotency_key')));
      await fixture.close(service);
    },
  );

  test(
    'continues read tool rounds until the model returns a final answer',
    () async {
      final fixture = await _AgentFixture.create();
      final requests = <Map<String, dynamic>>[];
      final service = ChatService(
        settings: FakeSettingsService(modelKey: 'test-key'),
        repository: fixture.chats,
        results: fixture.results,
        tables: fixture.tables,
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            final payload =
                jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            requests.add(payload);
            if (requests.length <= 3) {
              return _toolCallResponse(
                id: 'call_list_${requests.length}',
                name: 'table_list',
                arguments: {'offset': requests.length - 1, 'limit': 1},
              );
            }
            return _textResponse('已经完成三轮读取，表目录检查结束。');
          }),
        ),
      );

      final deltas = await (await service.streamReply(
        conversationId: fixture.conversationId,
      )).toList();

      expect(requests, hasLength(4));
      expect(
        (requests.last['messages'] as List).cast<Map>().where(
          (message) => message['role'] == 'tool',
        ),
        hasLength(3),
      );
      expect(deltas.map((delta) => delta.content).join(), '已经完成三轮读取，表目录检查结束。');
      expect(deltas.last.termination, ChatStreamTermination.completed);
      await fixture.close(service);
    },
  );

  test(
    're-resolves policy before tool dispatch and next model request',
    () async {
      final fixture = await _AgentFixture.create();
      final conversation = (await fixture.chats.findConversation(
        fixture.conversationId,
      ))!;
      await fixture.chats.setAiPolicy(
        conversation.id,
        AiPolicy.forPreset(AiPolicyPreset.fullAccess),
      );
      final requests = <Map<String, dynamic>>[];
      final service = ChatService(
        settings: FakeSettingsService(modelKey: 'test-key'),
        repository: fixture.chats,
        results: fixture.results,
        tables: fixture.tables,
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            final payload =
                jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            requests.add(payload);
            if (requests.length == 1) {
              await fixture.chats.setAiPolicy(
                conversation.id,
                AiPolicy.custom(decisions: const {}),
              );
              return _toolCallResponse(
                id: 'call_revoked_dispatch',
                name: 'table_list',
                arguments: const {'limit': 10},
              );
            }
            return _textResponse('读取权限已撤销，未继续读取。');
          }),
        ),
      );

      final deltas = await (await service.streamReply(
        conversationId: conversation.id,
      )).toList();

      expect(
        (requests.first['tools'] as List).cast<Map>().map(
          (tool) => (tool['function'] as Map)['name'],
        ),
        contains('table_list'),
      );
      final toolMessage = (requests.last['messages'] as List)
          .cast<Map>()
          .singleWhere((message) => message['role'] == 'tool');
      final denied =
          jsonDecode(toolMessage['content'] as String) as Map<String, dynamic>;
      expect(denied['status'], 'denied');
      expect(denied['coverage'], isA<Map>());
      expect(
        (requests.last['tools'] as List?) ?? const [],
        isEmpty,
        reason: 'the next model request must not retain revoked tools',
      );
      expect(deltas.last.termination, ChatStreamTermination.completed);
      await fixture.close(service);
    },
  );

  test(
    'injected write executor receives stable call data and real receipt',
    () async {
      final fixture = await _AgentFixture.create();
      final requests = <Map<String, dynamic>>[];
      ChatWriteToolCall? receivedCall;
      await fixture.chats.saveMessage(
        ChatMessage(
          id: 'msg_agent_assistant',
          conversationId: fixture.conversationId,
          role: ChatRole.assistant,
          content: '',
          status: ChatMessageStatus.streaming,
          createdAt: DateTime(2026, 11, 3, 10, 1),
          updatedAt: DateTime(2026, 11, 3, 10, 1),
        ),
      );
      final service = ChatService(
        settings: FakeSettingsService(modelKey: 'test-key'),
        repository: fixture.chats,
        results: fixture.results,
        tables: fixture.tables,
        writeToolExecutor: (call) async {
          receivedCall = call;
          return ChatWriteToolReceipt.succeeded(
            operationId: 'op_create_1',
            message: '已创建并读回。',
            data: {'entry_id': 'entry_created'},
          );
        },
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            final payload =
                jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            requests.add(payload);
            if (requests.length == 1) {
              return _toolCallResponse(
                id: 'call_create_1',
                name: 'content_create',
                arguments: {
                  'table_id': fixture.table.id,
                  'type': 'note',
                  'title': '课程安排',
                  'body': '周五提交作业',
                  'idempotency_key': 'intent_1',
                },
              );
            }
            return _textResponse('已经写入并核对。');
          }),
        ),
      );

      final deltas = await (await service.streamReply(
        conversationId: fixture.conversationId,
      )).toList();

      expect(receivedCall, isNotNull);
      expect(receivedCall!.turnId, 'msg_agent_assistant');
      expect(receivedCall!.conversationId, fixture.conversationId);
      expect(receivedCall!.index, 0);
      expect(receivedCall!.name, 'content.create');
      expect(receivedCall!.wireName, 'content_create');
      expect(receivedCall!.arguments['idempotency_key'], 'intent_1');
      expect(receivedCall!.rawArguments, contains('周五提交作业'));
      final toolMessage = (requests.last['messages'] as List)
          .cast<Map>()
          .singleWhere((message) => message['role'] == 'tool');
      expect(toolMessage['content'], contains('"status":"succeeded"'));
      expect(toolMessage['content'], contains('op_create_1'));
      expect(toolMessage['content'], contains('entry_created'));
      final writeDelta = deltas.singleWhere(
        (delta) => delta.toolCallIndex != null,
      );
      expect(writeDelta.toolCallIndex, 0);
      expect(writeDelta.toolCallId, 'call_create_1');
      expect(writeDelta.toolCallName, 'content.create');
      expect(writeDelta.toolArguments, receivedCall!.rawArguments);
      expect(deltas.last.termination, ChatStreamTermination.completed);
      await fixture.close(service);
    },
  );

  test(
    'failed write receipt is returned without fabricating success',
    () async {
      final fixture = await _AgentFixture.create();
      final requests = <Map<String, dynamic>>[];
      final service = ChatService(
        settings: FakeSettingsService(modelKey: 'test-key'),
        repository: fixture.chats,
        results: fixture.results,
        tables: fixture.tables,
        writeToolExecutor: (call) async => ChatWriteToolReceipt.failed(
          code: 'stale',
          message: '目标版本已经变化，未写入。',
        ),
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            final payload =
                jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            requests.add(payload);
            if (requests.length == 1) {
              return _toolCallResponse(
                id: 'call_create_failed',
                name: 'content_create',
                arguments: {
                  'table_id': fixture.table.id,
                  'type': 'note',
                  'title': '课程安排',
                  'body': '周五提交作业',
                  'idempotency_key': 'intent_failed',
                },
              );
            }
            return _textResponse('没有写入，目标版本已经变化。');
          }),
        ),
      );

      final deltas = await (await service.streamReply(
        conversationId: fixture.conversationId,
      )).toList();

      final toolMessage = (requests.last['messages'] as List)
          .cast<Map>()
          .where((message) => message['role'] == 'tool')
          .last;
      expect(toolMessage['content'], contains('"status":"failed"'));
      expect(toolMessage['content'], contains('目标版本已经变化'));
      expect(toolMessage['content'], isNot(contains('"status":"succeeded"')));
      expect(deltas.map((delta) => delta.content).join(), '没有写入，目标版本已经变化。');
      expect(deltas.last.termination, ChatStreamTermination.completed);
      await fixture.close(service);
    },
  );

  test(
    'content_verify checks an explicit target and reports coverage',
    () async {
      final fixture = await _AgentFixture.create();
      final requests = <Map<String, dynamic>>[];
      final service = ChatService(
        settings: FakeSettingsService(modelKey: 'test-key'),
        repository: fixture.chats,
        results: fixture.results,
        tables: fixture.tables,
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            final payload =
                jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            requests.add(payload);
            if (requests.length == 1) {
              return _toolCallResponse(
                id: 'call_verify_target',
                name: 'content_verify',
                arguments: {
                  'target_kind': 'table',
                  'target_id': fixture.table.id,
                  'expected_revision': fixture.table.revision,
                  'expected_fields': {'title': fixture.table.title},
                },
              );
            }
            return _textResponse('目标表和版本已核对。');
          }),
        ),
      );

      final deltas = await (await service.streamReply(
        conversationId: fixture.conversationId,
      )).toList();

      final toolMessage = (requests.last['messages'] as List)
          .cast<Map>()
          .singleWhere((message) => message['role'] == 'tool');
      final result =
          jsonDecode(toolMessage['content'] as String) as Map<String, dynamic>;
      expect(result['status'], 'ok');
      expect((result['data'] as Map)['verified'], isTrue);
      expect((result['coverage'] as Map)['complete'], isTrue);
      expect(deltas.map((delta) => delta.content).join(), '目标表和版本已核对。');
      expect(deltas.last.termination, ChatStreamTermination.completed);
      await fixture.close(service);
    },
  );

  test(
    'content_verify resolves a real write receipt to the persisted target',
    () async {
      final fixture = await _AgentFixture.create();
      final requests = <Map<String, dynamic>>[];
      late TableEntryDocument created;
      final service = ChatService(
        settings: FakeSettingsService(modelKey: 'test-key'),
        repository: fixture.chats,
        results: fixture.results,
        tables: fixture.tables,
        writeToolExecutor: (call) async {
          created = await fixture.tables.createEntry(
            TableEntryDocument(
              id: 'nt_verify_receipt',
              type: TableContentType.note,
              tableId: fixture.table.id,
              title: '回执核对',
              revision: 1,
              createdAt: DateTime(2026, 11, 3),
              updatedAt: DateTime(2026, 11, 3),
              body: '真实写入内容',
            ),
          );
          return ChatWriteToolReceipt.succeeded(
            operationId: 'op_verify_receipt',
            message: '已创建。',
            data: {'entry_id': created.id, 'new_revision': created.revision},
          );
        },
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            final payload =
                jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            requests.add(payload);
            if (requests.length == 1) {
              return _toolCallResponse(
                id: 'call_create_for_verify',
                name: 'content_create',
                arguments: {
                  'table_id': fixture.table.id,
                  'type': 'note',
                  'title': '回执核对',
                  'body': '真实写入内容',
                  'idempotency_key': 'verify_receipt_create',
                },
              );
            }
            if (requests.length == 2) {
              return _toolCallResponse(
                id: 'call_verify_receipt',
                name: 'content_verify',
                arguments: const {'operation_id': 'op_verify_receipt'},
              );
            }
            return _textResponse('写入回执和当前内容均已核对。');
          }),
        ),
      );

      final deltas = await (await service.streamReply(
        conversationId: fixture.conversationId,
      )).toList();

      final toolMessages = (requests.last['messages'] as List)
          .cast<Map>()
          .where((message) => message['role'] == 'tool')
          .toList(growable: false);
      final verification = jsonDecode(
        toolMessages.last['content'] as String,
      ) as Map<String, dynamic>;
      expect(
        (verification['data'] as Map)['operation_id'],
        'op_verify_receipt',
      );
      expect((verification['data'] as Map)['verified'], isTrue);
      expect((verification['data'] as Map)['target_id'], created.id);
      expect((verification['coverage'] as Map)['complete'], isTrue);
      expect(deltas.last.termination, ChatStreamTermination.completed);
      await fixture.close(service);
    },
  );

  test('unknown receipt is not treated as a successful verification', () async {
    final fixture = await _AgentFixture.create();
    final requests = <Map<String, dynamic>>[];
    final service = ChatService(
      settings: FakeSettingsService(modelKey: 'test-key'),
      repository: fixture.chats,
      results: fixture.results,
      tables: fixture.tables,
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          final payload =
              jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
          requests.add(payload);
          if (requests.length == 1) {
            return _toolCallResponse(
              id: 'call_unknown_receipt',
              name: 'content_verify',
              arguments: {
                'operation_id': 'op_does_not_exist',
                'target_kind': 'table',
                'target_id': fixture.table.id,
              },
            );
          }
          return _textResponse('找不到该回执，不能确认写入成功。');
        }),
      ),
    );

    final deltas = await (await service.streamReply(
      conversationId: fixture.conversationId,
    )).toList();

    final toolMessage = (requests.last['messages'] as List)
        .cast<Map>()
        .singleWhere((message) => message['role'] == 'tool');
    final result =
        jsonDecode(toolMessage['content'] as String) as Map<String, dynamic>;
    expect(result['status'], 'unresolved');
    expect((result['coverage'] as Map)['complete'], isFalse);
    expect(jsonEncode(result), isNot(contains('"verified":true')));
    expect(deltas.last.termination, ChatStreamTermination.completed);
    await fixture.close(service);
  });

  test(
    'content_verify resolves a persisted conversation action receipt',
    () async {
      final fixture = await _AgentFixture.create();
      final created = await fixture.tables.createEntry(
        TableEntryDocument(
          id: 'nt_persisted_verify',
          type: TableContentType.note,
          tableId: fixture.table.id,
          title: '持久化回执',
          revision: 1,
          createdAt: DateTime(2026, 11, 3),
          updatedAt: DateTime(2026, 11, 3),
          body: '动作已持久化',
        ),
      );
      await fixture.chats.saveMessage(
        ChatMessage(
          id: 'msg_persisted_action',
          conversationId: fixture.conversationId,
          role: ChatRole.assistant,
          content: '已写入。',
          status: ChatMessageStatus.complete,
          createdAt: DateTime(2026, 11, 3, 10, 2),
          updatedAt: DateTime(2026, 11, 3, 10, 2),
          tableActions: [
            TableChatAction(
              id: 'op_persisted_action',
              operation: 'content.create',
              title: '持久化回执',
              status: TableChatActionStatus.applied,
              createdAt: DateTime(2026, 11, 3, 10, 2),
              tableId: fixture.table.id,
              entryId: created.id,
              expectedRevision: created.revision,
            ),
          ],
        ),
      );
      final requests = <Map<String, dynamic>>[];
      final service = ChatService(
        settings: FakeSettingsService(modelKey: 'test-key'),
        repository: fixture.chats,
        results: fixture.results,
        tables: fixture.tables,
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            final payload =
                jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            requests.add(payload);
            if (requests.length == 1) {
              return _toolCallResponse(
                id: 'call_persisted_verify',
                name: 'content_verify',
                arguments: const {'operation_id': 'op_persisted_action'},
              );
            }
            return _textResponse('持久化回执已核对。');
          }),
        ),
      );

      await (await service.streamReply(conversationId: fixture.conversationId))
          .toList();

      final toolMessage = (requests.last['messages'] as List)
          .cast<Map>()
          .singleWhere((message) => message['role'] == 'tool');
      final result =
          jsonDecode(toolMessage['content'] as String) as Map<String, dynamic>;
      expect(result['status'], 'ok');
      expect((result['data'] as Map)['target_id'], created.id);
      expect((result['data'] as Map)['operation_status'], 'succeeded');
      await fixture.close(service);
    },
  );

  test('failed receipt verification remains visibly unsuccessful', () async {
    final fixture = await _AgentFixture.create();
    final requests = <Map<String, dynamic>>[];
    final service = ChatService(
      settings: FakeSettingsService(modelKey: 'test-key'),
      repository: fixture.chats,
      results: fixture.results,
      tables: fixture.tables,
      writeToolExecutor: (call) async => ChatWriteToolReceipt.failed(
        code: 'write_failed',
        operationId: 'op_failed_verify',
        message: '写入失败。',
        data: {
          'table_id': fixture.table.id,
          'new_revision': fixture.table.revision,
        },
      ),
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          final payload =
              jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
          requests.add(payload);
          if (requests.length == 1) {
            return _toolCallResponse(
              id: 'call_failed_create',
              name: 'content_create',
              arguments: {
                'table_id': fixture.table.id,
                'type': 'note',
                'title': '不会成功',
                'body': '',
                'idempotency_key': 'failed_verify_create',
              },
            );
          }
          if (requests.length == 2) {
            return _toolCallResponse(
              id: 'call_failed_verify',
              name: 'content_verify',
              arguments: const {'operation_id': 'op_failed_verify'},
            );
          }
          return _textResponse('写入失败，未声称操作成功。');
        }),
      ),
    );

    final deltas = await (await service.streamReply(
      conversationId: fixture.conversationId,
    )).toList();

    final toolMessages = (requests.last['messages'] as List)
        .cast<Map>()
        .where((message) => message['role'] == 'tool')
        .toList(growable: false);
    final verification = jsonDecode(
      toolMessages.last['content'] as String,
    ) as Map<String, dynamic>;
    expect(verification['status'], 'failed');
    expect((verification['data'] as Map)['verified'], isFalse);
    expect((verification['data'] as Map)['operation_status'], 'failed');
    expect(jsonEncode(verification), isNot(contains('"verified":true')));
    expect(deltas.last.termination, ChatStreamTermination.completed);
    await fixture.close(service);
  });

  test('usage meter records requests without gating the network', () async {
    final fixture = await _AgentFixture.create();
    var networkRequests = 0;
    final usage = AgentUsageMeter();
    final service = ChatService(
      settings: FakeSettingsService(modelKey: 'test-key'),
      repository: fixture.chats,
      results: fixture.results,
      tables: fixture.tables,
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          networkRequests++;
          return _textResponse('无预算请求已完成。');
        }),
      ),
    );

    final deltas = await (await service.streamReply(
      conversationId: fixture.conversationId,
      usage: usage,
    )).toList();

    expect(networkRequests, 1);
    expect(usage.requestCount, 1);
    expect(deltas.map((delta) => delta.content).join(), '无预算请求已完成。');
    expect(deltas.last.termination, ChatStreamTermination.completed);
    await fixture.close(service);
  });

  test(
    'request compaction preserves user facts, identities and receipts',
    () async {
      final fixture = await _AgentFixture.create();
      await fixture.chats.saveMessage(
        ChatMessage(
          id: 'msg_agent_supplement',
          conversationId: fixture.conversationId,
          role: ChatRole.user,
          content: '补充要求：课程是信号与系统，考试日期是 2026-12-18。',
          status: ChatMessageStatus.complete,
          createdAt: DateTime(2026, 11, 3, 10, 1),
          updatedAt: DateTime(2026, 11, 3, 10, 1),
        ),
      );
      final requests = <Map<String, dynamic>>[];
      final service = ChatService(
        settings: FakeSettingsService(modelKey: 'test-key'),
        repository: fixture.chats,
        results: fixture.results,
        tables: fixture.tables,
        agentLoopPolicy: const ChatAgentLoopPolicy(
          maxRequestContextChars: 5000,
        ),
        writeToolExecutor: (call) async => ChatWriteToolReceipt.conflict(
          operationId: 'op_safe_prefix_conflict',
          message: '写入冲突，等待重新确认。',
          data: {
            'table_id': fixture.table.id,
            'new_revision': fixture.table.revision,
          },
        ),
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            final payload =
                jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            requests.add(payload);
            if (requests.length == 1) {
              return _toolCallResponse(
                id: 'call_compact_write',
                name: 'content_create',
                arguments: {
                  'table_id': fixture.table.id,
                  'type': 'note',
                  'title': '冲突候选',
                  'body': '等待确认',
                  'idempotency_key': 'safe_prefix_conflict',
                },
              );
            }
            if (requests.length <= 7) {
              return _toolCallResponse(
                id: 'call_compact_${requests.length}',
                name: 'table_list',
                arguments: {'offset': requests.length - 1, 'limit': 1},
              );
            }
            return _textResponse('压缩后继续完成。');
          }),
        ),
      );

      final snapshots = <List<Map<String, dynamic>>>[];
      final deltas = await (await service.streamReply(
        conversationId: fixture.conversationId,
        persistToolTranscript: (snapshot) async {
          snapshots.add(snapshot);
        },
      )).toList();

      expect(
        snapshots.any(
          (snapshot) => snapshot.any(
            (item) =>
                item['role'] == 'system' &&
                '${item['content']}'.contains('本地安全前缀摘要'),
          ),
        ),
        isTrue,
      );
      expect(requests, hasLength(8));
      final messages = (requests.last['messages'] as List).cast<Map>();
      final summary = messages
          .singleWhere(
            (message) =>
                message['role'] == 'system' &&
                '${message['content']}'.contains('本地安全前缀摘要'),
          )['content']
          .toString();
      final facts = jsonDecode(
        summary.substring(summary.indexOf('\n') + 1),
      ) as Map<String, dynamic>;
      expect(facts['original_goal'], '请检查现有资料并继续完成任务。');
      expect(
        facts['supplemental_user_requirements'],
        contains('补充要求：课程是信号与系统，考试日期是 2026-12-18。'),
      );
      expect(
        jsonEncode(facts['object_id_revisions']),
        contains(fixture.table.id),
      );
      expect(
        (facts['operation_receipts'] as List).any(
          (receipt) =>
              receipt is Map &&
              receipt['operation_id'] == 'op_safe_prefix_conflict',
        ),
        isTrue,
      );
      expect(
        (facts['pending_conflicts'] as List).any(
          (receipt) => receipt is Map && receipt['status'] == 'conflict',
        ),
        isTrue,
      );
      final callIds = <String>{};
      for (final message in messages) {
        final calls = message['tool_calls'];
        if (calls is List) {
          for (final call in calls.whereType<Map>()) {
            final id = call['id']?.toString();
            if (id != null) callIds.add(id);
          }
        }
        if (message['role'] == 'tool') {
          expect(callIds, contains(message['tool_call_id']));
        }
      }
      expect(deltas.map((delta) => delta.content).join(), '压缩后继续完成。');
      expect(deltas.last.termination, ChatStreamTermination.completed);
      await fixture.close(service);
    },
  );

  test('oversized resumed tool output is bounded before the next model request', () async {
    final fixture = await _AgentFixture.create();
    final requests = <Map<String, dynamic>>[];
    final persistedSnapshots = <List<Map<String, dynamic>>>[];
    final oversizedResult = jsonEncode({
      'status': 'success',
      'message': 'content read completed',
      'data': {
        'entries': [
          {'id': 'entry_resumed_large', 'revision': 9, 'body': '完整正文。' * 1200},
        ],
      },
    });
    final service = ChatService(
      settings: FakeSettingsService(modelKey: 'test-key'),
      repository: fixture.chats,
      results: fixture.results,
      tables: fixture.tables,
      agentLoopPolicy: const ChatAgentLoopPolicy(maxRequestContextChars: 4000),
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          requests.add(
            jsonDecode(await body.bytesToString()) as Map<String, dynamic>,
          );
          return _textResponse('压缩后的工具结果已继续处理。');
        }),
      ),
    );

    final deltas = await (await service.streamReply(
      conversationId: fixture.conversationId,
      resumeToolTranscript: [
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': 'call_resumed_large',
              'type': 'function',
              'function': {
                'name': 'content_read',
                'arguments':
                    '{"entry_id":"entry_resumed_large","table_id":"${fixture.table.id}"}',
              },
            },
          ],
        },
        {
          'role': 'tool',
          'tool_call_id': 'call_resumed_large',
          'name': 'content_read',
          'content': oversizedResult,
        },
      ],
      persistToolTranscript: (snapshot) async {
        persistedSnapshots.add(snapshot);
      },
    )).toList();

    expect(requests, hasLength(1));
    final requestMessages = (requests.single['messages'] as List).cast<Map>();
    final compactedTool = requestMessages.singleWhere(
      (message) =>
          message['role'] == 'tool' &&
          message['tool_call_id'] == 'call_resumed_large',
    );
    expect('${compactedTool['content']}', contains('_context_compacted'));
    expect(
      persistedSnapshots.any(
        (snapshot) => snapshot.any(
          (message) =>
              message['role'] == 'system' &&
              '${message['content']}'.contains('本地安全前缀摘要'),
        ),
      ),
      isTrue,
    );
    expect(
      persistedSnapshots.any(
        (snapshot) => snapshot.any(
          (message) =>
              message['role'] == 'tool' &&
              message['tool_call_id'] == 'call_resumed_large' &&
              message['content'] == oversizedResult,
        ),
      ),
      isTrue,
    );
    expect(deltas.map((delta) => delta.content).join(), '压缩后的工具结果已继续处理。');
    expect(deltas.last.termination, ChatStreamTermination.completed);
    await fixture.close(service);
  });

  test('pauses without another model request when compacted context cannot persist', () async {
    final fixture = await _AgentFixture.create();
    await fixture.chats.saveMessage(
      ChatMessage(
        id: 'msg_compaction_persist_failure_supplement',
        conversationId: fixture.conversationId,
        role: ChatRole.user,
        content: '补充要求：课程是信号与系统，考试日期是 2026-12-18。',
        status: ChatMessageStatus.complete,
        createdAt: DateTime(2026, 11, 3, 10, 1),
        updatedAt: DateTime(2026, 11, 3, 10, 1),
      ),
    );
    final requests = <Map<String, dynamic>>[];
    final persistedSnapshots = <List<Map<String, dynamic>>>[];
    var compactionPersistenceFailures = 0;
    final service = ChatService(
      settings: FakeSettingsService(modelKey: 'test-key'),
      repository: fixture.chats,
      results: fixture.results,
      tables: fixture.tables,
      agentLoopPolicy: const ChatAgentLoopPolicy(maxRequestContextChars: 5000),
      writeToolExecutor: (call) async => ChatWriteToolReceipt.conflict(
        operationId: 'op_compaction_persist_failure',
        message: '写入冲突，等待重新确认。',
        data: {
          'table_id': fixture.table.id,
          'new_revision': fixture.table.revision,
        },
      ),
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          final payload =
              jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
          requests.add(payload);
          if (requests.length == 1) {
            return _toolCallResponse(
              id: 'call_compact_persist_conflict',
              name: 'content_create',
              arguments: {
                'table_id': fixture.table.id,
                'type': 'note',
                'title': '压缩持久化失败候选',
                'body': '等待确认',
                'idempotency_key': 'compact-persist-failure',
              },
            );
          }
          if (requests.length <= 7) {
            return _toolCallResponse(
              id: 'call_compact_persist_${requests.length}',
              name: 'table_list',
              arguments: {'offset': requests.length - 1, 'limit': 1},
            );
          }
          return _textResponse('压缩后不应发出的请求。');
        }),
      ),
    );

    final deltas = await (await service.streamReply(
      conversationId: fixture.conversationId,
      persistToolTranscript: (snapshot) async {
        if (snapshot.any(
          (item) =>
              item['role'] == 'system' &&
              '${item['content']}'.contains('本地安全前缀摘要'),
        )) {
          compactionPersistenceFailures++;
          throw StateError('simulated transcript checkpoint failure');
        }
        persistedSnapshots.add(snapshot);
      },
    )).toList();

    expect(compactionPersistenceFailures, 1);
    expect(requests, hasLength(7));
    expect(
      persistedSnapshots.every(
        (snapshot) => snapshot.every(
          (item) =>
              item['role'] != 'system' ||
              !'${item['content']}'.contains('本地安全前缀摘要'),
        ),
      ),
      isTrue,
    );
    expect(deltas.map((delta) => delta.content).join(), contains('上下文摘要保存失败'));
    expect(deltas.last.termination, ChatStreamTermination.incomplete);
    await fixture.close(service);
  });

  test('unsafe context reduction pauses before any model request', () async {
    final fixture = await _AgentFixture.create();
    await fixture.chats.saveMessage(
      ChatMessage(
        id: 'msg_uncompressible',
        conversationId: fixture.conversationId,
        role: ChatRole.user,
        content: List.filled(1000, '必须完整保留的要求').join(),
        status: ChatMessageStatus.complete,
        createdAt: DateTime(2026, 11, 3, 10, 1),
        updatedAt: DateTime(2026, 11, 3, 10, 1),
      ),
    );
    var requests = 0;
    final usage = AgentUsageMeter();
    final service = ChatService(
      settings: FakeSettingsService(modelKey: 'test-key'),
      repository: fixture.chats,
      results: fixture.results,
      tables: fixture.tables,
      agentLoopPolicy: const ChatAgentLoopPolicy(maxRequestContextChars: 400),
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          requests++;
          return _textResponse('不应发送');
        }),
      ),
    );

    final deltas = await (await service.streamReply(
      conversationId: fixture.conversationId,
      usage: usage,
    )).toList();

    expect(requests, 0);
    expect(usage.requestCount, 0);
    expect(deltas.map((delta) => delta.content).join(), contains('上下文无法安全压缩'));
    expect(deltas.last.termination, ChatStreamTermination.incomplete);
    await fixture.close(service);
  });

  test('retries retryable HTTP failures with configured backoff', () async {
    final fixture = await _AgentFixture.create();
    final waits = <Duration>[];
    final retryWaitStarted = Completer<void>();
    final releaseRetryWait = Completer<void>();
    final usage = AgentUsageMeter();
    var requests = 0;
    final service = ChatService(
      settings: FakeSettingsService(modelKey: 'test-key'),
      repository: fixture.chats,
      results: fixture.results,
      tables: fixture.tables,
      agentLoopPolicy: const ChatAgentLoopPolicy(retryDelays: [Duration.zero]),
      retryWait: (delay) async {
        waits.add(delay);
        retryWaitStarted.complete();
        await releaseRetryWait.future;
      },
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          await body.bytesToString();
          requests++;
          if (requests == 1) {
            return http.StreamedResponse(
              const Stream.empty(),
              429,
              headers: {'retry-after': '0'},
            );
          }
          return _textResponse('重试后已完成。');
        }),
      ),
    );

    final reply = (await service.streamReply(
      conversationId: fixture.conversationId,
      usage: usage,
    )).toList();
    await retryWaitStarted.future.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 35));
    expect(
      usage.activeDuration,
      greaterThanOrEqualTo(const Duration(milliseconds: 30)),
      reason: 'retry backoff remains visible in usage telemetry',
    );
    releaseRetryWait.complete();
    final deltas = await reply;

    expect(requests, 2);
    expect(waits, [Duration.zero]);
    expect(deltas.map((delta) => delta.content).join(), '重试后已完成。');
    expect(deltas.last.termination, ChatStreamTermination.completed);
    expect(
      usage.activeDuration,
      greaterThanOrEqualTo(const Duration(milliseconds: 30)),
    );
    await fixture.close(service);
  });

  test(
    'retries transient network failures before reporting a disconnect',
    () async {
      final fixture = await _AgentFixture.create();
      var requests = 0;
      final service = ChatService(
        settings: FakeSettingsService(modelKey: 'test-key'),
        repository: fixture.chats,
        results: fixture.results,
        tables: fixture.tables,
        agentLoopPolicy: const ChatAgentLoopPolicy(
          retryDelays: [Duration.zero],
        ),
        retryWait: (delay) async {},
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            await body.bytesToString();
            requests++;
            if (requests == 1) {
              throw http.ClientException(
                'temporary network failure',
                request.url,
              );
            }
            return _textResponse('网络恢复后已完成。');
          }),
        ),
      );

      final deltas = await (await service.streamReply(
        conversationId: fixture.conversationId,
      )).toList();

      expect(requests, 2);
      expect(deltas.map((delta) => delta.content).join(), '网络恢复后已完成。');
      expect(deltas.last.termination, ChatStreamTermination.completed);
      await fixture.close(service);
    },
  );

  test('automatically continues batches without resetting usage', () async {
    final fixture = await _AgentFixture.create();
    var requests = 0;
    final usage = AgentUsageMeter();
    final service = ChatService(
      settings: FakeSettingsService(modelKey: 'test-key'),
      repository: fixture.chats,
      results: fixture.results,
      tables: fixture.tables,
      agentLoopPolicy: const ChatAgentLoopPolicy(checkpointEveryRequests: 2),
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          await body.bytesToString();
          requests++;
          if (requests == 5) return _textResponse('已完成跨批任务');
          return _toolCallResponse(
            id: 'call_budget_$requests',
            name: 'table_list',
            arguments: {'offset': requests, 'limit': 1},
          );
        }),
      ),
    );

    final deltas = await (await service.streamReply(
      conversationId: fixture.conversationId,
      usage: usage,
    )).toList();

    expect(requests, 5);
    expect(usage.requestCount, 5);
    expect(deltas.map((delta) => delta.content).join(), contains('已完成跨批任务'));
    expect(deltas.last.termination, ChatStreamTermination.completed);
    await fixture.close(service);
  });

  test('continues beyond the former 240-request boundary', () async {
    final fixture = await _AgentFixture.create();
    var requests = 0;
    final usage = AgentUsageMeter(initial: const AgentUsage(usedRequests: 239));
    final service = ChatService(
      settings: FakeSettingsService(modelKey: 'test-key'),
      repository: fixture.chats,
      results: fixture.results,
      tables: fixture.tables,
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          await body.bytesToString();
          requests++;
          if (requests == 1) {
            return _toolCallResponse(
              id: 'call_cross_boundary',
              name: 'table_list',
              arguments: const {'offset': 0, 'limit': 1},
            );
          }
          return _textResponse('已越过旧上限并完成。');
        }),
      ),
    );

    final deltas = await (await service.streamReply(
      conversationId: fixture.conversationId,
      usage: usage,
    )).toList();

    expect(requests, 2);
    expect(usage.requestCount, 241);
    expect(deltas.map((delta) => delta.content).join(), contains('已越过旧上限并完成'));
    expect(deltas.last.termination, ChatStreamTermination.completed);
    await fixture.close(service);
  });

  test('records more than two active hours without blocking', () async {
    final fixture = await _AgentFixture.create();
    var requests = 0;
    final service = ChatService(
      settings: FakeSettingsService(modelKey: 'test-key'),
      repository: fixture.chats,
      results: fixture.results,
      tables: fixture.tables,
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          requests++;
          return _textResponse('超过两小时仍完成');
        }),
      ),
    );
    final usage = AgentUsageMeter(
      initial: AgentUsage(
        usedActiveMillis: const Duration(hours: 2, minutes: 1).inMilliseconds,
      ),
    );

    final deltas = await (await service.streamReply(
      conversationId: fixture.conversationId,
      usage: usage,
    )).toList();

    expect(requests, 1);
    expect(deltas.map((delta) => delta.content).join(), '超过两小时仍完成');
    expect(deltas.last.termination, ChatStreamTermination.completed);
    await fixture.close(service);
  });
}

class _AgentFixture {
  const _AgentFixture({
    required this.chats,
    required this.results,
    required this.tables,
    required this.conversationId,
    required this.table,
  });

  final ChatRepository chats;
  final ResultLibrary results;
  final TableLibrary tables;
  final String conversationId;
  final TableDocument table;

  static Future<_AgentFixture> create() async {
    final chats = ChatRepository(
      store: MemoryConversationStore(),
      attachments: MemoryAttachmentStore(),
    );
    await chats.initialize();
    final conversation = await chats.createConversation(
      createdAt: DateTime(2026, 11, 3, 10),
    );
    await chats.saveMessage(
      ChatMessage(
        id: 'msg_agent_question',
        conversationId: conversation.id,
        role: ChatRole.user,
        content: '请检查现有资料并继续完成任务。',
        status: ChatMessageStatus.complete,
        createdAt: conversation.createdAt,
        updatedAt: conversation.updatedAt,
      ),
    );
    final results = ResultLibrary(
      repository: ResultRepository(
        vault: MemoryVaultStore(),
        index: MemoryIndexDatabase(),
        deviceId: 'chat-agent-test',
      ),
    );
    await results.initialize();
    final tables = TableLibrary(
      repository: TableRepository(
        vault: MemoryVaultStore(),
        index: MemoryIndexDatabase(),
      ),
    );
    await tables.initialize();
    final table = await tables.createTable(title: '课程表');
    return _AgentFixture(
      chats: chats,
      results: results,
      tables: tables,
      conversationId: conversation.id,
      table: table,
    );
  }

  Future<void> close(ChatService service) async {
    service.close();
    await chats.close();
    tables.dispose();
    await results.shutdown();
    results.dispose();
  }
}

http.StreamedResponse _toolCallResponse({
  required String id,
  required String name,
  required Map<String, dynamic> arguments,
}) {
  final event = {
    'choices': [
      {
        'delta': {
          'tool_calls': [
            {
              'index': 0,
              'id': id,
              'function': {'name': name, 'arguments': jsonEncode(arguments)},
            },
          ],
        },
        'finish_reason': 'tool_calls',
      },
    ],
  };
  return http.StreamedResponse(
    Stream.fromIterable([
      utf8.encode('data: ${jsonEncode(event)}\n\n'),
      utf8.encode('data: [DONE]\n\n'),
    ]),
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}

http.StreamedResponse _textResponse(String text) {
  final event = {
    'choices': [
      {
        'delta': {'content': text},
      },
    ],
  };
  return http.StreamedResponse(
    Stream.fromIterable([
      utf8.encode('data: ${jsonEncode(event)}\n\n'),
      utf8.encode('data: [DONE]\n\n'),
    ]),
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}
