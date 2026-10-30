import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/modules/capture/capture_workflow.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';
import 'package:personal_ai_inbox/modules/tables/table_library.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';

import 'test_support.dart';

void main() {
  test(
    'high-confidence capture writes directly to its default table',
    () async {
      final harness = await _CaptureHarness.create(
        candidate: ClassificationCandidate(
          type: ResultType.todo,
          title: '交实验报告',
          confidence: 0.95,
          due: DateTime(2026, 11, 2, 17),
        ),
      );
      final outcome = await harness.workflow.captureText('周一下午五点交实验报告');
      expect(outcome.status, CaptureOutcomeStatus.created);
      expect(outcome.tableEntry!.type, TableContentType.todo);
      expect(
        outcome.tableEntry!.tableId,
        harness.tables.tables
            .singleWhere((table) => table.role == TableRole.inboxTodo)
            .id,
      );
      expect(harness.workflow.reviewCaptures, isEmpty);
      await harness.close();
    },
  );

  test(
    'low-confidence or failed analysis keeps raw text as an ordinary note',
    () async {
      final lowConfidence = await _CaptureHarness.create(
        candidate: const ClassificationCandidate(
          type: ResultType.event,
          title: '待整理安排',
          confidence: 0.4,
          needsReview: true,
        ),
      );
      final captured = await lowConfidence.workflow.captureText('下周找时间看房子');
      expect(captured.tableEntry!.type, TableContentType.note);
      expect(captured.tableEntry!.body, '下周找时间看房子');
      expect(
        captured.tableEntry!.tableId,
        lowConfidence.tables.tables
            .singleWhere((table) => table.role == TableRole.inboxEvent)
            .id,
      );
      expect(lowConfidence.workflow.reviewCaptures, isEmpty);
      await lowConfidence.close();

      final failed = await _CaptureHarness.create(failAnalysis: true);
      final failedOutcome = await failed.workflow.captureText('原文不能丢失');
      expect(failedOutcome.tableEntry!.type, TableContentType.note);
      expect(failedOutcome.tableEntry!.body, '原文不能丢失');
      expect(failed.workflow.reviewCaptures, isEmpty);
      await failed.close();
    },
  );
}

class _CaptureHarness {
  _CaptureHarness({
    required this.vault,
    required this.index,
    required this.results,
    required this.tables,
    required this.workflow,
  });

  final MemoryVaultStore vault;
  final MemoryIndexDatabase index;
  final ResultLibrary results;
  final TableLibrary tables;
  final CaptureWorkflow workflow;

  static Future<_CaptureHarness> create({
    ClassificationCandidate? candidate,
    bool failAnalysis = false,
  }) async {
    final vault = MemoryVaultStore();
    final index = MemoryIndexDatabase();
    final repository = ResultRepository(
      vault: vault,
      index: index,
      deviceId: 'capture-table-test',
    );
    await repository.initialize();
    final results = ResultLibrary(repository: repository);
    await results.initialize();
    final tables = TableLibrary(repository: repository.createTableRepository());
    await tables.initialize();
    final workflow = CaptureWorkflow(
      repository: repository,
      results: results,
      tables: tables,
      indexDatabase: index,
      captureService: _FakeCaptureService(
        candidate: candidate,
        fail: failAnalysis,
      ),
      now: () => DateTime(2026, 10, 30, 9),
    );
    await workflow.initialize();
    return _CaptureHarness(
      vault: vault,
      index: index,
      results: results,
      tables: tables,
      workflow: workflow,
    );
  }

  Future<void> close() async {
    workflow.dispose();
    tables.dispose();
    results.dispose();
    await results.shutdown();
  }
}

class _FakeCaptureService extends CaptureService {
  _FakeCaptureService({required this.candidate, required this.fail})
    : super(
        settings: FakeSettingsService(),
        parser: const DeterministicParser(),
      );

  final ClassificationCandidate? candidate;
  final bool fail;

  @override
  Future<CaptureAnalysis> analyze({
    required String text,
    required DateTime now,
    required bool preferModel,
  }) async {
    if (fail) throw StateError('analysis unavailable');
    return CaptureAnalysis(
      candidate:
          candidate ??
          ClassificationCandidate(
            type: ResultType.knowledge,
            title: '随手笔记',
            confidence: 0.95,
          ),
      usedModel: false,
    );
  }
}
