import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/services/chat_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'test_support.dart';

void main() {
  test(
    'connection test sends only fixed text without tools or images',
    () async {
      Map<String, dynamic>? requestBody;
      final client = MockClient.streaming((request, body) async {
        expect(request.headers['authorization'], 'Bearer test-key');
        requestBody =
            jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"connection-ok"}}]}\n\n',
            ),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final settings = FakeSettingsService(modelKey: 'test-key');
      final repository = ChatRepository(
        store: MemoryConversationStore(),
        attachments: MemoryAttachmentStore(),
      );
      final service = ChatService(
        settings: settings,
        repository: repository,
        modelClient: ModelClient(client: client),
      );

      expect(await service.testConnection(), 'connection-ok');
      final messages = requestBody!['messages'] as List<dynamic>;
      expect(messages, hasLength(2));
      expect(
        (messages.last as Map<String, dynamic>)['content'],
        'Connection test. Reply with exactly: connection-ok',
      );
      expect(requestBody!.containsKey('tools'), isFalse);
      service.close();
    },
  );

  test('connection test reports authentication failures', () async {
    final client = MockClient.streaming((request, body) async {
      await body.bytesToString();
      return http.StreamedResponse(Stream.empty(), 401);
    });
    final service = ChatService(
      settings: FakeSettingsService(modelKey: 'test-key'),
      repository: ChatRepository(
        store: MemoryConversationStore(),
        attachments: MemoryAttachmentStore(),
      ),
      modelClient: ModelClient(client: client),
    );

    await expectLater(
      service.testConnection(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('鉴权失败'),
        ),
      ),
    );
    service.close();
  });
}
