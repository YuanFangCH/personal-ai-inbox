import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/core/models.dart';
import 'package:personal_ai_inbox/data/index_database.dart';
import 'package:personal_ai_inbox/data/memory_index_database.dart';
import 'package:personal_ai_inbox/data/memory_vault_store.dart';
import 'package:personal_ai_inbox/data/result_repository.dart';
import 'package:personal_ai_inbox/modules/results/result_library.dart';
import 'package:personal_ai_inbox/modules/capture/capture_workflow.dart';
import 'package:personal_ai_inbox/services/capture_service.dart';

import 'test_support.dart';

void main() {
  late MemoryVaultStore vault;
  late MemoryIndexDatabase storage;
  late _RecordingIndexDatabase index;
  late ResultRepository repository;
  late ResultLibrary results;
  late List<String> events;

  setUp(() async {
    vault = MemoryVaultStore();
    storage = MemoryIndexDatabase();
    events = [];
    index = _RecordingIndexDatabase(storage, events);
    repository = ResultRepository(
      vault: vault,
      index: index,
      deviceId: 'test-device',
    );
    await repository.initialize();
    results = ResultLibrary(repository: repository);
    await results.initialize();
    events.clear();
  });

  CaptureWorkflow createWorkflow({
    ClassificationCandidate? candidate,
    CaptureAnalysis Function(String text, DateTime now, bool preferModel)?
    analyze,
  }) {
    final parser = const DeterministicParser();
    return CaptureWorkflow(
      repository: repository,
      results: results,
      indexDatabase: index,
      captureService: _RecordingCaptureService(
        events: events,
        onAnalyze:
            analyze ??
            (text, now, preferModel) {
              events.add('analyze');
              return CaptureAnalysis(
                candidate: candidate ?? parser.parse(text, now),
                usedModel: false,
              );
            },
      ),
      now: () => DateTime(2026, 10, 7, 9),
    );
  }

  test(
    'high-confidence input is persisted before analysis and created',
    () async {
      final workflow = createWorkflow();
      await workflow.initialize();

      final outcome = await workflow.captureText('明天下午三点和客户开会');

      expect(outcome.status, CaptureOutcomeStatus.created);
      expect(outcome.document, isNotNull);
      expect(outcome.document!.type, ResultType.event);
      expect(workflow.captures, hasLength(1));
      expect(workflow.captures.single.status, CaptureStatus.accepted);
      expect(workflow.captures.single.resultId, outcome.document!.id);
      expect(vault.files, contains(outcome.document!.markdownPath));
      expect(events, containsAllInOrder(const ['insertCapture', 'analyze']));
    },
  );

  test(
    'low-confidence input remains in review with its original text',
    () async {
      final workflow = createWorkflow();
      await workflow.initialize();

      final outcome = await workflow.captureText('下周找时间看房子');

      expect(outcome.status, CaptureOutcomeStatus.review);
      expect(outcome.capture, isNotNull);
      expect(workflow.captures, hasLength(1));
      expect(workflow.reviewCaptures, hasLength(1));
      expect(workflow.captures.single.text, '下周找时间看房子');
      expect(workflow.captures.single.status, CaptureStatus.needsReview);
      expect(await repository.listDocuments(), isEmpty);
    },
  );

  test(
    'acceptCapture creates a canonical result and resolves review',
    () async {
      final workflow = createWorkflow();
      await workflow.initialize();
      final captured = await workflow.captureText('稍后整理捕获工作流资料');
      final capture = captured.capture!;

      final document = await workflow.acceptCapture(
        capture,
        type: ResultType.todo,
        title: '整理捕获模块',
      );

      expect(document.type, ResultType.todo);
      expect(document.title, '整理捕获模块');
      expect(document.body, capture.text);
      expect(workflow.reviewCaptures, isEmpty);
      expect(workflow.captures.single.status, CaptureStatus.accepted);
      expect(workflow.captures.single.resultId, document.id);
    },
  );

  test('rejectCapture closes review without creating a result', () async {
    final workflow = createWorkflow();
    await workflow.initialize();
    final captured = await workflow.captureText('下周找时间看房子');

    await workflow.rejectCapture(captured.capture!);

    expect(workflow.reviewCaptures, isEmpty);
    expect(workflow.captures.single.status, CaptureStatus.failed);
    expect(await repository.listDocuments(), isEmpty);
  });

  test('empty input fails without persisting or analyzing', () async {
    final workflow = createWorkflow();
    await workflow.initialize();

    final outcome = await workflow.captureText('   ');

    expect(outcome.status, CaptureOutcomeStatus.failure);
    expect(outcome.message, '请输入内容');
    expect(workflow.captures, isEmpty);
    expect(events, isNot(contains('insertCapture')));
    expect(events, isNot(contains('analyze')));
  });

  test('analysis failure moves the persisted original into review', () async {
    final workflow = createWorkflow(
      analyze: (text, now, preferModel) {
        events.add('analyze');
        throw StateError('model unavailable');
      },
    );
    await workflow.initialize();

    final outcome = await workflow.captureText('不能丢失的原始输入');

    expect(outcome.status, CaptureOutcomeStatus.review);
    expect(outcome.warning, contains('model unavailable'));
    expect(workflow.captures.single.text, '不能丢失的原始输入');
    expect(workflow.captures.single.status, CaptureStatus.needsReview);
    expect(workflow.captures.single.reviewReason, '分析失败，原文已保留');
    expect(await repository.listDocuments(), isEmpty);
  });
}

class _RecordingCaptureService extends CaptureService {
  _RecordingCaptureService({
    required this.events,
    required CaptureAnalysis Function(
      String text,
      DateTime now,
      bool preferModel,
    )
    onAnalyze,
  }) : _onAnalyze = onAnalyze,
       super(
         settings: FakeSettingsService(),
         parser: const DeterministicParser(),
       );

  final List<String> events;
  final CaptureAnalysis Function(String text, DateTime now, bool preferModel)
  _onAnalyze;

  @override
  Future<CaptureAnalysis> analyze({
    required String text,
    required DateTime now,
    required bool preferModel,
  }) async {
    return _onAnalyze(text, now, preferModel);
  }
}

class _RecordingIndexDatabase implements IndexDatabase {
  _RecordingIndexDatabase(this._delegate, this._events);

  final IndexDatabase _delegate;
  final List<String> _events;

  @override
  Future<void> open() => _delegate.open();

  @override
  Future<void> close() => _delegate.close();

  @override
  Future<void> upsertResult(IndexedResult result) =>
      _delegate.upsertResult(result);

  @override
  Future<void> removeResult(String id) => _delegate.removeResult(id);

  @override
  Future<List<IndexedResult>> listResults() => _delegate.listResults();

  @override
  Future<IndexedResult?> findResult(String id) => _delegate.findResult(id);

  @override
  Future<void> replaceResults(List<IndexedResult> results) =>
      _delegate.replaceResults(results);

  @override
  Future<void> insertCapture(CaptureRecord capture) async {
    _events.add('insertCapture');
    await _delegate.insertCapture(capture);
  }

  @override
  Future<void> updateCapture(CaptureRecord capture) =>
      _delegate.updateCapture(capture);

  @override
  Future<List<CaptureRecord>> listCaptures({bool reviewOnly = false}) =>
      _delegate.listCaptures(reviewOnly: reviewOnly);

  @override
  Future<void> deleteCapture(String id) => _delegate.deleteCapture(id);

  @override
  Future<void> clear() => _delegate.clear();
}
