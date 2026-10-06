import 'package:path/path.dart' as p;

import 'conversation_store.dart';
import 'sqlite_conversation_store.dart';

Future<ConversationStore> createConversationStore(String appSupportPath) async {
  final store = SqliteConversationStore(
    p.join(appSupportPath, 'conversations.sqlite3'),
  );
  await store.open();
  return store;
}
