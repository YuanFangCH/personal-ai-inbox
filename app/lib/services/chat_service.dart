import 'dart:async';

import '../core/chat_models.dart';
import '../data/chat_repository.dart';
import '../data/settings_service.dart';
import 'model_client.dart';

class ChatService {
  ChatService({
    required SettingsService settings,
    required ChatRepository repository,
    ModelClient? modelClient,
  }) : _settings = settings,
       _repository = repository,
       _modelClient = modelClient ?? ModelClient();

  static const contextMessageLimit = 20;
  static const contextImageMessageLimit = 4;
  static const contextImageLimit = 8;

  final SettingsService _settings;
  final ChatRepository _repository;
  final ModelClient _modelClient;

  Future<bool> get isConfigured async {
    final settings = await _settings.load();
    return settings.hasModelKey;
  }

  Future<Stream<ChatStreamDelta>> streamReply({
    required String conversationId,
  }) async {
    final settings = await _settings.load();
    final apiKey = await _settings.readModelKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw StateError('请先在设置中配置云端模型 API Key');
    }

    final history = await _repository.listMessages(conversationId);
    final requestMessages = await _buildRequestMessages(history);
    return _modelClient.streamChat(
      messages: requestMessages,
      configuration: ModelConfiguration(
        baseUrl: settings.modelBaseUrl,
        model: settings.modelName,
        apiKey: apiKey,
      ),
      now: DateTime.now(),
    );
  }

  void close() => _modelClient.close();

  Future<List<ChatRequestMessage>> _buildRequestMessages(
    List<ChatMessage> history,
  ) async {
    final complete = history
        .where(
          (message) =>
              message.status != ChatMessageStatus.streaming &&
              (message.content.trim().isNotEmpty ||
                  message.attachments.isNotEmpty),
        )
        .toList(growable: false);
    final start = complete.length > contextMessageLimit
        ? complete.length - contextMessageLimit
        : 0;
    final selected = complete.sublist(start);
    final imageMessages = selected
        .where((message) => message.attachments.isNotEmpty)
        .toList(growable: false);
    final imageStart = imageMessages.length > contextImageMessageLimit
        ? imageMessages.length - contextImageMessageLimit
        : 0;
    final imageMessageIds = imageMessages
        .sublist(imageStart)
        .map((message) => message.id)
        .toSet();

    var imageCount = 0;
    final values = <ChatRequestMessage>[];
    for (final message in selected) {
      final images = <ChatRequestImage>[];
      if (imageMessageIds.contains(message.id)) {
        for (final attachment in message.attachments) {
          if (imageCount >= contextImageLimit) {
            break;
          }
          final resolved = await _repository.readAttachment(attachment);
          if (resolved == null) {
            continue;
          }
          images.add(
            ChatRequestImage(bytes: resolved, mimeType: attachment.mimeType),
          );
          imageCount++;
        }
      }
      values.add(
        ChatRequestMessage(
          role: message.role.wireName,
          text: message.content,
          images: images,
        ),
      );
    }
    return values;
  }
}
