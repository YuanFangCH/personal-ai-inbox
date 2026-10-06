import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/models.dart';

class ModelConfiguration {
  const ModelConfiguration({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    this.timeout = const Duration(seconds: 45),
  });

  final String baseUrl;
  final String model;
  final String apiKey;
  final Duration timeout;
}

class ChatRequestImage {
  const ChatRequestImage({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

class ChatRequestMessage {
  const ChatRequestMessage({
    required this.role,
    required this.text,
    this.images = const [],
  });

  final String role;
  final String text;
  final List<ChatRequestImage> images;
}

class ChatStreamDelta {
  const ChatStreamDelta({
    this.content = '',
    this.toolCallIndex,
    this.toolCallId,
    this.toolCallName,
    this.toolArguments = '',
  });

  final String content;
  final int? toolCallIndex;
  final String? toolCallId;
  final String? toolCallName;
  final String toolArguments;
}

class ModelClient {
  ModelClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<ClassificationCandidate> classify({
    required String text,
    required ModelConfiguration configuration,
    required DateTime now,
  }) async {
    final endpoint = Uri.parse(
      '${configuration.baseUrl.replaceAll(RegExp(r'/$'), '')}/chat/completions',
    );
    final response = await _client
        .post(
          endpoint,
          headers: {
            'Authorization': 'Bearer ${configuration.apiKey}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': configuration.model,
            'temperature': 0,
            'response_format': {'type': 'json_object'},
            'messages': [
              {'role': 'system', 'content': _systemPrompt(now)},
              {'role': 'user', 'content': text},
            ],
          }),
        )
        .timeout(configuration.timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Model request failed with HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Model response is not an object');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('Model response is missing choices');
    }
    final message = (choices.first as Map)['message'];
    final content = message is Map ? message['content']?.toString() : null;
    if (content == null || content.trim().isEmpty) {
      throw const FormatException('Model response is missing content');
    }
    final payload = _extractJsonObject(content);
    return _candidateFromPayload(payload, text);
  }

  Stream<ChatStreamDelta> streamChat({
    required List<ChatRequestMessage> messages,
    required ModelConfiguration configuration,
    required DateTime now,
  }) async* {
    final endpoint = Uri.parse(
      '${configuration.baseUrl.replaceAll(RegExp(r'/$'), '')}/chat/completions',
    );
    final request = http.Request('POST', endpoint)
      ..headers.addAll({
        'Authorization': 'Bearer ${configuration.apiKey}',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode({
        'model': configuration.model,
        'temperature': 0.2,
        'stream': true,
        'messages': [
          {'role': 'system', 'content': _chatSystemPrompt(now)},
          for (final message in messages) _requestMessage(message),
        ],
        'tools': [_createResultTool],
        'tool_choice': 'auto',
      });

    final response = await _client.send(request).timeout(configuration.timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw StateError(
        'Model chat request failed with HTTP ${response.statusCode}: $body',
      );
    }

    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('data:')) {
        continue;
      }
      final payload = trimmed.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') {
        continue;
      }
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        continue;
      }
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) {
        continue;
      }
      final choice = choices.first;
      if (choice is! Map) {
        continue;
      }
      final delta = choice['delta'];
      if (delta is! Map) {
        continue;
      }
      final content = delta['content']?.toString() ?? '';
      final toolCalls = delta['tool_calls'];
      if (content.isNotEmpty) {
        yield ChatStreamDelta(content: content);
      }
      if (toolCalls is List) {
        for (final rawCall in toolCalls) {
          if (rawCall is! Map) {
            continue;
          }
          final function = rawCall['function'];
          yield ChatStreamDelta(
            toolCallIndex: (rawCall['index'] as num?)?.toInt(),
            toolCallId: rawCall['id']?.toString(),
            toolCallName: function is Map ? function['name']?.toString() : null,
            toolArguments: function is Map
                ? function['arguments']?.toString() ?? ''
                : '',
          );
        }
      }
    }
  }

  void close() => _client.close();

  Map<String, dynamic> _requestMessage(ChatRequestMessage message) {
    if (message.images.isEmpty) {
      return {'role': message.role, 'content': message.text};
    }
    return {
      'role': message.role,
      'content': [
        if (message.text.trim().isNotEmpty)
          {'type': 'text', 'text': message.text},
        for (final image in message.images)
          {
            'type': 'image_url',
            'image_url': {
              'url':
                  'data:${image.mimeType};base64,${base64Encode(image.bytes)}',
              'detail': 'original',
            },
          },
      ],
    };
  }

  Map<String, dynamic> get _createResultTool {
    return {
      'type': 'function',
      'function': {
        'name': 'create_result',
        'description':
            'Create one new personal result only when it is explicitly clear, '
            'non-sensitive, and high confidence. Never update or delete.',
        'parameters': {
          'type': 'object',
          'additionalProperties': false,
          'properties': {
            'type': {
              'type': 'string',
              'enum': ['knowledge', 'todo', 'event', 'matter'],
            },
            'title': {'type': 'string'},
            'body': {'type': 'string'},
            'tags': {
              'type': 'array',
              'items': {'type': 'string'},
            },
            'confidence': {'type': 'number'},
            'sensitive': {'type': 'boolean'},
            'due': {
              'type': ['string', 'null'],
            },
            'start': {
              'type': ['string', 'null'],
            },
            'end': {
              'type': ['string', 'null'],
            },
            'all_day': {'type': 'boolean'},
            'recurrence': {
              'type': ['string', 'null'],
            },
          },
          'required': ['type', 'title', 'body', 'confidence', 'sensitive'],
        },
      },
    };
  }

  String _chatSystemPrompt(DateTime now) {
    return '''
你是个人 AI 收件箱中的长期记录助手。使用简体中文回答，内容可读、简洁。
当前时间：${now.toIso8601String()}
时区：Asia/Hong_Kong

你会看到当前会话最近的消息和图片。不要引用其他会话。
当对话或图片中包含明确、非敏感、值得长期保存的新内容时，调用 create_result：
- knowledge：可复用的知识、结论、资料摘要
- todo：明确行动；有截止时间时写入 due
- event：明确发生的日程；写入 start / end
- matter：需要聚合多个行动的独立事项

create_result 只用于新建，绝不修改或删除已有成果。
日期、金额、身份或指令含义不清楚时，不要调用工具。
重复规则、敏感内容、过去日程不要自动创建。
如果用户只是普通聊天，直接回答，不要强行提取。
''';
  }

  String _systemPrompt(DateTime now) {
    return '''
你是个人收件箱的分类器。只输出 JSON 对象，不要 Markdown。
当前时间：${now.toIso8601String()}
时区：Asia/Hong_Kong
字段：
{
  "intent": "knowledge|event|task|unknown",
  "title": "简短标题",
  "summary": "一句摘要",
  "confidence": 0.0,
  "tags": ["标签"],
  "start": "ISO8601 或 null",
  "end": "ISO8601 或 null",
  "due": "ISO8601 或 null",
  "needs_review": true,
  "review_reason": "原因或 null"
}
日期不明确时必须 needs_review=true。不得修改任何用户数据，只返回候选。
''';
  }

  Map<String, dynamic> _extractJsonObject(String content) {
    final trimmed = content
        .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) {
      throw const FormatException('Model content is not a JSON object');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  ClassificationCandidate _candidateFromPayload(
    Map<String, dynamic> payload,
    String originalText,
  ) {
    final intent = payload['intent']?.toString() ?? 'unknown';
    final type = switch (intent) {
      'event' => ResultType.event,
      'task' => ResultType.todo,
      'knowledge' => ResultType.knowledge,
      _ => ResultType.knowledge,
    };
    final review = payload['needs_review'] == true || intent == 'unknown';
    return ClassificationCandidate(
      type: type,
      title: (payload['title']?.toString().trim().isNotEmpty ?? false)
          ? payload['title'].toString().trim()
          : '待整理',
      confidence: (payload['confidence'] as num?)?.toDouble() ?? 0.5,
      summary: payload['summary']?.toString() ?? originalText,
      tags: _stringList(payload['tags']),
      start: _date(payload['start']),
      end: _date(payload['end']),
      due: _date(payload['due']),
      needsReview: review,
      reviewReason: review
          ? payload['review_reason']?.toString() ?? '需要人工确认'
          : null,
    );
  }

  List<String> _stringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  DateTime? _date(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString());
  }
}
