import 'package:flutter/services.dart';

import 'share_payload.dart';

const _channel = MethodChannel('com.yuanfang.aitext.personal_ai_inbox/share');

Future<void> initializeShareBridge(
  Future<void> Function(SharedCapturePayload payload) onPayload,
) async {
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'sharedPayload') {
      final payload = _decodePayload(call.arguments);
      if (!payload.isEmpty) {
        await onPayload(payload);
      }
    }
    return null;
  });

  try {
    final initial = await _channel.invokeMethod<dynamic>('getInitialPayload');
    final payload = _decodePayload(initial);
    if (!payload.isEmpty) {
      await onPayload(payload);
    }
  } on MissingPluginException {
    // The bridge is only implemented by the Android shell.
  }
}

SharedCapturePayload _decodePayload(dynamic value) {
  if (value is! Map) {
    return const SharedCapturePayload();
  }
  final text = value['text']?.toString() ?? '';
  final rawImages = value['images'];
  final images = <SharedImageFile>[];
  if (rawImages is List) {
    for (final rawImage in rawImages) {
      if (rawImage is! Map) {
        continue;
      }
      final path = rawImage['path']?.toString() ?? '';
      if (path.isEmpty) {
        continue;
      }
      images.add(
        SharedImageFile(
          path: path,
          fileName: rawImage['name']?.toString() ?? 'image.jpg',
          mimeType: rawImage['mime_type']?.toString() ?? 'image/jpeg',
        ),
      );
    }
  }
  return SharedCapturePayload(text: text, images: images);
}
