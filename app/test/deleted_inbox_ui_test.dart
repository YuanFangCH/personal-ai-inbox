import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/bootstrap/app_runtime.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_background_control.dart';
import 'package:personal_ai_inbox/modules/conversation/agent_task_store.dart';
import 'package:personal_ai_inbox/modules/tables/table_library.dart';

import 'test_support.dart';

void main() {
  testWidgets('home new todo survives deletion of its inbox target', (
    tester,
  ) async {
    final runtime = (await tester.runAsync(
      () => AppRuntime.bootstrap(
        vaultOverride: MemoryVaultStore(),
        indexOverride: MemoryIndexDatabase(),
        settingsOverride: FakeSettingsService(deviceId: 'deleted-inbox-ui'),
        agentTaskStore: MemoryAgentTaskStore(),
        agentBackground: DisabledAgentBackgroundControl(),
      ),
    ))!;
    try {
      final target = runtime.tables.tableForInboxAssignment(
        InboxAssignmentKind.todo,
      )!;
      await tester.runAsync(
        () => runtime.tables.deleteTable(
          id: target.id,
          expectedRevision: target.revision,
        ),
      );
      await tester.pumpWidget(PersonalAiInboxApp(runtime: runtime));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '新建').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('请先选择待办收纳目标，或在表中直接新建。'), findsOneWidget);
      expect(
        runtime.tables.tableForInboxAssignment(InboxAssignmentKind.todo),
        isNull,
      );
      final replacement = runtime.tables.tableForInboxAssignment(
        InboxAssignmentKind.event,
      )!;
      await tester.tap(find.byKey(const Key('inbox_assignments')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('inbox_target_todo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(replacement.title).last);
      await tester.pumpAndSettle();
      expect(
        tester
            .state<FormFieldState<String>>(
              find.byKey(const ValueKey('inbox_target_todo')),
            )
            .value,
        replacement.id,
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('save_inbox_assignments')));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(
        runtime.tables.tableForInboxAssignment(InboxAssignmentKind.todo)?.id,
        replacement.id,
      );
    } finally {
      await tester.runAsync(runtime.shutdown);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
