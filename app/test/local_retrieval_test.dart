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
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/data/table_repository.dart';
import 'package:personal_ai_inbox/modules/conversation/local_retrieval.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';
import 'package:personal_ai_inbox/modules/tables/table_library.dart';

void main() {
  late ChatRepository chats;
  late ResultRepository repository;
  late ResultLibrary results;
  late Conversation current;
  late Conversation history;
  late ResultDocument ordinary;
  late ResultDocument global;
  late TableLibrary tables;
  late TableDocument visibleTable;
  late TableDocument hiddenTable;
  late TableEntryDocument visibleEntry;
  late TableEntryDocument hiddenEntry;

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
      body: '课堂地点在教学楼二层。\n"实验课"使用东侧门。',
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
    tables = TableLibrary(
      repository: TableRepository(
        vault: MemoryVaultStore(),
        index: MemoryIndexDatabase(),
      ),
    );
    await tables.initialize();
    visibleTable = await tables.createTable(title: '可见课程');
    hiddenTable = await tables.createTable(title: '不可见课程');
    visibleEntry = await tables.createEntry(
      TableEntryDocument(
        id: 'nt_visible_scope',
        type: TableContentType.note,
        tableId: visibleTable.id,
        title: '可见笔记',
        revision: 1,
        createdAt: DateTime(2026, 11, 4),
        updatedAt: DateTime(2026, 11, 4),
        body: '可见正文',
      ),
    );
    hiddenEntry = await tables.createEntry(
      TableEntryDocument(
        id: 'nt_hidden_scope',
        type: TableContentType.note,
        tableId: hiddenTable.id,
        title: '隐藏笔记',
        revision: 1,
        createdAt: DateTime(2026, 11, 4),
        updatedAt: DateTime(2026, 11, 4),
        body: '不可泄漏正文',
      ),
    );
  });

  test('read disabled performs no searches or external reads', () async {
    final retrieval = LocalRetrieval(
      conversationId: current.id,
      permissions: const AiPermissions(read: false),
      chats: chats,
      results: results,
    );
    expect(
      jsonMap(await retrieval.searchResults(query: '课程資料'))['status'],
      'denied',
    );
    expect(
      jsonMap(await retrieval.searchOtherConversations('十六周'))['status'],
      'denied',
    );
    expect(jsonMap(await retrieval.readResult(global.id))['status'], 'denied');
    expect(retrieval.searchCalls, 0);
    expect(retrieval.detailCalls, 0);
  });

  test(
    'policy scopes filter tables, knowledge and conversation history',
    () async {
      final hiddenCandidate = await results.proposeGlobalKnowledgeChange(
        operation: GlobalKnowledgeOperation.create,
        candidateId: 'gkc_retrieval_hidden_semester',
        proposal: const {
          'title': '隐藏学期事实',
          'body': '这条学期事实不应出现在受限范围。',
          'facts': {'hidden': true},
        },
      );
      final hiddenGlobal = (await results.confirmGlobalKnowledgeChange(
        hiddenCandidate.id,
        displayedDigest: hiddenCandidate.digest,
      )).document;
      final hiddenHistory = await chats.createConversation(
        createdAt: DateTime(2026, 10, 17),
      );
      await chats.saveMessage(
        ChatMessage(
          id: 'msg_hidden_semester',
          conversationId: hiddenHistory.id,
          role: ChatRole.user,
          content: '隐藏会话也写了十六周。',
          status: ChatMessageStatus.complete,
          createdAt: hiddenHistory.createdAt,
          updatedAt: hiddenHistory.updatedAt,
        ),
      );
      final policy = AiPolicy.custom(
        decisions: const {
          AiPermissionAction.tableRead: AiPolicyDecision.allow,
          AiPermissionAction.contentRead: AiPolicyDecision.allow,
          AiPermissionAction.globalKnowledgeSearch: AiPolicyDecision.allow,
          AiPermissionAction.globalKnowledgeRead: AiPolicyDecision.allow,
          AiPermissionAction.conversationHistorySearch: AiPolicyDecision.allow,
          AiPermissionAction.conversationHistoryRead: AiPolicyDecision.allow,
        },
        tableScope: AiResourceScope.selected([visibleTable.id]),
        knowledgeReadScope: AiResourceScope.selected([global.id]),
        conversationHistoryReadScope: AiResourceScope.selected([history.id]),
      );
      final retrieval = LocalRetrieval(
        conversationId: current.id,
        policy: policy,
        chats: chats,
        results: results,
        tables: tables,
      );

      final catalog = jsonMap(await retrieval.listTables(limit: 50));
      expect(
        (jsonData(catalog)['hits'] as List).cast<Map>().map((hit) => hit['id']),
        contains(visibleTable.id),
      );
      expect(
        (jsonData(catalog)['hits'] as List).cast<Map>().map((hit) => hit['id']),
        isNot(contains(hiddenTable.id)),
      );
      expect((catalog['coverage']['checkedTables'] as List), [
        visibleTable.id,
      ], reason: 'coverage must not disclose out-of-scope table IDs');
      expect(
        jsonMap(await retrieval.readTableEntry(hiddenEntry.id))['status'],
        'denied',
      );
      expect(
        jsonMap(await retrieval.readTableEntry(visibleEntry.id))['status'],
        'ok',
      );

      final scopedResults = jsonMap(
        await retrieval.searchResults(query: '学期', globalKnowledgeOnly: true),
      );
      final knowledgeIds = (jsonData(scopedResults)['hits'] as List)
          .cast<Map>()
          .map((hit) => hit['id']);
      expect(knowledgeIds, contains(global.id));
      expect(knowledgeIds, isNot(contains(hiddenGlobal.id)));
      expect(
        jsonMap(await retrieval.readGlobalKnowledge(hiddenGlobal.id))['status'],
        'denied',
      );

      final scopedHistory = jsonMap(
        await retrieval.searchOtherConversations('十六周'),
      );
      expect(
        (jsonData(scopedHistory)['hits'] as List).cast<Map>().map(
          (hit) => hit['conversation_id'],
        ),
        [history.id],
      );

      retrieval.setPolicy(AiPolicy.custom(decisions: const {}));
      expect(
        jsonMap(await retrieval.listTables())['status'],
        'denied',
        reason:
            'a policy change must invalidate the old cache and revoke reads',
      );
    },
  );

  test(
    'valid reads are cached and invalidate when source revisions change',
    () async {
      final retrieval = LocalRetrieval(
        conversationId: current.id,
        permissions: const AiPermissions(),
        chats: chats,
        results: results,
      );
      final first = await retrieval.searchResults(
        query: '秋季学期',
        globalKnowledgeOnly: true,
      );
      final firstJson = jsonMap(first);
      expect(firstJson['status'], 'ok');
      final hits = jsonData(firstJson)['hits'] as List;
      expect(hits, hasLength(1));
      expect((hits.single as Map)['id'], global.id);
      expect((hits.single as Map)['snippet'], contains('week_count'));
      expect(
        jsonCoverage(firstJson)['checkedEntries'],
        greaterThanOrEqualTo(1),
      );

      final cached = await retrieval.searchResults(
        query: '秋季学期',
        globalKnowledgeOnly: true,
      );
      expect(cached, first);
      expect(retrieval.searchCalls, 2);
      expect(
        retrieval.resultChars,
        first.runes.length + cached.runes.length,
        reason:
            'replayed cached output still consumes the model-visible budget',
      );

      await results.createManual(
        type: ResultType.knowledge,
        title: '秋季学期补充',
        body: '新增了学期安排。',
      );
      final refreshed = jsonMap(await retrieval.searchResults(query: '秋季学期'));
      expect(refreshed['status'], 'ok');
      expect(jsonData(refreshed)['hits'], isNotEmpty);
      expect(retrieval.searchCalls, 3);

      final historyHits = jsonMap(
        await retrieval.searchOtherConversations('十六周'),
      );
      final messageId =
          ((jsonData(historyHits)['hits'] as List).single as Map)['message_id'];
      final message = jsonMap(
        await retrieval.readOtherConversationMessage(messageId as String),
      );
      expect(jsonData(message)['conversation_id'], history.id);
      expect(jsonData(message)['content'], contains('十六周'));
      expect(jsonData(message)['nextOffset'], isNull);
      expect(jsonCoverage(message)['complete'], isTrue);
    },
  );

  test(
    'detail reads use rune offsets and keep truncation inside JSON fields',
    () async {
      final longBody = [
        '开头😀',
        List.filled(30, '长内容，包含引号"和换行\n').join(),
        '末尾',
      ].join();
      final document = await results.createManual(
        type: ResultType.knowledge,
        title: '分段读取',
        body: longBody,
      );
      final retrieval = LocalRetrieval(
        conversationId: current.id,
        permissions: const AiPermissions(),
        chats: chats,
        results: results,
      );
      final first = jsonMap(
        await retrieval.readResult(document.id, length: 17),
      );
      expect(first['status'], 'ok');
      expect(jsonData(first)['revision'], document.revision);
      expect(jsonData(first)['content'], isA<String>());
      expect((jsonData(first)['content'] as String).runes.length, 17);
      expect(jsonData(first)['nextOffset'], 17);
      expect(jsonCoverage(first)['complete'], isFalse);

      var page = first;
      var offset = jsonData(page)['nextOffset'] as int;
      while (jsonData(page)['nextOffset'] != null) {
        page = jsonMap(
          await retrieval.readResult(document.id, offset: offset, length: 500),
        );
        expect(page['status'], 'ok');
        final next = jsonData(page)['nextOffset'];
        if (next == null) break;
        expect(next as int, greaterThan(offset));
        offset = next;
      }
      expect(jsonData(page)['nextOffset'], isNull);
      expect(jsonCoverage(page)['complete'], isTrue);
    },
  );

  test('known IDs read directly without a search round', () async {
    final retrieval = LocalRetrieval(
      conversationId: current.id,
      permissions: const AiPermissions(),
      chats: chats,
      results: results,
    );
    final direct = jsonMap(await retrieval.readResult(ordinary.id));
    expect(direct['status'], 'ok');
    expect(jsonData(direct)['versionStatus'], 'current');
    expect(jsonData(direct)['content'], contains('教学楼'));
  });

  test(
    'empty search uses the current envelope rather than top-level hits',
    () async {
      final retrieval = LocalRetrieval(
        conversationId: current.id,
        permissions: const AiPermissions(),
        chats: chats,
        results: results,
      );

      final result = jsonMap(
        await retrieval.searchResults(query: 'no_matching_source_contract'),
      );

      expect(result['status'], 'ok');
      expect(result.containsKey('hits'), isFalse);
      expect(jsonData(result)['hits'], isEmpty);
      expect(jsonCoverage(result)['complete'], isTrue);
      expect(retrieval.searchCalls, 1);
    },
  );

  test('search budget remains 20 calls and blocks the next call', () async {
    final retrieval = LocalRetrieval(
      conversationId: current.id,
      permissions: const AiPermissions(),
      chats: chats,
      results: results,
    );

    for (var index = 0; index < LocalRetrieval.maxSearches; index++) {
      final result = jsonMap(
        await retrieval.searchResults(query: 'no_match_$index'),
      );
      expect(result['status'], 'ok');
    }
    final blocked = jsonMap(
      await retrieval.searchResults(query: 'no_match_after_limit'),
    );

    expect(LocalRetrieval.maxSearches, 20);
    expect(retrieval.searchCalls, 21);
    expect(blocked['status'], 'batch_boundary');
    expect(jsonCoverage(blocked)['complete'], isFalse);
    expect(jsonEncode(blocked), contains('检索调用上限'));
  });

  test(
    'verify checks explicit target revision and fields with coverage',
    () async {
      final retrieval = LocalRetrieval(
        conversationId: current.id,
        permissions: const AiPermissions(),
        chats: chats,
        results: results,
      );

      final verified = jsonMap(
        await retrieval.verify(
          operationId: 'op_verify_result',
          operationStatus: 'succeeded',
          targetKind: 'result',
          targetId: ordinary.id,
          expectedRevision: ordinary.revision,
          expectedFields: const {'title': '课程资料', 'type': 'knowledge'},
        ),
      );
      expect(verified['status'], 'ok');
      expect(jsonData(verified)['operation_id'], 'op_verify_result');
      expect(jsonData(verified)['verified'], isTrue);
      expect(
        (jsonData(verified)['observed'] as Map)['revision'],
        ordinary.revision,
      );
      expect(jsonCoverage(verified)['complete'], isTrue);

      final mismatch = jsonMap(
        await retrieval.verify(
          targetKind: 'result',
          targetId: ordinary.id,
          expectedFields: const {'title': '不存在的标题'},
        ),
      );
      expect(mismatch['status'], 'mismatch');
      expect(jsonData(mismatch)['verified'], isFalse);
      expect(jsonData(mismatch)['mismatches'], ['title']);
      expect(jsonCoverage(mismatch)['uncovered'], contains('title'));

      final stale = jsonMap(
        await retrieval.verify(
          targetKind: 'result',
          targetId: ordinary.id,
          expectedRevision: ordinary.revision + 1,
        ),
      );
      expect(stale['status'], 'stale');
      expect(jsonData(stale)['verified'], isFalse);
      expect(jsonCoverage(stale)['complete'], isFalse);

      final pending = jsonMap(
        await retrieval.verify(
          operationId: 'op_pending',
          operationStatus: 'waiting_confirmation',
          targetKind: 'result',
          targetId: ordinary.id,
        ),
      );
      expect(pending['status'], 'waiting_confirmation');
      expect(jsonData(pending)['operation_status'], 'waiting_confirmation');
      expect(jsonData(pending)['verified'], isFalse);
    },
  );

  test('verify obeys read permission and detail budget', () async {
    final denied = LocalRetrieval(
      conversationId: current.id,
      permissions: const AiPermissions(read: false),
      chats: chats,
      results: results,
    );
    expect(
      jsonMap(
        await denied.verify(targetKind: 'result', targetId: ordinary.id),
      )['status'],
      'denied',
    );
    expect(denied.detailCalls, 0);

    final limited = LocalRetrieval(
      conversationId: current.id,
      permissions: const AiPermissions(),
      chats: chats,
      results: results,
    );
    for (var index = 0; index < LocalRetrieval.maxDetails; index++) {
      final result = jsonMap(
        await limited.verify(
          targetKind: 'result',
          targetId: ordinary.id,
          expectedFields: {'revision': -index},
        ),
      );
      expect(result['status'], 'mismatch');
    }
    final boundary = jsonMap(
      await limited.verify(
        targetKind: 'result',
        targetId: ordinary.id,
        expectedFields: const {'title': '边界'},
      ),
    );
    expect(boundary['status'], 'batch_boundary');
    expect(jsonCoverage(boundary)['complete'], isFalse);
  });

  test('output exhaustion returns a parseable boundary envelope', () async {
    const marker = 'boundary_marker';
    for (var index = 0; index < 60; index++) {
      await results.createManual(
        type: ResultType.knowledge,
        title: '$marker $index',
        body: List.filled(120, '预算边界正文').join(),
      );
    }
    final retrieval = LocalRetrieval(
      conversationId: current.id,
      permissions: const AiPermissions(),
      chats: chats,
      results: results,
    );
    var offset = 0;
    var sawBoundary = false;
    for (var pageIndex = 0; pageIndex < 8; pageIndex++) {
      final envelope = jsonMap(
        await retrieval.searchResults(
          query: marker,
          offset: offset,
          limit: LocalRetrieval.maxHitsPerSearch,
        ),
      );
      expect(envelope['status'], isA<String>());
      expect(envelope['coverage'], isA<Map>());
      if (envelope['status'] == 'batch_boundary') {
        sawBoundary = true;
        expect(envelope['warnings'], isNotEmpty);
        break;
      }
      final next = jsonData(envelope)['nextOffset'];
      if (next == null) break;
      offset = next as int;
    }
    expect(sawBoundary, isTrue);
    expect(
      retrieval.resultChars,
      lessThanOrEqualTo(LocalRetrieval.maxTurnChars),
    );
  });
}

Map<String, dynamic> jsonMap(String value) =>
    Map<String, dynamic>.from(jsonDecode(value) as Map);

Map<String, dynamic> jsonData(Map<String, dynamic> envelope) =>
    Map<String, dynamic>.from(envelope['data'] as Map);

Map<String, dynamic> jsonCoverage(Map<String, dynamic> envelope) =>
    Map<String, dynamic>.from(envelope['coverage'] as Map);
