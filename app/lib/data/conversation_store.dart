import '../core/chat_models.dart';

abstract interface class ConversationStore {
  Future<void> open();

  Future<void> close();

  Future<List<Conversation>> listConversations();

  Future<Conversation?> findConversation(String id);

  Future<void> upsertConversation(Conversation conversation);

  Future<void> deleteConversation(String id);

  Future<List<ChatMessage>> listMessages(String conversationId);

  Future<ChatMessage?> findMessage(String id);

  Future<void> upsertMessage(ChatMessage message);

  Future<void> deleteMessage(String id);

  Future<AutoRecordAction?> findAutoRecordAction(String id);

  Future<void> clear();
}
