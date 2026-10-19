import 'dart:convert';

import '../../core/chat_models.dart';
import '../../core/models.dart';
import '../../data/chat_repository.dart';
import '../results/result_library.dart';

/// Enforces one shared read budget for every local retrieval tool in a turn.
class LocalRetrieval {
  LocalRetrieval({
    required this.conversationId,
    required AiPermissions permissions,
    required ChatRepository chats,
    required ResultLibrary results,
  }) : _readAllowed = permissions.read,
       _chats = chats,
       _results = results;

  static const maxSearches = 2;
  static const maxHitsPerSearch = 5;
  static const maxDetails = 3;
  static const maxHitChars = 300;
  static const maxDetailChars = 1200;
  static const maxTurnChars = 6000;

  final String conversationId;
  final bool _readAllowed;
  final ChatRepository _chats;
  final ResultLibrary _results;
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
}
