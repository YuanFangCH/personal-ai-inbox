import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/modules/conversation/local_retrieval.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';

void main() {
  late ChatRepository chats;
  late ResultRepository repository;
  late ResultLibrary results;
  late Conversation current;
  late Conversation history;
  late ResultDocument ordinary;
  late ResultDocument global;

  setUp(() async {
    final store = MemoryConversationStore();
    chats = ChatRepository(store: store, attachments: MemoryAttachmentStore());
    await chats.initialize();
    final now = DateTime(2026, 10, 20, 10);
    current = await chats.createConversation(createdAt: now);
    history = await chats.createConversation(
      createdAt: now.subtract(const Duration(days: 2)),
    );
    await chats.saveMessage(
      ChatMessage(
        id: 'msg_old_semester',
        conversationId: history.id,
        role: ChatRole.user,
        content: '秋季学期从九月一日开始，共有十六周。',
        status: ChatMessageStatus.complete,
        createdAt: history.createdAt,
        updatedAt: history.updatedAt,
      ),
    );
    repository = ResultRepository(
      vault: MemoryVaultStore(),
      index: MemoryIndexDatabase(),
      deviceId: 'retrieval-test',
    );
    results = ResultLibrary(repository: repository);
    await results.initialize();
    ordinary = await results.createManual(
      type: ResultType.knowledge,
      title: '课程资料',
      body: '课堂地点在教学楼二层。',
    );
    final candidate = await results.proposeGlobalKnowledgeChange(
      operation: GlobalKnowledgeOperation.create,
      candidateId: 'gkc_retrieval_semester',
      proposal: const {
        'title': '秋季学期',
        'body': '起始日和周数用于计算教学周。',
        'facts': {'semester_start': '2026-09-01', 'week_count': 16},
      },
    );
    global = (await results.confirmGlobalKnowledgeChange(
      candidate.id,
      displayedDigest: candidate.digest,
    )).document;
  });

  test('read disabled performs no searches or external reads', () async {
    final retrieval = LocalRetrieval(
      conversationId: current.id,
      permissions: const AiPermissions(read: false),
      chats: chats,
      results: results,
    );
    expect(
      jsonMap(await retrieval.searchResults(query: '课程資料'))['error'],
      contains('读取权限'),
    );
    expect(
      jsonMap(await retrieval.searchOtherConversations('十六周'))['error'],
      contains('读取权限'),
    );
    expect(
      jsonMap(await retrieval.readResult(global.id))['error'],
      contains('读取权限'),
    );
    expect(retrieval.searchCalls, 0);
    expect(retrieval.detailCalls, 0);
  });

  test(
    'retrieval is bounded, deduplicated, scoped and reports source versions',
    () async {
      final retrieval = LocalRetrieval(
        conversationId: current.id,
        permissions: const AiPermissions(),
        chats: chats,
        results: results,
      );
      final facts = jsonMap(
        await retrieval.searchResults(query: '秋季学期', globalKnowledgeOnly: true),
      );
      final hits = facts['hits'] as List;
      expect(hits, hasLength(1));
      expect((hits.single as Map)['id'], global.id);
      expect((hits.single as Map)['snippet'], contains('week_count'));

      final historyHits = jsonMap(
        await retrieval.searchOtherConversations('十六周'),
      );
      expect(historyHits['hits'], hasLength(1));
      final messageId =
          ((historyHits['hits'] as List).single as Map)['message_id'];
      final message = jsonMap(
        await retrieval.readOtherConversationMessage(messageId as String),
      );
      expect(message['conversation_id'], history.id);
      expect(message['content'], contains('十六周'));

      final detail = jsonMap(await retrieval.readResult(ordinary.id));
      expect(detail['revision'], ordinary.revision);
      expect(detail['content'], contains('教学楼'));
      expect(retrieval.searchCalls, 2);
      expect(retrieval.detailCalls, 2);
      expect(
        retrieval.resultChars,
        lessThanOrEqualTo(LocalRetrieval.maxTurnChars),
      );

      final repeated = await retrieval.searchOtherConversations('十六周');
      expect(retrieval.searchCalls, 3);
      expect(jsonMap(repeated)['error'], contains('搜索次数上限'));
      expect(
        jsonMap(await retrieval.searchResults(query: '新范围'))['error'],
        contains('搜索次数上限'),
      );
    },
  );

  test(
    'details stop at three objects and each excerpt has a hard bound',
    () async {
      final retrieval = LocalRetrieval(
        conversationId: current.id,
        permissions: const AiPermissions(),
        chats: chats,
        results: results,
      );
      for (var index = 0; index < 3; index++) {
        expect(
          jsonMap(await retrieval.readResult(ordinary.id))['content'],
          isA<String>(),
        );
      }
      expect(
        jsonMap(await retrieval.readResult(ordinary.id))['error'],
        contains('详情读取上限'),
      );
      expect(retrieval.detailCalls, 3);
    },
  );
}

Map<String, dynamic> jsonMap(String value) =>
    Map<String, dynamic>.from(jsonDecode(value) as Map);
