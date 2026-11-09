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
    this.thinkingParameterSupported = false,
    this.responseHeaderTimeout = const Duration(seconds: 45),
    this.streamIdleTimeout = const Duration(seconds: 60),
    this.totalTimeout = const Duration(seconds: 300),
  });

  final String baseUrl;
  final String model;
  final String apiKey;
  final ModelCapabilities capabilities;
  final bool thinkingParameterSupported;
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
    this.toolCalls = const [],
    this.toolCallId,
    this.name,
    this.reasoningContent = '',
  });

  final String role;
  final String text;
  final List<ChatRequestImage> images;
  final List<Map<String, dynamic>> toolCalls;
  final String? toolCallId;
  final String? name;
  final String reasoningContent;
}

class ChatStreamDelta {
  const ChatStreamDelta({
    this.content = '',
    this.toolCallIndex,
    this.toolCallId,
    this.toolCallName,
    this.toolArguments = '',
    this.reasoningContent = '',
    this.toolTranscript = const [],
    this.termination,
  });

  final String content;
  final int? toolCallIndex;
  final String? toolCallId;
  final String? toolCallName;
  final String toolArguments;
  final String reasoningContent;
  final List<Map<String, dynamic>> toolTranscript;
  final ChatStreamTermination? termination;
}

enum ChatStreamTermination {
  completed,
  length,
  incomplete,
  empty,
  disconnected,
  cancelled,
}

class ModelHttpException extends StateError {
  ModelHttpException({
    required this.operation,
    required this.statusCode,
    this.retryAfterHeader,
    this.retryAfter,
  }) : super('Model $operation request failed with HTTP $statusCode');

  final String operation;
  final int statusCode;
  final String? retryAfterHeader;
  final Duration? retryAfter;
}

class ModelStreamProtocolException extends FormatException {
  const ModelStreamProtocolException(super.message);
}

class ModelCancelledException implements Exception {
  const ModelCancelledException();

  @override
  String toString() => 'Model request cancelled';
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
    final requestStartedAt = DateTime.now();
    final headerTimeout =
        configuration.responseHeaderTimeout < configuration.totalTimeout
        ? configuration.responseHeaderTimeout
        : configuration.totalTimeout;
    final response = await _sendAbortably(request, abortTrigger, headerTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _cancelResponse(response);
      throw _httpException(response, operation: 'classification', now: now);
    }

    final responseStream = StreamIterator<List<int>>(response.stream);
    final responseBytes = BytesBuilder(copy: false);
    var responseBodyCompleted = false;
    try {
      while (await _moveNextWithinTimeout(
        responseStream,
        requestStartedAt,
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
    String? systemPrompt,
    List<Map<String, dynamic>>? tools,
    bool thinkingEnabled = false,
    Future<void>? cancellationSignal,
  }) {
    final abortTrigger = Completer<void>();
    final cancellation = _CancellationSignal();
    StreamSubscription<ChatStreamDelta>? subscription;
    late final StreamController<ChatStreamDelta> controller;
    controller = StreamController<ChatStreamDelta>(
      onListen: () {
        subscription =
            _streamChat(
              messages: messages,
              configuration: configuration,
              now: now,
              systemPrompt: systemPrompt,
              tools: tools,
              thinkingEnabled: thinkingEnabled,
              abortTrigger: abortTrigger,
              cancellation: cancellation,
            ).listen(
              (delta) {
                if (!cancellation.isCancelled && !controller.isClosed) {
                  controller.add(delta);
                }
              },
              onError: (Object error, StackTrace stackTrace) {
                if (!cancellation.isCancelled && !controller.isClosed) {
                  controller.addError(error, stackTrace);
                }
              },
              onDone: () {
                if (!controller.isClosed) {
                  unawaited(controller.close());
                }
              },
            );
        if (cancellationSignal != null) {
          unawaited(
            cancellationSignal.then((_) {
              cancellation.cancel();
              if (!abortTrigger.isCompleted) abortTrigger.complete();
            }),
          );
        }
      },
      onCancel: () async {
        cancellation.cancel();
        if (!abortTrigger.isCompleted) {
          abortTrigger.complete();
        }
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<ChatStreamDelta> _streamChat({
    required List<ChatRequestMessage> messages,
    required ModelConfiguration configuration,
    required DateTime now,
    required String? systemPrompt,
    required List<Map<String, dynamic>>? tools,
    required bool thinkingEnabled,
    required Completer<void> abortTrigger,
    required _CancellationSignal cancellation,
  }) async* {
    final endpoint = Uri.parse(
      '${configuration.baseUrl.replaceAll(RegExp(r'/$'), '')}/chat/completions',
    );
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
            if (configuration.thinkingParameterSupported ||
                configuration.capabilities.thinking) ...{
              'thinking': {
                'type': thinkingEnabled && configuration.capabilities.thinking
                    ? 'enabled'
                    : 'disabled',
              },
              if (thinkingEnabled && configuration.capabilities.thinking)
                'reasoning_effort': 'high',
            },
            'messages': [
              {
                'role': 'system',
                'content': systemPrompt ?? _chatSystemPrompt(now),
              },
              for (final message in messages) _requestMessage(message),
            ],
            if (configuration.capabilities.toolCalls) ...{
              'tools': tools ?? [_createResultTool],
              'tool_choice': 'auto',
            },
          });

    final requestStartedAt = DateTime.now();
    final headerTimeout =
        configuration.responseHeaderTimeout < configuration.totalTimeout
        ? configuration.responseHeaderTimeout
        : configuration.totalTimeout;
    late final http.StreamedResponse response;
    try {
      response = await _sendAbortably(
        request,
        abortTrigger,
        headerTimeout,
        cancellation,
      );
    } on ModelCancelledException {
      return;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _cancelResponse(response);
      throw _httpException(response, operation: 'chat', now: now);
    }

    final lines = StreamIterator<String>(
      response.stream.transform(utf8.decoder).transform(const LineSplitter()),
    );
    final events = _SseEventAssembler();
    var terminalSent = false;
    var sawMeaningfulPayload = false;
    var reachedEof = false;
    try {
      while (!reachedEof) {
        String? payload;
        if (await _moveNextWithinTimeout(
          lines,
          requestStartedAt,
          configuration.streamIdleTimeout,
          configuration.totalTimeout,
          abortTrigger,
          cancellation,
        )) {
          payload = events.addLine(lines.current);
        } else {
          reachedEof = true;
          payload = events.finish();
        }
        if (payload == null || payload.isEmpty) {
          continue;
        }
        if (terminalSent) {
          continue;
        }
        if (payload == '[DONE]') {
          terminalSent = true;
          yield ChatStreamDelta(
            termination: sawMeaningfulPayload
                ? ChatStreamTermination.completed
                : ChatStreamTermination.empty,
          );
          return;
        }

        final event = _decodeChatEvent(
          payload,
          toolCallsSupported: configuration.capabilities.toolCalls,
        );
        sawMeaningfulPayload =
            sawMeaningfulPayload || event.hasMeaningfulPayload;
        for (final delta in event.deltas) {
          yield delta;
        }
        if (event.terminal != null) {
          terminalSent = true;
          yield ChatStreamDelta(
            termination: switch (event.terminal!) {
              _ChatTerminal.completedWithContent when sawMeaningfulPayload =>
                ChatStreamTermination.completed,
              _ChatTerminal.completedWithContent => ChatStreamTermination.empty,
              _ChatTerminal.completedToolCalls =>
                ChatStreamTermination.completed,
              _ChatTerminal.length => ChatStreamTermination.length,
              _ChatTerminal.incomplete => ChatStreamTermination.incomplete,
            },
          );
          return;
        }
      }
      if (!terminalSent) {
        yield ChatStreamDelta(
          termination: sawMeaningfulPayload
              ? ChatStreamTermination.disconnected
              : ChatStreamTermination.empty,
        );
      }
    } on ModelCancelledException {
      return;
    } finally {
      if (terminalSent) {
        if (!abortTrigger.isCompleted) abortTrigger.complete();
        unawaited(lines.cancel().catchError((Object _) {}));
      } else {
        await lines.cancel();
        if (!abortTrigger.isCompleted) {
          abortTrigger.complete();
        }
      }
    }
  }

  Future<http.StreamedResponse> _sendAbortably(
    http.AbortableRequest request,
    Completer<void> abortTrigger,
    Duration timeout, [
    _CancellationSignal? cancellation,
  ]) async {
    try {
      final send = _client.send(request);
      final response = cancellation == null
          ? send
          : Future.any<http.StreamedResponse>([
              send,
              cancellation.future.then<http.StreamedResponse>(
                (_) => throw const ModelCancelledException(),
              ),
            ]);
      return await response.timeout(
        timeout,
        onTimeout: () {
          if (!abortTrigger.isCompleted) {
            abortTrigger.complete();
          }
          throw TimeoutException('Model response headers timed out');
        },
      );
    } catch (error, stackTrace) {
      if (!abortTrigger.isCompleted) {
        abortTrigger.complete();
      }
      if (cancellation?.isCancelled ?? false) {
        throw const ModelCancelledException();
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<bool> _moveNextWithinTimeout<T>(
    StreamIterator<T> iterator,
    DateTime startedAt,
    Duration idleTimeout,
    Duration totalTimeout,
    Completer<void> abortTrigger, [
    _CancellationSignal? cancellation,
  ]) {
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
    final next = iterator.moveNext();
    final movement = cancellation == null
        ? next
        : Future.any<bool>([
            next,
            cancellation.future.then<bool>(
              (_) => throw const ModelCancelledException(),
            ),
          ]);
    return movement.timeout(
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

  _ChatEvent _decodeChatEvent(
    String payload, {
    required bool toolCallsSupported,
  }) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      throw const ModelStreamProtocolException(
        'Model stream event contains malformed JSON',
      );
    }
    if (decoded is! Map) {
      throw const ModelStreamProtocolException(
        'Model stream event is not an object',
      );
    }
    final choices = decoded['choices'];
    if (choices is! List) {
      throw const ModelStreamProtocolException(
        'Model stream event is missing choices',
      );
    }
    if (choices.isEmpty) {
      return const _ChatEvent(deltas: [], hasMeaningfulPayload: false);
    }
    final choice = choices.first;
    if (choice is! Map) {
      throw const ModelStreamProtocolException(
        'Model stream choice is not an object',
      );
    }
    final finishReason = choice['finish_reason'];
    final delta = choice['delta'];
    if (delta != null && delta is! Map) {
      throw const ModelStreamProtocolException(
        'Model stream delta is not an object',
      );
    }
    final terminal = switch (finishReason) {
      null => null,
      'stop' => _ChatTerminal.completedWithContent,
      'tool_calls' => _ChatTerminal.completedToolCalls,
      'length' => _ChatTerminal.length,
      _ => _ChatTerminal.incomplete,
    };
    if (delta == null) {
      return _ChatEvent(
        deltas: const [],
        terminal: terminal,
        hasMeaningfulPayload: false,
      );
    }

    final deltas = <ChatStreamDelta>[];
    final content = delta['content'];
    if (content != null && content is! String) {
      throw const ModelStreamProtocolException(
        'Model stream content is not text',
      );
    }
    final toolCalls = delta['tool_calls'];
    if (toolCalls != null && toolCalls is! List) {
      throw const ModelStreamProtocolException(
        'Model stream tool calls are not a list',
      );
    }
    final meaningfulContent = content is String && content.isNotEmpty;
    if (meaningfulContent) {
      deltas.add(ChatStreamDelta(content: content));
    }
    final reasoningContent = delta['reasoning_content'];
    if (reasoningContent != null && reasoningContent is! String) {
      throw const ModelStreamProtocolException(
        'Model stream reasoning content is not text',
      );
    }
    if (reasoningContent is String && reasoningContent.isNotEmpty) {
      deltas.add(ChatStreamDelta(reasoningContent: reasoningContent));
    }
    if (toolCallsSupported && toolCalls is List) {
      for (final rawCall in toolCalls) {
        if (rawCall is! Map) {
          throw const ModelStreamProtocolException(
            'Model stream tool call is not an object',
          );
        }
        final function = rawCall['function'];
        if (function != null && function is! Map) {
          throw const ModelStreamProtocolException(
            'Model stream tool function is invalid',
          );
        }
        final rawIndex = rawCall['index'];
        if (rawIndex is! num || !rawIndex.isFinite || rawIndex < 0) {
          throw const ModelStreamProtocolException(
            'Model stream tool index is invalid',
          );
        }
        final toolId = rawCall['id'];
        final toolName = function?['name'];
        final arguments = function?['arguments'];
        if ((toolId != null && toolId is! String) ||
            (toolName != null && toolName is! String) ||
            (arguments != null && arguments is! String)) {
          throw const ModelStreamProtocolException(
            'Model stream tool fields are invalid',
          );
        }
        deltas.add(
          ChatStreamDelta(
            toolCallIndex: rawIndex.toInt(),
            toolCallId: toolId as String?,
            toolCallName: toolName as String?,
            toolArguments: arguments as String? ?? '',
          ),
        );
      }
    } else if (toolCalls is List && toolCalls.isNotEmpty) {
      throw const ModelStreamProtocolException(
        'Model returned tool calls without tool-call capability',
      );
    }
    return _ChatEvent(
      deltas: deltas,
      terminal: terminal,
      hasMeaningfulPayload:
          meaningfulContent ||
          (toolCallsSupported && toolCalls is List && toolCalls.isNotEmpty),
    );
  }

  Future<void> _cancelResponse(http.StreamedResponse response) async {
    final subscription = response.stream.listen(null);
    await subscription.cancel();
  }

  ModelHttpException _httpException(
    http.StreamedResponse response, {
    required String operation,
    required DateTime now,
  }) {
    final retryAfterHeader = response.headers['retry-after'];
    return ModelHttpException(
      operation: operation,
      statusCode: response.statusCode,
      retryAfterHeader: retryAfterHeader,
      retryAfter: _parseRetryAfter(retryAfterHeader, now),
    );
  }

  Duration? _parseRetryAfter(String? rawValue, DateTime now) {
    final value = rawValue?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final seconds = int.tryParse(value);
    if (seconds != null) {
      return seconds < 0 ? null : Duration(seconds: seconds);
    }
    final match = RegExp(
      r'^(?:[A-Za-z]{3},\s*)?(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+'
      r'(\d{2}):(\d{2}):(\d{2})\s+GMT$',
    ).firstMatch(value);
    if (match == null) {
      return null;
    }
    const months = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final month = months[match.group(2)!.toLowerCase()];
    if (month == null) {
      return null;
    }
    final retryAt = DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
    final delay = retryAt.difference(now.toUtc());
    return delay.isNegative ? Duration.zero : delay;
  }

  Map<String, dynamic> _requestMessage(ChatRequestMessage message) {
    if (message.toolCallId != null) {
      return {
        'role': 'tool',
        'tool_call_id': message.toolCallId,
        if (message.name != null) 'name': message.name,
        'content': message.text,
      };
    }
    if (message.toolCalls.isNotEmpty) {
      return {
        'role': 'assistant',
        'content': message.text.isEmpty ? null : message.text,
        if (message.reasoningContent.isNotEmpty)
          'reasoning_content': message.reasoningContent,
        'tool_calls': message.toolCalls,
      };
    }
    if (message.role == 'assistant' && message.reasoningContent.isNotEmpty) {
      return {
        'role': 'assistant',
        'content': message.text,
        'reasoning_content': message.reasoningContent,
      };
    }
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
你是“懒狗秘书”，用户的个人秘书型助理。使用简体中文回答，简洁、清楚，帮助管理事项、待办、日历与知识。
当前时间：${now.toIso8601String()}
时区：Asia/Hong_Kong

只使用当前会话和用户本轮提供的信息。读取权限允许且答案确实缺少个人事实时，才使用本地搜索工具；寒暄、改写、总结已给内容和通用问题不要检索。每次搜索先选最小来源，命中足够即停，不得换词循环或自动搜索全库。
当对话或图片中包含明确、非敏感、值得长期保存的新内容时，调用 create_result：
- knowledge：可复用的知识、结论、资料摘要
- todo：明确行动；有截止时间时写入 due
- event：明确发生的日程；写入 start / end
- matter：需要聚合多个行动的独立事项

create_result 只用于新建。update_result 与 delete_result 只按用户明确要求操作普通成果；不得操作会话或历史消息。全局知识的变更只能提议，未获用户确认前不会生效。
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

class _CancellationSignal {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;
  Future<void> get future => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}

class _SseEventAssembler {
  final List<String> _data = [];
  bool _isFirstLine = true;

  String? addLine(String line) {
    var current = line;
    if (_isFirstLine) {
      _isFirstLine = false;
      if (current.startsWith('\uFEFF')) {
        current = current.substring(1);
      }
    }
    if (current.isEmpty) {
      return _takeEvent();
    }
    if (current.startsWith(':')) {
      return null;
    }
    final colon = current.indexOf(':');
    final field = colon < 0 ? current : current.substring(0, colon);
    if (field != 'data') {
      return null;
    }
    var value = colon < 0 ? '' : current.substring(colon + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }
    _data.add(value);
    return null;
  }

  String? finish() => _takeEvent();

  String? _takeEvent() {
    if (_data.isEmpty) {
      return null;
    }
    final payload = _data.join('\n');
    _data.clear();
    return payload;
  }
}

enum _ChatTerminal {
  completedWithContent,
  completedToolCalls,
  length,
  incomplete,
}

class _ChatEvent {
  const _ChatEvent({
    required this.deltas,
    required this.hasMeaningfulPayload,
    this.terminal,
  });

  final List<ChatStreamDelta> deltas;
  final bool hasMeaningfulPayload;
  final _ChatTerminal? terminal;
}
