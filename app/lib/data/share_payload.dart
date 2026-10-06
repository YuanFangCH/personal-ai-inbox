import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

class SharedImageFile {
  const SharedImageFile({
    required this.path,
    required this.fileName,
    required this.mimeType,
  });

  final String path;
  final String fileName;
  final String mimeType;
}

class SharedCapturePayload {
  const SharedCapturePayload({this.text = '', this.images = const []});

  final String text;
  final List<SharedImageFile> images;

  bool get isEmpty => text.trim().isEmpty && images.isEmpty;

  Future<List<({Uint8List bytes, String fileName, String mimeType})>>
  readImages() async {
    final values = <({Uint8List bytes, String fileName, String mimeType})>[];
    for (final image in images) {
      final bytes = await XFile(image.path).readAsBytes();
      if (bytes.isNotEmpty) {
        values.add((
          bytes: bytes,
          fileName: image.fileName,
          mimeType: image.mimeType,
        ));
      }
    }
    return values;
  }
}
