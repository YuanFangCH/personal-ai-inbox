import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
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

    Future<AppRuntime> boot() async {
      final index = SqliteIndexDatabase(indexPath);
      await index.open();
      return AppRuntime.bootstrap(
        vaultOverride: IoVaultStore.at(Directory(vaultPath)),
        indexOverride: index,
        conversationStoreOverride: chats,
        attachmentStoreOverride: attachments,
        settingsOverride: FakeSettingsService(
          deviceId: 'table-ai-android',
          modelKey: 'local-test-key',
        ),
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
    await runtime.shutdown();

    runtime = await boot();
    expect(
      runtime.tables.entries
          .singleWhere((entry) => entry.title == '实验报告要求')
          .tableId,
      homework.id,
    );
    expect(runtime.tables.tables.any((table) => table.title == '考试表'), isTrue);
    await runtime.shutdown();
  });
}

class _ResponsePlan {
  var calls = 0;
  String? contentTableId;

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
