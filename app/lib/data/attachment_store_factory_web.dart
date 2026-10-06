import 'attachment_store.dart';
import 'memory_attachment_store.dart';

Future<AttachmentStore> createAttachmentStore() async {
  final store = MemoryAttachmentStore();
  await store.initialize();
  return store;
}
