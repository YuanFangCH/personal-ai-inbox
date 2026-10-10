import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/app.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/data/sync_engine.dart';
import 'package:personal_ai_inbox/data/sync_provider.dart';
import 'package:personal_ai_inbox/services/app_controller.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';

import 'test_support.dart';

void main() {
  testWidgets('inbox handles capture review and sync conflicts', (
    tester,
  ) async {
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    await index.open();
    final settings = FakeSettingsService();
    final repository = ResultRepository(
      vault: vault,
      index: index,
      deviceId: 'test-device',
    );
    await repository.initialize();
    await index.insertCapture(
      CaptureRecord(
        id: 'cap_merge',
        deviceId: 'test-device',
        capturedAt: DateTime(2026, 10, 7, 9),
        sourceType: CaptureSourceType.text,
        text: '下周找时间确认资料',
        status: CaptureStatus.needsReview,
        candidateType: ResultType.knowledge,
        candidateTitle: '确认资料',
        confidence: 0.55,
        reviewReason: '日期需要确认',
      ),
    );
    await vault.write(
      'vault/conflicts/kn_conflict.conflict-tablet.md',
      '---\nid: kn_conflict\ntype: knowledge\ntitle: 冲突副本\n'
          'status: canonical\norigin_device: android-tablet\nrevision: 1\n'
          'created_at: 2026-10-07T09:00:00+08:00\n'
          'updated_at: 2026-10-07T09:00:00+08:00\ndeleted: false\n'
          'tags: []\nlinks: []\n---\n冲突正文\n',
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
    );
    await controller.initialize();

    await tester.pumpWidget(PersonalAiInboxApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_inbox')));
    await tester.pumpAndSettle();

    expect(find.text('待确认'), findsOneWidget);
    expect(find.text('按建议生成'), findsOneWidget);
    expect(find.text('调整'), findsOneWidget);
    expect(find.text('忽略'), findsOneWidget);
    expect(find.text('同步冲突'), findsOneWidget);
    expect(find.byTooltip('裁决冲突'), findsOneWidget);

    await tester.tap(find.text('按建议生成'));
    await tester.pumpAndSettle();
    expect(controller.reviewCaptures, isEmpty);
    expect(controller.documents, hasLength(1));

    await tester.tap(find.byTooltip('裁决冲突'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留本地版本'));
    await tester.pumpAndSettle();
    expect(controller.conflictFiles, isEmpty);
    controller.dispose();
  });
}
