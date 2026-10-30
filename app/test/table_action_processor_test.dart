import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
import 'package:personal_ai_inbox/modules/conversation/table_action_processor.dart';
import 'package:personal_ai_inbox/modules/tables/table_library.dart';

void main() {
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

  test(
    'structure proposals wait for chat confirmation and protect defaults',
    () async {
      final harness = await _Harness.create();
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
      final denied = await harness.run('table.propose', {
        'operation': 'delete',
        'table_id': defaultTable.id,
        'expected_revision': defaultTable.revision,
        'payload': {},
        'idempotency_key': 'propose-default-delete',
      }, createdAt: now.add(const Duration(minutes: 2)));
      expect(denied.status, TableChatActionStatus.failed);
      expect(harness.tables.findTable(defaultTable.id), isNotNull);
      await harness.close();
    },
  );

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

  static Future<_Harness> create({
    AiPermissions permissions = const AiPermissions(),
  }) async {
    final chats = ChatRepository(
      store: MemoryConversationStore(),
      attachments: MemoryAttachmentStore(),
    );
    await chats.initialize();
    final conversation = await chats.createConversation(
      aiPermissions: permissions,
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
      processor: TableActionProcessor(chatRepository: chats, tables: tables),
    );
  }

  Future<TableChatAction> run(
    String name,
    Map<String, Object?> arguments, {
    required DateTime createdAt,
  }) async {
    final userId = 'msg_table_user_${_turn++}';
    final assistantId = 'msg_table_assistant_${_turn++}';
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

  Future<void> close() async {
    await chats.close();
  }
}
