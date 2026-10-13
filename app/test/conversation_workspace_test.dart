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

  test(
    'replays a completed model response after a restart without a request',
    () async {
      final now = DateTime(2026, 10, 13, 10);
      final settings = FakeSettingsService();
      final vault = MemoryVaultStore();
      final index = MemoryIndexDatabase();
      final resultRepository = ResultRepository(
        vault: vault,
        index: index,
        deviceId: 'test-device',
      );
      await resultRepository.initialize();
      final results = ResultLibrary(repository: resultRepository);
      await results.initialize();
      final captures = CaptureWorkflow(
        repository: resultRepository,
        results: results,
        indexDatabase: index,
        captureService: CaptureService(
          settings: settings,
          parser: const DeterministicParser(),
        ),
      );
      await captures.initialize();
      final store = MemoryConversationStore();
      final chatRepository = ChatRepository(
        store: store,
        attachments: MemoryAttachmentStore(),
      );
      await chatRepository.initialize();
      final conversation = await chatRepository.createConversation(
        createdAt: now,
      );
      final user = ChatMessage(
        id: 'msg_recovery_user',
        conversationId: conversation.id,
        role: ChatRole.user,
        content: '存储这条知识',
        status: ChatMessageStatus.complete,
        createdAt: now,
        updatedAt: now,
      );
      final assistant = ChatMessage(
        id: 'msg_recovery_assistant',
        conversationId: conversation.id,
        role: ChatRole.assistant,
        content: '结论已整理',
        status: ChatMessageStatus.streaming,
        createdAt: now.add(const Duration(seconds: 1)),
        updatedAt: now.add(const Duration(seconds: 1)),
      );
      await chatRepository.saveMessage(user);
      await chatRepository.saveMessage(assistant);
      await chatRepository.saveGeneration(
        GenerationRun(
          assistantMessageId: assistant.id,
          conversationId: conversation.id,
          userMessageId: user.id,
          status: GenerationStatus.responseReady,
          responseText: '结论已整理',
          toolCalls: const [
            {
              'index': '0',
              'id': 'call_recovery',
              'name': 'create_result',
              'arguments': '{"type":"knowledge","title":"恢复知识","body":"完整模型响应","confidence":0.95,"sensitive":false}',
            },
          ],
          createdAt: assistant.createdAt,
          updatedAt: assistant.updatedAt,
        ),
      );
      var outboundRequests = 0;
      final model = ModelClient(
        client: MockClient.streaming((request, bodyStream) async {
          outboundRequests++;
          await bodyStream.toBytes();
          return http.StreamedResponse(const Stream.empty(), 400);
        }),
      );
      final workspace = ConversationWorkspace(
        repository: chatRepository,
        results: results,
        chatService: ChatService(
          settings: settings,
          repository: chatRepository,
          modelClient: model,
        ),
        autoRecordProcessor: AutoRecordProcessor(
          chatRepository: chatRepository,
          results: results,
          captures: captures,
          deviceId: () => 'test-device',
        ),
      );

      await workspace.initialize();

      expect(outboundRequests, 0);
      expect(results.documents, hasLength(1));
      expect(results.documents.single.title, '恢复知识');
      expect(
        workspace.messagesFor(conversation.id).isEmpty,
        isTrue,
        reason: 'startup refresh keeps the message load lazy',
      );
      final recovered = await chatRepository.findMessage(assistant.id);
      expect(recovered?.status, ChatMessageStatus.complete);
      expect(recovered?.content, '结论已整理');
      expect(recovered?.actions.single.resultId, results.documents.single.id);
      expect(
        (await chatRepository.findGeneration(assistant.id))?.status,
        GenerationStatus.completed,
      );

      final completedGeneration = (await chatRepository.findGeneration(
        assistant.id,
      ))!;
      final completedAssistant = (await chatRepository.findMessage(
        assistant.id,
      ))!;
      await chatRepository.saveGeneration(
        completedGeneration.copyWith(
          status: GenerationStatus.responseReady,
          updatedAt: DateTime.now(),
        ),
      );
      await chatRepository.saveMessage(
        completedAssistant.copyWith(
          status: ChatMessageStatus.streaming,
          actions: const [],
          updatedAt: DateTime.now(),
        ),
      );
      await workspace.initialize();

      expect(results.documents, hasLength(1));
      expect(
        (await chatRepository.findMessage(assistant.id))!
            .actions
            .single
            .resultId,
        results.documents.single.id,
      );
      workspace.dispose();
      await chatRepository.close();
    },
  );

  test(
    'marks an unfinished network request interrupted without resending',
    () async {
      final now = DateTime(2026, 10, 13, 10);
      final settings = FakeSettingsService(modelKey: 'test-key');
      final vault = MemoryVaultStore();
      final index = MemoryIndexDatabase();
      final resultRepository = ResultRepository(
        vault: vault,
        index: index,
        deviceId: 'test-device',
      );
      await resultRepository.initialize();
      final results = ResultLibrary(repository: resultRepository);
      await results.initialize();
      final captures = CaptureWorkflow(
        repository: resultRepository,
        results: results,
        indexDatabase: index,
        captureService: CaptureService(
          settings: settings,
          parser: const DeterministicParser(),
        ),
      );
      await captures.initialize();
      final chatRepository = ChatRepository(
        store: MemoryConversationStore(),
        attachments: MemoryAttachmentStore(),
      );
      await chatRepository.initialize();
      final conversation = await chatRepository.createConversation(
        createdAt: now,
      );
      final user = ChatMessage(
        id: 'msg_interrupted_user',
        conversationId: conversation.id,
        role: ChatRole.user,
        content: '保留这条请求',
        status: ChatMessageStatus.complete,
        createdAt: now,
        updatedAt: now,
      );
      final assistant = ChatMessage(
        id: 'msg_interrupted_assistant',
        conversationId: conversation.id,
        role: ChatRole.assistant,
        content: '未完成的部分',
        status: ChatMessageStatus.streaming,
        createdAt: now.add(const Duration(seconds: 1)),
        updatedAt: now.add(const Duration(seconds: 1)),
      );
      await chatRepository.saveMessage(user);
      await chatRepository.saveMessage(assistant);
      await chatRepository.saveGeneration(
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
      var outboundRequests = 0;
      final workspace = ConversationWorkspace(
        repository: chatRepository,
        results: results,
        chatService: ChatService(
          settings: settings,
          repository: chatRepository,
          modelClient: ModelClient(
            client: MockClient.streaming((request, bodyStream) async {
              outboundRequests++;
              await bodyStream.toBytes();
              return http.StreamedResponse(const Stream.empty(), 400);
            }),
          ),
        ),
        autoRecordProcessor: AutoRecordProcessor(
          chatRepository: chatRepository,
          results: results,
          captures: captures,
          deviceId: () => 'test-device',
        ),
      );

      await workspace.initialize();

      expect(outboundRequests, 0);
      expect(
        (await chatRepository.findMessage(assistant.id))?.status,
        ChatMessageStatus.interrupted,
      );
      expect(
        (await chatRepository.findGeneration(assistant.id))?.status,
        GenerationStatus.interrupted,
      );
      expect(
        (await chatRepository.listMessages(conversation.id)).first.content,
        '保留这条请求',
      );
      workspace.dispose();
      await chatRepository.close();
    },
  );
}
