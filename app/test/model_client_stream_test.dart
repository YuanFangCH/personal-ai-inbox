import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/services/model_client.dart';
import 'package:personal_ai_inbox/services/model_capabilities.dart';

void main() {
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
    await model
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
    model.close();
  });

  test('EOF without a completion signal is not reported as complete', () async {
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

    expect(deltas.any((delta) => delta.termination != null), false);
    model.close();
  });

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
