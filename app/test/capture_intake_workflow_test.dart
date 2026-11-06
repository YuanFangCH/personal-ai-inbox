import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/core/table_models.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/modules/capture/capture_workflow.dart';
import 'package:personal_ai_inbox/modules/conversation/content_duplicate_policy.dart';
import 'package:personal_ai_inbox/modules/conversation/content_intake.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';
import 'package:personal_ai_inbox/modules/tables/table_library.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';

import 'test_support.dart';

void main() {
  test(
    'exact capture reuse keeps both source records and one formal entry',
    () async {
      final harness = await _CaptureIntakeHarness.create(
        candidate: const ClassificationCandidate(
          type: ResultType.knowledge,
          title: '复习范围',
          confidence: 0.95,
        ),
      );
      addTearDown(harness.close);

      final first = await harness.workflow.captureText('第二章和第三章');
      final second = await harness.workflow.captureText('第二章和第三章');

      expect(first.tableEntry!.id, second.tableEntry!.id);
      expect(harness.workflow.captures, hasLength(2));
      expect(
        harness.workflow.captures.map((capture) => capture.text),
        everyElement('第二章和第三章'),
      );
      expect(
        harness.workflow.captures.map((capture) => capture.resultId).toSet(),
        {first.tableEntry!.id},
      );
      expect(
        await harness.tables.searchEntries(query: '', limit: 100),
        hasLength(1),
      );
    },
  );

  test(
    'same capture object with new evidence augments the reused ID',
    () async {
      final start = DateTime(2026, 11, 2, 9);
      final harness = await _CaptureIntakeHarness.create(
        candidate: ClassificationCandidate(
          type: ResultType.event,
          title: '期中考试',
          confidence: 0.95,
          start: start,
          end: start.add(const Duration(hours: 2)),
        ),
      );
      addTearDown(harness.close);

      final first = await harness.workflow.captureText('第一章至第三章');
      final second = await harness.workflow.captureText('补充地点：三教 101');
      final entries = await harness.tables.searchEntries(query: '', limit: 100);

      expect(second.tableEntry!.id, first.tableEntry!.id);
      expect(entries, hasLength(1));
      expect(entries.single.revision, 2);
      expect(entries.single.body, contains('第一章至第三章'));
      expect(entries.single.body, contains('补充地点：三教 101'));
      expect(
        harness.workflow.captures.map((capture) => capture.resultId).toSet(),
        {first.tableEntry!.id},
      );
    },
  );

  test('capture model dedupe receives capture-scoped context', () async {
    final start = DateTime(2026, 11, 2, 9);
    final contexts = <CaptureDuplicateExecutionContext>[];
    final writeAuthorizations = <ContentIntakeWriteAuthorization>[];
    var reads = 0;
    var modifies = 0;
    var reservations = 0;
    final harness = await _CaptureIntakeHarness.create(
      candidate: ClassificationCandidate(
        type: ResultType.event,
        title: '权限隔离考试',
        confidence: 0.95,
        start: start,
        end: start.add(const Duration(hours: 2)),
      ),
      duplicateDecisionSourceFactory: (context) {
        contexts.add(context);
        return _CaptureContextDecisionSource(context);
      },
      canReadDuplicateCandidates: (_) async {
        reads++;
        return true;
      },
      canModifyDuplicateCandidates: (_) async {
        modifies++;
        return true;
      },
      reserveDuplicateModelRequest: (_) async {
        reservations++;
        return true;
      },
      duplicateCancellation: () async {},
      contentWriteAuthorization: (authorization) async {
        writeAuthorizations.add(authorization);
        return true;
      },
    );
    addTearDown(harness.close);

    await harness.workflow.captureText('原内容');
    await harness.workflow.captureText('补充内容');

    expect(contexts, hasLength(2));
    expect(
      contexts.map((context) => context.scopeId),
      harness.workflow.captures.map((capture) => 'capture:${capture.id}'),
    );
    expect(contexts.every((context) => context.cancellation != null), isTrue);
    expect(reads, 1);
    expect(modifies, 1);
    expect(reservations, 1);
    expect(writeAuthorizations, hasLength(2));
    expect(writeAuthorizations.map((authorization) => authorization.kind), [
      ContentIntakeWriteKind.create,
      ContentIntakeWriteKind.augment,
    ]);
    expect(
      writeAuthorizations.last.targetId,
      harness.workflow.captures.last.resultId,
    );
    expect(harness.workflow.captures, hasLength(2));
    expect(
      harness.workflow.captures.map((capture) => capture.resultId).toSet(),
      hasLength(1),
    );
  });

  test(
    'failed analysis reuses its fallback note instead of duplicating it',
    () async {
      final harness = await _CaptureIntakeHarness.create(failAnalysis: true);
      addTearDown(harness.close);

      final first = await harness.workflow.captureText('模型失败时的原文');
      final second = await harness.workflow.captureText('模型失败时的原文');

      expect(first.tableEntry!.id, second.tableEntry!.id);
      expect(harness.workflow.captures, hasLength(2));
      expect(
        harness.workflow.captures.map((capture) => capture.resultId).toSet(),
        {first.tableEntry!.id},
      );
      expect(
        await harness.tables.searchEntries(query: '', limit: 100),
        hasLength(1),
      );
    },
  );

  test(
    'missing inbox assignment keeps capture review without formal write',
    () async {
      final harness = await _CaptureIntakeHarness.create(failAnalysis: true);
      addTearDown(harness.close);
      final eventTable = harness.tables.tables.singleWhere(
        (table) => table.role == TableRole.inboxEvent,
      );
      await harness.tables.deleteTable(
        id: eventTable.id,
        expectedRevision: eventTable.revision,
      );

      final outcome = await harness.workflow.captureText('暂时没有收纳目标');

      expect(outcome.status, CaptureOutcomeStatus.review);
      expect(outcome.capture!.text, '暂时没有收纳目标');
      expect(outcome.capture!.status, CaptureStatus.needsReview);
      expect(outcome.capture!.reviewReason, contains('收纳目标'));
      expect(
        await harness.tables.searchEntries(query: '', limit: 100),
        isEmpty,
      );
    },
  );
}

class _CaptureIntakeHarness {
  _CaptureIntakeHarness({
    required this.results,
    required this.tables,
    required this.workflow,
  });

  final ResultLibrary results;
  final TableLibrary tables;
  final CaptureWorkflow workflow;

  static Future<_CaptureIntakeHarness> create({
    ClassificationCandidate? candidate,
    bool failAnalysis = false,
    CaptureDuplicateDecisionSourceFactory? duplicateDecisionSourceFactory,
    CaptureDuplicateReadPermissionCheck? canReadDuplicateCandidates,
    CaptureDuplicateModifyPermissionCheck? canModifyDuplicateCandidates,
    CaptureDuplicateModelRequestBudget? reserveDuplicateModelRequest,
    CaptureDuplicateCancellationProvider? duplicateCancellation,
    ContentIntakeAuthorizationGuard? contentWriteAuthorization,
  }) async {
    final index = MemoryIndexDatabase();
    final repository = ResultRepository(
      vault: MemoryVaultStore(),
      index: index,
      deviceId: 'capture-intake-test',
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
      captureService: _CaptureIntakeService(
        candidate: candidate,
        fail: failAnalysis,
      ),
      now: () => DateTime(2026, 10, 30, 9),
      duplicateDecisionSourceFactory: duplicateDecisionSourceFactory,
      canReadDuplicateCandidates: canReadDuplicateCandidates,
      canModifyDuplicateCandidates: canModifyDuplicateCandidates,
      reserveDuplicateModelRequest: reserveDuplicateModelRequest,
      duplicateCancellation: duplicateCancellation,
      contentWriteAuthorization: contentWriteAuthorization,
    );
    await workflow.initialize();
    return _CaptureIntakeHarness(
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

class _CaptureContextDecisionSource implements SemanticDuplicateDecisionSource {
  _CaptureContextDecisionSource(this.context);

  final CaptureDuplicateExecutionContext context;

  @override
  Future<SemanticDuplicateDecision> decide(
    SemanticDuplicateRequest request,
  ) async {
    expect(await context.canReadCandidates(request), isTrue);
    expect(await context.canModifyExisting(request), isTrue);
    expect(await context.reserveModelRequest(request), isTrue);
    final target = request.candidates.single;
    return SemanticDuplicateDecision(
      action: SemanticDuplicateAction.augment,
      targetId: target.entry.id,
      expectedRevision: target.entry.revision,
      evidence: request.signal
          .sharedVerifiableSemanticEvidenceWith(target.signal)
          .toList(),
      bodyAddition: request.signal.body,
    );
  }
}

class _CaptureIntakeService extends CaptureService {
  _CaptureIntakeService({required this.candidate, required this.fail})
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
            title: '捕获笔记',
            confidence: 0.95,
          ),
      usedModel: false,
    );
  }
}
