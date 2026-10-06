import 'dart:typed_data';

import '../core/chat_models.dart';

abstract interface class AttachmentStore {
  Future<void> initialize();

  Future<ChatAttachment> save(
    ChatAttachmentInput input, {
    required String conversationId,
    required String messageId,
  });

  Future<Uint8List?> read(ChatAttachment attachment);

  Future<void> delete(ChatAttachment attachment);

  Future<void> deleteConversation(String conversationId);

  Future<String> describeRoot();
}
