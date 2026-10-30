import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/core/markdown_codec.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/io_vault_store.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_conversation_store.dart';
import 'package:personal_ai_inbox/data/memory_attachment_store.dart';

import '../test/test_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('legacy documents open in a read-only migration gate', (
    tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('table-migration-gate');
    addTearDown(() => root.delete(recursive: true));
    final vault = IoVaultStore.at(root);
    await vault.initialize();
    final now = DateTime.now();
    final legacy = ResultDocument(
      id: 'matter_android_gate',
      type: ResultType.matter,
      title: 'AVD 只读迁移样例',
      status: ResultStatus.canonical,
      originDevice: 'android-migration-test',
      revision: 1,
      createdAt: now,
      updatedAt: now,
      body: '此内容只在合成测试 vault 中。',
    );
    final codec = const MarkdownCodec();
    final source = codec.encode(legacy);
    await vault.write(legacy.markdownPath, source);

    final runtime = await AppRuntime.bootstrap(
      vaultOverride: vault,
      indexOverride: MemoryIndexDatabase(),
      conversationStoreOverride: MemoryConversationStore(),
      attachmentStoreOverride: MemoryAttachmentStore(),
      settingsOverride: FakeSettingsService(deviceId: 'android-migration-test'),
    );
    await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
    await tester.pumpAndSettle();

    expect(runtime.migrationGate.requiresReadOnly, isTrue);
    expect(find.text('旧资料只读预检'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('AVD 只读迁移样例'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('AVD 只读迁移样例'), findsOneWidget);
    expect(find.byKey(const Key('nav_home')), findsNothing);
    expect(await vault.read(legacy.markdownPath), source);

    await tester.pumpWidget(const SizedBox.shrink());
    await runtime.shutdown();
  });
}
