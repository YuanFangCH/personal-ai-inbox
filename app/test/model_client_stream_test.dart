import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

void main() {
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
    expect(request['tools'], isA<List<dynamic>>());
    model.close();
  });
}
