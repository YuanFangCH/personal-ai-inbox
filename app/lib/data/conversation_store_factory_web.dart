import 'conversation_store.dart';
import 'memory_conversation_store.dart';

Future<ConversationStore> createConversationStore(String appSupportPath) async {
  final store = MemoryConversationStore();
  await store.open();
  return store;
}
