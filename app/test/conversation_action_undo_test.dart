import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/modules/capture/capture_workflow.dart';
import 'package:personal_ai_inbox/modules/conversation/auto_record_processor.dart';
import 'package:personal_ai_inbox/modules/conversation/conversation_workspace.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';
import 'package:personal_ai_inbox/services/chat_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'test_support.dart';

void main() {
  test(
    'conversation undo restores updated and deleted results from ledger',
    () async {
      final settings = FakeSettingsService(modelKey: 'test-key');
      final index = MemoryIndexDatabase();
      final repository = ResultRepository(
        vault: MemoryVaultStore(),
        index: index,
        deviceId: 'chat-undo-test',
      );
      await repository.initialize();
      final results = ResultLibrary(repository: repository);
      await results.initialize();
      final captures = CaptureWorkflow(
        repository: repository,
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

      final updatedOriginal = await results.createManual(
        type: ResultType.knowledge,
        title: '作业截止时间',
        body: '周三提交',
      );
      final update = await results.modifyWithUndo(
        document: updatedOriginal.copyWith(body: '周四提交'),
        expectedRevision: updatedOriginal.revision,
        expectedHash: (await results.hashManagedDocument(updatedOriginal.id))!,
        actionId: 'chat_action_update',
      );

      final deletedOriginal = await results.createManual(
        type: ResultType.todo,
        title: '寄出资料',
        body: '保留原始待办',
      );
      final delete = await results.deleteWithUndo(
        id: deletedOriginal.id,
        expectedRevision: deletedOriginal.revision,
        expectedHash: (await results.hashManagedDocument(deletedOriginal.id))!,
        actionId: 'chat_action_delete',
      );

      final now = DateTime.now();
      final conversation = await chatRepository.createConversation(
        createdAt: now,
      );
      await chatRepository.saveMessage(
        ChatMessage(
          id: 'assistant_update',
          conversationId: conversation.id,
          role: ChatRole.assistant,
          content: '已修改成果。',
          status: ChatMessageStatus.complete,
          actions: [
            AutoRecordAction(
              id: 'chat_action_update',
              type: ResultType.knowledge,
              title: update.document.title,
              status: AutoRecordStatus.created,
              operation: AutoRecordOperation.update,
              resultId: update.document.id,
              createdAt: now,
              undoUntil: update.action.undoUntil,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );
      await chatRepository.saveMessage(
        ChatMessage(
          id: 'assistant_delete',
          conversationId: conversation.id,
          role: ChatRole.assistant,
          content: '已删除成果。',
          status: ChatMessageStatus.complete,
          actions: [
            AutoRecordAction(
              id: 'chat_action_delete',
              type: ResultType.todo,
              title: delete.document.title,
              status: AutoRecordStatus.created,
              operation: AutoRecordOperation.delete,
              resultId: delete.document.id,
              createdAt: now,
              undoUntil: delete.action.undoUntil,
            ),
          ],
          createdAt: now.add(const Duration(seconds: 1)),
          updatedAt: now.add(const Duration(seconds: 1)),
        ),
      );

      final workspace = ConversationWorkspace(
        repository: chatRepository,
        results: results,
        chatService: ChatService(
          settings: settings,
          repository: chatRepository,
          modelClient: ModelClient(
            client: MockClient((_) async => http.Response('', 500)),
          ),
        ),
        autoRecordProcessor: AutoRecordProcessor(
          chatRepository: chatRepository,
          results: results,
          captures: captures,
          deviceId: () => 'chat-undo-test',
        ),
        defaultPermissions: () => const AiPermissions(),
      );
      await workspace.initialize();

      await workspace.undoAutoRecord('chat_action_update');
      await workspace.undoAutoRecord('chat_action_delete');

      expect((await results.readDocument(updatedOriginal.id))?.body, '周三提交');
      expect(
        (await results.readDocument(deletedOriginal.id))?.deleted,
        isFalse,
      );
      final actions = workspace
          .messagesFor(conversation.id)
          .expand((message) => message.actions)
          .toList();
      expect(
        actions.map((action) => action.status),
        everyElement(AutoRecordStatus.undone),
      );

      await workspace.shutdown();
      workspace.dispose();
      await chatRepository.close();
      await results.shutdown();
      results.dispose();
    },
  );
}
