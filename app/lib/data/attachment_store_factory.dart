import 'attachment_store.dart';
import 'attachment_store_factory_io.dart'
    if (dart.library.js_interop) 'attachment_store_factory_web.dart'
    as platform;

Future<AttachmentStore> createAttachmentStore() {
  return platform.createAttachmentStore();
}
