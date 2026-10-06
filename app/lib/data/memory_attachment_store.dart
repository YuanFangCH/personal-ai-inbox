import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../core/chat_models.dart';
import 'attachment_store.dart';

class MemoryAttachmentStore implements AttachmentStore {
  final Map<String, Uint8List> _values = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<ChatAttachment> save(
    ChatAttachmentInput input, {
    required String conversationId,
    required String messageId,
  }) async {
    final id = 'att_${const Uuid().v4()}';
    final storageKey = '$conversationId/$messageId/$id';
    _values[storageKey] = Uint8List.fromList(input.bytes);
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
    return _values[attachment.storageKey];
  }

  @override
  Future<void> delete(ChatAttachment attachment) async {
    _values.remove(attachment.storageKey);
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    _values.removeWhere((key, _) => key.startsWith('$conversationId/'));
  }

  @override
  Future<String> describeRoot() async => '内存图片存储';
}
