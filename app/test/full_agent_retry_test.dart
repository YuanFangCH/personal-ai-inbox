import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';
import 'package:personal_ai_inbox/services/chat_service.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'test_support.dart';

void main() {
  test(
    'full-agent mode exposes protected-capable app management tools',
    () async {
      final toolNames = await _exposedToolNames(fullAgentMode: true);
      expect(toolNames, contains('conversation_manage'));
      expect(toolNames, contains('attachment_manage'));
      expect(toolNames, contains('app_settings_update'));
    },
  );

  test('standard mode keeps app management write tools hidden', () async {
    final toolNames = await _exposedToolNames(fullAgentMode: false);
    expect(toolNames, isNot(contains('conversation_manage')));
    expect(toolNames, isNot(contains('attachment_manage')));
    expect(toolNames, isNot(contains('app_settings_update')));
  });

  test(
    'app settings tool changes ordinary settings and rejects protected ones',
    () async {
      final repository = ChatRepository(
        store: MemoryConversationStore(),
        attachments: MemoryAttachmentStore(),
      );
      await repository.initialize();
      final results = ResultLibrary(
        repository: ResultRepository(
          vault: MemoryVaultStore(),
          index: MemoryIndexDatabase(),
          deviceId: 'full-agent-settings-test',
        ),
      );
      await results.initialize();
      final settings = FakeSettingsService(modelKey: 'test-key');
      final conversation = await repository.createConversation(
        aiPolicy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
      );
      await repository.saveMessage(
        ChatMessage(
          id: repository.newMessageId(),
          conversationId: conversation.id,
          role: ChatRole.user,
          content: '修改普通设置但不要碰模型配置',
          status: ChatMessageStatus.complete,
          createdAt: DateTime(2026, 11, 9),
          updatedAt: DateTime(2026, 11, 9),
        ),
      );
      var requests = 0;
      final model = ModelClient(
        client: MockClient.streaming((request, body) async {
          await body.bytesToString();
          requests++;
          if (requests == 1) {
            return http.StreamedResponse(
              Stream.fromIterable([
                _toolCallsEvent([
                  {
                    'index': 0,
                    'id': 'call_theme',
                    'function': {
                      'name': 'app_settings_update',
                      'arguments': jsonEncode({'theme_mode': 'dark'}),
                    },
                  },
                  {
                    'index': 1,
                    'id': 'call_model',
                    'function': {
                      'name': 'app_settings_update',
                      'arguments': jsonEncode({'model_name': 'evil-model'}),
                    },
                  },
                ]),
              ]),
              200,
              headers: const {'content-type': 'text/event-stream'},
            );
          }
          return http.StreamedResponse(
            Stream.fromIterable([
              utf8.encode(
                'data: {"choices":[{"delta":{"content":"设置处理完成"},"finish_reason":"stop"}]}\n\n',
              ),
              utf8.encode('data: [DONE]\n\n'),
            ]),
            200,
            headers: const {'content-type': 'text/event-stream'},
          );
        }),
      );
      final service = ChatService(
        settings: settings,
        repository: repository,
        results: results,
        modelClient: model,
      );

      await (await service.streamReply(conversationId: conversation.id))
          .toList();

      expect(
        settings.load().then((value) => value.themeMode),
        completion(ThemePreference.dark),
      );
      expect((await settings.load()).modelName, 'deepseek-flash');
      await repository.close();
      await results.shutdown();
      model.close();
    },
  );

  test('full-agent mode retries beyond the standard retry cap', () async {
    final repository = ChatRepository(
      store: MemoryConversationStore(),
      attachments: MemoryAttachmentStore(),
    );
    await repository.initialize();
    addTearDown(repository.close);
    final conversation = await repository.createConversation(
      aiPolicy: AiPolicy.forPreset(AiPolicyPreset.fullAccess),
    );
    await repository.saveMessage(
      ChatMessage(
        id: repository.newMessageId(),
        conversationId: conversation.id,
        role: ChatRole.user,
        content: '重试请求',
        status: ChatMessageStatus.complete,
        createdAt: DateTime(2026, 11, 9),
        updatedAt: DateTime(2026, 11, 9),
      ),
    );
    var requests = 0;
    final model = ModelClient(
      client: MockClient.streaming((request, body) async {
        await body.bytesToString();
        requests++;
        if (requests <= 3) {
          return http.StreamedResponse(
            const Stream.empty(),
            503,
            headers: const {'content-type': 'text/plain'},
          );
        }
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"恢复成功"},"finish_reason":"stop"}]}\n\n',
            ),
            utf8.encode('data: [DONE]\n\n'),
          ]),
          200,
          headers: const {'content-type': 'text/event-stream'},
        );
      }),
    );
    addTearDown(model.close);
    final service = ChatService(
      settings: FakeSettingsService(modelKey: 'test-key', fullAgentMode: true),
      repository: repository,
      modelClient: model,
      retryWait: (_) async {},
    );

    final deltas = await (await service.streamReply(
      conversationId: conversation.id,
    )).toList();

    expect(requests, 4);
    expect(deltas.map((delta) => delta.content).join(), '恢复成功');
    expect(deltas.last.termination, ChatStreamTermination.completed);
  });
}

List<int> _toolCallsEvent(List<Map<String, dynamic>> calls) => utf8.encode(
  'data: ${jsonEncode({
    'choices': [
      {
        'delta': {'tool_calls': calls},
        'finish_reason': 'tool_calls',
      },
    ],
  })}\n\n',
);

Future<Set<String>> _exposedToolNames({required bool fullAgentMode}) async {
  final repository = ChatRepository(
    store: MemoryConversationStore(),
    attachments: MemoryAttachmentStore(),
  );
  await repository.initialize();
  final results = ResultLibrary(
    repository: ResultRepository(
      vault: MemoryVaultStore(),
      index: MemoryIndexDatabase(),
      deviceId: 'full-agent-tool-test',
    ),
  );
  await results.initialize();
  final conversation = await repository.createConversation(
    aiPolicy: AiPolicy.forPreset(AiPolicyPreset.standard),
  );
  await repository.saveMessage(
    ChatMessage(
      id: repository.newMessageId(),
      conversationId: conversation.id,
      role: ChatRole.user,
      content: '检查工具',
      status: ChatMessageStatus.complete,
      createdAt: DateTime(2026, 11, 9),
      updatedAt: DateTime(2026, 11, 9),
    ),
  );
  late Map<String, dynamic> requestBody;
  final model = ModelClient(
    client: MockClient.streaming((request, body) async {
      requestBody =
          jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
      return http.StreamedResponse(
        Stream.fromIterable([
          utf8.encode(
            'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}\n\n',
          ),
          utf8.encode('data: [DONE]\n\n'),
        ]),
        200,
        headers: const {'content-type': 'text/event-stream'},
      );
    }),
  );
  final service = ChatService(
    settings: FakeSettingsService(
      modelKey: 'test-key',
      fullAgentMode: fullAgentMode,
    ),
    repository: repository,
    results: results,
    modelClient: model,
  );
  await (await service.streamReply(conversationId: conversation.id)).toList();
  await repository.close();
  await results.shutdown();
  model.close();
  final tools = requestBody['tools'];
  if (tools is! List) return const {};
  return {
    for (final tool in tools.whereType<Map>())
      if (tool['function'] is Map)
        (tool['function'] as Map)['name']?.toString() ?? '',
  }..remove('');
}
