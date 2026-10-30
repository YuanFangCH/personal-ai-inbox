import 'dart:convert';

import '../../core/chat_models.dart';
import '../../core/models.dart';
import '../../core/table_models.dart';
import '../../data/chat_repository.dart';
import '../results/result_library.dart';
import '../tables/table_library.dart';

/// Enforces one shared read budget for every local retrieval tool in a turn.
class LocalRetrieval {
  LocalRetrieval({
    required this.conversationId,
    required AiPermissions permissions,
    required ChatRepository chats,
    required ResultLibrary results,
    TableLibrary? tables,
  }) : _readAllowed = permissions.read,
       _chats = chats,
       _results = results,
       _tables = tables;

  static const maxSearches = 2;
  static const maxHitsPerSearch = 5;
  static const maxDetails = 3;
  static const maxTablesPerSearch = 20;
  static const maxHitChars = 300;
  static const maxDetailChars = 1200;
  static const maxTurnChars = 6000;

  final String conversationId;
  final bool _readAllowed;
  final ChatRepository _chats;
  final ResultLibrary _results;
  final TableLibrary? _tables;
  final Map<String, String> _cache = {};
  var _searchCalls = 0;
  var _detailCalls = 0;
  var _resultChars = 0;

  int get searchCalls => _searchCalls;
  int get detailCalls => _detailCalls;
  int get resultChars => _resultChars;
  int get searchRounds => _searchCalls == 0 ? 0 : ((_searchCalls - 1) ~/ 2) + 1;

  Future<String> searchResults({
    required String query,
    ResultType? type,
    bool globalKnowledgeOnly = false,
  }) async {
    if (!_readAllowed) return _error('当前会话未开启读取权限。');
    final key =
        'results:${type?.wireName}:$globalKnowledgeOnly:${_normalize(query)}';
    final cached = _beginSearch(key);
    if (cached != null) return cached;
    if (query.trim().isEmpty) return _record(key, _error('搜索词不能为空。'));
    final documents = await _results.searchResults(
      query: query,
      type: globalKnowledgeOnly ? ResultType.knowledge : type,
      globalKnowledgeOnly: globalKnowledgeOnly,
      limit: maxHitsPerSearch,
    );
    final hits = documents
        .map((document) {
          final source = document.isGlobalKnowledge
              ? jsonEncode(document.extensionFields['global_facts'] ?? {})
              : document.body;
          return {
            'id': document.id,
            'type': document.type.wireName,
            'title': document.title,
            'revision': document.revision,
            'snippet': _clip(source, maxHitChars),
            'truncated': _runeLength(source) > maxHitChars,
          };
        })
        .toList(growable: false);
    return _record(key, _encodeBounded({'source': 'results', 'hits': hits}));
  }

  Future<String> searchOtherConversations(String query) async {
    if (!_readAllowed) return _error('当前会话未开启读取权限。');
    final key = 'chats:${_normalize(query)}';
    final cached = _beginSearch(key);
    if (cached != null) return cached;
    if (query.trim().isEmpty) return _record(key, _error('搜索词不能为空。'));
    final messages = await _chats.searchOtherConversations(
      query: query,
      currentConversationId: conversationId,
      limit: maxHitsPerSearch,
    );
    final hits = <Map<String, Object?>>[];
    for (final message in messages) {
      if (message.status != ChatMessageStatus.complete) continue;
      final conversation = await _chats.findConversation(
        message.conversationId,
      );
      hits.add({
        'message_id': message.id,
        'conversation_id': message.conversationId,
        'conversation_title': conversation?.title ?? '已删除会话',
        'role': message.role.wireName,
        'snippet': _clip(message.content, maxHitChars),
        'truncated': _runeLength(message.content) > maxHitChars,
      });
    }
    return _record(
      key,
      _encodeBounded({'source': 'conversations', 'hits': hits}),
    );
  }

  Future<String> listTables({String? role, int limit = 20}) async {
    if (!_readAllowed) return _error('当前会话未开启读取权限。');
    final tables = _tables;
    if (tables == null) return _error('表库暂不可用。');
    final key = 'table_list:${role ?? ''}:$limit';
    final cached = _beginSearch(key);
    if (cached != null) return cached;
    final selected = tables.tables
        .where((table) => role == null || table.role.name == role)
        .take(limit.clamp(1, 50))
        .map(
          (table) => {
            'id': table.id,
            'title': table.title,
            'role': table.role.name,
            'revision': table.revision,
            'summary': _clip(table.body, maxHitChars),
          },
        )
        .toList(growable: false);
    return _record(key, _encodeBounded({'source': 'tables', 'hits': selected}));
  }

  Future<String> searchTables(
    String query, {
    int limit = maxHitsPerSearch,
  }) async {
    if (!_readAllowed) return _error('当前会话未开启读取权限。');
    final tables = _tables;
    if (tables == null) return _error('表库暂不可用。');
    final key = 'table_search:${_normalize(query)}:$limit';
    final cached = _beginSearch(key);
    if (cached != null) return cached;
    if (query.trim().isEmpty) return _record(key, _error('搜索词不能为空。'));
    final matches = await tables.searchTables(
      query: query,
      limit: limit.clamp(1, maxHitsPerSearch),
    );
    return _record(
      key,
      _encodeBounded({
        'source': 'tables',
        'hits': [
          for (final table in matches)
            {
              'id': table.id,
              'title': table.title,
              'role': table.role.name,
              'revision': table.revision,
              'snippet': _clip(table.body, maxHitChars),
              'truncated': _runeLength(table.body) > maxHitChars,
            },
        ],
      }),
    );
  }

  Future<String> searchTableEntries({
    required String query,
    List<String> tableIds = const [],
    List<String> types = const [],
    DateTime? from,
    DateTime? through,
    Map<String, Object?> fieldFilters = const {},
    int limit = maxHitsPerSearch,
  }) async {
    if (!_readAllowed) return _error('当前会话未开启读取权限。');
    final tables = _tables;
    if (tables == null) return _error('表库暂不可用。');
    if (from != null && through != null && through.isBefore(from)) {
      return _error('时间范围结束早于开始。');
    }
    final safeTypes = <TableContentType>[];
    for (final value in types) {
      final type = TableContentType.values
          .where((candidate) => candidate.name == value)
          .firstOrNull;
      if (type == null) return _error('内容类型无效：$value');
      safeTypes.add(type);
    }
    if (tableIds.length > maxTablesPerSearch) {
      return _error('一次最多跨表搜索 $maxTablesPerSearch 张表。');
    }
    final allTableIds = tables.tables.map((table) => table.id).toList();
    final selectedIds = tableIds.isEmpty
        ? allTableIds.take(maxTablesPerSearch).toList(growable: false)
        : tableIds;
    if (selectedIds.any((id) => tables.findTable(id) == null)) {
      return _error('查询包含不存在的表。');
    }
    final key =
        'content_search:${jsonEncode({'query': _normalize(query), 'tables': selectedIds, 'types': types, 'from': from?.toIso8601String(), 'through': through?.toIso8601String(), 'fields': fieldFilters, 'limit': limit})}';
    final cached = _beginSearch(key);
    if (cached != null) return cached;
    final entries = <TableEntryDocument>[];
    for (final id in selectedIds) {
      final typesForQuery = safeTypes.isEmpty ? [null] : safeTypes;
      for (final type in typesForQuery) {
        entries.addAll(
          await tables.searchEntries(
            query: query,
            tableId: id,
            type: type,
            from: from,
            through: through,
            fieldFilters: fieldFilters,
            limit: limit.clamp(1, maxHitsPerSearch),
          ),
        );
      }
    }
    final selected = entries.toList()
      ..sort(
        (a, b) => (_businessAt(b) ?? b.updatedAt).compareTo(
          _businessAt(a) ?? a.updatedAt,
        ),
      );
    final hits = selected
        .take(limit.clamp(1, maxHitsPerSearch))
        .map((entry) {
          final table = tables.findTable(entry.tableId)!;
          final source = '${entry.title}\n${entry.body}';
          return {
            'id': entry.id,
            'table_id': entry.tableId,
            'table_title': table.title,
            'type': entry.type.name,
            'revision': entry.revision,
            'business_at': _businessAt(entry)?.toIso8601String(),
            'custom_values': _boundedFieldValues(entry.customValues),
            'snippet': _clip(source, maxHitChars),
            'truncated': _runeLength(source) > maxHitChars,
          };
        })
        .toList(growable: false);
    return _record(
      key,
      _encodeBounded({
        'source': 'table_entries',
        'hits': hits,
        'table_scope_truncated':
            tableIds.isEmpty && allTableIds.length > maxTablesPerSearch,
      }),
    );
  }

  Future<String> readTableEntry(String id, {int? expectedRevision}) async {
    if (!_readAllowed) return _error('当前会话未开启读取权限。');
    if (expectedRevision == null) return _error('读取表内内容必须提供搜索结果中的 revision。');
    if (_detailCalls >= maxDetails) return _error('已达到本轮详情读取上限。');
    _detailCalls++;
    final entry = await _tables?.readEntry(id);
    if (entry == null || entry.deleted) return _error('表内内容不存在或不可读取。');
    if (entry.revision != expectedRevision) {
      return _error('内容版本已变化，请重新搜索后读取。');
    }
    final table = _tables!.findTable(entry.tableId);
    if (table == null || table.deleted) return _error('内容所属表不可读取。');
    final detail = _clip(entry.body, maxDetailChars);
    return _recordText(
      jsonEncode({
        'source': 'table_entry',
        'id': entry.id,
        'table_id': table.id,
        'table_title': table.title,
        'type': entry.type.name,
        'title': entry.title,
        'revision': entry.revision,
        'body': detail,
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
        'truncated': _runeLength(entry.body) > maxDetailChars,
      }),
    );
  }

  Future<String> readTable(String id, {int? expectedRevision}) async {
    if (!_readAllowed) return _error('当前会话未开启读取权限。');
    if (expectedRevision == null) return _error('读取表必须提供搜索结果中的 revision。');
    if (_detailCalls >= maxDetails) return _error('已达到本轮详情读取上限。');
    _detailCalls++;
    final table = _tables?.findTable(id);
    if (table == null || table.deleted) return _error('表不存在或不可读取。');
    if (table.revision != expectedRevision) {
      return _error('表版本已变化，请重新读取。');
    }
    final body = _clip(table.body, maxDetailChars);
    return _recordText(
      jsonEncode({
        'source': 'table',
        'id': table.id,
        'title': table.title,
        'role': table.role.name,
        'revision': table.revision,
        'body': body,
        'fields': [
          for (final field in table.fields)
            {
              'id': field.id,
              'name': field.name,
              'type': field.type.name,
              'options': [
                for (final option in field.options)
                  {'id': option.id, 'label': option.label},
              ],
            },
        ],
        'truncated': _runeLength(table.body) > maxDetailChars,
      }),
    );
  }

  Future<String> readResult(String id) async {
    if (!_readAllowed) return _error('当前会话未开启读取权限。');
    if (_detailCalls >= maxDetails) return _error('已达到本轮详情读取上限。');
    _detailCalls++;
    final document = await _results.readDocument(id);
    if (document == null ||
        document.deleted ||
        document.status != ResultStatus.canonical) {
      return _error('成果不存在或当前不可读取。');
    }
    final detail = document.isGlobalKnowledge
        ? jsonEncode(document.extensionFields['global_facts'] ?? {})
        : document.body;
    final clipped = _clip(detail, maxDetailChars);
    return _recordText(
      jsonEncode({
        'source': 'result',
        'id': document.id,
        'type': document.type.wireName,
        'title': document.title,
        'revision': document.revision,
        'content': clipped,
        'truncated': _runeLength(detail) > maxDetailChars,
      }),
    );
  }

  Future<String> readGlobalKnowledge(String id) async {
    if (!_readAllowed) return _error('当前会话未开启读取权限。');
    if (_detailCalls >= maxDetails) return _error('已达到本轮详情读取上限。');
    _detailCalls++;
    final document = await _results.readDocument(id);
    if (document == null ||
        document.deleted ||
        document.status != ResultStatus.canonical ||
        !document.isGlobalKnowledge) {
      return _error('全局知识不存在或当前不可读取。');
    }
    final detail = jsonEncode(document.extensionFields['global_facts'] ?? {});
    return _recordText(
      jsonEncode({
        'source': 'global_knowledge',
        'id': document.id,
        'title': document.title,
        'revision': document.revision,
        'content': _clip(detail, maxDetailChars),
        'truncated': _runeLength(detail) > maxDetailChars,
      }),
    );
  }

  Future<String> readOtherConversationMessage(String id) async {
    if (!_readAllowed) return _error('当前会话未开启读取权限。');
    if (_detailCalls >= maxDetails) return _error('已达到本轮详情读取上限。');
    _detailCalls++;
    final message = await _chats.findMessage(id);
    if (message == null ||
        message.conversationId == conversationId ||
        message.status != ChatMessageStatus.complete) {
      return _error('历史消息不存在或当前不可读取。');
    }
    final conversation = await _chats.findConversation(message.conversationId);
    final clipped = _clip(message.content, maxDetailChars);
    return _recordText(
      jsonEncode({
        'source': 'conversation_message',
        'message_id': message.id,
        'conversation_id': message.conversationId,
        'conversation_title': conversation?.title ?? '已删除会话',
        'role': message.role.wireName,
        'content': clipped,
        'truncated': _runeLength(message.content) > maxDetailChars,
      }),
    );
  }

  String? _beginSearch(String key) {
    _searchCalls++;
    if (_searchCalls > maxSearches) return _error('已达到本轮搜索次数上限。');
    return _cache[key];
  }

  String _record(String key, String value) {
    final bounded = _recordText(value);
    _cache[key] = bounded;
    return bounded;
  }

  String _recordText(String value) {
    final remaining = maxTurnChars - _resultChars;
    if (remaining <= 0) return _error('已达到本轮检索内容上限。');
    final bounded = _clip(value, remaining);
    _resultChars += _runeLength(bounded);
    return bounded;
  }

  String _encodeBounded(Map<String, Object?> value) => jsonEncode(value);

  String _error(String message) => jsonEncode({'error': message});

  String _normalize(String query) =>
      query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String _clip(String value, int limit) {
    final runes = value.runes;
    final length = _runeLength(value);
    if (length <= limit) return value;
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

  Map<String, Object?> _boundedFieldValues(Map<String, Object?> values) => {
    for (final entry in values.entries)
      entry.key: entry.value is String
          ? _clip(entry.value as String, maxHitChars)
          : entry.value is List
          ? (entry.value as List)
                .take(20)
                .map((value) => value is String ? _clip(value, 80) : value)
                .toList(growable: false)
          : entry.value,
  };
}
