import 'share_bridge_io.dart'
    if (dart.library.js_interop) 'share_bridge_web.dart'
    as platform;
import 'share_payload.dart';

typedef SharedPayloadHandler = Future<void> Function(
  SharedCapturePayload payload,
);

Future<void> initializeShareBridge(SharedPayloadHandler onPayload) {
  return platform.initializeShareBridge(onPayload);
}
