import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/chat_models.dart';
import 'attachment_store.dart';

class IoAttachmentStore implements AttachmentStore {
  IoAttachmentStore._(this._root);

  final Directory _root;

  static Future<IoAttachmentStore> create() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'chat_attachments'));
    await root.create(recursive: true);
    return IoAttachmentStore._(root);
  }

  @override
  Future<void> initialize() => _root.create(recursive: true);

  @override
  Future<ChatAttachment> save(
    ChatAttachmentInput input, {
    required String conversationId,
    required String messageId,
  }) async {
    final id = 'att_${const Uuid().v4()}';
    final extension = _extension(input.fileName, input.mimeType);
    final storageKey =
        '${_safe(conversationId)}/${_safe(messageId)}/$id$extension';
    final file = _resolve(storageKey);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(input.bytes, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
    return ChatAttachment(
      id: id,
      storageKey: storageKey,
      fileName: input.fileName,
      mimeType: input.mimeType,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<Uint8List?> read(ChatAttachment attachment) async {
    final file = _resolve(attachment.storageKey);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  @override
  Future<void> delete(ChatAttachment attachment) async {
    final file = _resolve(attachment.storageKey);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    final directory = Directory(p.join(_root.path, _safe(conversationId)));
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  @override
  Future<String> describeRoot() async => _root.path;

  File _resolve(String storageKey) {
    final normalized = p.normalize(storageKey).replaceAll('\\', '/');
    if (normalized == '..' || normalized.startsWith('../')) {
      throw ArgumentError.value(storageKey, 'storageKey', 'Must stay in root');
    }
    return File(p.join(_root.path, normalized));
  }

  String _extension(String fileName, String mimeType) {
    final extension = p.extension(fileName).toLowerCase();
    if (extension.isNotEmpty) {
      return extension;
    }
    return switch (mimeType.toLowerCase()) {
      'image/png' => '.png',
      'image/webp' => '.webp',
      'image/gif' => '.gif',
      _ => '.jpg',
    };
  }

  String _safe(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }
}
