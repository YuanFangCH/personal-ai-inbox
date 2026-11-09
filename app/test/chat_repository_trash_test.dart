import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';

void main() {
  test('conversation and attachment deletion round-trip through trash', () async {
    final store = MemoryConversationStore();
    final repository = ChatRepository(
      store: store,
      attachments: MemoryAttachmentStore(),
    );
    await repository.initialize();
    final conversation = await repository.createConversation();
    final messageId = repository.newMessageId();
    final attachments = await repository.saveAttachments(
      conversationId: conversation.id,
      messageId: messageId,
      inputs: [
        ChatAttachmentInput(
          bytes: Uint8List.fromList([1, 2, 3, 4]),
          fileName: 'note.txt',
          mimeType: 'text/plain',
        ),
      ],
    );
    await repository.saveMessage(
      ChatMessage(
        id: messageId,
        conversationId: conversation.id,
        role: ChatRole.user,
        content: '保留正文',
        status: ChatMessageStatus.complete,
        createdAt: DateTime(2026, 11, 9),
        updatedAt: DateTime(2026, 11, 9),
        attachments: attachments,
      ),
    );

    final attachmentTrash = await repository.trashAttachment(
      conversationId: conversation.id,
      messageId: messageId,
      attachmentId: attachments.single.id,
    );
    expect(
      (await repository.findMessage(messageId))!.attachments,
      isEmpty,
    );
    expect(attachmentTrash.kind, 'attachment');
    expect(
      await repository.readAttachment(attachments.single),
      Uint8List.fromList([1, 2, 3, 4]),
    );
    await repository.restoreAttachment(attachmentTrash.id);
    expect(
      (await repository.findMessage(messageId))!.attachments.single.id,
      attachments.single.id,
    );

    final conversationTrash = await repository.trashConversation(
      conversation.id,
    );
    expect(await repository.findConversation(conversation.id), isNull);
    expect(await repository.listTrash(kind: 'conversation'), hasLength(1));
    final restored = await repository.restoreConversation(
      conversationTrash.id,
    );
    expect(restored.id, conversation.id);
    expect(
      (await repository.findMessage(messageId))!.content,
      '保留正文',
    );
    expect(
      await repository.readAttachment(attachments.single),
      Uint8List.fromList([1, 2, 3, 4]),
    );
  });
}
