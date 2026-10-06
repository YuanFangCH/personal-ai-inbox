import '../core/chat_models.dart';
import 'conversation_store.dart';

class MemoryConversationStore implements ConversationStore {
  final Map<String, Conversation> _conversations = {};
  final Map<String, ChatMessage> _messages = {};

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
  Future<ChatMessage?> findMessage(String id) async => _messages[id];

  @override
  Future<void> upsertMessage(ChatMessage message) async {
    _messages[message.id] = message;
  }

  @override
  Future<void> deleteMessage(String id) async {
    _messages.remove(id);
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
  }
}
