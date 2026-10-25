import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/chat_models.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';

import 'test_support.dart';

void main() {
  testWidgets('local message save failure leaves the composer draft intact', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final runtime = await AppRuntime.bootstrap(
      vaultOverride: MemoryVaultStore(),
      indexOverride: MemoryIndexDatabase(),
      conversationStoreOverride: _FailFirstMessageStore(),
      attachmentStoreOverride: MemoryAttachmentStore(),
      settingsOverride: FakeSettingsService(
        deviceId: 'send-failure-ui',
        modelKey: 'test-key',
      ),
    );
    addTearDown(runtime.dispose);

    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_inbox')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('chat_input')), '重要的本地草稿');
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('chat_input')))
          .controller!
          .text,
      '重要的本地草稿',
    );
    expect(find.textContaining('发送流程未完成'), findsOneWidget);
    expect(
      runtime.conversations.messagesFor(
        runtime.conversations.conversations.single.id,
      ),
      isEmpty,
    );
  });
}

class _FailFirstMessageStore extends MemoryConversationStore {
  bool _failFirstMessage = true;

  @override
  Future<void> upsertMessage(ChatMessage message) async {
    if (_failFirstMessage) {
      _failFirstMessage = false;
      throw StateError('模拟本地保存失败');
    }
    await super.upsertMessage(message);
  }
}
