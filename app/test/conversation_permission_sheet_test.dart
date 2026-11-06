import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/ai_policy.dart';
import 'package:personal_ai_inbox/ui/pages/conversation/conversation_permission_sheet.dart';

void main() {
  testWidgets('selects and returns full access after explicit confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(const _PermissionSheetHarness());
    await tester.tap(find.byKey(const Key('open_permissions')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('permission_preset_read_only')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('permission_preset_standard')), findsOneWidget);
    expect(
      find.byKey(const Key('permission_preset_full_access')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('permission_preset_custom')), findsOneWidget);

    await tester.tap(find.byKey(const Key('permission_preset_full_access')));
    await tester.ensureVisible(
      find.byKey(const Key('conversation_permissions_apply')),
    );
    await tester.tap(find.byKey(const Key('conversation_permissions_apply')));
    await tester.pumpAndSettle();

    expect(find.text('启用完全权限？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('permission_full_access_confirm')));
    await tester.pumpAndSettle();

    final result = tester
        .state<_PermissionSheetHarnessState>(
          find.byType(_PermissionSheetHarness),
        )
        .result;
    expect(result?.preset, AiPolicyPreset.fullAccess);
    expect(
      result?.decisionFor(
        AiPermissionAction.tableDelete,
        tableIds: const ['tb_inbox_todo'],
      ),
      AiPolicyDecision.allow,
    );
  });

  testWidgets('custom mode can deny a decision group', (tester) async {
    await tester.pumpWidget(const _PermissionSheetHarness());
    await tester.tap(find.byKey(const Key('open_permissions')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('permission_preset_custom')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('permission_group_read')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('禁止').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('conversation_permissions_apply')),
    );
    await tester.tap(find.byKey(const Key('conversation_permissions_apply')));
    await tester.pumpAndSettle();

    final result = tester
        .state<_PermissionSheetHarnessState>(
          find.byType(_PermissionSheetHarness),
        )
        .result;
    expect(result?.preset, AiPolicyPreset.custom);
    expect(
      result?.decisionFor(AiPermissionAction.tableRead),
      AiPolicyDecision.deny,
    );
    expect(
      result?.decisionFor(AiPermissionAction.contentCreate),
      AiPolicyDecision.allow,
    );
  });

  testWidgets('permission sheet remains usable on a narrow phone layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const _PermissionSheetHarness());
    await tester.tap(find.byKey(const Key('open_permissions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('permission_preset_full_access')));
    await tester.ensureVisible(
      find.byKey(const Key('conversation_permissions_apply')),
    );

    expect(
      find.byKey(const Key('conversation_permissions_apply')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _PermissionSheetHarness extends StatefulWidget {
  const _PermissionSheetHarness();

  @override
  State<_PermissionSheetHarness> createState() =>
      _PermissionSheetHarnessState();
}

class _PermissionSheetHarnessState extends State<_PermissionSheetHarness> {
  AiPolicy? result;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                key: const Key('open_permissions'),
                onPressed: () async {
                  final selected = await showConversationPermissionSheet(
                    context: context,
                    initialPolicy: AiPolicy.forPreset(AiPolicyPreset.standard),
                  );
                  if (mounted && selected != null) {
                    setState(() => result = selected);
                  }
                },
                child: const Text('打开权限'),
              ),
              Text(result?.preset.wireName ?? 'none'),
            ],
          ),
        ),
      ),
    );
  }
}
