import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/ai_policy.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/table_repository.dart';
import 'package:personal_ai_inbox/modules/conversation/auto_record_processor.dart';
import 'package:personal_ai_inbox/modules/conversation/content_duplicate_policy.dart';
import 'package:personal_ai_inbox/modules/conversation/table_action_processor.dart';
import 'package:personal_ai_inbox/modules/tables/table_library.dart';

void main() {
  test(
    'revoking permission during duplicate preparation prevents commit',
    () async {
      late _Harness harness;
      harness = await _Harness.create(
        aiPolicy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
        semanticDuplicateDecisionSource: _RevokingDuplicateSource(() async {
          final conversation = (await harness.chats.findConversation(
            harness.conversationId,
          ))!;
          await harness.chats.saveConversation(
            conversation.copyWith(
              aiPolicy: AiPolicy.forPreset(AiPolicyPreset.readOnly),
            ),
          );
        }),
      );
      try {
        final table = harness.tables.tables.first;
        final first = await harness.run('content.create', {
          'table_id': table.id,
          'type': 'note',
          'title': '权限切换记录',
          'body': '原正文',
          'idempotency_key': 'before-revocation',
        }, createdAt: DateTime(2026, 11, 4));
        final second = await harness.run('content.create', {
          'table_id': table.id,
          'type': 'note',
          'title': '权限切换记录',
          'body': '原正文和新增事实',
          'idempotency_key': 'after-revocation',
        }, createdAt: DateTime(2026, 11, 4, 0, 1));
        expect(first.status, TableChatActionStatus.applied);
        expect(second.status, TableChatActionStatus.failed);
        expect(second.message, contains('权限'));
        expect(harness.tables.entries, hasLength(1));
        expect((await harness.tables.readEntry(first.entryId!))!.body, '原正文');
      } finally {
        await harness.close();
      }
    },
  );

  test('legacy receipt without request evidence blocks automatic replay', () async {
    final harness = await _Harness.create();
    try {
      final table = harness.tables.tables.first;
      final first = await harness.run('content.create', {
        'table_id': table.id,
        'type': 'note',
        'title': '旧记录',
        'body': '旧正文',
        'idempotency_key': 'legacy',
      }, createdAt: DateTime(2026, 11, 4));
      final legacy = first.toJson()
        ..['id'] =
            'act_${sha256.convert(utf8.encode('conversation:msg_table_user_0:0')).toString().substring(0, 24)}'
        ..remove('request_fingerprint');
      final assistant = (await harness.chats.findMessage(
        harness._lastAssistantId!,
      ))!;
      await harness.chats.saveMessage(
        assistant.copyWith(tableActions: [TableChatAction.fromJson(legacy)]),
      );
      final replay = await harness.replayLastWith(harness.processor);
      expect(replay.status, TableChatActionStatus.failed);
      expect(replay.message, contains('无法核对'));
      expect(harness.tables.entries, hasLength(1));
    } finally {
      await harness.close();
    }
  });

  test(
    'rejects changed arguments in an already executed tool position',
    () async {
      final harness = await _Harness.create();
      try {
        final table = harness.tables.tables.first;
        final first = await harness.run('content.create', {
          'table_id': table.id,
          'type': 'note',
          'title': '原记录',
          'idempotency_key': 'first',
          'body': '原正文',
        }, createdAt: DateTime(2026, 11, 4));
        final call = ToolCallAccumulator()
          ..index = 0
          ..name = 'content.create'
          ..arguments.write(
            jsonEncode({
              'table_id': table.id,
              'type': 'note',
              'title': '另一个操作',
              'idempotency_key': 'changed',
              'body': '不同正文',
            }),
          );
        final replay = await harness.processor.processToolCalls(
          harness._lastAssistantId!,
          [call],
        );
        expect(first.status, TableChatActionStatus.applied);
        expect(replay.single.status, TableChatActionStatus.failed);
        expect(replay.single.message, contains('已有不同'));
        expect(harness.tables.entries, hasLength(1));
      } finally {
        await harness.close();
      }
    },
  );

  test('resolves permission again for each tool in a batch', () async {
    final harness = await _Harness.create();
    try {
      final table = harness.tables.tables.first;
      await harness.run('content.create', {
        'table_id': table.id,
        'type': 'note',
        'title': '初始',
        'idempotency_key': 'initial',
        'body': '初始正文',
      }, createdAt: DateTime(2026, 11, 4));
      var checks = 0;
      final processor = TableActionProcessor(
        chatRepository: harness.chats,
        tables: harness.tables,
        policyResolver: (_) => AiPolicy.forPreset(
          ++checks == 1 ? AiPolicyPreset.standard : AiPolicyPreset.readOnly,
        ),
      );
      final actions = await processor.processToolCalls(
        harness._lastAssistantId!,
        [
          for (var index = 1; index <= 2; index++)
            ToolCallAccumulator()
              ..index = index
              ..name = 'table.body.update'
              ..arguments.write(
                jsonEncode({
                  'table_id': table.id,
                  'if_revision': table.revision + index - 1,
                  'idempotency_key': 'batch_$index',
                  'body': '正文$index',
                }),
              ),
        ],
      );
      expect(actions.map((action) => action.status), [
        TableChatActionStatus.applied,
        TableChatActionStatus.failed,
      ]);
      expect(checks, 2);
    } finally {
      await harness.close();
    }
  });

  test(
    'table content operations apply by ID and preserve recoverable delete',
    () async {
      final harness = await _Harness.create();
      final now = DateTime.now();
      final source = await harness.tables.createTable(title: '作业表');
      final target = await harness.tables.createTable(title: '考试表');
      await harness.tables.updateTable(
        source.copyWith(
          fields: [
            TableFieldDefinition(
              id: 'fld_course',
              name: '课程',
              type: CustomFieldType.text,
            ),
          ],
        ),
        expectedRevision: source.revision,
      );
      await harness.tables.updateTable(
        target.copyWith(
          fields: [
            TableFieldDefinition(
              id: 'fld_course_target',
              name: '课程名称',
              type: CustomFieldType.text,
            ),
          ],
        ),
        expectedRevision: target.revision,
      );

      final created = await harness.run('content.create', {
        'table_id': source.id,
        'type': 'note',
        'title': '复习第三章',
        'body': '信号与系统',
        'custom_values': {'fld_course': '信号与系统'},
        'idempotency_key': 'create-note',
      }, createdAt: now);
      final createdId = created.entryId!;
      expect(created.status, TableChatActionStatus.applied);
      expect(harness.tables.findTable(source.id)!.id, source.id);
      expect((await harness.tables.readEntry(createdId))!.tableId, source.id);

      final updated = await harness.run('content.update', {
        'id': createdId,
        'if_revision': 1,
        'changes': {'title': '复习第三章和第四章'},
        'idempotency_key': 'update-note',
      }, createdAt: now.add(const Duration(minutes: 1)));
      expect(updated.status, TableChatActionStatus.applied);
      expect((await harness.tables.readEntry(createdId))!.title, '复习第三章和第四章');

      final moved = await harness.run('content.move', {
        'id': createdId,
        'if_revision': 2,
        'to_table_id': target.id,
        'field_mapping': {'fld_course': 'fld_course_target'},
        'idempotency_key': 'move-note',
      }, createdAt: now.add(const Duration(minutes: 2)));
      expect(moved.status, TableChatActionStatus.applied);
      final afterMove = await harness.tables.readEntry(createdId);
      expect(afterMove!.tableId, target.id);
      expect(afterMove.customValues['fld_course_target'], '信号与系统');

      final deleted = await harness.run('content.delete', {
        'id': createdId,
        'if_revision': 3,
        'idempotency_key': 'delete-note',
      }, createdAt: now.add(const Duration(minutes: 3)));
      expect(deleted.status, TableChatActionStatus.applied);
      expect(deleted.recoveryBatchId, isNotNull);
      expect((await harness.tables.readEntry(createdId))!.deleted, isTrue);
      await harness.processor.undoDelete(deleted);
      final restored = await harness.tables.readEntry(createdId);
      expect(restored!.deleted, isFalse);
      expect(restored.tableId, target.id);
      expect(restored.customValues['fld_course_target'], '信号与系统');
      await harness.close();
    },
  );

  test('standard structure proposals wait and preconfigured tables can be confirmed', () async {
    final harness = await _Harness.create(
      aiPolicy: AiPolicy.forPreset(AiPolicyPreset.standard),
    );
    final now = DateTime.now();
    final pending = await harness.run('table.propose', {
      'operation': 'create',
      'payload': {'title': '考试安排'},
      'idempotency_key': 'propose-table',
    }, createdAt: now);
    expect(pending.status, TableChatActionStatus.pendingConfirmation);
    expect(
      harness.tables.findTable(pending.tableId!),
      isNull,
      reason: 'A proposal must not change table structure.',
    );
    final created = await harness.processor.confirmStructure(pending);
    expect(created.status, TableChatActionStatus.applied);
    expect(harness.tables.findTable(pending.tableId!)!.title, '考试安排');

    final table = harness.tables.findTable(pending.tableId!)!;
    final fieldCandidate = await harness.run('table.propose', {
      'operation': 'upsert_field',
      'table_id': table.id,
      'expected_revision': table.revision,
      'payload': {
        'field': {
          'name': '科目',
          'type': 'singleSelect',
          'options': [
            {'label': '数学'},
            {'label': '英语'},
          ],
        },
      },
      'idempotency_key': 'propose-field',
    }, createdAt: now.add(const Duration(minutes: 1)));
    expect(harness.tables.findTable(table.id)!.fields, isEmpty);
    final fieldApplied = await harness.processor.confirmStructure(
      fieldCandidate,
    );
    expect(fieldApplied.status, TableChatActionStatus.applied);
    expect(
      harness.tables.findTable(table.id)!.fields.single.options,
      hasLength(2),
    );

    final defaultTable = harness.tables.tables.singleWhere(
      (candidate) => candidate.role == TableRole.inboxTodo,
    );
    final pendingDelete = await harness.run('table.propose', {
      'operation': 'delete',
      'table_id': defaultTable.id,
      'expected_revision': defaultTable.revision,
      'payload': {},
      'idempotency_key': 'propose-default-delete',
    }, createdAt: now.add(const Duration(minutes: 2)));
    expect(pendingDelete.status, TableChatActionStatus.pendingConfirmation);
    expect(harness.tables.findTable(defaultTable.id)?.deleted, isFalse);
    final deleted = await harness.processor.confirmStructure(pendingDelete);
    expect(deleted.status, TableChatActionStatus.applied);
    expect(harness.tables.findTable(defaultTable.id), isNull);
    await harness.close();
  });

  test('permission denial prevents table content writes', () async {
    final harness = await _Harness.create(
      permissions: const AiPermissions(
        read: true,
        create: false,
        modifyDelete: false,
      ),
    );
    final table = harness.tables.tables.first;
    final action = await harness.run('content.create', {
      'table_id': table.id,
      'type': 'note',
      'title': '不应写入',
      'body': '权限关闭',
      'idempotency_key': 'denied-create',
    }, createdAt: DateTime(2026, 10, 30));
    expect(action.status, TableChatActionStatus.failed);
    expect(
      harness.tables.entries.any((entry) => entry.title == '不应写入'),
      isFalse,
    );
    await harness.close();
  });

  test(
    'AI table body update applies without creating a structure proposal',
    () async {
      final harness = await _Harness.create();
      final table = await harness.tables.createTable(
        title: '课程笔记',
        body: '旧正文',
      );
      final action = await harness.run('table.body.update', {
        'table_id': table.id,
        'if_revision': table.revision,
        'body': '新的课程背景和说明',
        'idempotency_key': 'update-table-body',
      }, createdAt: DateTime.now());
      expect(action.status, TableChatActionStatus.applied);
      expect(action.operation, 'table.body.update');
      expect(harness.tables.findTable(table.id)!.body, '新的课程背景和说明');
      await harness.close();
    },
  );

  test(
    'stale structure confirmation leaves the newer table version unchanged',
    () async {
      final harness = await _Harness.create();
      final table = await harness.tables.createTable(title: '考试安排');
      final candidate = await harness.run('table.propose', {
        'operation': 'rename',
        'table_id': table.id,
        'expected_revision': table.revision,
        'payload': {'name': '期末考试'},
        'idempotency_key': 'propose-rename',
      }, createdAt: DateTime.now());
      final current = harness.tables.findTable(table.id)!;
      await harness.tables.updateTable(
        current.copyWith(body: '新版本的表正文'),
        expectedRevision: current.revision,
      );

      final stale = await harness.processor.confirmStructure(candidate);
      expect(stale.status, TableChatActionStatus.stale);
      expect(harness.tables.findTable(table.id)!.title, '考试安排');
      expect(harness.tables.findTable(table.id)!.body, '新版本的表正文');
      await harness.close();
    },
  );

  test(
    'schedule change retains its event and updates the referenced schedule',
    () async {
      final harness = await _Harness.create();
      final scheduleTable = harness.tables.tables.singleWhere(
        (table) => table.role == TableRole.inboxSchedule,
      );
      final now = DateTime.now();
      final schedule = await harness.tables.createEntry(
        TableEntryDocument(
          id: 'sc_ai_change',
          type: TableContentType.schedule,
          tableId: scheduleTable.id,
          title: '期中考试',
          revision: 1,
          createdAt: now,
          updatedAt: now,
          body: '',
          start: now.add(const Duration(days: 3)),
        ),
      );
      final changedStart = now.add(const Duration(days: 5));
      final action = await harness.run('schedule.change', {
        'schedule_id': schedule.id,
        'if_revision': schedule.revision,
        'event_title': '老师调整考试时间',
        'event_body': '改到下周',
        'event_occurred_at': now.toIso8601String(),
        'new_start': changedStart.toIso8601String(),
        'idempotency_key': 'change-exam-date',
      }, createdAt: now);
      final updated = await harness.tables.readEntry(schedule.id);
      final notice = await harness.tables.readEntry(action.relatedEntryId!);
      expect(action.status, TableChatActionStatus.applied);
      expect(updated!.start, changedStart);
      expect(notice!.type, TableContentType.event);
      expect(notice.title, '老师调整考试时间');
      expect(notice.affects.single.scheduleId, schedule.id);
      await harness.close();
    },
  );

  test(
    'same schedule notice reuses its receipt after the schedule moves tables',
    () async {
      final harness = await _Harness.create(
        aiPolicy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
      );
      addTearDown(harness.close);
      final sourceTable = harness.tables.tables.singleWhere(
        (table) => table.role == TableRole.inboxSchedule,
      );
      final destinationTable = await harness.tables.createTable(title: '期中考试');
      final now = DateTime.parse('2026-11-05T09:00:00+08:00');
      final schedule = await harness.tables.createEntry(
        TableEntryDocument(
          id: 'sc_cross_table_retry',
          type: TableContentType.schedule,
          tableId: sourceTable.id,
          title: '期中考试',
          revision: 1,
          createdAt: now,
          updatedAt: now,
          body: '',
          start: now.add(const Duration(days: 5)),
        ),
      );
      final changedStart = DateTime.parse('2026-11-12T14:00:00+08:00');
      final payload = {
        'schedule_id': schedule.id,
        'if_revision': schedule.revision,
        'event_title': '老师调整了期中考试时间',
        'event_body': '考试改至下周四下午。',
        'event_occurred_at': now.toIso8601String(),
        'new_start': changedStart.toIso8601String(),
        'new_end': null,
        'idempotency_key': 'model-randomized-key-1',
      };

      final first = await harness.run(
        'schedule.change',
        payload,
        createdAt: now,
      );
      final changed = await harness.tables.readEntry(schedule.id);
      final moved = await harness.tables.moveEntry(
        id: schedule.id,
        tableId: destinationTable.id,
        expectedRevision: changed!.revision,
      );
      final second = await harness.run('schedule.change', {
        ...payload,
        'if_revision': moved.revision,
        'idempotency_key': 'model-randomized-key-2',
      }, createdAt: now.add(const Duration(minutes: 1)));

      expect(first.status, TableChatActionStatus.applied);
      expect(second.status, TableChatActionStatus.applied);
      expect(second.id, isNot(first.id));
      expect(second.relatedEntryId, first.relatedEntryId);
      expect(second.tableId, destinationTable.id);
      expect(
        (await harness.tables.readEntry(schedule.id))!.tableId,
        destinationTable.id,
      );
      expect(
        (await harness.tables.readEntry(first.relatedEntryId!))!.tableId,
        sourceTable.id,
      );
      expect(
        harness.tables.entries
            .where((entry) => entry.type == TableContentType.event)
            .where(
              (entry) => entry.affects.any(
                (change) => change.scheduleId == schedule.id,
              ),
            ),
        hasLength(1),
      );
      final missingOccurrence = await harness.run('schedule.change', {
        ...payload,
        'if_revision': (await harness.tables.readEntry(schedule.id))!.revision,
        'event_occurred_at': 'not-a-date',
      }, createdAt: now.add(const Duration(minutes: 3)));
      expect(missingOccurrence.status, TableChatActionStatus.failed);
      expect(missingOccurrence.message, contains('日期时间格式无效'));
      expect((await harness.tables.readEntry(schedule.id))!.revision, 3);
      final conflicting = await harness.run('schedule.change', {
        ...payload,
        'if_revision': (await harness.tables.readEntry(schedule.id))!.revision,
        'new_start': DateTime.parse('2026-11-14T14:00:00+08:00')
            .toIso8601String(),
      }, createdAt: now.add(const Duration(minutes: 2)));
      expect(conflicting.status, TableChatActionStatus.failed);
      expect(conflicting.message, contains('核对'));
      expect((await harness.tables.readEntry(schedule.id))!.revision, 3);
      expect(
        harness.tables.entries
            .where((entry) => entry.type == TableContentType.event)
            .where(
              (entry) => entry.affects.any(
                (change) => change.scheduleId == schedule.id,
              ),
            ),
        hasLength(1),
      );
    },
  );

  test(
    'content create reuses the same exact item across user messages',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final table = await harness.tables.createTable(title: '课程事项');
      final now = DateTime.parse('2026-11-03T09:00:00+08:00');

      final first = await harness.run('content.create', {
        'table_id': table.id,
        'type': 'note',
        'title': '固定复习内容',
        'body': '第二章与第三章',
        'tags': ['复习'],
        'idempotency_key': 'legacy-message-one',
      }, createdAt: now);
      final second = await harness.run('content.create', {
        'table_id': table.id,
        'type': 'note',
        'title': '固定复习内容',
        'body': '第二章与第三章',
        'tags': ['复习'],
        'idempotency_key': 'legacy-message-two',
      }, createdAt: now.add(const Duration(minutes: 1)));

      expect(first.status, TableChatActionStatus.applied);
      expect(
        first.entryId,
        'nt_${first.id.substring(4)}',
        reason: '应继续使用稳定的旧入口 ID 派生规则。',
      );
      expect(second.status, TableChatActionStatus.applied);
      expect(second.entryId, first.entryId);
      expect(second.message, contains('复用'));
      expect(second.undoUntil, isNull);
      expect(
        await harness.tables.searchEntries(
          query: '',
          tableId: table.id,
          limit: 100,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'saved action receipt replays before processing content again',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final table = await harness.tables.createTable(title: '回执');
      final first = await harness.run('content.create', {
        'table_id': table.id,
        'type': 'note',
        'title': '只写入一次',
        'body': '正文',
        'idempotency_key': 'replay-action',
      }, createdAt: DateTime.parse('2026-11-03T10:00:00+08:00'));

      final replayProcessor = TableActionProcessor(
        chatRepository: harness.chats,
        tables: harness.tables,
        policyResolver: (_) => throw StateError('策略存储损坏'),
      );
      final replayed = await harness.replayLastWith(replayProcessor);

      expect(replayed.toJson(), first.toJson());
      expect(
        harness.tables.entries.where((entry) => entry.title == '只写入一次'),
        hasLength(1),
      );
    },
  );

  test(
    'full access executes structure while standard remains pending',
    () async {
      final standard = await _Harness.create(
        aiPolicy: AiPolicy.forPreset(AiPolicyPreset.standard),
      );
      addTearDown(standard.close);
      final pending = await standard.run('table.propose', {
        'operation': 'create',
        'payload': {'title': '标准确认表'},
        'idempotency_key': 'standard-structure',
      }, createdAt: DateTime.parse('2026-11-03T11:00:00+08:00'));
      expect(pending.status, TableChatActionStatus.pendingConfirmation);
      expect(standard.tables.findTable(pending.tableId!), isNull);

      final full = await _Harness.create(
        aiPolicy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
      );
      addTearDown(full.close);
      final applied = await full.run('table.propose', {
        'operation': 'create',
        'payload': {'title': '全权限直接表'},
        'idempotency_key': 'full-structure',
      }, createdAt: DateTime.parse('2026-11-03T11:01:00+08:00'));
      expect(applied.status, TableChatActionStatus.applied);
      expect(full.tables.findTable(applied.tableId!)!.title, '全权限直接表');
      final preconfigured = full.tables.tables.singleWhere(
        (table) => table.role == TableRole.inboxTodo,
      );
      final defaultDeleted = await full.run('table.propose', {
        'operation': 'delete',
        'table_id': preconfigured.id,
        'expected_revision': preconfigured.revision,
        'payload': {},
        'idempotency_key': 'full-access-default-delete',
      }, createdAt: DateTime.parse('2026-11-03T11:02:00+08:00'));
      expect(defaultDeleted.status, TableChatActionStatus.applied);
      expect(defaultDeleted.recoveryBatchId, isNotNull);
      expect(full.tables.findTable(preconfigured.id), isNull);
    },
  );

  test('inbox assignment rechecks allow at commit and can resume only after confirmation', () async {
    var policy = AiPolicy.forPreset(AiPolicyPreset.fullAccess);
    final harness = await _Harness.create(
      aiPolicy: policy,
      policyResolver: (_) => policy,
    );
    addTearDown(harness.close);
    final source = harness.tables.inboxAssignments.targetFor(
      InboxAssignmentKind.todo,
    )!;
    final target = await harness.tables.createTable(title: '待办目标');
    var resolutionCount = 0;
    final revokingProcessor = TableActionProcessor(
      chatRepository: harness.chats,
      tables: harness.tables,
      policyResolver: (_) {
        resolutionCount++;
        return resolutionCount == 1
            ? AiPolicy.forPreset(AiPolicyPreset.fullAccess)
            : AiPolicy.forPreset(AiPolicyPreset.readOnly);
      },
    );
    final pending = await harness.runWith(revokingProcessor, 'table.propose', {
      'operation': 'assign_inbox_target',
      'table_id': target.id,
      'expected_revision': 0,
      'payload': {'kind': 'todo', 'expected_current_table_id': source},
      'idempotency_key': 'revoked-inbox-target',
    }, createdAt: DateTime(2026, 11, 5));

    expect(pending.status, TableChatActionStatus.pendingConfirmation);
    expect(
      harness.tables.inboxAssignments.targetFor(InboxAssignmentKind.todo),
      source,
    );
    expect(await harness.tables.pendingInboxAssignmentOperationId(), isNull);

    policy = AiPolicy.forPreset(AiPolicyPreset.standard);
    final confirmed = await harness.processor.confirmStructure(pending);
    expect(confirmed.status, TableChatActionStatus.applied);
    expect(
      harness.tables.inboxAssignments.targetFor(InboxAssignmentKind.todo),
      target.id,
    );
    await harness.processor.acknowledgeInboxAssignmentOperation(confirmed);
    expect(await harness.tables.pendingInboxAssignmentOperationId(), isNull);
  });

  test('journal reconciliation requires a persisted applied action', () async {
    final harness = await _Harness.create();
    addTearDown(harness.close);
    final source = harness.tables.inboxAssignments.targetFor(
      InboxAssignmentKind.todo,
    )!;
    final target = await harness.tables.createTable(title: '待核对目标');
    final assignments = await harness.tables.readInboxAssignments();
    const operationId = 'act_missing_persisted_action';
    await harness.tables.assignInboxTargetForOperation(
      operationId: operationId,
      kind: InboxAssignmentKind.todo,
      expectedRevision: assignments.revision,
      expectedPreviousTableId: source,
      tableId: target.id,
      authorizationGuard: () async => true,
    );

    await harness.processor.reconcileInboxAssignmentJournal();

    expect(
      await harness.tables.pendingInboxAssignmentOperationId(),
      operationId,
    );
  });

  test(
    'inbox assignment rejects either target outside selected scope',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final source = harness.tables.inboxAssignments.targetFor(
        InboxAssignmentKind.todo,
      )!;
      final target = await harness.tables.createTable(title: '受限目标');
      final before = await harness.tables.readInboxAssignments();

      for (final allowedIds in [
        <String>{source},
        <String>{target.id},
      ]) {
        await harness.chats.setAiPolicy(
          harness.conversationId,
          AiPolicy.custom(
            tableScope: AiResourceScope.selected(allowedIds),
            decisions: const {
              AiPermissionAction.inboxTargetAdjust: AiPolicyDecision.allow,
            },
          ),
        );
        final rejected = await harness.run('table.propose', {
          'operation': 'assign_inbox_target',
          'table_id': target.id,
          'expected_revision': before.revision,
          'payload': {'kind': 'todo', 'expected_current_table_id': source},
          'idempotency_key': 'out-of-scope-${allowedIds.single}',
        }, createdAt: DateTime(2026, 11, 5, allowedIds.length));

        expect(rejected.status, TableChatActionStatus.failed);
        expect(rejected.message, isNot(contains(source)));
        expect(rejected.message, isNot(contains(target.id)));
        expect(await harness.tables.readInboxAssignments(), before);
        expect(
          await harness.tables.pendingInboxAssignmentOperationId(),
          isNull,
        );
      }

      await harness.chats.setAiPolicy(
        harness.conversationId,
        AiPolicy.custom(
          tableScope: const AiResourceScope.all(),
          decisions: const {
            AiPermissionAction.inboxTargetAdjust: AiPolicyDecision.deny,
          },
        ),
      );
      final denied = await harness.run('table.propose', {
        'operation': 'assign_inbox_target',
        'table_id': target.id,
        'expected_revision': before.revision,
        'payload': {'kind': 'todo', 'expected_current_table_id': source},
        'idempotency_key': 'denied-inbox-target',
      }, createdAt: DateTime(2026, 11, 5, 0, 1));
      expect(denied.status, TableChatActionStatus.failed);
      expect(denied.message, isNot(contains(source)));
      expect(denied.message, isNot(contains(target.id)));
      expect(await harness.tables.readInboxAssignments(), before);
      expect(await harness.tables.pendingInboxAssignmentOperationId(), isNull);
    },
  );

  test('selected table scope blocks new tables at execution', () async {
    final harness = await _Harness.create(
      aiPolicy: AiPolicy.custom(
        tableScope: AiResourceScope.selected(const ['tb_existing']),
        decisions: const {
          AiPermissionAction.tableCreate: AiPolicyDecision.allow,
        },
      ),
    );
    addTearDown(harness.close);
    final existing = harness.tables.tables.map((table) => table.id).toSet();

    for (final scope in [
      AiResourceScope.selected(const ['tb_existing']),
      const AiResourceScope.none(),
    ]) {
      await harness.chats.setAiPolicy(
        harness.conversationId,
        AiPolicy.custom(
          tableScope: scope,
          decisions: const {
            AiPermissionAction.tableCreate: AiPolicyDecision.allow,
          },
        ),
      );
      final rejected = await harness.run('table.propose', {
        'operation': 'create',
        'payload': {'title': '不应创建'},
        'idempotency_key': 'restricted-scope-create-${scope.kind.wireName}',
      }, createdAt: DateTime(2026, 11, 5, 0, 2));

      expect(rejected.status, TableChatActionStatus.failed);
      expect(harness.tables.tables.map((table) => table.id).toSet(), existing);
    }
  });

  test(
    'structure confirmation rechecks the effective conversation policy',
    () async {
      final harness = await _Harness.create(
        aiPolicy: AiPolicy.forPreset(AiPolicyPreset.standard),
      );
      addTearDown(harness.close);
      final pending = await harness.run('table.propose', {
        'operation': 'create',
        'payload': {'title': '撤销授权后的表'},
        'idempotency_key': 'revoked-structure',
      }, createdAt: DateTime.parse('2026-11-03T11:03:00+08:00'));
      await harness.chats.setAiPolicy(
        harness.conversationId,
        AiPolicy.forPreset(AiPolicyPreset.readOnly),
      );

      final denied = await harness.processor.confirmStructure(pending);

      expect(denied.status, TableChatActionStatus.failed);
      expect(harness.tables.findTable(pending.tableId!), isNull);
    },
  );
}

class _RevokingDuplicateSource implements SemanticDuplicateDecisionSource {
  _RevokingDuplicateSource(this.revoke);
  final Future<void> Function() revoke;

  @override
  Future<SemanticDuplicateDecision> decide(
    SemanticDuplicateRequest request,
  ) async {
    await revoke();
    final candidate = request.candidates.first;
    return SemanticDuplicateDecision(
      action: SemanticDuplicateAction.augment,
      targetId: candidate.entry.id,
      expectedRevision: candidate.entry.revision,
      evidence: candidate.signal
          .sharedVerifiableSemanticEvidenceWith(request.signal)
          .toList(),
      bodyAddition: '新增事实',
    );
  }
}

class _Harness {
  _Harness({
    required this.chats,
    required this.tables,
    required this.processor,
    required this.conversationId,
  });

  final ChatRepository chats;
  final TableLibrary tables;
  final TableActionProcessor processor;
  final String conversationId;
  var _turn = 0;
  String? _lastAssistantId;
  String? _lastToolName;
  Map<String, Object?>? _lastArguments;

  static Future<_Harness> create({
    AiPermissions permissions = const AiPermissions(),
    AiPolicy? aiPolicy,
    SemanticDuplicateDecisionSource? semanticDuplicateDecisionSource,
    AiPolicy Function(Conversation conversation)? policyResolver,
  }) async {
    final chats = ChatRepository(
      store: MemoryConversationStore(),
      attachments: MemoryAttachmentStore(),
    );
    await chats.initialize();
    final conversation = await chats.createConversation(
      aiPermissions: permissions,
      aiPolicy: aiPolicy,
      createdAt: DateTime(2026, 10, 30),
    );
    final tables = TableLibrary(
      repository: TableRepository(
        vault: MemoryVaultStore(),
        index: MemoryIndexDatabase(),
      ),
    );
    await tables.initialize();
    return _Harness(
      chats: chats,
      tables: tables,
      conversationId: conversation.id,
      processor: TableActionProcessor(
        chatRepository: chats,
        tables: tables,
        semanticDuplicateDecisionSource: semanticDuplicateDecisionSource,
        policyResolver: policyResolver,
      ),
    );
  }

  Future<TableChatAction> run(
    String name,
    Map<String, Object?> arguments, {
    required DateTime createdAt,
  }) async {
    final userId = 'msg_table_user_${_turn++}';
    final assistantId = 'msg_table_assistant_${_turn++}';
    _lastAssistantId = assistantId;
    _lastToolName = name;
    _lastArguments = Map.unmodifiable(arguments);
    await chats.saveMessage(
      ChatMessage(
        id: userId,
        conversationId: conversationId,
        role: ChatRole.user,
        content: '测试工具 $name',
        status: ChatMessageStatus.complete,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await chats.saveMessage(
      ChatMessage(
        id: assistantId,
        conversationId: conversationId,
        role: ChatRole.assistant,
        content: '',
        status: ChatMessageStatus.streaming,
        createdAt: createdAt.add(const Duration(milliseconds: 1)),
        updatedAt: createdAt.add(const Duration(milliseconds: 1)),
      ),
    );
    final call = ToolCallAccumulator()
      ..index = 0
      ..id = 'call_$_turn'
      ..name = name
      ..arguments.write(jsonEncode(arguments));
    final actions = await processor.processToolCalls(assistantId, [
      call,
    ], completedAt: createdAt);
    expect(actions, hasLength(1));
    final assistant = (await chats.findMessage(assistantId))!;
    await chats.saveMessage(assistant.copyWith(tableActions: actions));
    return actions.single;
  }

  Future<TableChatAction> replayLastWith(
    TableActionProcessor replayProcessor,
  ) async {
    final assistantId = _lastAssistantId;
    final name = _lastToolName;
    final arguments = _lastArguments;
    if (assistantId == null || name == null || arguments == null) {
      throw StateError('没有可重放的工具调用。');
    }
    final call = ToolCallAccumulator()
      ..index = 0
      ..id = 'call_replay'
      ..name = name
      ..arguments.write(jsonEncode(arguments));
    final actions = await replayProcessor.processToolCalls(assistantId, [call]);
    expect(actions, hasLength(1));
    return actions.single;
  }

  Future<TableChatAction> runWith(
    TableActionProcessor processor,
    String name,
    Map<String, Object?> arguments, {
    required DateTime createdAt,
  }) async {
    final userId = 'msg_table_user_${_turn++}';
    final assistantId = 'msg_table_assistant_${_turn++}';
    _lastAssistantId = assistantId;
    _lastToolName = name;
    _lastArguments = Map.unmodifiable(arguments);
    await chats.saveMessage(
      ChatMessage(
        id: userId,
        conversationId: conversationId,
        role: ChatRole.user,
        content: '测试工具 $name',
        status: ChatMessageStatus.complete,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
    await chats.saveMessage(
      ChatMessage(
        id: assistantId,
        conversationId: conversationId,
        role: ChatRole.assistant,
        content: '',
        status: ChatMessageStatus.streaming,
        createdAt: createdAt.add(const Duration(milliseconds: 1)),
        updatedAt: createdAt.add(const Duration(milliseconds: 1)),
      ),
    );
    final call = ToolCallAccumulator()
      ..index = 0
      ..id = 'call_$_turn'
      ..name = name
      ..arguments.write(jsonEncode(arguments));
    final actions = await processor.processToolCalls(assistantId, [call]);
    expect(actions, hasLength(1));
    final assistant = (await chats.findMessage(assistantId))!;
    await chats.saveMessage(assistant.copyWith(tableActions: actions));
    return actions.single;
  }

  Future<void> close() async {
    await chats.close();
  }
}
