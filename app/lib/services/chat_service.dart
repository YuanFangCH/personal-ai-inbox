import 'dart:async';

import '../core/chat_models.dart';
import '../data/chat_repository.dart';
import '../data/settings_service.dart';
import 'model_client.dart';
import 'model_capabilities.dart';
import 'model_request_policy.dart';

class ChatService {
  ChatService({
    required SettingsService settings,
    required ChatRepository repository,
    ModelClient? modelClient,
    ModelRequestPolicy requestPolicy = const ModelRequestPolicy(),
  }) : _settings = settings,
       _repository = repository,
       _modelClient = modelClient ?? ModelClient(),
       _requestPolicy = requestPolicy;

  final SettingsService _settings;
  final ChatRepository _repository;
  final ModelClient _modelClient;
  final ModelRequestPolicy _requestPolicy;

  Future<bool> get isConfigured async {
    final settings = await _settings.load();
    return settings.hasModelKey;
  }

  Future<Stream<ChatStreamDelta>> streamReply({
    required String conversationId,
    Set<String> excludedMessageIds = const {},
  }) async {
    final settings = await _settings.load();
    final apiKey = await _settings.readModelKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw StateError('请先在设置中配置云端模型 API Key');
    }

    final capabilities = ModelCapabilities.forModel(settings.modelName);
    final imagesAllowed = settings.allowImageEgress && capabilities.vision;
    final plan = _requestPolicy.prepare(
      history: await _repository.listMessages(conversationId),
      imagesAllowed: imagesAllowed,
      imageBlockReason: settings.allowImageEgress ? '当前模型不支持图片' : '图片出网已关闭',
      excludedMessageIds: excludedMessageIds,
    );
    if (plan.blockedReason != null) {
      throw StateError(plan.blockedReason!);
    }
    final requestMessages = await _buildRequestMessages(
      plan.messages,
      imageMessageIds: plan.imageMessageIds,
      includeImages: plan.imagesAllowed,
    );
    if (!requestMessages.any(
      (message) => message.text.trim().isNotEmpty || message.images.isNotEmpty,
    )) {
      throw StateError('没有可发送的文字或图片内容。');
    }
    return _modelClient.streamChat(
      messages: requestMessages,
      configuration: ModelConfiguration(
        baseUrl: settings.modelBaseUrl,
        model: settings.modelName,
        apiKey: apiKey,
        capabilities: capabilities,
      ),
      now: DateTime.now(),
    );
  }

  void close() => _modelClient.close();

  Future<List<ChatRequestMessage>> _buildRequestMessages(
    List<ChatMessage> selected, {
    required Set<String> imageMessageIds,
    required bool includeImages,
  }) async {
    var imageCount = 0;
    final values = <ChatRequestMessage>[];
    for (final message in selected) {
      final images = <ChatRequestImage>[];
      if (includeImages && imageMessageIds.contains(message.id)) {
        for (final attachment in message.attachments) {
          if (imageCount >= ModelRequestPolicy.imageLimit) {
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
