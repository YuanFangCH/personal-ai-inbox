import 'dart:convert';

import '../../core/chat_models.dart';
import '../../core/models.dart';
import '../../core/table_models.dart';
import '../../data/chat_repository.dart';
import '../results/result_library.dart';
import '../tables/table_library.dart';
import 'retrieval_support.dart';

/// Read-only access used by the secretary. Every response is a complete JSON
/// envelope so pagination, provenance and truncation remain machine-readable.
class LocalRetrieval {
  LocalRetrieval({
    required this.conversationId,
    AiPermissions? permissions,
    AiPolicy? policy,
    required ChatRepository chats,
    required ResultLibrary results,
    TableLibrary? tables,
  }) : assert(permissions != null || policy != null),
       _policy =
           policy ??
           AiPolicy.fromLegacyPermissions(permissions ?? const AiPermissions()),
       _chats = chats,
       _results = results,
       _tables = tables,
       _policyVersion = retrievalDigest(
         (policy ??
                 AiPolicy.fromLegacyPermissions(
                   permissions ?? const AiPermissions(),
                 ))
             .toJson(),
       );

  static const maxSearches = 20;
  static const maxHitsPerSearch = 20;
  static const maxDetails = 20;
  static const maxTablePageSize = 100;
  static const maxHitChars = 300;
  static const maxDetailChars = 4000;
  static const maxTurnChars = 24000;
  static const _maxCacheEntries = 64;
  static const _outputReserve = 320;

  final String conversationId;
  AiPolicy _policy;
  String _policyVersion;
  final ChatRepository _chats;
  final ResultLibrary _results;
  final TableLibrary? _tables;
  final Map<String, _CachedResponse> _cache = {};
  var _searchCalls = 0;
  var _detailCalls = 0;
  var _resultChars = 0;

  int get searchCalls => _searchCalls;
  int get detailCalls => _detailCalls;
  int get resultChars => _resultChars;
  int get searchRounds => _searchCalls == 0 ? 0 : ((_searchCalls - 1) ~/ 2) + 1;

  AiPolicy get policy => _policy;

  void beginNextBatch() {
    _searchCalls = 0;
    _detailCalls = 0;
    _resultChars = 0;
    _cache.clear();
  }

  void setPolicy(AiPolicy policy) {
    if (identical(policy, _policy)) return;
    _policy = policy;
    _policyVersion = retrievalDigest(policy.toJson());
    _cache.clear();
  }

  Future<String> searchResults({
    required String query,
    ResultType? type,
    bool globalKnowledgeOnly = false,
    int offset = 0,
    int limit = 5,
    String? cursor,
  }) async {
    final ordinaryDecision = _policy.decisionFor(
      AiPermissionAction.contentRead,
    );
    final knowledgeDecision = _policy.decisionFor(
      AiPermissionAction.globalKnowledgeSearch,
    );
    if (globalKnowledgeOnly) {
      final denied = _readDecisionFailure(knowledgeDecision);
      if (denied != null) return denied;
    } else if (ordinaryDecision == AiPolicyDecision.deny &&
        knowledgeDecision == AiPolicyDecision.deny) {
      return _denied();
    } else if (ordinaryDecision == AiPolicyDecision.ask &&
        knowledgeDecision == AiPolicyDecision.ask) {
      return _confirmationRequired();
    }
    if (query.trim().isEmpty) return _failure('invalid_argument', '搜索词不能为空。');
    final sourceToken = _resultsSourceToken();
    final queryToken = retrievalDigest({
      'query': normalizeRetrievalText(query),
      'type': type?.wireName,
      'globalKnowledgeOnly': globalKnowledgeOnly,
    });
    final safeLimit = limit.clamp(1, maxHitsPerSearch);
    try {
      offset = _cursorOffset(
        cursor: cursor,
        kind: 'result_search',
        queryToken: queryToken,
        sourceToken: sourceToken,
        fallback: offset,
      );
    } on _StaleCursor {
      return _staleCursor('结果已变化，请从第一页重新检索。');
    } on FormatException catch (error) {
      return _failure('invalid_cursor', error.message);
    }
    final key = _cacheKey('result_search', queryToken, sourceToken, {
      'offset': offset,
      'limit': safeLimit,
    });
    final decision = _beginSearch(key, sourceToken);
    if (!decision.proceed) return decision.response;

    final candidates = _results.documents
        .where(
          (document) =>
              !document.deleted &&
              document.status == ResultStatus.canonical &&
              (document.isGlobalKnowledge
                  ? knowledgeDecision == AiPolicyDecision.allow &&
                        _policy.knowledgeReadScope.covers(document.id)
                  : ordinaryDecision == AiPolicyDecision.allow) &&
              (type == null || document.type == type) &&
              (!globalKnowledgeOnly || document.isGlobalKnowledge),
        )
        .toList(growable: false);
    final ranked =
        candidates
            .map((document) {
              final extra = document.isGlobalKnowledge
                  ? jsonEncode(document.extensionFields['global_facts'] ?? {})
                  : '';
              final score = retrievalRelevance(
                query: query,
                title: document.title,
                body: document.body,
                extra: extra,
              );
              return score == null
                  ? null
                  : (document: document, score: score, extra: extra);
            })
            .whereType<
              ({ResultDocument document, double score, String extra})
            >()
            .toList()
          ..sort((left, right) {
            final byScore = right.score.compareTo(left.score);
            if (byScore != 0) return byScore;
            final byId = left.document.id.compareTo(right.document.id);
            return byId;
          });
    final page = _paginate(ranked, offset, safeLimit);
    final hits = page.items
        .map((match) {
          final document = match.document;
          final source = document.isGlobalKnowledge
              ? match.extra
              : '${document.title}\n${document.body}';
          final excerpt = relevantRetrievalExcerpt(source, query, maxHitChars);
          return <String, Object?>{
            'id': document.id,
            'type': document.type.wireName,
            'title': document.title,
            'revision': document.revision,
            'snippet': excerpt.text,
            'snippet_offset': excerpt.offset,
            'truncated': excerpt.truncated,
            'relevance': match.score,
          };
        })
        .toList(growable: false);
    final nextCursor = page.nextOffset == null
        ? null
        : opaqueRetrievalCursor({
            'kind': 'result_search',
            'offset': page.nextOffset,
            'query': queryToken,
            'source': sourceToken,
            'session': conversationId,
            'policy': _policyVersion,
          });
    final data = <String, Object?>{
      'source': 'results',
      'offset': page.offset,
      'nextOffset': page.nextOffset,
      'hits': hits,
    };
    return _finishSuccess(
      key: key,
      sourceToken: sourceToken,
      data: data,
      coverage: _coverage(
        complete: page.nextOffset == null,
        checkedEntries: candidates.length,
        matchedEntries: ranked.length,
        returnedEntries: hits.length,
        characters: _dataCharacters(data),
        nextOffset: page.nextOffset,
        reason: page.nextOffset == null ? null : '还有结果未进入本页。',
      ),
      nextCursor: nextCursor,
    );
  }

  Future<String> searchOtherConversations(
    String query, {
    int offset = 0,
    int limit = 5,
    String? cursor,
  }) async {
    final denied = _readDecisionFailure(
      _policy.decisionFor(AiPermissionAction.conversationHistorySearch),
    );
    if (denied != null) return denied;
    if (query.trim().isEmpty) return _failure('invalid_argument', '搜索词不能为空。');
    final sourceToken = await _chatSourceToken();
    final queryToken = retrievalDigest({
      'query': normalizeRetrievalText(query),
    });
    final safeLimit = limit.clamp(1, maxHitsPerSearch);
    try {
      offset = _cursorOffset(
        cursor: cursor,
        kind: 'conversation_search',
        queryToken: queryToken,
        sourceToken: sourceToken,
        fallback: offset,
      );
    } on _StaleCursor {
      return _staleCursor('历史会话已变化，请从第一页重新检索。');
    } on FormatException catch (error) {
      return _failure('invalid_cursor', error.message);
    }
    final key = _cacheKey('conversation_search', queryToken, sourceToken, {
      'offset': offset,
      'limit': safeLimit,
    });
    final decision = _beginSearch(key, sourceToken);
    if (!decision.proceed) return decision.response;

    final conversations = await _chats.listConversations();
    final titles = {
      for (final conversation in conversations)
        conversation.id: conversation.title,
    };
    final ranked = <({ChatMessage message, String title, double score})>[];
    var checkedEntries = 0;
    for (final conversation in conversations) {
      if (conversation.id == conversationId) continue;
      if (!_policy.conversationHistoryReadScope.covers(conversation.id)) {
        continue;
      }
      for (final message in await _chats.listMessages(conversation.id)) {
        if (message.status != ChatMessageStatus.complete) continue;
        checkedEntries++;
        final score = retrievalRelevance(
          query: query,
          title: titles[message.conversationId] ?? '',
          body: message.content,
        );
        if (score != null) {
          ranked.add((
            message: message,
            title: titles[message.conversationId] ?? '已删除会话',
            score: score,
          ));
        }
      }
    }
    ranked.sort((left, right) {
      final byScore = right.score.compareTo(left.score);
      if (byScore != 0) return byScore;
      final byDate = right.message.createdAt.compareTo(left.message.createdAt);
      return byDate != 0 ? byDate : left.message.id.compareTo(right.message.id);
    });
    final page = _paginate(ranked, offset, safeLimit);
    final hits = page.items
        .map((match) {
          final excerpt = relevantRetrievalExcerpt(
            match.message.content,
            query,
            maxHitChars,
          );
          return <String, Object?>{
            'message_id': match.message.id,
            'conversation_id': match.message.conversationId,
            'conversation_title': match.title,
            'role': match.message.role.wireName,
            'snippet': excerpt.text,
            'snippet_offset': excerpt.offset,
            'truncated': excerpt.truncated,
            'relevance': match.score,
          };
        })
        .toList(growable: false);
    final nextCursor = page.nextOffset == null
        ? null
        : opaqueRetrievalCursor({
            'kind': 'conversation_search',
            'offset': page.nextOffset,
            'query': queryToken,
            'source': sourceToken,
            'session': conversationId,
            'policy': _policyVersion,
          });
    final data = <String, Object?>{
      'source': 'conversations',
      'offset': page.offset,
      'nextOffset': page.nextOffset,
      'hits': hits,
    };
    return _finishSuccess(
      key: key,
      sourceToken: sourceToken,
      data: data,
      coverage: _coverage(
        complete: page.nextOffset == null,
        checkedEntries: checkedEntries,
        matchedEntries: ranked.length,
        returnedEntries: hits.length,
        characters: _dataCharacters(data),
        nextOffset: page.nextOffset,
        reason: page.nextOffset == null ? null : '还有历史消息未进入本页。',
      ),
      nextCursor: nextCursor,
    );
  }

  Future<String> listTables({
    String? role,
    int? limit,
    int offset = 0,
    String? cursor,
  }) async {
    final denied = _readDecisionFailure(
      _policy.decisionFor(AiPermissionAction.tableRead),
    );
    if (denied != null) return denied;
    final tables = _tables;
    if (tables == null) return _failure('unavailable', '表库暂不可用。');
    final roleName = _parseRole(role);
    if (role != null && roleName == null) {
      return _failure('invalid_argument', '表角色无效：$role');
    }
    final sourceToken = _tableSourceToken(includeEntries: false);
    final queryToken = retrievalDigest({'role': roleName});
    final safeLimit = limit?.clamp(1, maxTablePageSize).toInt();
    try {
      offset = _cursorOffset(
        cursor: cursor,
        kind: 'table_list',
        queryToken: queryToken,
        sourceToken: sourceToken,
        fallback: offset,
      );
    } on _StaleCursor {
      return _staleCursor('表目录已变化，请从第一页重新读取。');
    } on FormatException catch (error) {
      return _failure('invalid_cursor', error.message);
    }
    final key = _cacheKey('table_list', queryToken, sourceToken, {
      'offset': offset,
      'limit': safeLimit ?? 'all',
    });
    final decision = _beginSearch(key, sourceToken);
    if (!decision.proceed) return decision.response;

    final selected =
        tables.tables
            .where(
              (table) =>
                  _policy.tableScope.covers(table.id) &&
                  (roleName == null || table.role.name == roleName),
            )
            .toList(growable: false)
          ..sort((left, right) {
            final byUpdate = right.updatedAt.compareTo(left.updatedAt);
            return byUpdate != 0 ? byUpdate : left.id.compareTo(right.id);
          });
    final page = _paginate(selected, offset, safeLimit);
    final hits = page.items
        .map((table) {
          final excerpt = relevantRetrievalExcerpt(
            '${table.title}\n${table.body}',
            '',
            maxHitChars,
          );
          return <String, Object?>{
            'id': table.id,
            'title': table.title,
            'role': table.role.name,
            'roleWireName': table.role.wireName,
            'revision': table.revision,
            'fieldCount': table.fields.length,
            'summary': excerpt.text,
            'truncated': excerpt.truncated,
          };
        })
        .toList(growable: false);
    final nextCursor = page.nextOffset == null
        ? null
        : opaqueRetrievalCursor({
            'kind': 'table_list',
            'offset': page.nextOffset,
            'query': queryToken,
            'source': sourceToken,
            'session': conversationId,
            'policy': _policyVersion,
          });
    final data = <String, Object?>{
      'source': 'tables',
      'offset': page.offset,
      'nextOffset': page.nextOffset,
      'total': selected.length,
      'hits': hits,
    };
    return _finishSuccess(
      key: key,
      sourceToken: sourceToken,
      data: data,
      coverage: _coverage(
        complete: page.nextOffset == null,
        checkedTables: selected.map((table) => table.id).toList(),
        checkedEntries: 0,
        matchedEntries: selected.length,
        returnedEntries: hits.length,
        characters: _dataCharacters(data),
        nextOffset: page.nextOffset,
        reason: page.nextOffset == null ? null : '还有表未进入本页。',
      ),
      nextCursor: nextCursor,
    );
  }

  Future<String> searchTables(
    String query, {
    int limit = 5,
    int offset = 0,
    String? cursor,
  }) async {
    final denied = _readDecisionFailure(
      _policy.decisionFor(AiPermissionAction.tableRead),
    );
    if (denied != null) return denied;
    final tables = _tables;
    if (tables == null) return _failure('unavailable', '表库暂不可用。');
    if (query.trim().isEmpty) return _failure('invalid_argument', '搜索词不能为空。');
    final sourceToken = _tableSourceToken(includeEntries: false);
    final queryToken = retrievalDigest({
      'query': normalizeRetrievalText(query),
    });
    final safeLimit = limit.clamp(1, maxHitsPerSearch);
    try {
      offset = _cursorOffset(
        cursor: cursor,
        kind: 'table_search',
        queryToken: queryToken,
        sourceToken: sourceToken,
        fallback: offset,
      );
    } on _StaleCursor {
      return _staleCursor('表目录已变化，请从第一页重新检索。');
    } on FormatException catch (error) {
      return _failure('invalid_cursor', error.message);
    }
    final key = _cacheKey('table_search', queryToken, sourceToken, {
      'offset': offset,
      'limit': safeLimit,
    });
    final decision = _beginSearch(key, sourceToken);
    if (!decision.proceed) return decision.response;

    final ranked =
        tables.tables
            .where((table) => _policy.tableScope.covers(table.id))
            .map((table) {
              final score = retrievalRelevance(
                query: query,
                title: table.title,
                body: table.body,
                extra: table.fields.map((field) => field.name).join(' '),
              );
              return score == null ? null : (table: table, score: score);
            })
            .whereType<({TableDocument table, double score})>()
            .toList()
          ..sort((left, right) {
            final byScore = right.score.compareTo(left.score);
            if (byScore != 0) return byScore;
            final byUpdate = right.table.updatedAt.compareTo(
              left.table.updatedAt,
            );
            return byUpdate != 0
                ? byUpdate
                : left.table.id.compareTo(right.table.id);
          });
    final page = _paginate(ranked, offset, safeLimit);
    final hits = page.items
        .map((match) {
          final excerpt = relevantRetrievalExcerpt(
            '${match.table.title}\n${match.table.body}',
            query,
            maxHitChars,
          );
          return <String, Object?>{
            'id': match.table.id,
            'title': match.table.title,
            'role': match.table.role.name,
            'roleWireName': match.table.role.wireName,
            'revision': match.table.revision,
            'fieldCount': match.table.fields.length,
            'snippet': excerpt.text,
            'snippet_offset': excerpt.offset,
            'truncated': excerpt.truncated,
            'relevance': match.score,
          };
        })
        .toList(growable: false);
    final nextCursor = page.nextOffset == null
        ? null
        : opaqueRetrievalCursor({
            'kind': 'table_search',
            'offset': page.nextOffset,
            'query': queryToken,
            'source': sourceToken,
            'session': conversationId,
            'policy': _policyVersion,
          });
    final data = <String, Object?>{
      'source': 'tables',
      'offset': page.offset,
      'nextOffset': page.nextOffset,
      'hits': hits,
    };
    return _finishSuccess(
      key: key,
      sourceToken: sourceToken,
      data: data,
      coverage: _coverage(
        complete: page.nextOffset == null,
        checkedTables: tables.tables
            .where((table) => _policy.tableScope.covers(table.id))
            .map((table) => table.id)
            .toList(),
        checkedEntries: 0,
        matchedEntries: ranked.length,
        returnedEntries: hits.length,
        characters: _dataCharacters(data),
        nextOffset: page.nextOffset,
        reason: page.nextOffset == null ? null : '还有表命中未进入本页。',
      ),
      nextCursor: nextCursor,
    );
  }

  Future<String> searchTableEntries({
    required String query,
    List<String> tableIds = const [],
    List<String> types = const [],
    DateTime? from,
    DateTime? through,
    Map<String, Object?> fieldFilters = const {},
    int limit = 5,
    int offset = 0,
    String? cursor,
  }) async {
    final denied = _readDecisionFailure(
      _policy.decisionFor(AiPermissionAction.contentRead),
    );
    if (denied != null) return denied;
    final tables = _tables;
    if (tables == null) return _failure('unavailable', '表库暂不可用。');
    if (from != null && through != null && through.isBefore(from)) {
      return _failure('invalid_argument', '时间范围结束早于开始。');
    }
    final safeTypes = <TableContentType>[];
    for (final value in types) {
      final type = TableContentType.values
          .where(
            (candidate) =>
                candidate.name == value || candidate.wireName == value,
          )
          .firstOrNull;
      if (type == null) {
        return _failure('invalid_argument', '内容类型无效：$value');
      }
      if (!safeTypes.contains(type)) safeTypes.add(type);
    }
    final allTableIds = tables.tables
        .map((table) => table.id)
        .where(_policy.tableScope.covers)
        .toList();
    final selectedTableIds = tableIds.isEmpty
        ? allTableIds.toSet()
        : tableIds.toSet();
    if (selectedTableIds.any((id) => !_policy.tableScope.covers(id))) {
      return _scopeDenied('当前会话的表读取范围不包含请求目标。');
    }
    final missingIds = selectedTableIds.difference(allTableIds.toSet());
    if (missingIds.isNotEmpty) {
      return _failure('invalid_argument', '查询包含不存在的表：${missingIds.join('、')}');
    }
    final sourceToken = _tableSourceToken(includeEntries: true);
    final normalizedQuery = normalizeRetrievalText(query);
    final queryToken = retrievalDigest({
      'query': normalizedQuery,
      'tables': selectedTableIds.toList()..sort(),
      'types': safeTypes.map((type) => type.wireName).toList()..sort(),
      'from': from?.toIso8601String(),
      'through': through?.toIso8601String(),
      'fields': fieldFilters,
    });
    final safeLimit = limit.clamp(1, maxHitsPerSearch);
    try {
      offset = _cursorOffset(
        cursor: cursor,
        kind: 'table_entry_search',
        queryToken: queryToken,
        sourceToken: sourceToken,
        fallback: offset,
      );
    } on _StaleCursor {
      return _staleCursor('表内容已变化，请从第一页重新检索。');
    } on FormatException catch (error) {
      return _failure('invalid_cursor', error.message);
    }
    final key = _cacheKey('table_entry_search', queryToken, sourceToken, {
      'offset': offset,
      'limit': safeLimit,
    });
    final decision = _beginSearch(key, sourceToken);
    if (!decision.proceed) return decision.response;

    final activeTables = {for (final table in tables.tables) table.id: table};
    final ranked =
        tables.entries
            .where((entry) {
              if (entry.deleted || !selectedTableIds.contains(entry.tableId)) {
                return false;
              }
              if (safeTypes.isNotEmpty && !safeTypes.contains(entry.type)) {
                return false;
              }
              final businessAt = _businessAt(entry);
              if (from != null &&
                  (businessAt == null || businessAt.isBefore(from))) {
                return false;
              }
              if (through != null &&
                  (businessAt == null || businessAt.isAfter(through))) {
                return false;
              }
              for (final filter in fieldFilters.entries) {
                if (!entry.customValues.containsKey(filter.key) ||
                    !retrievalValueEquals(
                      entry.customValues[filter.key],
                      filter.value,
                    )) {
                  return false;
                }
              }
              return true;
            })
            .map((entry) {
              final score = retrievalRelevance(
                query: query,
                title: entry.title,
                body: entry.body,
                extra: [
                  activeTables[entry.tableId]?.title ?? '',
                  entry.tags.join(' '),
                  jsonEncode(entry.customValues),
                ].join(' '),
              );
              return score == null ? null : (entry: entry, score: score);
            })
            .whereType<({TableEntryDocument entry, double score})>()
            .toList()
          ..sort((left, right) {
            final byScore = right.score.compareTo(left.score);
            if (byScore != 0) return byScore;
            final leftDate = _businessAt(left.entry) ?? left.entry.updatedAt;
            final rightDate = _businessAt(right.entry) ?? right.entry.updatedAt;
            final byDate = rightDate.compareTo(leftDate);
            return byDate != 0
                ? byDate
                : left.entry.id.compareTo(right.entry.id);
          });
    final page = _paginate(ranked, offset, safeLimit);
    final hits = page.items
        .map((match) {
          final entry = match.entry;
          final table = activeTables[entry.tableId]!;
          final excerpt = relevantRetrievalExcerpt(
            '${entry.title}\n${entry.body}',
            query,
            maxHitChars,
          );
          return <String, Object?>{
            'id': entry.id,
            'table_id': entry.tableId,
            'table_title': table.title,
            'type': entry.type.name,
            'typeWireName': entry.type.wireName,
            'revision': entry.revision,
            'business_at': _businessAt(entry)?.toIso8601String(),
            'custom_values': _boundedFieldValues(entry.customValues),
            'snippet': excerpt.text,
            'snippet_offset': excerpt.offset,
            'truncated': excerpt.truncated,
            'relevance': match.score,
          };
        })
        .toList(growable: false);
    final nextCursor = page.nextOffset == null
        ? null
        : opaqueRetrievalCursor({
            'kind': 'table_entry_search',
            'offset': page.nextOffset,
            'query': queryToken,
            'source': sourceToken,
            'session': conversationId,
            'policy': _policyVersion,
          });
    final data = <String, Object?>{
      'source': 'table_entries',
      'offset': page.offset,
      'nextOffset': page.nextOffset,
      'hits': hits,
      'table_scope_truncated': false,
    };
    return _finishSuccess(
      key: key,
      sourceToken: sourceToken,
      data: data,
      coverage: _coverage(
        complete: page.nextOffset == null,
        checkedTables: selectedTableIds.toList()..sort(),
        checkedEntries: tables.entries
            .where((entry) => selectedTableIds.contains(entry.tableId))
            .length,
        matchedEntries: ranked.length,
        returnedEntries: hits.length,
        characters: _dataCharacters(data),
        nextOffset: page.nextOffset,
        reason: page.nextOffset == null ? null : '还有表内容命中未进入本页。',
      ),
      nextCursor: nextCursor,
    );
  }

  /// Verifies the current state of an explicit local target.
  ///
  /// Receipt resolution stays in ChatService because receipts are conversation
  /// ledger data. This method only reports what the readable source currently
  /// contains and never treats expected values as evidence.
  Future<String> verify({
    String? operationId,
    String? operationStatus,
    required String targetKind,
    required String targetId,
    int? expectedRevision,
    Map<String, Object?> expectedFields = const {},
  }) async {
    final id = targetId.trim();
    if (id.isEmpty) {
      return _failure('invalid_argument', 'target_id 不能为空。');
    }
    if (expectedRevision != null && expectedRevision < 1) {
      return _failure('invalid_argument', 'expected_revision 必须为正整数。');
    }
    if (expectedFields.keys.any((key) => key.trim().isEmpty)) {
      return _failure('invalid_argument', 'expected_fields 字段名不能为空。');
    }
    final kind = switch (targetKind) {
      'table' => 'table',
      'entry' || 'table_entry' => 'entry',
      'result' => 'result',
      'global_knowledge' => 'global_knowledge',
      _ => null,
    };
    if (kind == null) {
      return _failure(
        'invalid_argument',
        'target_kind 仅支持 table、entry、result、global_knowledge。',
      );
    }
    final sourceToken = switch (kind) {
      'table' || 'entry' => _tableSourceToken(includeEntries: true),
      'result' || 'global_knowledge' => _resultsSourceToken(),
      _ => throw StateError('unreachable'),
    };
    final queryToken = retrievalDigest({
      'operationId': operationId,
      'operationStatus': operationStatus,
      'kind': kind,
      'id': id,
      'expectedRevision': expectedRevision,
      'expectedFields': expectedFields,
    });
    final snapshot = await _verificationSnapshot(kind, id);
    if (snapshot == null) {
      return _verificationFailure(
        key: _cacheKey('verify', queryToken, sourceToken, const {}),
        sourceToken: sourceToken,
        status: 'not_found',
        operationId: operationId,
        operationStatus: operationStatus,
        targetKind: kind,
        targetId: id,
        message: '目标不存在或当前不可读取。',
        uncovered: const ['目标'],
      );
    }
    final policyDecision = switch (kind) {
      'table' => _policy.decisionFor(
        AiPermissionAction.tableRead,
        tableIds: [id],
      ),
      'entry' => _policy.decisionFor(
        AiPermissionAction.contentRead,
        tableIds: [snapshot.fields['table_id']?.toString() ?? ''],
      ),
      'result' => _policy.decisionFor(AiPermissionAction.contentRead),
      'global_knowledge' => _policy.decisionFor(
        AiPermissionAction.globalKnowledgeRead,
        knowledgeId: id,
      ),
      _ => AiPolicyDecision.deny,
    };
    final denied = _readDecisionFailure(policyDecision);
    if (denied != null) return denied;
    final detailDecision = _detailDecision(
      key: _cacheKey('verify', queryToken, sourceToken, const {}),
      sourceToken: sourceToken,
    );
    if (!detailDecision.proceed) return detailDecision.response;
    if (operationStatus != null && operationStatus != 'succeeded') {
      return _verificationFailure(
        key: _cacheKey('verify', queryToken, sourceToken, const {}),
        sourceToken: sourceToken,
        status: operationStatus,
        operationId: operationId,
        operationStatus: operationStatus,
        targetKind: kind,
        targetId: id,
        message: '操作回执状态为 $operationStatus，不能视为成功。',
        observed: snapshot.fields,
        uncovered: const ['操作成功状态'],
      );
    }
    if (snapshot.fields['deleted'] == true &&
        expectedFields['deleted'] != true) {
      return _verificationFailure(
        key: _cacheKey('verify', queryToken, sourceToken, const {}),
        sourceToken: sourceToken,
        status: 'deleted',
        operationId: operationId,
        operationStatus: operationStatus,
        targetKind: kind,
        targetId: id,
        message: '目标当前已删除，不能视为有效写入结果。',
        observed: snapshot.fields,
        uncovered: const ['有效目标'],
      );
    }
    if (expectedRevision != null && snapshot.revision != expectedRevision) {
      return _verificationFailure(
        key: _cacheKey('verify', queryToken, sourceToken, const {}),
        sourceToken: sourceToken,
        status: 'stale',
        operationId: operationId,
        operationStatus: operationStatus,
        targetKind: kind,
        targetId: id,
        message: '目标版本已变化。',
        observed: snapshot.fields,
        uncovered: const ['revision'],
      );
    }
    final mismatches = <String>[];
    for (final entry in expectedFields.entries) {
      if (!snapshot.fields.containsKey(entry.key)) {
        return _failure(
          'invalid_argument',
          '目标不支持字段 ${entry.key}。',
          data: {
            'operation_id': ?operationId,
            'target_kind': kind,
            'target_id': id,
            'observed': snapshot.fields,
          },
        );
      }
      if (!_verificationValuesEqual(snapshot.fields[entry.key], entry.value)) {
        mismatches.add(entry.key);
      }
    }
    if (mismatches.isNotEmpty) {
      return _verificationFailure(
        key: _cacheKey('verify', queryToken, sourceToken, const {}),
        sourceToken: sourceToken,
        status: 'mismatch',
        operationId: operationId,
        operationStatus: operationStatus,
        targetKind: kind,
        targetId: id,
        message: '目标存在，但字段与预期不一致。',
        observed: snapshot.fields,
        expectedFields: expectedFields,
        mismatches: mismatches,
        uncovered: mismatches,
      );
    }

    final data = <String, Object?>{
      'operation_id': ?operationId,
      'operation_status': ?operationStatus,
      'target_kind': kind,
      'target_id': id,
      'verified': true,
      'observed': snapshot.fields,
      'expected_fields': expectedFields,
      'mismatches': const <String>[],
    };
    return _finishSuccess(
      key: _cacheKey('verify', queryToken, sourceToken, const {}),
      sourceToken: sourceToken,
      data: data,
      coverage: _coverage(
        complete: true,
        checkedTables: kind == 'table' || kind == 'entry' ? [id] : const [],
        checkedEntries:
            kind == 'entry' || kind == 'result' || kind == 'global_knowledge'
            ? 1
            : 0,
        matchedEntries: 1,
        returnedEntries: 1,
        characters: _dataCharacters(data),
      ),
    );
  }

  Future<_VerificationSnapshot?> _verificationSnapshot(
    String kind,
    String id,
  ) async {
    switch (kind) {
      case 'table':
        final table = _tables?.findTable(id);
        if (table == null) return null;
        return _VerificationSnapshot(
          revision: table.revision,
          fields: {
            'id': table.id,
            'kind': 'table',
            'title': table.title,
            'revision': table.revision,
            'deleted': table.deleted,
            'role': table.role.name,
          },
        );
      case 'entry':
        final entry = await _tables?.readEntry(id);
        if (entry == null) return null;
        return _VerificationSnapshot(
          revision: entry.revision,
          fields: {
            'id': entry.id,
            'kind': 'entry',
            'table_id': entry.tableId,
            'title': entry.title,
            'type': entry.type.wireName,
            'revision': entry.revision,
            'deleted': entry.deleted,
            'done': entry.done,
          },
        );
      case 'result':
      case 'global_knowledge':
        final document = await _results.readDocument(id);
        if (document == null ||
            (kind == 'global_knowledge' && !document.isGlobalKnowledge)) {
          return null;
        }
        return _VerificationSnapshot(
          revision: document.revision,
          fields: {
            'id': document.id,
            'kind': kind,
            'title': document.title,
            'type': document.type.wireName,
            'status': document.status.wireName,
            'revision': document.revision,
            'deleted': document.deleted,
            'global_knowledge': document.isGlobalKnowledge,
          },
        );
      default:
        return null;
    }
  }

  String _verificationFailure({
    required String key,
    required String sourceToken,
    required String status,
    required String targetKind,
    required String targetId,
    required String message,
    String? operationId,
    String? operationStatus,
    Map<String, Object?>? observed,
    Map<String, Object?> expectedFields = const {},
    List<String> mismatches = const [],
    List<String> uncovered = const [],
  }) {
    final data = <String, Object?>{
      'operation_id': ?operationId,
      'operation_status': ?operationStatus,
      'target_kind': targetKind,
      'target_id': targetId,
      'verified': false,
      'observed': ?observed,
      'expected_fields': expectedFields,
      'mismatches': mismatches,
    };
    final response = _recordEnvelope(
      status: status,
      data: data,
      coverage: {
        'complete': uncovered.isEmpty,
        'scopeComplete': true,
        'checkedTables': targetKind == 'table' || targetKind == 'entry'
            ? [targetId]
            : <String>[],
        'checkedEntries': observed == null ? 0 : 1,
        'matchedEntries': observed == null ? 0 : 1,
        'returnedEntries': 1,
        'characters': _dataCharacters(data),
        'nextOffset': null,
        'uncovered': uncovered,
      },
      warnings: [message],
    );
    final decoded = jsonDecode(response);
    if (decoded is Map && decoded['status'] != 'batch_boundary') {
      _cache[key] = _CachedResponse(sourceToken: sourceToken, value: response);
    }
    return response;
  }

  bool _verificationValuesEqual(Object? left, Object? right) {
    if (left == right) return true;
    try {
      return jsonEncode(left) == jsonEncode(right);
    } on JsonUnsupportedObjectError {
      return false;
    }
  }

  Future<String> readTableEntry(
    String id, {
    int? expectedRevision,
    int offset = 0,
    int length = 1200,
    String? cursor,
  }) async {
    final tables = _tables;
    if (tables == null) return _failure('unavailable', '表库暂不可用。');
    final entry = await tables.readEntry(id);
    if (entry == null || entry.deleted) {
      return _failure('not_found', '表内内容不存在或不可读取。');
    }
    final table = tables.findTable(entry.tableId);
    if (table == null || table.deleted) {
      return _failure('not_found', '内容所属表不可读取。');
    }
    final denied = _readDecisionFailure(
      _policy.decisionFor(AiPermissionAction.contentRead, tableIds: [table.id]),
    );
    if (denied != null) return denied;
    if (expectedRevision != null && entry.revision != expectedRevision) {
      return _failure(
        'stale',
        '内容版本已变化；请以当前版本重新读取。',
        data: {'id': entry.id, 'currentRevision': entry.revision},
      );
    }
    final sourceToken = retrievalDigest([
      entry.id,
      entry.revision,
      entry.updatedAt.toIso8601String(),
      table.id,
      table.revision,
    ]);
    final queryToken = retrievalDigest({
      'id': id,
      'expectedRevision': expectedRevision,
    });
    final decision = _detailDecision(
      key: _cacheKey('entry_read', queryToken, sourceToken, {
        'offset': offset,
        'length': length,
      }),
      sourceToken: sourceToken,
    );
    if (!decision.proceed) return decision.response;
    try {
      offset = _cursorOffset(
        cursor: cursor,
        kind: 'entry_read',
        queryToken: queryToken,
        sourceToken: sourceToken,
        fallback: offset,
      );
    } on _StaleCursor {
      return _staleCursor('内容已变化，请重新读取。');
    } on FormatException catch (error) {
      return _failure('invalid_cursor', error.message);
    }
    final slice = retrievalTextSlice(
      entry.body,
      offset: offset,
      length: length.clamp(1, maxDetailChars),
    );
    final data = <String, Object?>{
      'source': 'table_entry',
      'id': entry.id,
      'table_id': table.id,
      'table_title': table.title,
      'type': entry.type.name,
      'typeWireName': entry.type.wireName,
      'title': entry.title,
      'revision': entry.revision,
      'versionStatus': expectedRevision == null ? 'current' : 'matched',
      'body': slice.text,
      'bodyOffset': slice.offset,
      'bodyLength': slice.length,
      'bodyTotalLength': slice.totalLength,
      'nextOffset': slice.nextOffset,
      'business_at': _businessAt(entry)?.toIso8601String(),
      'due': entry.due?.toIso8601String(),
      'start': entry.start?.toIso8601String(),
      'end': entry.end?.toIso8601String(),
      'occurred_at': entry.occurredAt?.toIso8601String(),
      'done': entry.done,
      'all_day': entry.allDay,
      'recurrence': entry.recurrence,
      'tags': entry.tags,
      'links': entry.links,
      'affects': [
        for (final link in entry.affects)
          {'schedule_id': link.scheduleId, 'summary': link.summary},
      ],
      'custom_values': _boundedFieldValues(entry.customValues),
      'truncated': slice.nextOffset != null,
    };
    return _finishSuccess(
      key: _cacheKey('entry_read', queryToken, sourceToken, {
        'offset': slice.offset,
        'length': length,
      }),
      sourceToken: sourceToken,
      data: data,
      coverage: _coverage(
        complete: slice.nextOffset == null,
        checkedTables: [table.id],
        checkedEntries: 1,
        matchedEntries: 1,
        returnedEntries: 1,
        characters: _dataCharacters(data),
        nextOffset: slice.nextOffset,
        reason: slice.nextOffset == null ? null : '正文尚未读完。',
      ),
      nextCursor: slice.nextOffset == null
          ? null
          : opaqueRetrievalCursor({
              'kind': 'entry_read',
              'offset': slice.nextOffset,
              'query': queryToken,
              'source': sourceToken,
              'session': conversationId,
              'policy': _policyVersion,
            }),
    );
  }

  Future<String> readTable(
    String id, {
    int? expectedRevision,
    int offset = 0,
    int length = 1200,
    String? cursor,
  }) async {
    final denied = _readDecisionFailure(
      _policy.decisionFor(AiPermissionAction.tableRead, tableIds: [id]),
    );
    if (denied != null) return denied;
    final tables = _tables;
    if (tables == null) return _failure('unavailable', '表库暂不可用。');
    final table = tables.findTable(id);
    if (table == null || table.deleted) {
      return _failure('not_found', '表不存在或不可读取。');
    }
    if (expectedRevision != null && table.revision != expectedRevision) {
      return _failure(
        'stale',
        '表版本已变化；请以当前版本重新读取。',
        data: {'id': table.id, 'currentRevision': table.revision},
      );
    }
    final sourceToken = retrievalDigest([
      table.id,
      table.revision,
      table.updatedAt.toIso8601String(),
    ]);
    final queryToken = retrievalDigest({
      'id': id,
      'expectedRevision': expectedRevision,
    });
    final decision = _detailDecision(
      key: _cacheKey('table_read', queryToken, sourceToken, {
        'offset': offset,
        'length': length,
      }),
      sourceToken: sourceToken,
    );
    if (!decision.proceed) return decision.response;
    try {
      offset = _cursorOffset(
        cursor: cursor,
        kind: 'table_read',
        queryToken: queryToken,
        sourceToken: sourceToken,
        fallback: offset,
      );
    } on _StaleCursor {
      return _staleCursor('表已变化，请重新读取。');
    } on FormatException catch (error) {
      return _failure('invalid_cursor', error.message);
    }
    final slice = retrievalTextSlice(
      table.body,
      offset: offset,
      length: length.clamp(1, maxDetailChars),
    );
    final data = <String, Object?>{
      'source': 'table',
      'id': table.id,
      'title': table.title,
      'role': table.role.name,
      'roleWireName': table.role.wireName,
      'revision': table.revision,
      'versionStatus': expectedRevision == null ? 'current' : 'matched',
      'body': slice.text,
      'bodyOffset': slice.offset,
      'bodyLength': slice.length,
      'bodyTotalLength': slice.totalLength,
      'nextOffset': slice.nextOffset,
      'fields': [
        for (final field in table.fields)
          {
            'id': field.id,
            'name': field.name,
            'type': field.type.name,
            'typeWireName': field.type.wireName,
            'required': field.required,
            'defaultValue': _boundedValue(field.defaultValue),
            'options': [
              for (final option in field.options)
                {'id': option.id, 'label': option.label},
            ],
          },
      ],
      'truncated': slice.nextOffset != null,
    };
    return _finishSuccess(
      key: _cacheKey('table_read', queryToken, sourceToken, {
        'offset': slice.offset,
        'length': length,
      }),
      sourceToken: sourceToken,
      data: data,
      coverage: _coverage(
        complete: slice.nextOffset == null,
        checkedTables: [table.id],
        checkedEntries: 0,
        matchedEntries: 1,
        returnedEntries: 1,
        characters: _dataCharacters(data),
        nextOffset: slice.nextOffset,
        reason: slice.nextOffset == null ? null : '表正文尚未读完。',
      ),
      nextCursor: slice.nextOffset == null
          ? null
          : opaqueRetrievalCursor({
              'kind': 'table_read',
              'offset': slice.nextOffset,
              'query': queryToken,
              'source': sourceToken,
              'session': conversationId,
              'policy': _policyVersion,
            }),
    );
  }

  Future<String> readResult(
    String id, {
    int offset = 0,
    int length = 1200,
    String? cursor,
  }) async {
    final denied = _readDecisionFailure(
      _policy.decisionFor(AiPermissionAction.contentRead),
    );
    if (denied != null) return denied;
    final document = await _results.readDocument(id);
    if (document == null ||
        document.deleted ||
        document.status != ResultStatus.canonical) {
      return _failure('not_found', '成果不存在或当前不可读取。');
    }
    return _readResultLike(
      document: document,
      kind: 'result_read',
      source: 'result',
      requireGlobalKnowledge: false,
      offset: offset,
      length: length,
      cursor: cursor,
    );
  }

  Future<String> readGlobalKnowledge(
    String id, {
    int offset = 0,
    int length = 1200,
    String? cursor,
  }) async {
    final denied = _readDecisionFailure(
      _policy.decisionFor(
        AiPermissionAction.globalKnowledgeRead,
        knowledgeId: id,
      ),
    );
    if (denied != null) return denied;
    final document = await _results.readDocument(id);
    if (document == null ||
        document.deleted ||
        document.status != ResultStatus.canonical ||
        !document.isGlobalKnowledge) {
      return _failure('not_found', '全局知识不存在或当前不可读取。');
    }
    return _readResultLike(
      document: document,
      kind: 'global_knowledge_read',
      source: 'global_knowledge',
      requireGlobalKnowledge: true,
      offset: offset,
      length: length,
      cursor: cursor,
    );
  }

  Future<String> readOtherConversationMessage(
    String id, {
    int offset = 0,
    int length = 1200,
    String? cursor,
  }) async {
    final message = await _chats.findMessage(id);
    if (message == null ||
        message.conversationId == conversationId ||
        message.status != ChatMessageStatus.complete) {
      return _failure('not_found', '历史消息不存在或当前不可读取。');
    }
    final denied = _readDecisionFailure(
      _policy.decisionFor(
        AiPermissionAction.conversationHistoryRead,
        conversationId: message.conversationId,
      ),
    );
    if (denied != null) return denied;
    final sourceToken = await _chatSourceToken();
    final queryToken = retrievalDigest({'id': id});
    final decision = _detailDecision(
      key: _cacheKey('conversation_read', queryToken, sourceToken, {
        'offset': offset,
        'length': length,
      }),
      sourceToken: sourceToken,
    );
    if (!decision.proceed) return decision.response;
    try {
      offset = _cursorOffset(
        cursor: cursor,
        kind: 'conversation_read',
        queryToken: queryToken,
        sourceToken: sourceToken,
        fallback: offset,
      );
    } on _StaleCursor {
      return _staleCursor('历史会话已变化，请重新读取。');
    } on FormatException catch (error) {
      return _failure('invalid_cursor', error.message);
    }
    final conversation = await _chats.findConversation(message.conversationId);
    final slice = retrievalTextSlice(
      message.content,
      offset: offset,
      length: length.clamp(1, maxDetailChars),
    );
    final data = <String, Object?>{
      'source': 'conversation_message',
      'message_id': message.id,
      'conversation_id': message.conversationId,
      'conversation_title': conversation?.title ?? '已删除会话',
      'role': message.role.wireName,
      'content': slice.text,
      'contentOffset': slice.offset,
      'contentLength': slice.length,
      'contentTotalLength': slice.totalLength,
      'nextOffset': slice.nextOffset,
      'truncated': slice.nextOffset != null,
    };
    return _finishSuccess(
      key: _cacheKey('conversation_read', queryToken, sourceToken, {
        'offset': slice.offset,
        'length': length,
      }),
      sourceToken: sourceToken,
      data: data,
      coverage: _coverage(
        complete: slice.nextOffset == null,
        checkedEntries: 1,
        matchedEntries: 1,
        returnedEntries: 1,
        characters: _dataCharacters(data),
        nextOffset: slice.nextOffset,
        reason: slice.nextOffset == null ? null : '消息正文尚未读完。',
      ),
      nextCursor: slice.nextOffset == null
          ? null
          : opaqueRetrievalCursor({
              'kind': 'conversation_read',
              'offset': slice.nextOffset,
              'query': queryToken,
              'source': sourceToken,
              'session': conversationId,
              'policy': _policyVersion,
            }),
    );
  }

  Future<String> _readResultLike({
    required ResultDocument document,
    required String kind,
    required String source,
    required bool requireGlobalKnowledge,
    required int offset,
    required int length,
    required String? cursor,
  }) async {
    if (requireGlobalKnowledge && !document.isGlobalKnowledge) {
      return _failure('not_found', '全局知识不存在或当前不可读取。');
    }
    final sourceToken = retrievalDigest([
      document.id,
      document.revision,
      document.updatedAt.toIso8601String(),
      document.status.name,
    ]);
    final queryToken = retrievalDigest({'id': document.id});
    final decision = _detailDecision(
      key: _cacheKey(kind, queryToken, sourceToken, {
        'offset': offset,
        'length': length,
      }),
      sourceToken: sourceToken,
    );
    if (!decision.proceed) return decision.response;
    try {
      offset = _cursorOffset(
        cursor: cursor,
        kind: kind,
        queryToken: queryToken,
        sourceToken: sourceToken,
        fallback: offset,
      );
    } on _StaleCursor {
      return _staleCursor('成果已变化，请重新读取。');
    } on FormatException catch (error) {
      return _failure('invalid_cursor', error.message);
    }
    final facts = jsonEncode(document.extensionFields['global_facts'] ?? {});
    final content = document.isGlobalKnowledge ? facts : document.body;
    final slice = retrievalTextSlice(
      content,
      offset: offset,
      length: length.clamp(1, maxDetailChars),
    );
    final data = <String, Object?>{
      'source': source,
      'id': document.id,
      'type': document.type.wireName,
      'title': document.title,
      'revision': document.revision,
      'versionStatus': 'current',
      'content': slice.text,
      'contentOffset': slice.offset,
      'contentLength': slice.length,
      'contentTotalLength': slice.totalLength,
      'nextOffset': slice.nextOffset,
      'truncated': slice.nextOffset != null,
    };
    return _finishSuccess(
      key: _cacheKey(kind, queryToken, sourceToken, {
        'offset': slice.offset,
        'length': length,
      }),
      sourceToken: sourceToken,
      data: data,
      coverage: _coverage(
        complete: slice.nextOffset == null,
        checkedEntries: 1,
        matchedEntries: 1,
        returnedEntries: 1,
        characters: _dataCharacters(data),
        nextOffset: slice.nextOffset,
        reason: slice.nextOffset == null ? null : '正文尚未读完。',
      ),
      nextCursor: slice.nextOffset == null
          ? null
          : opaqueRetrievalCursor({
              'kind': kind,
              'offset': slice.nextOffset,
              'query': queryToken,
              'source': sourceToken,
              'session': conversationId,
              'policy': _policyVersion,
            }),
    );
  }

  _CacheDecision _beginSearch(String key, String sourceToken) {
    _searchCalls++;
    if (_searchCalls > maxSearches) {
      return _CacheDecision(
        proceed: false,
        response: _budgetBoundary('已达到本轮检索调用上限；请保存覆盖范围后继续。'),
      );
    }
    final cached = _cache[key];
    if (cached != null && cached.sourceToken == sourceToken) {
      return _CacheDecision(
        proceed: false,
        response: _reuseCached(cached.value),
      );
    }
    return const _CacheDecision(proceed: true);
  }

  _CacheDecision _detailDecision({
    required String key,
    required String sourceToken,
  }) {
    _detailCalls++;
    if (_detailCalls > maxDetails) {
      return _CacheDecision(
        proceed: false,
        response: _budgetBoundary('已达到本轮详情读取调用上限；请保存覆盖范围后继续。'),
      );
    }
    final cached = _cache[key];
    if (cached != null && cached.sourceToken == sourceToken) {
      return _CacheDecision(
        proceed: false,
        response: _reuseCached(cached.value),
      );
    }
    return const _CacheDecision(proceed: true);
  }

  String _finishSuccess({
    required String key,
    required String sourceToken,
    required Map<String, Object?> data,
    required Map<String, Object?> coverage,
    String? nextCursor,
    List<String> warnings = const [],
  }) {
    final response = _recordEnvelope(
      status: 'ok',
      data: data,
      coverage: coverage,
      nextCursor: nextCursor,
      warnings: warnings,
    );
    final decoded = jsonDecode(response);
    if (decoded is Map && decoded['status'] == 'ok') {
      _cache.remove(key);
      _cache[key] = _CachedResponse(sourceToken: sourceToken, value: response);
      while (_cache.length > _maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
    }
    return response;
  }

  String _recordEnvelope({
    required String status,
    required Map<String, Object?> data,
    required Map<String, Object?> coverage,
    String? nextCursor,
    List<String> warnings = const [],
  }) {
    final remaining = maxTurnChars - _resultChars;
    final envelope = <String, Object?>{
      'status': status,
      'data': data,
      'coverage': coverage,
      'nextCursor': nextCursor,
      'warnings': warnings,
      'budget': {
        'limitChars': maxTurnChars,
        'usedChars': _resultChars,
        'remainingChars': remaining,
        'searchCalls': _searchCalls,
        'detailCalls': _detailCalls,
      },
    };
    final encoded = jsonEncode(envelope);
    if (_runeLength(encoded) <= remaining - _outputReserve) {
      _resultChars += _runeLength(encoded);
      return encoded;
    }
    return _outputBoundary(nextCursor);
  }

  String _outputBoundary(String? nextCursor) {
    final response = jsonEncode({
      'status': 'batch_boundary',
      'data': <String, Object?>{},
      'coverage': {
        'complete': false,
        'reason': '本轮输出预算不足以完整返回下一项结果。',
        'uncovered': ['输出预算外的剩余结果'],
      },
      'nextCursor': nextCursor,
      'warnings': ['请保存检查点并在追加额度后从游标继续。'],
      'budget': {
        'limitChars': maxTurnChars,
        'usedChars': _resultChars,
        'remainingChars': (maxTurnChars - _resultChars).clamp(0, maxTurnChars),
      },
    });
    final remaining = maxTurnChars - _resultChars;
    if (_runeLength(response) <= remaining) {
      _resultChars += _runeLength(response);
    }
    return response;
  }

  String _reuseCached(String response) {
    final length = _runeLength(response);
    if (_resultChars + length <= maxTurnChars) {
      _resultChars += length;
      return response;
    }
    return _outputBoundary(null);
  }

  String? _readDecisionFailure(AiPolicyDecision decision) => switch (decision) {
    AiPolicyDecision.allow => null,
    AiPolicyDecision.ask => _confirmationRequired(),
    AiPolicyDecision.deny => _denied(),
  };

  String _denied() =>
      _failure('denied', '当前会话已关闭读取权限或该读取范围。', consumeBudget: false);

  String _scopeDenied(String message) =>
      _failure('denied', message, consumeBudget: false);

  String _confirmationRequired() => _failure(
    'confirmation_required',
    '当前读取动作需要用户确认后才能执行。',
    consumeBudget: false,
  );

  String _staleCursor(String message) => _failure('stale', message);

  String _budgetBoundary(String message) {
    return jsonEncode({
      'status': 'batch_boundary',
      'data': <String, Object?>{},
      'coverage': {
        'complete': false,
        'reason': message,
        'uncovered': ['本调用未执行'],
      },
      'nextCursor': null,
      'warnings': [message],
      'budget': {
        'limitChars': maxTurnChars,
        'usedChars': _resultChars,
        'remainingChars': (maxTurnChars - _resultChars).clamp(0, maxTurnChars),
        'searchCalls': _searchCalls,
        'detailCalls': _detailCalls,
      },
    });
  }

  String _failure(
    String status,
    String message, {
    Map<String, Object?> data = const {},
    bool consumeBudget = true,
  }) {
    final response = jsonEncode({
      'status': status,
      'error': message,
      'data': data,
      'coverage': {
        'complete': false,
        'reason': message,
        'uncovered': ['请求未完成'],
      },
      'nextCursor': null,
      'warnings': [message],
      'budget': {
        'limitChars': maxTurnChars,
        'usedChars': _resultChars,
        'remainingChars': (maxTurnChars - _resultChars).clamp(0, maxTurnChars),
        'searchCalls': _searchCalls,
        'detailCalls': _detailCalls,
      },
    });
    if (consumeBudget) {
      final remaining = maxTurnChars - _resultChars;
      if (_runeLength(response) <= remaining) {
        _resultChars += _runeLength(response);
      }
    }
    return response;
  }

  String _cacheKey(
    String kind,
    String queryToken,
    String sourceToken,
    Map<String, Object?> page,
  ) => retrievalDigest({
    'conversationId': conversationId,
    'policy': _policyVersion,
    'kind': kind,
    'query': queryToken,
    'source': sourceToken,
    'page': page,
  });

  int _cursorOffset({
    required String? cursor,
    required String kind,
    required String queryToken,
    required String sourceToken,
    required int fallback,
  }) {
    if (cursor == null) return fallback < 0 ? 0 : fallback;
    final payload = decodeRetrievalCursor(cursor);
    if (payload['kind'] != kind) {
      throw const FormatException('检索游标用途不匹配。');
    }
    if (payload['session'] != conversationId ||
        payload['policy'] != _policyVersion) {
      throw const _StaleCursor();
    }
    if (payload['query'] != queryToken || payload['source'] != sourceToken) {
      throw const _StaleCursor();
    }
    final value = payload['offset'];
    if (value is! num || value < 0) {
      throw const FormatException('检索游标位置无效。');
    }
    return value.toInt();
  }

  String? _parseRole(String? role) {
    if (role == null) return null;
    for (final candidate in TableRole.values) {
      if (candidate.name == role || candidate.wireName == role) {
        return candidate.name;
      }
    }
    return null;
  }

  String _tableSourceToken({required bool includeEntries}) {
    final tables = _tables;
    if (tables == null) return retrievalDigest('tables:none');
    return retrievalDigest({
      'tables': [
        for (final table in tables.tables)
          if (_policy.tableScope.covers(table.id))
            [
              table.id,
              table.revision,
              table.deleted,
              table.updatedAt.toIso8601String(),
            ],
      ],
      if (includeEntries)
        'entries': [
          for (final entry in tables.entries)
            if (_policy.tableScope.covers(entry.tableId))
              [
                entry.id,
                entry.revision,
                entry.deleted,
                entry.tableId,
                entry.updatedAt.toIso8601String(),
              ],
        ],
    });
  }

  String _resultsSourceToken() => retrievalDigest([
    for (final document in _results.documents)
      if (document.isGlobalKnowledge
          ? _policy.decisionFor(AiPermissionAction.globalKnowledgeSearch) !=
                    AiPolicyDecision.deny &&
                _policy.knowledgeReadScope.covers(document.id)
          : _policy.decisionFor(AiPermissionAction.contentRead) !=
                AiPolicyDecision.deny)
        [
          document.id,
          document.type.wireName,
          document.revision,
          document.status.name,
          document.deleted,
          document.updatedAt.toIso8601String(),
        ],
  ]);

  Future<String> _chatSourceToken() async {
    final conversations = await _chats.listConversations();
    final values = <Object?>[];
    for (final conversation in conversations) {
      if (conversation.id == conversationId) continue;
      if (!_policy.conversationHistoryReadScope.covers(conversation.id)) {
        continue;
      }
      values.add([conversation.id, conversation.updatedAt.toIso8601String()]);
      for (final message in await _chats.listMessages(conversation.id)) {
        values.add([
          message.id,
          message.status.name,
          message.updatedAt.toIso8601String(),
        ]);
      }
    }
    return retrievalDigest(values);
  }

  _LocalPage<T> _paginate<T>(List<T> values, int offset, int? limit) {
    final safeOffset = offset.clamp(0, values.length);
    final end = limit == null
        ? values.length
        : (safeOffset + limit).clamp(safeOffset, values.length);
    return _LocalPage(
      items: List.unmodifiable(values.sublist(safeOffset, end)),
      offset: safeOffset,
      nextOffset: end < values.length ? end : null,
    );
  }

  Map<String, Object?> _coverage({
    required bool complete,
    List<String> checkedTables = const [],
    int? checkedEntries,
    int? matchedEntries,
    int? returnedEntries,
    int? characters,
    int? nextOffset,
    String? reason,
  }) => {
    'complete': complete,
    'scopeComplete': true,
    'checkedTables': checkedTables,
    'checkedEntries': checkedEntries,
    'matchedEntries': matchedEntries,
    'returnedEntries': returnedEntries,
    'characters': characters,
    'nextOffset': nextOffset,
    'uncovered': reason == null ? <String>[] : [reason],
  };

  int _dataCharacters(Map<String, Object?> data) =>
      _runeLength(jsonEncode(data));

  Map<String, Object?> _boundedFieldValues(Map<String, Object?> values) => {
    for (final entry in values.entries) entry.key: _boundedValue(entry.value),
  };

  Object? _boundedValue(Object? value) {
    if (value is String) return _clip(value, maxHitChars);
    if (value is List) {
      return value.take(20).map(_boundedValue).toList(growable: false);
    }
    if (value is Map) {
      return {
        for (final entry in value.entries.take(20))
          '${entry.key}': _boundedValue(entry.value),
      };
    }
    return value;
  }

  String _clip(String value, int limit) {
    final runes = value.runes.toList(growable: false);
    if (runes.length <= limit) return value;
    if (limit <= 1) return '…';
    return '${String.fromCharCodes(runes.take(limit - 1))}…';
  }

  int _runeLength(String value) => value.runes.length;

  DateTime? _businessAt(TableEntryDocument entry) => switch (entry.type) {
    TableContentType.todo => entry.due,
    TableContentType.schedule => entry.start,
    TableContentType.event => entry.occurredAt,
    TableContentType.note => null,
  };
}

class _CachedResponse {
  const _CachedResponse({required this.sourceToken, required this.value});

  final String sourceToken;
  final String value;
}

class _CacheDecision {
  const _CacheDecision({required this.proceed, String? response})
    : _response = response;

  final bool proceed;
  final String? _response;

  String get response => _response!;
}

class _LocalPage<T> {
  const _LocalPage({
    required this.items,
    required this.offset,
    required this.nextOffset,
  });

  final List<T> items;
  final int offset;
  final int? nextOffset;
}

class _VerificationSnapshot {
  const _VerificationSnapshot({required this.revision, required this.fields});

  final int revision;
  final Map<String, Object?> fields;
}

class _StaleCursor implements Exception {
  const _StaleCursor();
}
