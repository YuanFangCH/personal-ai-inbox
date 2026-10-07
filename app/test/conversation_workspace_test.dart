import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/modules/conversation/auto_record_processor.dart';
import 'package:personal_ai_inbox/modules/conversation/conversation_workspace.dart';
import 'package:personal_ai_inbox/modules/capture/capture_workflow.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';
import 'package:personal_ai_inbox/services/chat_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'test_support.dart';

void main() {
  test('creates a guarded result and supports undo', () async {
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    final settings = FakeSettingsService(modelKey: 'test-key');
    final results = ResultRepository(
      vault: vault,
      index: index,
      deviceId: 'test-device',
    );
    await results.initialize();
    final library = ResultLibrary(repository: results);
    await library.initialize();
    final capture = CaptureWorkflow(
      repository: results,
      results: library,
      indexDatabase: index,
      captureService: CaptureService(
        settings: settings,
        parser: const DeterministicParser(),
      ),
    );
    await capture.initialize();
    final chatRepository = ChatRepository(
      store: MemoryConversationStore(),
      attachments: MemoryAttachmentStore(),
    );
    final model = ModelClient(
      client: MockClient.streaming((request, bodyStream) async {
        final events = <String>[
          'data: {"choices":[{"delta":{"content":"已记录"}}]}\n\n',
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_test',
                      'function': {
                        'name': 'create_result',
                        'arguments': jsonEncode({'type': 'todo', 'title': '提交材料', 'body': '周五下午三点前提交', 'confidence': 0.94, 'sensitive': false}),
                      },
                    },
                  ],
                },
              },
            ],
          })}\n\n',
          'data: [DONE]\n\n',
        ];
        return http.StreamedResponse(
          Stream.fromIterable(events.map(utf8.encode)),
          200,
        );
      }),
    );
    final workspace = ConversationWorkspace(
      repository: chatRepository,
      results: library,
      chatService: ChatService(
        settings: settings,
        repository: chatRepository,
        modelClient: model,
      ),
      autoRecordProcessor: AutoRecordProcessor(
        chatRepository: chatRepository,
        results: library,
        captures: capture,
        deviceId: () => 'test-device',
      ),
    );
    await workspace.initialize();

    final conversation = await workspace.createConversation();
    await workspace.sendChatMessage(conversation.id, text: '记住周五提交材料');

    final message = workspace.messagesFor(conversation.id).last;
    expect(message.actions.single.status, AutoRecordStatus.created);
    expect(await results.listDocuments(), hasLength(1));

    await workspace.undoAutoRecord(message.actions.single.id);

    expect(await results.listDocuments(), isEmpty);
    expect(
      workspace.messagesFor(conversation.id).last.actions.single.status,
      AutoRecordStatus.undone,
    );
    workspace.dispose();
  });
}
