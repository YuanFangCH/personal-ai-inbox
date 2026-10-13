import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/models.dart';
import 'model_capabilities.dart';

class ModelConfiguration {
  const ModelConfiguration({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    this.capabilities = ModelCapabilities.textOnly,
    this.responseHeaderTimeout = const Duration(seconds: 45),
    this.streamIdleTimeout = const Duration(seconds: 60),
    this.totalTimeout = const Duration(seconds: 300),
  });

  final String baseUrl;
  final String model;
  final String apiKey;
  final ModelCapabilities capabilities;
  final Duration responseHeaderTimeout;
  final Duration streamIdleTimeout;
  final Duration totalTimeout;
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
    this.termination,
  });

  final String content;
  final int? toolCallIndex;
  final String? toolCallId;
  final String? toolCallName;
  final String toolArguments;
  final ChatStreamTermination? termination;
}

enum ChatStreamTermination { completed, incomplete }

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
    final abortTrigger = Completer<void>();
    final request =
        http.AbortableRequest(
            'POST',
            endpoint,
            abortTrigger: abortTrigger.future,
          )
          ..headers.addAll({
            'Authorization': 'Bearer ${configuration.apiKey}',
            'Content-Type': 'application/json',
          })
          ..body = jsonEncode({
            'model': configuration.model,
            'temperature': 0,
            if (configuration.capabilities.jsonOutput)
              'response_format': {'type': 'json_object'},
            'messages': [
              {'role': 'system', 'content': _systemPrompt(now)},
              {'role': 'user', 'content': text},
            ],
          });
    final response = await _sendAbortably(
      request,
      abortTrigger,
      configuration.responseHeaderTimeout,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      unawaited(response.stream.listen((_) {}).cancel());
      throw StateError('Model request failed with HTTP ${response.statusCode}');
    }

    final startedAt = DateTime.now();
    final responseStream = StreamIterator<List<int>>(response.stream);
    final responseBytes = BytesBuilder(copy: false);
    var responseBodyCompleted = false;
    try {
      while (await _moveNextWithinTimeout(
        responseStream,
        startedAt,
        configuration.streamIdleTimeout,
        configuration.totalTimeout,
        abortTrigger,
      )) {
        responseBytes.add(responseStream.current);
      }
      responseBodyCompleted = true;
      final decoded = jsonDecode(utf8.decode(responseBytes.takeBytes()));
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
    } finally {
      unawaited(responseStream.cancel());
      if (!responseBodyCompleted && !abortTrigger.isCompleted) {
        abortTrigger.complete();
      }
    }
  }

  Stream<ChatStreamDelta> streamChat({
    required List<ChatRequestMessage> messages,
    required ModelConfiguration configuration,
    required DateTime now,
  }) async* {
    final endpoint = Uri.parse(
      '${configuration.baseUrl.replaceAll(RegExp(r'/$'), '')}/chat/completions',
    );
    final abortTrigger = Completer<void>();
    final request =
        http.AbortableRequest(
            'POST',
            endpoint,
            abortTrigger: abortTrigger.future,
          )
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
            if (configuration.capabilities.toolCalls) ...{
              'tools': [_createResultTool],
              'tool_choice': 'auto',
            },
          });

    final response = await _sendAbortably(
      request,
      abortTrigger,
      configuration.responseHeaderTimeout,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      unawaited(response.stream.listen((_) {}).cancel());
      throw StateError(
        'Model chat request failed with HTTP ${response.statusCode}',
      );
    }

    final startedAt = DateTime.now();
    final lines = StreamIterator<String>(
      response.stream.transform(utf8.decoder).transform(const LineSplitter()),
    );
    var terminalSent = false;
    try {
      while (await _moveNextWithinTimeout(
        lines,
        startedAt,
        configuration.streamIdleTimeout,
        configuration.totalTimeout,
        abortTrigger,
      )) {
        final line = lines.current;
        final trimmed = line.trim();
        if (trimmed.isEmpty ||
            trimmed.startsWith(':') ||
            !trimmed.startsWith('data:')) {
          continue;
        }
        final payload = trimmed.substring(5).trim();
        if (payload.isEmpty) {
          continue;
        }
        if (terminalSent) {
          continue;
        }
        if (payload == '[DONE]') {
          terminalSent = true;
          abortTrigger.complete();
          yield const ChatStreamDelta(
            termination: ChatStreamTermination.completed,
          );
          return;
        }

        final decoded = jsonDecode(payload);
        if (decoded is! Map) {
          throw const FormatException('Model stream event is not an object');
        }
        final choices = decoded['choices'];
        if (choices is! List) {
          throw const FormatException('Model stream event is missing choices');
        }
        if (choices.isEmpty) {
          continue;
        }
        final choice = choices.first;
        if (choice is! Map) {
          throw const FormatException('Model stream choice is not an object');
        }
        final finishReason = choice['finish_reason'];
        final delta = choice['delta'];
        if (delta != null && delta is! Map) {
          throw const FormatException('Model stream delta is not an object');
        }
        if (delta == null) {
          if (finishReason == null) {
            continue;
          }
          final completed =
              finishReason == 'stop' || finishReason == 'tool_calls';
          terminalSent = true;
          abortTrigger.complete();
          yield ChatStreamDelta(
            termination: completed
                ? ChatStreamTermination.completed
                : ChatStreamTermination.incomplete,
          );
          return;
        }
        final content = delta['content'];
        if (content != null && content is! String) {
          throw const FormatException('Model stream content is not text');
        }
        final toolCalls = delta['tool_calls'];
        if (toolCalls != null && toolCalls is! List) {
          throw const FormatException('Model stream tool calls are not a list');
        }
        if (content is String && content.isNotEmpty) {
          yield ChatStreamDelta(content: content);
        }
        if (configuration.capabilities.toolCalls && toolCalls is List) {
          for (final rawCall in toolCalls) {
            if (rawCall is! Map) {
              throw const FormatException(
                'Model stream tool call is not an object',
              );
            }
            final function = rawCall['function'];
            if (function != null && function is! Map) {
              throw const FormatException(
                'Model stream tool function is invalid',
              );
            }
            final rawIndex = rawCall['index'];
            if (rawIndex is! num || !rawIndex.isFinite || rawIndex < 0) {
              throw const FormatException('Model stream tool index is invalid');
            }
            final toolId = rawCall['id'];
            final toolName = function?['name'];
            final arguments = function?['arguments'];
            if ((toolId != null && toolId is! String) ||
                (toolName != null && toolName is! String) ||
                (arguments != null && arguments is! String)) {
              throw const FormatException(
                'Model stream tool fields are invalid',
              );
            }
            yield ChatStreamDelta(
              toolCallIndex: rawIndex.toInt(),
              toolCallId: toolId as String?,
              toolCallName: toolName as String?,
              toolArguments: arguments as String? ?? '',
            );
          }
        } else if (toolCalls is List && toolCalls.isNotEmpty) {
          throw const FormatException(
            'Model returned tool calls without tool-call capability',
          );
        }
        if (finishReason != null) {
          final completed =
              finishReason == 'stop' || finishReason == 'tool_calls';
          terminalSent = true;
          abortTrigger.complete();
          yield ChatStreamDelta(
            termination: completed
                ? ChatStreamTermination.completed
                : ChatStreamTermination.incomplete,
          );
          return;
        }
      }
    } finally {
      unawaited(lines.cancel());
      if (!terminalSent && !abortTrigger.isCompleted) {
        abortTrigger.complete();
      }
    }
  }

  Future<http.StreamedResponse> _sendAbortably(
    http.AbortableRequest request,
    Completer<void> abortTrigger,
    Duration timeout,
  ) async {
    try {
      return await _client
          .send(request)
          .timeout(
            timeout,
            onTimeout: () {
              if (!abortTrigger.isCompleted) {
                abortTrigger.complete();
              }
              throw TimeoutException('Model response headers timed out');
            },
          );
    } catch (_) {
      if (!abortTrigger.isCompleted) {
        abortTrigger.complete();
      }
      rethrow;
    }
  }

  Future<bool> _moveNextWithinTimeout<T>(
    StreamIterator<T> iterator,
    DateTime startedAt,
    Duration idleTimeout,
    Duration totalTimeout,
    Completer<void> abortTrigger,
  ) {
    final elapsed = DateTime.now().difference(startedAt);
    final remainingTotal = totalTimeout - elapsed;
    if (remainingTotal <= Duration.zero) {
      if (!abortTrigger.isCompleted) {
        abortTrigger.complete();
      }
      throw TimeoutException('Model response exceeded its total time limit');
    }
    final totalExpiresFirst = remainingTotal <= idleTimeout;
    final wait = totalExpiresFirst ? remainingTotal : idleTimeout;
    return iterator.moveNext().timeout(
      wait,
      onTimeout: () {
        if (!abortTrigger.isCompleted) {
          abortTrigger.complete();
        }
        throw TimeoutException(
          totalExpiresFirst
              ? 'Model response exceeded its total time limit'
              : 'Model response stream was idle too long',
        );
      },
    );
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
