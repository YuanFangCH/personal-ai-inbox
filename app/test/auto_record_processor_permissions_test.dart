import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
import 'package:personal_ai_inbox/modules/results/result_library.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';

import 'test_support.dart';

void main() {
  test(
    'direct result mutations recheck session permission and are undoable',
    () async {
      final settings = FakeSettingsService();
      final index = MemoryIndexDatabase();
      final repository = ResultRepository(
        vault: MemoryVaultStore(),
        index: index,
        deviceId: 'mutation-test',
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
      final chats = ChatRepository(
        store: MemoryConversationStore(),
        attachments: MemoryAttachmentStore(),
      );
      await chats.initialize();
      final conversation = await chats.createConversation(
        aiPermissions: const AiPermissions(modifyDelete: true),
        createdAt: DateTime(2026, 10, 20, 9),
      );
      final original = await results.createManual(
        type: ResultType.knowledge,
        title: '物理作业',
        body: '周三提交',
      );
      final processor = AutoRecordProcessor(
        chatRepository: chats,
        results: results,
        captures: captures,
        deviceId: () => 'mutation-test',
      );

      await _seedTurn(
        chats,
        conversation,
        'user_update',
        'assistant_update',
        1,
      );
      final updated = (await processor.processToolCalls('assistant_update', [
        _toolCall(0, 'update_result', {
          'id': original.id,
          'expected_revision': original.revision,
          'body': '周四提交',
        }),
      ], completedAt: DateTime(2026, 10, 20, 10))).single;
      expect(updated.status, AutoRecordStatus.created);
      expect(updated.undoUntil, isNotNull);
      expect((await results.readDocument(original.id))?.body, '周四提交');
      final committedRevision = (await results.readDocument(original.id))!
          .revision;
      final replayed = (await processor.processToolCalls('assistant_update', [
        _toolCall(0, 'update_result', {
          'id': original.id,
          'expected_revision': original.revision,
          'body': '周四提交',
        }),
      ], completedAt: DateTime(2026, 10, 20, 10))).single;
      expect(replayed.id, updated.id);
      expect(
        (await results.readDocument(original.id))!.revision,
        committedRevision,
      );
      await results.undoAction(updated.id);
      expect((await results.readDocument(original.id))?.body, '周三提交');

      await _seedTurn(
        chats,
        conversation,
        'user_delete',
        'assistant_delete',
        2,
      );
      final current = (await results.readDocument(original.id))!;
      final deleted = (await processor.processToolCalls('assistant_delete', [
        _toolCall(0, 'delete_result', {
          'id': current.id,
          'expected_revision': current.revision,
        }),
      ], completedAt: DateTime(2026, 10, 20, 11))).single;
      expect((await results.readDocument(original.id))?.deleted, isTrue);
      await results.undoAction(deleted.id);
      expect((await results.readDocument(original.id))?.deleted, isFalse);

      await _seedTurn(
        chats,
        conversation,
        'user_permission',
        'assistant_permission',
        3,
      );
      await chats.saveConversation(
        conversation.copyWith(
          aiPermissions: const AiPermissions(modifyDelete: false),
          updatedAt: DateTime(2026, 10, 20, 12),
        ),
      );
      final beforeDeniedCall = await results.readDocument(original.id);
      final denied = (await processor.processToolCalls('assistant_permission', [
        _toolCall(0, 'delete_result', {
          'id': original.id,
          'expected_revision': beforeDeniedCall!.revision,
        }),
      ])).single;
      expect(denied.status, AutoRecordStatus.skipped);
      expect((await results.readDocument(original.id))?.deleted, isFalse);
      await chats.close();
      await results.shutdown();
      results.dispose();
    },
  );
}

ToolCallAccumulator _toolCall(
  int index,
  String name,
  Map<String, Object?> payload,
) => ToolCallAccumulator()
  ..index = index
  ..id = 'call_$index'
  ..name = name
  ..arguments.write(jsonEncode(payload));

Future<void> _seedTurn(
  ChatRepository chats,
  Conversation conversation,
  String userId,
  String assistantId,
  int hour,
) async {
  final at = DateTime(2026, 10, 20, hour);
  await chats.saveMessage(
    ChatMessage(
      id: userId,
      conversationId: conversation.id,
      role: ChatRole.user,
      content: '请修改/删除物理作业。',
      status: ChatMessageStatus.complete,
      createdAt: at,
      updatedAt: at,
    ),
  );
  await chats.saveMessage(
    ChatMessage(
      id: assistantId,
      conversationId: conversation.id,
      role: ChatRole.assistant,
      content: '',
      status: ChatMessageStatus.complete,
      createdAt: at.add(const Duration(minutes: 1)),
      updatedAt: at.add(const Duration(minutes: 1)),
    ),
  );
}
