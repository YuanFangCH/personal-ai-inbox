import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/data/chat_repository.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/data/sync_engine.dart';
import 'package:personal_ai_inbox/data/sync_provider.dart';
import 'package:personal_ai_inbox/services/app_controller.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';
import 'package:personal_ai_inbox/services/chat_service.dart';

import 'test_support.dart';

void main() {
  testWidgets('cold start opens one empty conversation', (tester) async {
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    await index.open();
    final settings = FakeSettingsService(modelKey: 'test-key');
    final repository = ResultRepository(
      vault: vault,
      index: index,
      deviceId: 'test-device',
    );
    final chatRepository = ChatRepository(
      store: MemoryConversationStore(),
      attachments: MemoryAttachmentStore(),
    );
    final controller = AppController(
      repository: repository,
      indexDatabase: index,
      captureService: CaptureService(
        settings: settings,
        parser: const DeterministicParser(),
      ),
      settingsService: settings,
      syncEngine: SyncEngine(
        repository: repository,
        provider: MemorySyncProvider(),
        deviceId: 'test-device',
      ),
      chatRepository: chatRepository,
      chatService: ChatService(settings: settings, repository: chatRepository),
      autoOpenStartupConversation: true,
    );
    await controller.initialize();

    await tester.pumpWidget(PersonalAiInboxApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat_input')), findsOneWidget);
    expect(controller.conversations, hasLength(1));
    expect(controller.messagesFor(controller.activeConversationId!), isEmpty);

    await tester.pumpWidget(PersonalAiInboxApp(controller: controller));
    await tester.pumpAndSettle();
    expect(controller.conversations, hasLength(1));
    controller.dispose();
  });
}
