import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../core/chat_models.dart';
import 'attachment_store.dart';
import 'conversation_store.dart';

class ChatRepository {
  ChatRepository({
    required ConversationStore store,
    required AttachmentStore attachments,
  }) : _store = store,
       _attachments = attachments;

  final ConversationStore _store;
  final AttachmentStore _attachments;

  Future<void> initialize() async {
    await _store.open();
    await _attachments.initialize();
  }

  Future<void> close() async {
    await _store.close();
  }

  Future<List<Conversation>> listConversations() {
    return _store.listConversations();
  }

  Future<int> deleteEmptyConversations() async {
    var deleted = 0;
    for (final conversation in await _store.listConversations()) {
      if ((await _store.listMessages(conversation.id)).isNotEmpty) {
        continue;
      }
      await deleteConversation(conversation.id);
      deleted++;
    }
    return deleted;
  }

  Future<Conversation?> findConversation(String id) {
    return _store.findConversation(id);
  }

  Future<Conversation> createConversation({DateTime? createdAt}) async {
    final timestamp = createdAt ?? DateTime.now();
    final conversation = Conversation(
      id: 'cnv_${const Uuid().v4()}',
      title: _newConversationTitle(timestamp),
      createdAt: timestamp,
      updatedAt: timestamp,
      autoTitle: true,
    );
    await _store.upsertConversation(conversation);
    return conversation;
  }

  Future<Conversation> saveConversation(Conversation conversation) async {
    await _store.upsertConversation(conversation);
    return conversation;
  }

  Future<void> deleteConversation(String id) async {
    await _store.deleteConversation(id);
    await _attachments.deleteConversation(id);
  }

  Future<List<ChatMessage>> listMessages(String conversationId) {
    return _store.listMessages(conversationId);
  }

  Future<ChatMessage?> findMessage(String id) => _store.findMessage(id);

  Future<void> saveMessage(ChatMessage message) =>
      _store.upsertMessage(message);

  Future<void> deleteMessage(String id) async {
    final message = await _store.findMessage(id);
    if (message != null) {
      for (final attachment in message.attachments) {
        await _attachments.delete(attachment);
      }
    }
    await _store.deleteMessage(id);
  }

  Future<List<ChatAttachment>> saveAttachments({
    required String conversationId,
    required String messageId,
    required List<ChatAttachmentInput> inputs,
  }) async {
    final values = <ChatAttachment>[];
    for (final input in inputs) {
      values.add(
        await _attachments.save(
          input,
          conversationId: conversationId,
          messageId: messageId,
        ),
      );
    }
    return values;
  }

  Future<Uint8List?> readAttachment(ChatAttachment attachment) {
    return _attachments.read(attachment);
  }

  Future<AutoRecordAction?> findAutoRecordAction(String id) {
    return _store.findAutoRecordAction(id);
  }

  String newMessageId() => 'msg_${const Uuid().v4()}';

  String newActionId() => 'act_${const Uuid().v4()}';

  String _newConversationTitle(DateTime timestamp) {
    final month = timestamp.month.toString().padLeft(2, '0');
    final day = timestamp.day.toString().padLeft(2, '0');
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return '新对话 · $month-$day $hour:$minute';
  }
}
