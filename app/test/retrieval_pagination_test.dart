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
  late ResultLibrary results;
  late TableRepository tableRepository;
  late TableLibrary tables;
  late Conversation current;
  const targetEntryId = 'nt_long_00';

  setUp(() async {
    chats = ChatRepository(
      store: MemoryConversationStore(),
      attachments: MemoryAttachmentStore(),
    );
    await chats.initialize();
    current = await chats.createConversation();
    results = ResultLibrary(
      repository: ResultRepository(
        vault: MemoryVaultStore(),
        index: MemoryIndexDatabase(),
        deviceId: 'retrieval-pagination-test',
      ),
    );
    await results.initialize();
    tableRepository = TableRepository(
      vault: MemoryVaultStore(),
      index: MemoryIndexDatabase(),
      deviceId: 'retrieval-pagination-test',
    );
    await tableRepository.initialize();
    for (var index = 0; index < 25; index++) {
      final suffix = index.toString().padLeft(2, '0');
      final table = await tableRepository.createTable(
        id: 'tb_page_$suffix',
        title: '考试资料 $suffix',
        body: '第 $suffix 张表',
      );
      final timestamp = DateTime.utc(2026, 10, 1).add(Duration(minutes: index));
      await tableRepository.createEntry(
        TableEntryDocument(
          id: 'nt_long_$suffix',
          type: TableContentType.note,
          tableId: table.id,
          title: '考试范围 $suffix',
          revision: 1,
          createdAt: timestamp,
          updatedAt: timestamp,
          body: index == 0
              ? '开头😀 考试范围包含第一章和第二章。\n"逐字"保留特殊字符。${List.filled(80, '后段').join()}'
              : '考试范围包含第 $suffix 章，地点在东楼。',
        ),
      );
    }
    tables = TableLibrary(repository: tableRepository);
    await tables.initialize();
  });

  tearDown(() async {
    tables.dispose();
    await results.shutdown();
    results.dispose();
    await chats.close();
  });

  test(
    'table listing has no implicit 20-row limit and cursors are opaque',
    () async {
      final retrieval = _buildRetrieval(chats, results, tables, current);
      final all = jsonMap(await retrieval.listTables());
      expect(all['status'], 'ok');
      expect(jsonData(all)['hits'], hasLength(28));
      expect(jsonData(all)['nextOffset'], isNull);
      expect(jsonCoverage(all)['complete'], isTrue);

      final firstPage = jsonMap(await retrieval.listTables(limit: 10));
      expect(jsonData(firstPage)['hits'], hasLength(10));
      expect(jsonData(firstPage)['nextOffset'], 10);
      final cursor = firstPage['nextCursor'] as String;
      expect(cursor, isNot(contains('{')));

      final secondPage = jsonMap(
        await retrieval.listTables(limit: 10, cursor: cursor),
      );
      expect(jsonData(secondPage)['hits'], hasLength(10));
      expect(jsonData(secondPage)['offset'], 10);

      final anotherConversation = await chats.createConversation();
      final otherSession = _buildRetrieval(
        chats,
        results,
        tables,
        anotherConversation,
      );
      final crossSession = jsonMap(
        await otherSession.listTables(limit: 10, cursor: cursor),
      );
      expect(crossSession['status'], 'stale');

      await tableRepository.createTable(
        id: 'tb_after_cursor',
        title: '游标之后新增的表',
      );
      await tables.refresh();
      final stale = jsonMap(
        await retrieval.listTables(limit: 10, cursor: cursor),
      );
      expect(stale['status'], 'stale');
      expect(jsonCoverage(stale)['complete'], isFalse);
    },
  );

  test('cross-table search pages all tables and reports coverage', () async {
    final retrieval = _buildRetrieval(chats, results, tables, current);
    final firstPage = jsonMap(
      await retrieval.searchTableEntries(
        query: '考试范围',
        types: const ['note'],
        limit: 5,
      ),
    );
    expect(firstPage['status'], 'ok');
    expect(jsonData(firstPage)['hits'], hasLength(5));
    expect(jsonData(firstPage)['nextOffset'], 5);
    expect(jsonData(firstPage)['table_scope_truncated'], isFalse);
    expect(jsonCoverage(firstPage)['checkedTables'], hasLength(28));
    expect(jsonCoverage(firstPage)['checkedEntries'], 25);
    expect(jsonCoverage(firstPage)['complete'], isFalse);

    final secondPage = jsonMap(
      await retrieval.searchTableEntries(
        query: '考试范围',
        types: const ['note'],
        limit: 5,
        cursor: firstPage['nextCursor'] as String,
      ),
    );
    expect(secondPage['status'], 'ok');
    expect(jsonData(secondPage)['offset'], 5);
    expect(jsonData(secondPage)['hits'], hasLength(5));
  });

  test(
    'known entry IDs read directly with segmented body and stale revisions',
    () async {
      final retrieval = _buildRetrieval(chats, results, tables, current);
      final first = jsonMap(
        await retrieval.readTableEntry(targetEntryId, length: 9),
      );
      expect(first['status'], 'ok');
      expect(jsonData(first)['versionStatus'], 'current');
      expect(jsonData(first)['bodyOffset'], 0);
      expect((jsonData(first)['body'] as String).runes.length, 9);
      expect(jsonData(first)['nextOffset'], 9);
      expect(jsonCoverage(first)['complete'], isFalse);

      final second = jsonMap(
        await retrieval.readTableEntry(
          targetEntryId,
          cursor: first['nextCursor'] as String,
          length: 20,
        ),
      );
      expect(second['status'], 'ok');
      expect(jsonData(second)['bodyOffset'], 9);
      expect(jsonData(second)['body'], contains('第一章'));

      final stale = jsonMap(
        await retrieval.readTableEntry(targetEntryId, expectedRevision: 2),
      );
      expect(stale['status'], 'stale');
      expect(jsonData(stale)['currentRevision'], 1);
    },
  );
}

LocalRetrieval _buildRetrieval(
  ChatRepository chats,
  ResultLibrary results,
  TableLibrary tables,
  Conversation current,
) => LocalRetrieval(
  conversationId: current.id,
  permissions: const AiPermissions(),
  chats: chats,
  results: results,
  tables: tables,
);

Map<String, dynamic> jsonMap(String value) =>
    Map<String, dynamic>.from(jsonDecode(value) as Map);

Map<String, dynamic> jsonData(Map<String, dynamic> envelope) =>
    Map<String, dynamic>.from(envelope['data'] as Map);

Map<String, dynamic> jsonCoverage(Map<String, dynamic> envelope) =>
    Map<String, dynamic>.from(envelope['coverage'] as Map);
