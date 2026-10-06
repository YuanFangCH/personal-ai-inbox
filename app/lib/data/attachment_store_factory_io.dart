import 'attachment_store.dart';
import 'io_attachment_store.dart';

Future<AttachmentStore> createAttachmentStore() {
  return IoAttachmentStore.create();
}
