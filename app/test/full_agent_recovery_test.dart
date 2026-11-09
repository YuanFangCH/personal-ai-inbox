import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/data/io_vault_store.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/sqlite_conversation_store.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_task_store.dart';
import 'package:personal_ai_inbox/services/model_client.dart';

import 'test_support.dart';

void main() {
  test('full-agent mode continues a length-limited response', () async {
    var requests = 0;
    final runtime = await AppRuntime.bootstrap(
      vaultOverride: IoVaultStore.at(
        await Directory.systemTemp.createTemp('full-agent-output-'),
      ),
      indexOverride: MemoryIndexDatabase(),
      attachmentStoreOverride: MemoryAttachmentStore(),
      settingsOverride: FakeSettingsService(
        deviceId: 'full-agent-output',
        modelKey: 'test-key',
        fullAgentMode: true,
      ),
      modelClient: ModelClient(
        client: MockClient.streaming((request, body) async {
          await body.bytesToString();
          requests++;
          if (requests == 1) {
            return http.StreamedResponse(
              Stream.fromIterable([
                utf8.encode(
                  'data: {"choices":[{"delta":{"content":"前半段"},"finish_reason":"length"}]}\n\n',
                ),
              ]),
              200,
              headers: const {'content-type': 'text/event-stream'},
            );
          }
          return http.StreamedResponse(
            Stream.fromIterable([
              utf8.encode(
                'data: {"choices":[{"delta":{"content":"后半段"},"finish_reason":"stop"}]}\n\n',
              ),
              utf8.encode('data: [DONE]\n\n'),
            ]),
            200,
            headers: const {'content-type': 'text/event-stream'},
          );
        }),
      ),
    );
    addTearDown(runtime.shutdown);
    final conversation = await runtime.conversations.createConversation();
    await runtime.conversations.sendChatMessage(conversation.id, text: '写完整回复');

    final assistant = runtime.conversations
        .messagesFor(conversation.id)
        .lastWhere((message) => message.role == ChatRole.assistant);
    expect(assistant.status, ChatMessageStatus.complete);
    expect(assistant.content, '前半段后半段');
    expect(requests, 2);
  });

  test(
    'full-agent mode resumes a safe app-close checkpoint on startup',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'full-agent-recovery-',
      );
      final firstResponse = StreamController<List<int>>();
      final resumedResponse = StreamController<List<int>>();
      final firstStarted = Completer<void>();
      final resumedStarted = Completer<void>();
      var firstRequests = 0;
      var resumedRequests = 0;
      late AppRuntime runtime;

      Future<AppRuntime> boot(ModelClient client) {
        return AppRuntime.bootstrap(
          vaultOverride: IoVaultStore.at(Directory('${root.path}/vault')),
          indexOverride: MemoryIndexDatabase(),
          conversationStoreOverride: SqliteConversationStore(
            '${root.path}/conversations.sqlite',
          ),
          attachmentStoreOverride: MemoryAttachmentStore(),
          agentTaskStore: VaultAgentTaskStore(
            IoVaultStore.at(Directory('${root.path}/vault')),
          ),
          settingsOverride: FakeSettingsService(
            deviceId: 'full-agent-recovery',
            modelKey: 'test-key',
            fullAgentMode: true,
          ),
          modelClient: client,
        );
      }

      final firstClient = ModelClient(
        client: MockClient.streaming((request, body) async {
          await body.bytesToString();
          firstRequests++;
          if (!firstStarted.isCompleted) firstStarted.complete();
          return http.StreamedResponse(
            firstResponse.stream,
            200,
            headers: const {'content-type': 'text/event-stream'},
          );
        }),
      );
      runtime = await boot(firstClient);
      final conversation = await runtime.conversations.createConversation();
      final send = runtime.conversations.sendChatMessage(
        conversation.id,
        text: '关闭后自动继续',
      );
      await firstStarted.future.timeout(const Duration(seconds: 2));
      firstResponse.add(_contentEvent('已保存片段'));
      await _waitFor(() {
        return runtime.conversations
            .messagesFor(conversation.id)
            .any((message) => message.content == '已保存片段');
      });

      await runtime.shutdown().timeout(const Duration(seconds: 3));
      await send.timeout(const Duration(seconds: 3));
      await firstResponse.close();

      final resumedClient = ModelClient(
        client: MockClient.streaming((request, body) async {
          await body.bytesToString();
          resumedRequests++;
          if (!resumedStarted.isCompleted) resumedStarted.complete();
          return http.StreamedResponse(
            resumedResponse.stream,
            200,
            headers: const {'content-type': 'text/event-stream'},
          );
        }),
      );
      runtime = await boot(resumedClient);
      addTearDown(() async {
        if (!resumedResponse.isClosed) await resumedResponse.close();
        await runtime.shutdown();
        try {
          await root.delete(recursive: true);
        } on FileSystemException {
          // Windows may release SQLite handles just after shutdown.
        }
      });

      await resumedStarted.future.timeout(const Duration(seconds: 3));
      resumedResponse.add(_contentEvent('自动续跑完成'));
      resumedResponse.add(utf8.encode('data: [DONE]\n\n'));
      await resumedResponse.close();
      await _waitFor(() {
        final messages = runtime.conversations.messagesFor(conversation.id);
        return messages.any(
          (message) =>
              message.role == ChatRole.assistant &&
              message.status == ChatMessageStatus.complete &&
              message.content == '自动续跑完成',
        );
      });

      expect(firstRequests, 1);
      expect(resumedRequests, 1);
      expect(runtime.conversations.tasksNeedingAction, isEmpty);
    },
  );
}

List<int> _contentEvent(String content) => utf8.encode(
  'data: ${jsonEncode({
    'choices': [
      {
        'delta': {'content': content},
      },
    ],
  })}\n\n',
);

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not reached before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
