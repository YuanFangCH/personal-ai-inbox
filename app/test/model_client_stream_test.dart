import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/services/model_client.dart';
import 'package:personal_ai_inbox/services/model_capabilities.dart';

void main() {
  test('terminal completes the outer stream before HTTP body cancellation finishes', () async {
    final bodyCancellationStarted = Completer<void>();
    final bodyCancellationGate = Completer<void>();
    final bodyCancellationFinished = Completer<void>();
    final terminalReceived = Completer<ChatStreamTermination?>();
    final outerStreamDone = Completer<void>();
    final body = StreamController<List<int>>(
      onCancel: () async {
        if (!bodyCancellationStarted.isCompleted) {
          bodyCancellationStarted.complete();
        }
        await bodyCancellationGate.future;
        if (!bodyCancellationFinished.isCompleted) {
          bodyCancellationFinished.complete();
        }
      },
    );
    final model = ModelClient(
      client: MockClient.streaming((request, requestBody) async {
        await requestBody.bytesToString();
        return http.StreamedResponse(body.stream, 200);
      }),
    );
    model
        .streamChat(
          messages: const [ChatRequestMessage(role: 'user', text: 'continue')],
          configuration: const ModelConfiguration(
            baseUrl: 'https://example.com',
            model: 'test-model',
            apiKey: 'test-key',
          ),
          now: DateTime(2026, 11, 5),
        )
        .listen(
          (delta) {
            if (delta.termination != null && !terminalReceived.isCompleted) {
              terminalReceived.complete(delta.termination);
            }
          },
          onDone: () {
            if (!outerStreamDone.isCompleted) outerStreamDone.complete();
          },
        );

    body.add(
      utf8.encode(
        'data: {"choices":[{"delta":{"content":"complete"},"finish_reason":"stop"}]}\n\n',
      ),
    );

    try {
      expect(
        await terminalReceived.future.timeout(const Duration(seconds: 1)),
        ChatStreamTermination.completed,
      );
      await bodyCancellationStarted.future.timeout(const Duration(seconds: 1));
      expect(bodyCancellationFinished.isCompleted, isFalse);
      await outerStreamDone.future.timeout(const Duration(seconds: 1));
      expect(bodyCancellationFinished.isCompleted, isFalse);
    } finally {
      if (!bodyCancellationGate.isCompleted) bodyCancellationGate.complete();
      if (bodyCancellationStarted.isCompleted) {
        await bodyCancellationFinished.future.timeout(
          const Duration(seconds: 1),
        );
      }
      await body.close();
      model.close();
    }
  });

  test(
    'cancelling streamed model deltas cancels the HTTP response body',
    () async {
      final bodyCancelled = Completer<void>();
      final body = StreamController<List<int>>(
        onCancel: () {
          if (!bodyCancelled.isCompleted) bodyCancelled.complete();
        },
      );
      final model = ModelClient(
        client: MockClient.streaming((request, requestBody) async {
          await requestBody.bytesToString();
          return http.StreamedResponse(body.stream, 200);
        }),
      );
      final subscription = model
          .streamChat(
            messages: const [ChatRequestMessage(role: 'user', text: 'stop')],
            configuration: const ModelConfiguration(
              baseUrl: 'https://example.com',
              model: 'test-model',
              apiKey: 'test-key',
            ),
            now: DateTime(2026, 11, 5),
          )
          .listen((_) {});
      body.add(
        utf8.encode('data: {"choices":[{"delta":{"content":"首段"}}]}\n\n'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await subscription.cancel();

      await bodyCancelled.future.timeout(const Duration(seconds: 1));
      await body.close();
      model.close();
    },
  );

  test(
    'thinking mode is capability gated and carries reasoning for tool turns',
    () async {
      Map<String, dynamic>? requestBody;
      final client = MockClient.streaming((request, body) async {
        requestBody =
            jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
        final event = {
          'choices': [
            {
              'delta': {
                'reasoning_content': 'hidden reasoning',
                'content': 'Visible answer',
              },
            },
          ],
        };
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode('data: ${jsonEncode(event)}\n\n'),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
        );
      });
      final model = ModelClient(client: client);
      final deltas = await model
          .streamChat(
            messages: const [
              ChatRequestMessage(
                role: 'assistant',
                text: '',
                reasoningContent: 'previous hidden reasoning',
                toolCalls: [
                  {
                    'id': 'call_previous',
                    'type': 'function',
                    'function': {'name': 'search_results', 'arguments': '{}'},
                  },
                ],
              ),
              ChatRequestMessage(
                role: 'tool',
                text: '{"hits":[]}',
                toolCallId: 'call_previous',
                name: 'search_results',
              ),
              ChatRequestMessage(role: 'user', text: 'What did you find?'),
            ],
            configuration: const ModelConfiguration(
              baseUrl: 'https://api.deepseek.com',
              model: 'deepseek-flash',
              apiKey: 'test-key',
              capabilities: ModelCapabilities.deepseekFlash,
            ),
            now: DateTime(2026, 10, 20),
            thinkingEnabled: true,
          )
          .toList();

      expect(requestBody!['thinking'], {'type': 'enabled'});
      expect(requestBody!['reasoning_effort'], 'high');
      final messages = requestBody!['messages'] as List;
      expect(messages[1]['reasoning_content'], 'previous hidden reasoning');
      expect(messages[2]['tool_call_id'], 'call_previous');
      expect(deltas.map((delta) => delta.content).join(), 'Visible answer');
      expect(
        deltas.map((delta) => delta.reasoningContent).join(),
        'hidden reasoning',
      );
      expect(deltas.last.termination, ChatStreamTermination.completed);
      model.close();
    },
  );

  test('streamChat parses content and tool call fragments', () async {
    String? requestBody;
    final client = MockClient.streaming((request, bodyStream) async {
      requestBody = await bodyStream.bytesToString();
      final chunks = <String>[
        'data: {"choices":[{"delta":{"content":"已"}}]}\n\n',
        'data: {"choices":[{"delta":{"content":"记录"}}]}\n\n',
        'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"create_result","arguments":"{\\"type\\":\\"todo\\","}}]}}]}\n\n',
        'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"title\\":\\"交材料\\",\\"confidence\\":0.9,\\"sensitive\\":false}"}}]}}]}\n\n',
        'data: [DONE]\n\n',
      ];
      return http.StreamedResponse(
        Stream.fromIterable(chunks.map(utf8.encode)),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final model = ModelClient(client: client);

    final deltas = await model
        .streamChat(
          messages: const [ChatRequestMessage(role: 'user', text: '记住周五交材料')],
          configuration: const ModelConfiguration(
            baseUrl: 'https://example.com',
            model: 'test-model',
            apiKey: 'test-key',
            capabilities: ModelCapabilities.deepseekFlash,
          ),
          now: DateTime(2026, 10, 4),
        )
        .toList();

    expect(deltas.map((delta) => delta.content).join(), '已记录');
    final tool = deltas.where((delta) => delta.toolCallIndex != null).toList();
    expect(tool.first.toolCallId, 'call_1');
    expect(tool.first.toolCallName, 'create_result');
    expect(
      tool.map((delta) => delta.toolArguments).join(),
      contains('"title":"交材料"'),
    );
    final request = jsonDecode(requestBody!) as Map<String, dynamic>;
    expect(request['stream'], true);
    expect(request['thinking'], {'type': 'disabled'});
    expect(request['tools'], isA<List<dynamic>>());
    expect(deltas.last.termination, ChatStreamTermination.completed);
    model.close();
  });

  test('finish_reason tool_calls is an explicit complete terminal', () async {
    final client = MockClient.streaming((request, body) async {
      await body.bytesToString();
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            'data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}\n\n',
          ),
        ),
        200,
      );
    });
    final model = ModelClient(client: client);
    final deltas = await model
        .streamChat(
          messages: const [ChatRequestMessage(role: 'user', text: 'hello')],
          configuration: const ModelConfiguration(
            baseUrl: 'https://example.com',
            model: 'custom-text-only',
            apiKey: 'test-key',
          ),
          now: DateTime(2026),
        )
        .toList();

    expect(deltas.single.termination, ChatStreamTermination.completed);
    model.close();
  });

  test('finish_reason stop without content is not a complete answer', () async {
    final client = MockClient.streaming((request, body) async {
      await body.bytesToString();
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n',
          ),
        ),
        200,
      );
    });
    final model = ModelClient(client: client);
    final deltas = await model
        .streamChat(
          messages: const [ChatRequestMessage(role: 'user', text: 'hello')],
          configuration: const ModelConfiguration(
            baseUrl: 'https://example.com',
            model: 'custom-text-only',
            apiKey: 'test-key',
          ),
          now: DateTime(2026),
        )
        .toList();

    expect(deltas.single.termination, ChatStreamTermination.empty);
    model.close();
  });

  test(
    'finish_reason length remains incomplete even after a tool delta',
    () async {
      final client = MockClient.streaming((request, body) async {
        await body.bytesToString();
        final event = {
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {
                      'name': 'create_result',
                      'arguments': '{"type":"knowledge"}',
                    },
                  },
                ],
              },
              'finish_reason': 'length',
            },
          ],
        };
        return http.StreamedResponse(
          Stream.value(utf8.encode('data: ${jsonEncode(event)}\n\n')),
          200,
        );
      });
      final model = ModelClient(client: client);
      final deltas = await model
          .streamChat(
            messages: const [ChatRequestMessage(role: 'user', text: 'hello')],
            configuration: const ModelConfiguration(
              baseUrl: 'https://example.com',
              model: 'test-model',
              apiKey: 'test-key',
              capabilities: ModelCapabilities.deepseekFlash,
            ),
            now: DateTime(2026),
          )
          .toList();

      expect(deltas.any((delta) => delta.toolCallIndex != null), isTrue);
      expect(deltas.last.termination, ChatStreamTermination.incomplete);
      model.close();
    },
  );

  test('text-only capability omits tools and JSON response mode', () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient.streaming((request, body) async {
      requestBody =
          jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
      return http.StreamedResponse(
        Stream.value(utf8.encode('data: [DONE]\n\n')),
        200,
      );
    });
    final model = ModelClient(client: client);
    final deltas = await model
        .streamChat(
          messages: const [ChatRequestMessage(role: 'user', text: 'hello')],
          configuration: const ModelConfiguration(
            baseUrl: 'https://example.com',
            model: 'unregistered',
            apiKey: 'test-key',
          ),
          now: DateTime(2026),
        )
        .toList();

    expect(requestBody.containsKey('tools'), false);
    expect(requestBody.containsKey('tool_choice'), false);
    expect(requestBody['messages'], isA<List<dynamic>>());
    expect(deltas.single.termination, ChatStreamTermination.empty);
    model.close();
  });

  test('EOF without a completion signal has an explicit end reason', () async {
    final client = MockClient.streaming((request, body) async {
      await body.bytesToString();
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            'data: {"choices":[{"delta":{"content":"partial"}}]}\n\n',
          ),
        ),
        200,
      );
    });
    final model = ModelClient(client: client);
    final deltas = await model
        .streamChat(
          messages: const [ChatRequestMessage(role: 'user', text: 'hello')],
          configuration: const ModelConfiguration(
            baseUrl: 'https://example.com',
            model: 'custom-text-only',
            apiKey: 'test-key',
          ),
          now: DateTime(2026),
        )
        .toList();

    expect(deltas.where((delta) => delta.termination != null), hasLength(1));
    expect(
      deltas.singleWhere((delta) => delta.termination != null).termination,
      isNot(ChatStreamTermination.completed),
    );
    model.close();
  });

  test('assembles multiline SSE data fields before decoding JSON', () async {
    final client = MockClient.streaming((request, body) async {
      await body.bytesToString();
      const response = '''
: keep-alive
event: message
data: {"choices":[
data: {"delta":{"content":"第一行\\n第二行"}}
data: ]}

data: [DONE]

''';
      return http.StreamedResponse(
        Stream.fromIterable([
          utf8.encode(response.substring(0, 37)),
          utf8.encode(response.substring(37)),
        ]),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final model = ModelClient(client: client);

    final deltas = await model
        .streamChat(
          messages: const [ChatRequestMessage(role: 'user', text: 'hello')],
          configuration: const ModelConfiguration(
            baseUrl: 'https://example.com',
            model: 'custom-text-only',
            apiKey: 'test-key',
          ),
          now: DateTime(2026),
        )
        .toList();

    expect(deltas.first.content, '第一行\n第二行');
    expect(deltas.last.termination, ChatStreamTermination.completed);
    model.close();
  });

  test('an empty response has an explicit end reason', () async {
    final client = MockClient.streaming((request, body) async {
      await body.bytesToString();
      return http.StreamedResponse(const Stream.empty(), 200);
    });
    final model = ModelClient(client: client);

    final deltas = await model
        .streamChat(
          messages: const [ChatRequestMessage(role: 'user', text: 'hello')],
          configuration: const ModelConfiguration(
            baseUrl: 'https://example.com',
            model: 'custom-text-only',
            apiKey: 'test-key',
          ),
          now: DateTime(2026),
        )
        .toList();

    expect(deltas, hasLength(1));
    expect(deltas.single.termination, isNot(ChatStreamTermination.completed));
    model.close();
  });

  test('malformed SSE data raises a typed protocol error', () async {
    final client = MockClient.streaming((request, body) async {
      await body.bytesToString();
      return http.StreamedResponse(
        Stream.value(utf8.encode('data: {"choices":\n\n')),
        200,
      );
    });
    final model = ModelClient(client: client);

    await expectLater(
      model
          .streamChat(
            messages: const [ChatRequestMessage(role: 'user', text: 'hello')],
            configuration: const ModelConfiguration(
              baseUrl: 'https://example.com',
              model: 'custom-text-only',
              apiKey: 'test-key',
            ),
            now: DateTime(2026),
          )
          .toList(),
      throwsA(isA<ModelStreamProtocolException>()),
    );
    model.close();
  });

  test(
    'HTTP failures expose status and Retry-After without the API key',
    () async {
      const apiKey = 'super-secret-api-key';
      final client = MockClient.streaming((request, body) async {
        await body.bytesToString();
        return http.StreamedResponse(
          Stream.value(utf8.encode('rate limited')),
          429,
          headers: {'retry-after': '7'},
        );
      });
      final model = ModelClient(client: client);

      Object? failure;
      try {
        await model
            .streamChat(
              messages: const [ChatRequestMessage(role: 'user', text: 'hello')],
              configuration: const ModelConfiguration(
                baseUrl: 'https://example.com',
                model: 'custom-text-only',
                apiKey: apiKey,
              ),
              now: DateTime(2026),
            )
            .toList();
      } catch (error) {
        failure = error;
      }

      expect(failure, isA<ModelHttpException>());
      final httpError = failure! as ModelHttpException;
      expect(httpError.statusCode, 429);
      expect(httpError.retryAfterHeader, '7');
      expect(httpError.retryAfter, const Duration(seconds: 7));
      expect(httpError.toString(), isNot(contains(apiKey)));
      model.close();
    },
  );

  test('cancelling the public stream aborts the outbound request', () async {
    final aborted = Completer<void>();
    final responseBytes = StreamController<List<int>>();
    final client = MockClient.streaming((request, body) async {
      await body.bytesToString();
      final abortable = request as http.AbortableRequest;
      unawaited(
        abortable.abortTrigger!.then((_) {
          if (!aborted.isCompleted) {
            aborted.complete();
          }
        }),
      );
      return http.StreamedResponse(responseBytes.stream, 200);
    });
    final model = ModelClient(client: client);
    final subscription = model
        .streamChat(
          messages: const [ChatRequestMessage(role: 'user', text: 'hello')],
          configuration: const ModelConfiguration(
            baseUrl: 'https://example.com',
            model: 'custom-text-only',
            apiKey: 'test-key',
          ),
          now: DateTime(2026),
        )
        .listen((_) {});

    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    await aborted.future.timeout(const Duration(seconds: 1));
    await responseBytes.close();
    model.close();
  });

  test(
    'cancelling while waiting for headers aborts without waiting for timeout',
    () async {
      final aborted = Completer<void>();
      final client = MockClient.streaming((request, body) async {
        await body.bytesToString();
        final abortable = request as http.AbortableRequest;
        await abortable.abortTrigger!;
        aborted.complete();
        return http.StreamedResponse(const Stream.empty(), 200);
      });
      final model = ModelClient(client: client);
      final subscription = model
          .streamChat(
            messages: const [ChatRequestMessage(role: 'user', text: 'hello')],
            configuration: const ModelConfiguration(
              baseUrl: 'https://example.com',
              model: 'custom-text-only',
              apiKey: 'test-key',
              responseHeaderTimeout: Duration(seconds: 30),
            ),
            now: DateTime(2026),
          )
          .listen((_) {});

      await Future<void>.delayed(Duration.zero);
      await subscription.cancel().timeout(const Duration(seconds: 1));
      await aborted.future.timeout(const Duration(seconds: 1));
      model.close();
    },
  );

  test(
    'cancellation signal aborts while waiting for response headers',
    () async {
      final aborted = Completer<void>();
      final cancellation = Completer<void>();
      final client = MockClient.streaming((request, body) async {
        await body.bytesToString();
        final abortable = request as http.AbortableRequest;
        await abortable.abortTrigger!;
        if (!aborted.isCompleted) aborted.complete();
        return http.StreamedResponse(const Stream.empty(), 200);
      });
      final model = ModelClient(client: client);
      final subscription = model
          .streamChat(
            messages: const [ChatRequestMessage(role: 'user', text: 'hello')],
            configuration: const ModelConfiguration(
              baseUrl: 'https://example.com',
              model: 'custom-text-only',
              apiKey: 'test-key',
              responseHeaderTimeout: Duration(seconds: 30),
            ),
            now: DateTime(2026),
            cancellationSignal: cancellation.future,
          )
          .listen((_) {});

      await Future<void>.delayed(Duration.zero);
      cancellation.complete();
      await aborted.future.timeout(const Duration(seconds: 1));
      await subscription.cancel().timeout(const Duration(seconds: 1));
      model.close();
    },
  );

  test('stream idle timeout applies after response headers', () async {
    final bytes = StreamController<List<int>>();
    final client = MockClient.streaming((request, body) async {
      await body.bytesToString();
      return http.StreamedResponse(bytes.stream, 200);
    });
    final model = ModelClient(client: client);

    await expectLater(
      model
          .streamChat(
            messages: const [ChatRequestMessage(role: 'user', text: 'hello')],
            configuration: const ModelConfiguration(
              baseUrl: 'https://example.com',
              model: 'custom-text-only',
              apiKey: 'test-key',
              streamIdleTimeout: Duration(milliseconds: 20),
              totalTimeout: Duration(seconds: 1),
            ),
            now: DateTime(2026),
          )
          .toList(),
      throwsA(isA<TimeoutException>()),
    );
    await bytes.close();
    model.close();
  });

  test('total timeout applies even while the stream emits no bytes', () async {
    final bytes = StreamController<List<int>>();
    final client = MockClient.streaming((request, body) async {
      await body.bytesToString();
      return http.StreamedResponse(bytes.stream, 200);
    });
    final model = ModelClient(client: client);

    await expectLater(
      model
          .streamChat(
            messages: const [ChatRequestMessage(role: 'user', text: 'hello')],
            configuration: const ModelConfiguration(
              baseUrl: 'https://example.com',
              model: 'custom-text-only',
              apiKey: 'test-key',
              streamIdleTimeout: Duration(seconds: 1),
              totalTimeout: Duration(milliseconds: 20),
            ),
            now: DateTime(2026),
          )
          .toList(),
      throwsA(isA<TimeoutException>()),
    );
    await bytes.close();
    model.close();
  });

  test('response header timeout aborts the outbound request', () async {
    final client = MockClient.streaming((request, body) async {
      await body.bytesToString();
      return Completer<http.StreamedResponse>().future;
    });
    final model = ModelClient(client: client);

    await expectLater(
      model
          .streamChat(
            messages: const [ChatRequestMessage(role: 'user', text: 'hello')],
            configuration: const ModelConfiguration(
              baseUrl: 'https://example.com',
              model: 'custom-text-only',
              apiKey: 'test-key',
              responseHeaderTimeout: Duration(milliseconds: 20),
            ),
            now: DateTime(2026),
          )
          .toList(),
      throwsA(isA<TimeoutException>()),
    );
    model.close();
  });
}
