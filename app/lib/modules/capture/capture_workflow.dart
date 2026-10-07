import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/models.dart';
import '../../data/index_database.dart';
import '../../data/result_repository.dart';
import '../../services/capture_service.dart';
import '../results/result_library.dart';
import 'capture_outcome.dart';

export 'capture_outcome.dart';

class CaptureWorkflow extends ChangeNotifier {
  CaptureWorkflow({
    required ResultRepository repository,
    required ResultLibrary results,
    required IndexDatabase indexDatabase,
    required CaptureService captureService,
    Uuid? uuid,
    DateTime Function()? now,
  }) : _repository = repository,
       _results = results,
       _indexDatabase = indexDatabase,
       _captureService = captureService,
       _uuid = uuid ?? const Uuid(),
       _now = now ?? DateTime.now;

  static const _reviewConfidenceThreshold = 0.72;

  final ResultRepository _repository;
  final ResultLibrary _results;
  final IndexDatabase _indexDatabase;
  final CaptureService _captureService;
  final Uuid _uuid;
  final DateTime Function() _now;

  List<CaptureRecord> _captures = const [];
  List<CaptureRecord> _reviewCaptures = const [];

  List<CaptureRecord> get captures => _captures;

  List<CaptureRecord> get reviewCaptures => _reviewCaptures;

  Future<void> initialize() => refresh();

  Future<void> refresh() async {
    final captures = await _indexDatabase.listCaptures();
    _captures = List.unmodifiable(captures);
    _reviewCaptures = List.unmodifiable(
      captures.where((capture) => capture.status == CaptureStatus.needsReview),
    );
    notifyListeners();
  }

  Future<CaptureOutcome> captureText(
    String text, {
    bool preferModel = true,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return const CaptureOutcome.failure('请输入内容');
    }

    final now = _now();
    final capture = CaptureRecord(
      id: 'cap_${_uuid.v4()}',
      deviceId: _repository.deviceId,
      capturedAt: now,
      sourceType: _sourceType(normalized),
      text: normalized,
      status: CaptureStatus.processing,
    );

    await _indexDatabase.insertCapture(capture);
    await refresh();

    final CaptureAnalysis analysis;
    try {
      analysis = await _captureService.analyze(
        text: normalized,
        now: now,
        preferModel: preferModel,
      );
    } catch (error) {
      return _moveToReview(
        capture,
        reviewReason: '分析失败，原文已保留',
        warning: error.toString(),
      );
    }

    final candidate = analysis.candidate;
    final updated = capture.copyWith(
      candidateType: candidate.type,
      candidateTitle: candidate.title,
      candidateAt: candidate.start ?? candidate.due,
      confidence: candidate.confidence,
      reviewReason: candidate.reviewReason,
      status:
          candidate.needsReview ||
              candidate.confidence < _reviewConfidenceThreshold
          ? CaptureStatus.needsReview
          : CaptureStatus.accepted,
    );

    if (updated.status == CaptureStatus.needsReview) {
      await _replaceCapture(updated);
      return CaptureOutcome.review(updated, warning: analysis.warning);
    }

    final ResultDocument document;
    try {
      document = await _createFromCandidate(candidate);
    } catch (error) {
      return _moveToReview(
        updated,
        reviewReason: '成果写入失败，原文已保留',
        warning: error.toString(),
      );
    }

    await _replaceCapture(updated.copyWith(resultId: document.id));
    return CaptureOutcome.created(
      document,
      usedModel: analysis.usedModel,
      warning: analysis.warning,
    );
  }

  Future<ResultDocument> acceptCapture(
    CaptureRecord capture, {
    ResultType? type,
    String? title,
  }) async {
    final effectiveType = type ?? capture.candidateType ?? ResultType.knowledge;
    final document = await _results.createManual(
      type: effectiveType,
      title: title?.trim().isNotEmpty == true
          ? title!.trim()
          : capture.candidateTitle ?? '待整理',
      body: capture.text,
      status: ResultStatus.canonical,
      due: effectiveType == ResultType.todo ? capture.candidateAt : null,
      start: effectiveType == ResultType.event ? capture.candidateAt : null,
      end: effectiveType == ResultType.event && capture.candidateAt != null
          ? capture.candidateAt!.add(const Duration(hours: 1))
          : null,
    );
    await _replaceCapture(
      capture.copyWith(
        status: CaptureStatus.accepted,
        resultId: document.id,
        candidateType: effectiveType,
        candidateTitle: document.title,
      ),
    );
    return document;
  }

  Future<void> rejectCapture(CaptureRecord capture) async {
    await _replaceCapture(capture.copyWith(status: CaptureStatus.failed));
  }

  /// Adds a model-produced candidate to the shared review queue.
  ///
  /// This is the application seam used by conversation and capture
  /// coordinators so review state always has one owner.
  Future<void> enqueueReview(CaptureRecord capture) async {
    await _indexDatabase.insertCapture(capture);
    await refresh();
  }

  Future<void> _replaceCapture(CaptureRecord capture) async {
    await _indexDatabase.updateCapture(capture);
    await refresh();
  }

  Future<CaptureOutcome> _moveToReview(
    CaptureRecord capture, {
    required String reviewReason,
    required String warning,
  }) async {
    final updated = capture.copyWith(
      status: CaptureStatus.needsReview,
      reviewReason: reviewReason,
    );
    await _replaceCapture(updated);
    return CaptureOutcome.review(updated, warning: warning);
  }

  Future<ResultDocument> _createFromCandidate(
    ClassificationCandidate candidate,
  ) {
    return _results.createFromCandidate(candidate);
  }

  CaptureSourceType _sourceType(String text) {
    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme && !text.contains(RegExp(r'\s'))) {
      return CaptureSourceType.url;
    }
    return CaptureSourceType.text;
  }
}
