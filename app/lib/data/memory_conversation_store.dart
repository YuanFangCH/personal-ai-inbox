import '../core/chat_models.dart';
import 'conversation_store.dart';

class MemoryConversationStore implements ConversationStore {
  final Map<String, Conversation> _conversations = {};
  final Map<String, ChatMessage> _messages = {};
  final Map<String, GenerationRun> _generations = {};

  @override
  Future<void> open() async {}

  @override
  Future<void> close() async {}

  @override
  Future<List<Conversation>> listConversations() async {
    final values = _conversations.values.toList(growable: false)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return values;
  }

  @override
  Future<Conversation?> findConversation(String id) async => _conversations[id];

  @override
  Future<void> upsertConversation(Conversation conversation) async {
    _conversations[conversation.id] = conversation;
  }

  @override
  Future<void> deleteConversation(String id) async {
    _conversations.remove(id);
    _messages.removeWhere((_, message) => message.conversationId == id);
    _generations.removeWhere(
      (_, generation) => generation.conversationId == id,
    );
  }

  @override
  Future<List<ChatMessage>> listMessages(String conversationId) async {
    final values =
        _messages.values
            .where((message) => message.conversationId == conversationId)
            .toList(growable: false)
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return values;
  }

  @override
  Future<List<ChatMessage>> searchMessages({
    required String query,
    required String excludedConversationId,
    required int limit,
  }) async {
    final terms = query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((term) => term.isEmpty);
    if (terms.isEmpty) return const [];
    final messages =
        _messages.values
            .where(
              (message) =>
                  message.conversationId != excludedConversationId &&
                  message.status == ChatMessageStatus.complete &&
                  terms.every(
                    (term) => message.content.toLowerCase().contains(term),
                  ),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return messages.take(limit.clamp(1, 5)).toList(growable: false);
  }

  @override
  Future<ChatMessage?> findMessage(String id) async => _messages[id];

  @override
  Future<void> upsertMessage(ChatMessage message) async {
    _messages[message.id] = message;
  }

  @override
  Future<GenerationRun?> findGeneration(String assistantMessageId) async =>
      _generations[assistantMessageId];

  @override
  Future<void> upsertGeneration(GenerationRun generation) async {
    _generations[generation.assistantMessageId] = generation;
  }

  @override
  Future<void> deleteGeneration(String assistantMessageId) async {
    _generations.remove(assistantMessageId);
  }

  @override
  Future<List<GenerationRun>> listRecoverableGenerations() async {
    return _generations.values
        .where(
          (generation) =>
              generation.status == GenerationStatus.requesting ||
              generation.status == GenerationStatus.responseReady,
        )
        .toList(growable: false);
  }

  @override
  Future<void> deleteMessage(String id) async {
    _messages.remove(id);
    _generations.remove(id);
  }

  @override
  Future<AutoRecordAction?> findAutoRecordAction(String id) async {
    for (final message in _messages.values) {
      for (final action in message.actions) {
        if (action.id == id) {
          return action;
        }
      }
    }
    return null;
  }

  @override
  Future<void> clear() async {
    _conversations.clear();
    _messages.clear();
    _generations.clear();
  }
}
