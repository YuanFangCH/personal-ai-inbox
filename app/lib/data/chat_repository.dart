import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../core/chat_models.dart';
import '../core/models.dart';
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

  static const trashRetention = Duration(days: 30);

  Future<void> initialize() async {
    await _store.open();
    await _attachments.initialize();
    await purgeExpiredTrash();
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

  Future<Conversation> createConversation({
    DateTime? createdAt,
    AiPermissions aiPermissions = const AiPermissions(),
    AiPolicy? aiPolicy,
  }) async {
    final timestamp = createdAt ?? DateTime.now();
    final conversation = Conversation(
      id: 'cnv_${const Uuid().v4()}',
      title: _newConversationTitle(timestamp),
      createdAt: timestamp,
      updatedAt: timestamp,
      autoTitle: true,
      aiPermissions: aiPermissions,
      aiPolicy: aiPolicy,
    );
    await _store.upsertConversation(conversation);
    return conversation;
  }

  Future<Conversation> saveConversation(Conversation conversation) async {
    await _store.upsertConversation(conversation);
    return conversation;
  }

  Future<Conversation?> setAiPolicy(
    String conversationId,
    AiPolicy aiPolicy,
  ) async {
    final conversation = await _store.findConversation(conversationId);
    if (conversation == null) return null;
    final updated = conversation.copyWith(
      aiPolicy: aiPolicy,
      updatedAt: DateTime.now(),
    );
    await _store.upsertConversation(updated);
    return updated;
  }

  Future<void> deleteConversation(String id) async {
    await _store.deleteConversation(id);
    await _attachments.deleteConversation(id);
  }

  Future<LocalTrashEntry> trashConversation(String id) async {
    final trashId = 'conversation:$id';
    final existing = await _store.findTrashEntry(trashId);
    if (existing != null) return existing;
    final conversation = await _store.findConversation(id);
    if (conversation == null) {
      throw StateError('对话不存在：$id');
    }
    final messages = await _store.listMessages(id);
    final entry = LocalTrashEntry(
      id: trashId,
      kind: 'conversation',
      expiresAt: DateTime.now().add(trashRetention),
      payload: {
        'conversation': conversation.toJson(),
        'messages': messages.map((message) => message.toJson()).toList(),
      },
    );
    await _store.saveTrashEntry(entry);
    await _store.deleteConversation(id);
    return entry;
  }

  Future<Conversation> restoreConversation(String trashId) async {
    final entry = await _store.findTrashEntry(trashId);
    if (entry == null || entry.kind != 'conversation') {
      throw StateError('对话回收站条目不存在：$trashId');
    }
    final rawConversation = entry.payload['conversation'];
    final rawMessages = entry.payload['messages'];
    if (rawConversation is! Map || rawMessages is! List) {
      throw const FormatException('对话回收站条目格式错误');
    }
    final conversation = Conversation.fromJson(
      Map<String, dynamic>.from(rawConversation),
    );
    if (await _store.findConversation(conversation.id) != null) {
      throw StateError('对话已存在，不能覆盖：${conversation.id}');
    }
    await _store.upsertConversation(conversation);
    for (final rawMessage in rawMessages.whereType<Map>()) {
      await _store.upsertMessage(
        ChatMessage.fromJson(Map<String, dynamic>.from(rawMessage)),
      );
    }
    await _store.deleteTrashEntry(trashId);
    return conversation;
  }

  Future<LocalTrashEntry> trashAttachment({
    required String conversationId,
    required String messageId,
    required String attachmentId,
  }) async {
    final message = await _store.findMessage(messageId);
    if (message == null || message.conversationId != conversationId) {
      throw StateError('消息不存在：$messageId');
    }
    ChatAttachment? attachment;
    for (final candidate in message.attachments) {
      if (candidate.id == attachmentId) {
        attachment = candidate;
        break;
      }
    }
    if (attachment == null) {
      throw StateError('附件不存在：$attachmentId');
    }
    final entry = LocalTrashEntry(
      id: 'attachment:$attachmentId',
      kind: 'attachment',
      expiresAt: DateTime.now().add(trashRetention),
      payload: {
        'conversation_id': conversationId,
        'message_id': messageId,
        'attachment': attachment.toJson(),
      },
    );
    await _store.saveTrashEntry(entry);
    await _store.upsertMessage(
      message.copyWith(
        attachments: message.attachments
            .where((item) => item.id != attachmentId)
            .toList(growable: false),
        updatedAt: DateTime.now(),
      ),
    );
    return entry;
  }

  Future<ChatAttachment> restoreAttachment(String trashId) async {
    final entry = await _store.findTrashEntry(trashId);
    if (entry == null || entry.kind != 'attachment') {
      throw StateError('附件回收站条目不存在：$trashId');
    }
    final messageId = entry.payload['message_id']?.toString();
    final rawAttachment = entry.payload['attachment'];
    if (messageId == null || rawAttachment is! Map) {
      throw const FormatException('附件回收站条目格式错误');
    }
    final message = await _store.findMessage(messageId);
    if (message == null) {
      throw StateError('原消息不存在，附件文件仍保留在本机：$messageId');
    }
    final attachment = ChatAttachment.fromJson(
      Map<String, dynamic>.from(rawAttachment),
    );
    if (!message.attachments.any((item) => item.id == attachment.id)) {
      await _store.upsertMessage(
        message.copyWith(
          attachments: [...message.attachments, attachment],
          updatedAt: DateTime.now(),
        ),
      );
    }
    await _store.deleteTrashEntry(trashId);
    return attachment;
  }

  Future<List<LocalTrashEntry>> listTrash({String? kind}) async {
    final entries = await _store.listTrashEntries();
    return entries
        .where((entry) => kind == null || entry.kind == kind)
        .toList(growable: false);
  }

  Future<void> purgeExpiredTrash() async {
    final now = DateTime.now();
    for (final entry in await _store.listTrashEntries()) {
      if (entry.expiresAt.isAfter(now)) continue;
      if (entry.kind == 'conversation') {
        final rawConversation = entry.payload['conversation'];
        if (rawConversation is Map) {
          final id = rawConversation['id']?.toString();
          if (id != null && id.isNotEmpty) {
            await _attachments.deleteConversation(id);
          }
        }
      } else if (entry.kind == 'attachment') {
        final rawAttachment = entry.payload['attachment'];
        if (rawAttachment is Map) {
          await _attachments.delete(
            ChatAttachment.fromJson(Map<String, dynamic>.from(rawAttachment)),
          );
        }
      }
      await _store.deleteTrashEntry(entry.id);
    }
  }

  Future<List<ChatMessage>> listMessages(String conversationId) {
    return _store.listMessages(conversationId);
  }

  Future<List<ChatMessage>> searchOtherConversations({
    required String query,
    required String currentConversationId,
    int limit = 5,
  }) => _store.searchMessages(
    query: query,
    excludedConversationId: currentConversationId,
    limit: limit,
  );

  Future<ChatMessage?> findMessage(String id) => _store.findMessage(id);

  Future<void> saveMessage(ChatMessage message) =>
      _store.upsertMessage(message);

  Future<GenerationRun?> findGeneration(String assistantMessageId) {
    return _store.findGeneration(assistantMessageId);
  }

  Future<void> saveGeneration(GenerationRun generation) {
    return _store.upsertGeneration(generation);
  }

  Future<List<GenerationRun>> listRecoverableGenerations() {
    return _store.listRecoverableGenerations();
  }

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

  Future<(ChatMessage, TableChatAction)?> findTableChatAction(String id) async {
    for (final conversation in await _store.listConversations()) {
      for (final message in await _store.listMessages(conversation.id)) {
        for (final action in message.tableActions) {
          if (action.id == id) return (message, action);
        }
      }
    }
    return null;
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
