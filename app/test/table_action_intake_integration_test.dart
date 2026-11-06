import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/ai_policy.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
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
    'exact duplicate outside table scope does not disclose its receipt',
    () async {
      final harness = await _Harness.create(
        policy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
      );
      addTearDown(harness.close);
      final secret = await harness.tables.createTable(title: '受限');
      final allowed = await harness.tables.createTable(title: '允许');
      final first = await harness.run(
        _payload(secret.id, '同一内容', '输入原文', 'first'),
        createdAt: DateTime(2026, 11, 4, 10),
      );
      await harness.chats.setAiPolicy(
        harness.conversationId,
        AiPolicy.custom(
          tableScope: AiResourceScope.selected({allowed.id}),
          decisions: const {
            AiPermissionAction.contentCreate: AiPolicyDecision.allow,
            AiPermissionAction.contentRead: AiPolicyDecision.allow,
          },
        ),
      );
      final second = await harness.run(
        _payload(allowed.id, '同一内容', '输入原文', 'second'),
        createdAt: DateTime(2026, 11, 4, 10, 1),
      );
      expect(second.status, TableChatActionStatus.failed);
      expect(second.entryId, isNull);
      expect(second.tableId, isNull);
      expect(second.message, isNot(contains(first.entryId!)));
      expect(harness.tables.entries, hasLength(1));
    },
  );
  test('automatic intake supplement respects modify permission', () async {
    final denied = await _Harness.create(
      policy: AiPolicy.custom(
        tableScope: const AiResourceScope.all(),
        decisions: const {
          AiPermissionAction.contentCreate: AiPolicyDecision.allow,
          AiPermissionAction.contentUpdate: AiPolicyDecision.deny,
        },
      ),
    );
    addTearDown(denied.close);
    final deniedTable = await denied.tables.createTable(title: '权限拒绝');
    final deniedFirst = await denied.run(
      _payload(deniedTable.id, '修改权限', '原内容', 'denied-initial'),
      createdAt: DateTime.parse('2026-11-03T12:00:00+08:00'),
    );
    final deniedSecond = await denied.run(
      _payload(deniedTable.id, '修改权限', '原内容和新增内容', 'denied-later'),
      createdAt: DateTime.parse('2026-11-03T12:01:00+08:00'),
    );

    expect(deniedFirst.status, TableChatActionStatus.applied);
    expect(deniedSecond.status, TableChatActionStatus.failed);
    expect(deniedSecond.message, contains('修改权限'));
    final deniedEntry = await denied.tables.readEntry(deniedFirst.entryId!);
    expect(deniedEntry!.body, '原内容');
    expect(deniedEntry.revision, 1);

    final allowed = await _Harness.create(
      policy: AiPolicy.custom(
        tableScope: const AiResourceScope.all(),
        decisions: const {
          AiPermissionAction.contentCreate: AiPolicyDecision.allow,
          AiPermissionAction.contentUpdate: AiPolicyDecision.allow,
        },
      ),
    );
    addTearDown(allowed.close);
    final allowedTable = await allowed.tables.createTable(title: '权限允许');
    final allowedFirst = await allowed.run(
      _payload(allowedTable.id, '允许补充', '原内容', 'allowed-initial'),
      createdAt: DateTime.parse('2026-11-03T12:02:00+08:00'),
    );
    final allowedSecond = await allowed.run(
      _payload(allowedTable.id, '允许补充', '原内容和新增内容', 'allowed-later'),
      createdAt: DateTime.parse('2026-11-03T12:03:00+08:00'),
    );

    expect(allowedFirst.status, TableChatActionStatus.applied);
    expect(allowedSecond.status, TableChatActionStatus.applied);
    expect(allowedSecond.entryId, allowedFirst.entryId);
    expect(allowedSecond.message, contains('补充'));
    final allowedEntry = await allowed.tables.readEntry(allowedFirst.entryId!);
    expect(allowedEntry!.body, contains('原内容'));
    expect(allowedEntry.body, contains('新增内容'));
    expect(allowedEntry.revision, 2);
  });
}

Map<String, Object?> _payload(
  String tableId,
  String title,
  String body,
  String key,
) => {
  'table_id': tableId,
  'type': 'note',
  'title': title,
  'body': body,
  'idempotency_key': key,
};

class _AugmentSource implements SemanticDuplicateDecisionSource {
  @override
  Future<SemanticDuplicateDecision> decide(
    SemanticDuplicateRequest request,
  ) async {
    final candidate = request.candidates.single;
    final evidence =
        request.signal
            .sharedVerifiableSemanticEvidenceWith(candidate.signal)
            .toList()
          ..sort();
    return SemanticDuplicateDecision(
      action: SemanticDuplicateAction.augment,
      targetId: candidate.entry.id,
      expectedRevision: candidate.entry.revision,
      evidence: evidence,
      bodyAddition: '新增内容',
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

  static Future<_Harness> create({required AiPolicy policy}) async {
    final chats = ChatRepository(
      store: MemoryConversationStore(),
      attachments: MemoryAttachmentStore(),
    );
    await chats.initialize();
    final conversation = await chats.createConversation(
      aiPolicy: policy,
      createdAt: DateTime.parse('2026-11-03T11:59:00+08:00'),
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
        semanticDuplicateDecisionSource: _AugmentSource(),
      ),
    );
  }

  Future<TableChatAction> run(
    Map<String, Object?> arguments, {
    required DateTime createdAt,
  }) async {
    final userId = 'msg_intake_user_${_turn++}';
    final assistantId = 'msg_intake_assistant_${_turn++}';
    await chats.saveMessage(
      ChatMessage(
        id: userId,
        conversationId: conversationId,
        role: ChatRole.user,
        content: '新增内容',
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
      ..id = 'call_intake_$_turn'
      ..name = 'content.create'
      ..arguments.write(jsonEncode(arguments));
    final actions = await processor.processToolCalls(assistantId, [
      call,
    ], completedAt: createdAt);
    final assistant = (await chats.findMessage(assistantId))!;
    await chats.saveMessage(assistant.copyWith(tableActions: actions));
    return actions.single;
  }

  Future<void> close() => chats.close();
}
