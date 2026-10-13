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
    final invalidSettings = settings.validate();
    if (invalidSettings.isNotEmpty) {
      throw StateError('模型配置需要修正：${invalidSettings.join('；')}');
    }
    final apiKey = await _settings.readModelKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw StateError('请先在设置中配置云端模型 API Key');
    }

    final capabilities = ModelCapabilities.resolve(settings);
    final imagesAllowed = settings.allowImageEgress && capabilities.vision;
    final plan = _requestPolicy.prepare(
      history: await _repository.listMessages(conversationId),
      imagesAllowed: imagesAllowed,
      imageBlockReason: settings.allowImageEgress ? '当前模型不支持图片' : '图片出网已关闭',
      messageLimit: settings.contextMessageLimit,
      imageMessageLimit: settings.imageMessageLimit,
      excludedMessageIds: excludedMessageIds,
    );
    if (plan.blockedReason != null) {
      throw StateError(plan.blockedReason!);
    }
    final requestMessages = await _buildRequestMessages(
      plan.messages,
      imageMessageIds: plan.imageMessageIds,
      includeImages: plan.imagesAllowed,
      imageLimit: settings.imageLimit,
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
        responseHeaderTimeout: Duration(
          seconds: settings.responseHeaderTimeoutSeconds,
        ),
        streamIdleTimeout: Duration(seconds: settings.streamIdleTimeoutSeconds),
        totalTimeout: Duration(seconds: settings.totalTimeoutSeconds),
      ),
      now: DateTime.now(),
    );
  }

  Future<String> testConnection() async {
    final settings = await _settings.load();
    final errors = settings.validate();
    if (errors.isNotEmpty) throw StateError(errors.join('；'));
    final apiKey = await _settings.readModelKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw StateError('请先保存模型 API Key');
    }
    try {
      final stream = _modelClient.streamChat(
        messages: const [
          ChatRequestMessage(
            role: 'user',
            text: 'Connection test. Reply with exactly: connection-ok',
          ),
        ],
        configuration: ModelConfiguration(
          baseUrl: settings.modelBaseUrl,
          model: settings.modelName,
          apiKey: apiKey,
          capabilities: ModelCapabilities.textOnly,
          responseHeaderTimeout: Duration(
            seconds: settings.responseHeaderTimeoutSeconds,
          ),
          streamIdleTimeout: Duration(
            seconds: settings.streamIdleTimeoutSeconds,
          ),
          totalTimeout: Duration(seconds: settings.totalTimeoutSeconds),
        ),
        now: DateTime.now(),
      );
      final response = StringBuffer();
      var completed = false;
      await for (final delta in stream) {
        response.write(delta.content);
        if (delta.termination == ChatStreamTermination.incomplete) {
          throw StateError('连接请求未正常完成');
        }
        if (delta.termination == ChatStreamTermination.completed) {
          completed = true;
        }
      }
      if (!completed) throw StateError('服务器未返回完整完成信号');
      return response.toString().trim();
    } on TimeoutException {
      throw StateError('连接超时：检查响应头等待、流空闲和总时限设置。');
    } on StateError catch (error) {
      final message = error.message;
      if (message.contains('HTTP 401') || message.contains('HTTP 403')) {
        throw StateError('鉴权失败：请检查 API Key。');
      }
      if (message.contains('HTTP 404')) {
        throw StateError('路径错误：请检查 Base URL 是否为 API 根地址。');
      }
      if (message.contains('HTTP 400')) {
        throw StateError('请求被拒绝：检查模型名称或端点支持的文本格式。');
      }
      if (message.contains('HTTP 429')) {
        throw StateError('服务限流：请稍后重试或检查当前账户配额。');
      }
      if (RegExp(r'HTTP 5\d\d').hasMatch(message)) {
        throw StateError('模型服务暂时不可用；请稍后重试。');
      }
      rethrow;
    }
  }

  void close() => _modelClient.close();

  Future<List<ChatRequestMessage>> _buildRequestMessages(
    List<ChatMessage> selected, {
    required Set<String> imageMessageIds,
    required bool includeImages,
    required int imageLimit,
  }) async {
    var imageCount = 0;
    final values = <ChatRequestMessage>[];
    for (final message in selected) {
      final images = <ChatRequestImage>[];
      if (includeImages && imageMessageIds.contains(message.id)) {
        for (final attachment in message.attachments) {
          if (imageCount >= imageLimit) {
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
