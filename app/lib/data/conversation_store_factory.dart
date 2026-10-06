import 'conversation_store.dart';
import 'conversation_store_factory_io.dart'
    if (dart.library.js_interop) 'conversation_store_factory_web.dart'
    as platform;

Future<ConversationStore> createConversationStore(String appSupportPath) {
  return platform.createConversationStore(appSupportPath);
}
