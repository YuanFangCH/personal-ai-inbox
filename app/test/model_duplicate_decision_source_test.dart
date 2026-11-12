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
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/modules/capture/capture_outcome.dart';
import 'package:personal_ai_inbox/modules/conversation/content_duplicate_policy.dart';
import 'package:personal_ai_inbox/modules/conversation/model_duplicate_decision_source.dart';
import 'package:personal_ai_inbox/services/model_capabilities.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'test_support.dart';

void main() {
  test('does not send candidates without explicit read permission', () async {
    var httpCalls = 0;
    var budgetCalls = 0;
    final model = _modelClient((_) async {
      httpCalls++;
      return _completedResponse(_decisionJson(action: 'create'));
    });
    addTearDown(model.close);
    final source = _source(
      model: model,
      canRead: (_) async => false,
      canModify: (_) async => true,
      reserveBudget: (_) async {
        budgetCalls++;
        return true;
      },
    );

    final decision = await source.decide(_request());

    expect(decision.action, SemanticDuplicateAction.conflict);
    expect(decision.reason, contains('未允许读取'));
    expect(decision.comparisonComplete, isFalse);
    expect(httpCalls, 0);
    expect(budgetCalls, 0);
    source.close();
  });

  test('does not request a merge decision without modify permission', () async {
    var httpCalls = 0;
    var budgetCalls = 0;
    final model = _modelClient((_) async {
      httpCalls++;
      return _completedResponse(_decisionJson(action: 'create'));
    });
    addTearDown(model.close);
    final source = _source(
      model: model,
      canRead: (_) async => true,
      canModify: (_) async => false,
      reserveBudget: (_) async {
        budgetCalls++;
        return true;
      },
    );

    final decision = await source.decide(_request());

    expect(decision.action, SemanticDuplicateAction.conflict);
    expect(decision.reason, contains('未允许修改'));
    expect(decision.comparisonComplete, isFalse);
    expect(httpCalls, 0);
    expect(budgetCalls, 0);
    source.close();
  });

  test(
    'rechecks permission after budget persistence before network send',
    () async {
      var readChecks = 0;
      var modifyChecks = 0;
      var httpCalls = 0;
      final budgetStarted = Completer<void>();
      final budgetRelease = Completer<bool>();
      final model = _modelClient((_) async {
        httpCalls++;
        return _completedResponse(_decisionJson(action: 'create'));
      });
      addTearDown(model.close);
      final source = _source(
        model: model,
        canRead: (_) async {
          readChecks++;
          return readChecks < 3;
        },
        canModify: (_) async {
          modifyChecks++;
          return true;
        },
        reserveBudget: (_) async {
          budgetStarted.complete();
          return budgetRelease.future;
        },
      );

      final pending = source.decide(_request());
      await budgetStarted.future;
      budgetRelease.complete(true);
      final decision = await pending;

      expect(decision.action, SemanticDuplicateAction.conflict);
      expect(decision.reason, contains('未允许读取'));
      expect(decision.comparisonComplete, isFalse);
      expect(readChecks, 3);
      expect(modifyChecks, 2);
      expect(httpCalls, 0);
      source.close();
    },
  );

  test('already-cancelled work sends no model request or budget', () async {
    var httpCalls = 0;
    var budgetCalls = 0;
    final model = _modelClient((_) async {
      httpCalls++;
      return _completedResponse(_decisionJson(action: 'create'));
    });
    addTearDown(model.close);
    final cancellation = Completer<void>()..complete();
    final source = _source(
      model: model,
      reserveBudget: (_) async {
        budgetCalls++;
        return true;
      },
      cancellation: () => cancellation.future,
    );

    final decision = await source.decide(_request());

    expect(decision.action, SemanticDuplicateAction.conflict);
    expect(decision.reason, contains('已取消'));
    expect(httpCalls, 0);
    expect(budgetCalls, 0);
    source.close();
  });

  test('different dates and courses never reach the model', () async {
    var httpCalls = 0;
    var budgetCalls = 0;
    final model = _modelClient((_) async {
      httpCalls++;
      return _completedResponse(_decisionJson(action: 'augment'));
    });
    addTearDown(model.close);
    final source = _source(
      model: model,
      reserveBudget: (_) async {
        budgetCalls++;
        return true;
      },
    );

    final differentDate = await source.decide(
      _request(candidateStart: DateTime.parse('2026-11-11T09:00:00+08:00')),
    );
    final differentCourse = await source.decide(
      _request(candidateEvidence: const ['course:networks']),
    );

    expect(differentDate.action, SemanticDuplicateAction.create);
    expect(differentCourse.action, SemanticDuplicateAction.create);
    expect(httpCalls, 0);
    expect(budgetCalls, 0);
    source.close();
  });

  test('derived object hash alone does not authorize semantic merge', () async {
    var httpCalls = 0;
    final model = _modelClient((_) async {
      httpCalls++;
      return _completedResponse(_decisionJson(action: 'create'));
    });
    addTearDown(model.close);
    final source = _source(model: model);
    const title = '考试范围';
    final evidence = contentObjectEvidenceKey(
      type: TableContentType.note,
      title: title,
    );
    final signal = ContentIdentitySignal(
      type: TableContentType.note,
      title: title,
      body: '第三章到第五章',
      identity: ContentBusinessIdentity(evidence: [evidence]),
      businessAnchor: contentBusinessAnchor(type: TableContentType.note),
    );
    final candidateSignal = ContentIdentitySignal(
      type: TableContentType.note,
      title: title,
      body: '与考试范围无关的补充说明',
      identity: ContentBusinessIdentity(evidence: [evidence]),
      businessAnchor: contentBusinessAnchor(type: TableContentType.note),
    );
    final now = DateTime.parse('2026-11-03T10:00:00+08:00');

    final decision = await source.decide(
      SemanticDuplicateRequest(
        signal: signal,
        candidates: [
          ContentDuplicateCandidate(
            entry: TableEntryDocument(
              id: 'entry_legacy_object',
              type: TableContentType.note,
              tableId: 'table_events',
              title: title,
              revision: 1,
              createdAt: now,
              updatedAt: now,
              body: '与考试范围无关的补充说明',
            ),
            signal: candidateSignal,
            fingerprint: const ContentDuplicatePolicy().fingerprint(
              candidateSignal,
            ),
          ),
        ],
      ),
    );

    expect(decision.action, SemanticDuplicateAction.create);
    expect(httpCalls, 0);
    source.close();
  });

  test(
    'sends a bounded structured prompt and parses a valid augment',
    () async {
      Map<String, dynamic>? requestBody;
      final model = _modelClient((body) async {
        requestBody = body;
        return _completedResponse(
          _decisionJson(
            action: 'augment',
            targetId: 'entry_signals',
            expectedRevision: 3,
            evidence: const ['course:signals'],
            bodyAddition: '新增范围：第三章',
            fieldAdditions: const {'room': '三教 101'},
          ),
        );
      });
      addTearDown(model.close);
      final source = _source(model: model);

      final decision = await source.decide(_request());

      expect(decision.action, SemanticDuplicateAction.augment);
      expect(decision.targetId, 'entry_signals');
      expect(decision.expectedRevision, 3);
      expect(decision.bodyAddition, '新增范围：第三章');
      expect(decision.fieldAdditions, {'room': '三教 101'});
      expect(requestBody!.containsKey('tools'), isFalse);
      final messages = requestBody!['messages'] as List<dynamic>;
      expect(
        (messages.first as Map<String, dynamic>)['content'],
        contains('Different dates, courses'),
      );
      final userPayload = jsonDecode(
        (messages.last as Map<String, dynamic>)['content'] as String,
      ) as Map<String, dynamic>;
      expect(userPayload['incoming'], isA<Map<String, dynamic>>());
      expect(userPayload['bounded_candidates'], hasLength(1));
      expect(
        (userPayload['bounded_candidates'] as List<dynamic>).single['id'],
        'entry_signals',
      );
      source.close();
    },
  );

  test('an invalid augment target becomes a conflict', () async {
    final model = _modelClient(
      (_) async => _completedResponse(
        _decisionJson(
          action: 'augment',
          targetId: 'entry_not_checked',
          expectedRevision: 3,
          evidence: const ['course:signals'],
          bodyAddition: '不能自动合并',
        ),
      ),
    );
    addTearDown(model.close);
    final source = _source(model: model);

    final decision = await source.decide(_request());

    expect(decision.action, SemanticDuplicateAction.conflict);
    expect(decision.reason, contains('不在本次严格候选中'));
    source.close();
  });

  test('incomplete model streams become a conflict', () async {
    final model = _modelClient(
      (_) async => http.StreamedResponse(
        Stream.value(
          utf8.encode(
            'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': _decisionJson(action: 'create')},
                },
              ],
            })}\n\n',
          ),
        ),
        200,
        headers: {'content-type': 'text/event-stream'},
      ),
    );
    addTearDown(model.close);
    final source = _source(model: model);

    final decision = await source.decide(_request());

    expect(decision.action, SemanticDuplicateAction.conflict);
    expect(decision.reason, contains('流未完整结束'));
    source.close();
  });

  test('caller cancellation aborts the model stream', () async {
    final cancellation = Completer<void>();
    final responseBytes = StreamController<List<int>>();
    final aborted = Completer<void>();
    final model = _modelClientWithRequest((request, body) async {
      await body.bytesToString();
      final abortable = request as http.AbortableRequest;
      unawaited(
        abortable.abortTrigger!.then((_) {
          if (!aborted.isCompleted) aborted.complete();
        }),
      );
      scheduleMicrotask(cancellation.complete);
      return http.StreamedResponse(
        responseBytes.stream,
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    addTearDown(model.close);
    final source = _source(
      model: model,
      cancellation: () => cancellation.future,
    );

    final decision = await source
        .decide(_request())
        .timeout(const Duration(seconds: 2));
    await aborted.future.timeout(const Duration(seconds: 2));

    expect(decision.action, SemanticDuplicateAction.conflict);
    expect(decision.reason, contains('已取消'));
    await responseBytes.close();
    source.close();
  });

  test(
    'bootstrap injects the model source for automatic augmentation',
    () async {
      late final AppRuntime runtime;
      var chatRequests = 0;
      var duplicateRequests = 0;
      runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        conversationStoreOverride: MemoryConversationStore(),
        attachmentStoreOverride: MemoryAttachmentStore(),
        settingsOverride: FakeSettingsService(
          modelKey: 'test-key',
          defaultAiPolicy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
        ),
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            final payload =
                jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            final messages = (payload['messages'] as List).cast<Map>();
            final system = messages.first['content'] as String? ?? '';
            if (system.contains('You compare one incoming personal-content')) {
              duplicateRequests++;
              final user = messages.lastWhere(
                (message) => message['role'] == 'user',
              );
              final prompt =
                  jsonDecode(user['content'] as String) as Map<String, dynamic>;
              final candidates = (prompt['bounded_candidates'] as List)
                  .cast<Map<String, dynamic>>();
              if (duplicateRequests == 1) {
                expect(candidates, hasLength(10));
                return _completedResponse(_decisionJson(action: 'create'));
              }
              expect(candidates, hasLength(1));
              final candidate = candidates.single;
              final evidence =
                  ((prompt['incoming'] as Map)['identity_evidence'] as List)
                      .cast<String>();
              return _completedResponse(
                _decisionJson(
                  action: 'augment',
                  targetId: candidate['id'] as String,
                  expectedRevision: candidate['revision'] as int,
                  evidence: evidence,
                  bodyAddition: '第四章到第五章',
                ),
              );
            }

            chatRequests++;
            if (!messages.any((message) => message['role'] == 'tool')) {
              final table = runtime.tables.tables.singleWhere(
                (item) => item.role == TableRole.inboxSchedule,
              );
              final start = DateTime.parse('2026-11-10T09:00:00+08:00');
              return _toolCallResponse(
                id: 'call_model_duplicate',
                name: 'content_create',
                arguments: {
                  'table_id': table.id,
                  'type': 'schedule',
                  'title': '期中考试',
                  'body': '第四章到第五章',
                  'start': start.toIso8601String(),
                  'end': start.add(const Duration(hours: 2)).toIso8601String(),
                  'idempotency_key': 'bootstrap-model-duplicate',
                },
              );
            }
            return _completedResponse('已自动补充到考试范围。');
          }),
        ),
      );
      addTearDown(runtime.shutdown);
      final table = runtime.tables.tables.singleWhere(
        (item) => item.role == TableRole.inboxSchedule,
      );
      final start = DateTime.parse('2026-11-10T09:00:00+08:00');
      final end = start.add(const Duration(hours: 2));
      final evidence = semanticFactEvidenceForContent(
        type: TableContentType.schedule,
        start: start,
        end: end,
      );
      final objectEvidence = contentObjectEvidenceKey(
        type: TableContentType.schedule,
        title: '期中考试',
        start: start,
        end: end,
      );
      final now = DateTime.parse('2026-11-03T10:00:00+08:00');
      for (var index = 0; index < 10; index++) {
        await runtime.tables.createEntry(
          TableEntryDocument(
            id: 'entry_candidate_${index.toString().padLeft(2, '0')}',
            type: TableContentType.schedule,
            tableId: table.id,
            title: '期中考试',
            revision: 1,
            createdAt: now,
            updatedAt: now,
            body: '已有范围 $index',
            start: start,
            end: end,
            extensionFields: {
              contentIntakeEvidenceExtensionKey: [...evidence, objectEvidence],
            },
          ),
        );
      }
      await runtime.tables.createEntry(
        TableEntryDocument(
          id: 'entry_existing_scope',
          type: TableContentType.schedule,
          tableId: table.id,
          title: '期中考试',
          revision: 1,
          createdAt: now,
          updatedAt: now,
          body: '第三章',
          start: start,
          end: end,
          extensionFields: {
            contentIntakeEvidenceExtensionKey: [...evidence, objectEvidence],
          },
        ),
      );
      final conversation = await runtime.conversations.createConversation(
        policy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
      );

      await runtime.conversations.sendChatMessage(
        conversation.id,
        text: '补充考试范围到第五章',
      );

      expect(chatRequests, 2);
      expect(duplicateRequests, 2);
      final updated = await runtime.tables.readEntry('entry_existing_scope');
      expect(updated!.body, contains('第三章'));
      expect(updated.title, '期中考试');
      expect(
        runtime.tables.entries.where(
          (entry) => entry.start?.isAtSameMomentAs(start) ?? false,
        ),
        hasLength(11),
      );
      final assistant = runtime.conversations.messagesFor(conversation.id).last;
      expect(assistant.status, ChatMessageStatus.complete);
      expect(updated.body, contains('第四章到第五章'), reason: assistant.content);
      expect(assistant.content, contains('已自动补充'));
    },
  );

  test(
    'bootstrap capture uses device policy and an independent model budget',
    () async {
      var duplicateRequests = 0;
      final runtime = await AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        conversationStoreOverride: MemoryConversationStore(),
        attachmentStoreOverride: MemoryAttachmentStore(),
        settingsOverride: FakeSettingsService(
          modelKey: 'test-key',
          defaultAiPolicy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
        ),
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            final payload =
                jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            final messages = (payload['messages'] as List).cast<Map>();
            final system = messages.first['content'] as String? ?? '';
            expect(
              system,
              contains('You compare one incoming personal-content'),
            );
            duplicateRequests++;
            final user = messages.lastWhere(
              (message) => message['role'] == 'user',
            );
            final prompt =
                jsonDecode(user['content'] as String) as Map<String, dynamic>;
            final candidate =
                (prompt['bounded_candidates'] as List).single
                    as Map<String, dynamic>;
            final sharedEvidence =
                (candidate['shared_verifiable_evidence'] as List)
                    .cast<String>();
            return _completedResponse(
              _decisionJson(
                action: 'augment',
                targetId: candidate['id'] as String,
                expectedRevision: candidate['revision'] as int,
                evidence: [sharedEvidence.first],
                bodyAddition: '第四章',
              ),
            );
          }),
        ),
      );
      addTearDown(runtime.shutdown);
      final table = runtime.tables.tables.singleWhere(
        (item) => item.role == TableRole.inboxSchedule,
      );
      final future = DateTime.now().add(const Duration(days: 7));
      final start = DateTime(future.year, future.month, future.day, 9);
      final end = start.add(const Duration(hours: 1));
      final title =
          '${start.year}-${start.month.toString().padLeft(2, '0')}-'
          '${start.day.toString().padLeft(2, '0')} 09:00 信号与系统期中考试';
      final evidence = semanticFactEvidenceForContent(
        type: TableContentType.schedule,
        start: start,
        end: end,
      );
      final objectEvidence = contentObjectEvidenceKey(
        type: TableContentType.schedule,
        title: title,
        start: start,
        end: end,
      );
      await runtime.tables.createEntry(
        TableEntryDocument(
          id: 'entry_capture_scope',
          type: TableContentType.schedule,
          tableId: table.id,
          title: title,
          revision: 1,
          createdAt: DateTime(2026, 11, 1, 9),
          updatedAt: DateTime(2026, 11, 1, 9),
          body: '第三章',
          start: start,
          end: end,
          extensionFields: {
            contentIntakeEvidenceExtensionKey: [...evidence, objectEvidence],
          },
        ),
      );

      final outcome = await runtime.capture.captureText(
        title,
        preferModel: false,
      );

      expect(
        outcome.status,
        CaptureOutcomeStatus.created,
        reason: '${outcome.capture?.reviewReason}\n${outcome.warning ?? ''}',
      );
      expect(outcome.tableEntry!.id, 'entry_capture_scope');
      expect(duplicateRequests, 1);
      final updated = await runtime.tables.readEntry('entry_capture_scope');
      expect(updated!.title, title);
      expect(updated.body, contains('第三章'));
      expect(updated.body, contains('第四章'));
      expect(
        runtime.tables.entries.where(
          (entry) => entry.start?.isAtSameMomentAs(start) ?? false,
        ),
        hasLength(1),
      );
    },
  );
}

ModelSemanticDuplicateDecisionSource _source({
  required ModelClient model,
  ModelConfiguration configuration = _configuration,
  Future<bool> Function(SemanticDuplicateRequest)? canRead,
  Future<bool> Function(SemanticDuplicateRequest)? canModify,
  Future<bool> Function(SemanticDuplicateRequest)? reserveBudget,
  DuplicateDecisionCancellationProvider? cancellation,
}) => ModelSemanticDuplicateDecisionSource(
  configurationProvider: () async => configuration,
  canReadCandidates: canRead ?? (_) async => true,
  canModifyExisting: canModify ?? (_) async => true,
  reserveModelRequest: reserveBudget ?? (_) async => true,
  cancellation: cancellation,
  modelClient: model,
  clock: () => DateTime.parse('2026-11-03T10:00:00+08:00'),
);

SemanticDuplicateRequest _request({
  DateTime? candidateStart,
  List<String> candidateEvidence = const ['course:signals'],
}) {
  const title = '期中考试';
  final incomingStart = DateTime.parse('2026-11-10T09:00:00+08:00');
  final incomingEnd = DateTime.parse('2026-11-10T11:00:00+08:00');
  final signal = ContentIdentitySignal(
    type: TableContentType.schedule,
    title: title,
    body: '闭卷；范围见课程通知',
    identity: ContentBusinessIdentity(
      evidence: const ['course:signals', 'session:midterm'],
    ),
    businessAnchor: contentBusinessAnchor(
      type: TableContentType.schedule,
      start: incomingStart,
      end: incomingEnd,
    ),
  );
  final entry = TableEntryDocument(
    id: 'entry_signals',
    type: TableContentType.schedule,
    tableId: 'table_courses',
    title: title,
    revision: 3,
    createdAt: DateTime.parse('2026-11-01T09:00:00+08:00'),
    updatedAt: DateTime.parse('2026-11-02T09:00:00+08:00'),
    body: '闭卷',
    start: candidateStart ?? incomingStart,
    end: incomingEnd,
  );
  final candidateSignal = ContentIdentitySignal(
    type: TableContentType.schedule,
    title: title,
    body: entry.body,
    identity: ContentBusinessIdentity(
      evidence: [
        ...candidateEvidence,
        'session:midterm',
        'legacy-content-create:derived',
      ],
    ),
    businessAnchor: contentBusinessAnchor(
      type: TableContentType.schedule,
      start: entry.start,
      end: entry.end,
    ),
  );
  return SemanticDuplicateRequest(
    signal: signal,
    candidates: [
      ContentDuplicateCandidate(
        entry: entry,
        signal: candidateSignal,
        fingerprint: const ContentDuplicatePolicy().fingerprint(
          candidateSignal,
        ),
      ),
    ],
  );
}

String _decisionJson({
  required String action,
  String? targetId,
  int? expectedRevision,
  List<String> evidence = const [],
  String bodyAddition = '',
  Map<String, Object?> fieldAdditions = const {},
}) => jsonEncode({
  'action': action,
  'target_id': targetId,
  'expected_revision': expectedRevision,
  'evidence': evidence,
  'body_addition': bodyAddition,
  'field_additions': fieldAdditions,
  'reason': 'structured test decision',
});

ModelClient _modelClient(
  Future<http.StreamedResponse> Function(Map<String, dynamic> body) handler,
) {
  return _modelClientWithRequest((request, body) async {
    final decoded =
        jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
    return handler(decoded);
  });
}

ModelClient _modelClientWithRequest(
  Future<http.StreamedResponse> Function(
    http.BaseRequest request,
    http.ByteStream body,
  )
  handler,
) {
  return ModelClient(
    client: MockClient.streaming((request, body) => handler(request, body)),
  );
}

Future<http.StreamedResponse> _completedResponse(String content) async {
  return http.StreamedResponse(
    Stream.fromIterable([
      utf8.encode(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': content},
            },
          ],
        })}\n\n',
      ),
      utf8.encode('data: [DONE]\n\n'),
    ]),
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}

Future<http.StreamedResponse> _toolCallResponse({
  required String id,
  required String name,
  required Map<String, Object?> arguments,
}) async {
  return http.StreamedResponse(
    Stream.value(
      utf8.encode(
        'data: ${jsonEncode({
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
        })}\n\n',
      ),
    ),
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}

const _configuration = ModelConfiguration(
  baseUrl: 'https://api.deepseek.com',
  model: 'deepseek-flash',
  apiKey: 'test-key',
  capabilities: ModelCapabilities.deepseekFlash,
);
