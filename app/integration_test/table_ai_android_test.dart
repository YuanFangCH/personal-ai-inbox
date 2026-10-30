import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/calendar.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/io_vault_store.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/sqlite_index_database.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import '../test/test_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AI table write and confirmed table creation survive restart', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('table-ai-android');
    addTearDown(() => root.delete(recursive: true));
    final vaultPath = '${root.path}/vault';
    final indexPath = '${root.path}/index.sqlite3';
    final chats = MemoryConversationStore();
    final attachments = MemoryAttachmentStore();
    final responses = _ResponsePlan();
    final settings = FakeSettingsService(
      deviceId: 'table-ai-android',
      modelKey: 'local-test-key',
    );

    Future<AppRuntime> boot() async {
      final index = SqliteIndexDatabase(indexPath);
      await index.open();
      return AppRuntime.bootstrap(
        vaultOverride: IoVaultStore.at(Directory(vaultPath)),
        indexOverride: index,
        conversationStoreOverride: chats,
        attachmentStoreOverride: attachments,
        settingsOverride: settings,
        modelClient: ModelClient(
          client: MockClient.streaming((request, body) async {
            expect(request.url.path, endsWith('/chat/completions'));
            return responses.next();
          }),
        ),
      );
    }

    var runtime = await boot();
    final homework = await runtime.tables.createTable(title: '作业表');
    final conversation = await runtime.conversations.createConversation();
    responses.contentTableId = homework.id;
    await runtime.conversations.sendChatMessage(
      conversation.id,
      text: '把实验报告要求记到作业表',
    );
    final note = runtime.tables.entries.singleWhere(
      (entry) => entry.title == '实验报告要求',
    );
    expect(note.tableId, homework.id);
    expect(note.type, TableContentType.note);
    final contentAction = runtime.conversations
        .messagesFor(conversation.id)
        .last
        .tableActions
        .single;
    expect(contentAction.status, TableChatActionStatus.applied);

    await runtime.conversations.sendChatMessage(conversation.id, text: '新建考试表');
    final structureAction = runtime.conversations
        .messagesFor(conversation.id)
        .last
        .tableActions
        .single;
    expect(structureAction.status, TableChatActionStatus.pendingConfirmation);
    expect(runtime.tables.tables.any((table) => table.title == '考试表'), isFalse);
    await runtime.conversations.confirmTableStructureAction(structureAction.id);
    expect(runtime.tables.tables.any((table) => table.title == '考试表'), isTrue);

    final examTable = runtime.tables.tables.singleWhere(
      (table) => table.title == '考试表',
    );
    final originalStart = DateTime.now().add(const Duration(days: 5));
    final schedule = await runtime.tables.createEntry(
      TableEntryDocument(
        id: 'android_exam_schedule',
        type: TableContentType.schedule,
        tableId: examTable.id,
        title: '期中考试',
        revision: 1,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        body: '信号与系统期中考试',
        start: originalStart,
        end: originalStart.add(const Duration(hours: 2)),
      ),
    );
    responses.scheduleId = schedule.id;
    final changedStart = DateTime.now().add(const Duration(days: 8));
    responses.changedStart = changedStart;
    await runtime.conversations.sendChatMessage(
      conversation.id,
      text: '老师把期中考试改期了',
    );
    final changeAction = runtime.conversations
        .messagesFor(conversation.id)
        .last
        .tableActions
        .single;
    expect(changeAction.operation, 'schedule.change');
    expect(changeAction.status, TableChatActionStatus.applied);
    final changedSchedule = runtime.tables.entries.singleWhere(
      (entry) => entry.id == schedule.id,
    );
    final notification = runtime.tables.entries.singleWhere(
      (entry) => entry.id == changeAction.relatedEntryId,
    );
    expect(changedSchedule.start, changedStart);
    expect(notification.type, TableContentType.event);
    expect(notification.affects.single.scheduleId, schedule.id);

    await runtime.preferences.update(
      calendarVisibleTableIds: [examTable.id],
      homeTableOrder: [examTable.id],
    );
    expect(runtime.preferences.settings.calendarVisibleTableIds, [
      examTable.id,
    ]);
    expect(runtime.preferences.settings.homeTableOrder, [examTable.id]);
    final calendarProjection = projectTableCalendarDocuments(
      tables: runtime.tables.tables,
      entries: runtime.tables.entries,
      visibleTableIds: runtime.preferences.settings.calendarVisibleTableIds,
    );
    expect(calendarProjection.map((entry) => entry.id), contains(schedule.id));
    expect(
      calendarProjection.map((entry) => entry.id),
      contains(notification.id),
    );
    final deleted = await runtime.tables.deleteTable(
      id: examTable.id,
      expectedRevision: examTable.revision,
      idempotencyKey: 'android-delete-exam-table',
    );
    await runtime.shutdown();

    runtime = await boot();
    expect(
      runtime.tables.entries
          .singleWhere((entry) => entry.title == '实验报告要求')
          .tableId,
      homework.id,
    );
    expect(runtime.tables.tables.any((table) => table.title == '考试表'), isFalse);
    expect(runtime.preferences.settings.calendarVisibleTableIds, [
      examTable.id,
    ]);
    expect(runtime.preferences.settings.homeTableOrder, [examTable.id]);
    final recoveryBatches = await runtime.tables.recoveryBatches();
    expect(recoveryBatches.any((batch) => batch.id == deleted.id), isTrue);
    await runtime.tables.restoreRecoveryBatch(deleted.id);
    expect(runtime.tables.tables.any((table) => table.title == '考试表'), isTrue);
    expect(
      runtime.tables.entries
          .singleWhere((entry) => entry.id == schedule.id)
          .start,
      changedStart,
    );
    expect(
      runtime.tables.entries.any((entry) => entry.id == notification.id),
      isTrue,
    );
    await runtime.shutdown();
  });
}

class _ResponsePlan {
  var calls = 0;
  String? contentTableId;
  String? scheduleId;
  DateTime? changedStart;

  Future<http.StreamedResponse> next() async {
    calls++;
    if (calls == 1) {
      return _stream({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call_android_content_create',
                  'function': {
                    'name': 'content.create',
                    'arguments': jsonEncode({
                      'table_id': contentTableId,
                      'type': 'note',
                      'title': '实验报告要求',
                      'body': '报告包含实验目标、过程和结论。',
                      'idempotency_key': 'android-content-create',
                    }),
                  },
                },
              ],
            },
          },
        ],
      }, finish: 'tool_calls');
    }
    if (calls == 2) {
      return _stream({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call_android_table_propose',
                  'function': {
                    'name': 'table.propose',
                    'arguments': jsonEncode({
                      'operation': 'create',
                      'payload': {'title': '考试表'},
                      'idempotency_key': 'android-table-create',
                    }),
                  },
                },
              ],
            },
          },
        ],
      }, finish: 'tool_calls');
    }
    if (calls == 3) {
      final start = changedStart!;
      return _stream({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call_android_schedule_change',
                  'function': {
                    'name': 'schedule.change',
                    'arguments': jsonEncode({
                      'schedule_id': scheduleId,
                      'if_revision': 1,
                      'event_title': '老师调整了考试日期',
                      'event_body': '考试改到新的日期。',
                      'event_occurred_at': DateTime.now().toIso8601String(),
                      'new_start': start.toIso8601String(),
                      'new_end': start
                          .add(const Duration(hours: 2))
                          .toIso8601String(),
                      'idempotency_key': 'android-schedule-change',
                    }),
                  },
                },
              ],
            },
          },
        ],
      }, finish: 'tool_calls');
    }
    throw StateError('Unexpected mock model request $calls');
  }
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
