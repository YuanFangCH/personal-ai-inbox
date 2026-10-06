import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../core/chat_models.dart';

class ImageInputService {
  ImageInputService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  static const maxImagesPerMessage = 4;
  static const _maxImageBytes = 12 * 1024 * 1024;
  static const _maxImageDimension = 2048;

  final ImagePicker _picker;

  Future<List<ChatAttachmentInput>> pickFromGallery({
    int limit = maxImagesPerMessage,
  }) async {
    final files = await _picker.pickMultiImage(
      imageQuality: 95,
      maxWidth: _maxImageDimension.toDouble(),
      maxHeight: _maxImageDimension.toDouble(),
      limit: limit,
    );
    return _normalizeAll(files.take(limit));
  }

  Future<List<ChatAttachmentInput>> pickFromCamera() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
      maxWidth: _maxImageDimension.toDouble(),
      maxHeight: _maxImageDimension.toDouble(),
    );
    if (file == null) {
      return const [];
    }
    return _normalizeAll([file]);
  }

  Future<List<ChatAttachmentInput>> fromBytes(
    Iterable<({Uint8List bytes, String fileName, String mimeType})> values,
  ) {
    return _normalizeAll(
      values.map(
        (value) => XFile.fromData(
          value.bytes,
          name: value.fileName,
          mimeType: value.mimeType,
        ),
      ),
    );
  }

  Future<List<ChatAttachmentInput>> _normalizeAll(Iterable<XFile> files) async {
    final result = <ChatAttachmentInput>[];
    for (final file in files) {
      final normalized = await _normalize(file);
      if (normalized != null) {
        result.add(normalized);
      }
    }
    return result;
  }

  Future<ChatAttachmentInput?> _normalize(XFile file) async {
    final sourceBytes = await file.readAsBytes();
    if (sourceBytes.isEmpty) {
      return null;
    }
    var bytes = sourceBytes;
    var mimeType = file.mimeType ?? _mimeFromName(file.name);
    var fileName = _normalizeName(file.name, mimeType);

    final decoded = img.decodeImage(sourceBytes);
    if (decoded != null) {
      var image = img.bakeOrientation(decoded);
      if (image.width > _maxImageDimension ||
          image.height > _maxImageDimension) {
        image = img.copyResize(
          image,
          width: image.width >= image.height ? _maxImageDimension : null,
          height: image.height > image.width ? _maxImageDimension : null,
          interpolation: img.Interpolation.linear,
        );
      }
      bytes = Uint8List.fromList(img.encodeJpg(image, quality: 86));
      mimeType = 'image/jpeg';
      fileName = '${_baseName(file.name)}.jpg';
    }

    if (bytes.length > _maxImageBytes) {
      return null;
    }
    return ChatAttachmentInput(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
  }

  String _mimeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    return 'image/jpeg';
  }

  String _normalizeName(String name, String mimeType) {
    if (name.trim().isNotEmpty) {
      return name;
    }
    return switch (mimeType) {
      'image/png' => 'image.png',
      'image/webp' => 'image.webp',
      'image/gif' => 'image.gif',
      _ => 'image.jpg',
    };
  }

  String _baseName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      return 'image';
    }
    final dot = normalized.lastIndexOf('.');
    return dot <= 0 ? normalized : normalized.substring(0, dot);
  }
}
