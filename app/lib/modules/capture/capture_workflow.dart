import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/models.dart';
import '../../core/table_models.dart';
import '../../data/index_database.dart';
import '../../data/result_repository.dart';
import '../../services/capture_service.dart';
import '../results/result_library.dart';
import '../tables/table_library.dart';
import 'capture_outcome.dart';

export 'capture_outcome.dart';

class CaptureWorkflow extends ChangeNotifier {
  CaptureWorkflow({
    required ResultRepository repository,
    required ResultLibrary results,
    TableLibrary? tables,
    required IndexDatabase indexDatabase,
    required CaptureService captureService,
    Uuid? uuid,
    DateTime Function()? now,
  }) : _repository = repository,
       _results = results,
       _tables = tables,
       _indexDatabase = indexDatabase,
       _captureService = captureService,
       _uuid = uuid ?? const Uuid(),
       _now = now ?? DateTime.now;

  static const _reviewConfidenceThreshold = 0.72;

  final ResultRepository _repository;
  final ResultLibrary _results;
  final TableLibrary? _tables;
  final IndexDatabase _indexDatabase;
  final CaptureService _captureService;
  final Uuid _uuid;
  final DateTime Function() _now;

  List<CaptureRecord> _captures = const [];
  List<CaptureRecord> _reviewCaptures = const [];

  List<CaptureRecord> get captures => _captures;

  List<CaptureRecord> get reviewCaptures => _reviewCaptures;

  Future<void> initialize() async {
    for (final capture in await _indexDatabase.listCaptures()) {
      if (capture.status != CaptureStatus.processing) {
        continue;
      }
      await _indexDatabase.updateCapture(
        capture.copyWith(
          status: CaptureStatus.needsReview,
          reviewReason: '应用在整理期间关闭；原文已保留，请手动继续。',
        ),
      );
    }
    await refresh();
  }

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
      if (_tables != null) {
        try {
          final entry = await _createFallbackNote(capture, title: '捕获笔记');
          await _replaceCapture(
            capture.copyWith(
              status: CaptureStatus.accepted,
              resultId: entry.id,
              candidateType: ResultType.knowledge,
              candidateTitle: entry.title,
              reviewReason: '分析失败；原文已保存为普通笔记。',
            ),
          );
          return CaptureOutcome.tableCreated(
            entry,
            warning: '分析失败；原文已保存为普通笔记。',
          );
        } on Object catch (writeError) {
          return _moveToReview(
            capture,
            reviewReason: '分析和表内保存均失败，原文仍保留在本机捕获记录中。',
            warning: writeError.toString(),
          );
        }
      }
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
      if (_tables != null) {
        try {
          final entry = await _createFallbackNote(
            updated,
            title: candidate.title.trim().isEmpty ? '待整理笔记' : candidate.title,
          );
          await _replaceCapture(
            updated.copyWith(
              status: CaptureStatus.accepted,
              resultId: entry.id,
              candidateType: ResultType.knowledge,
              candidateTitle: entry.title,
              reviewReason: candidate.reviewReason ?? '置信度不足；已保存为普通笔记。',
            ),
          );
          return CaptureOutcome.tableCreated(
            entry,
            usedModel: analysis.usedModel,
            warning: analysis.warning ?? '置信度不足；已保存为普通笔记。',
          );
        } on Object catch (error) {
          return _moveToReview(
            updated,
            reviewReason: '自动分类未确认，表内写入失败；原文已保留。',
            warning: error.toString(),
          );
        }
      }
      await _replaceCapture(updated);
      return CaptureOutcome.review(updated, warning: analysis.warning);
    }

    final tableLibrary = _tables;
    if (tableLibrary != null) {
      try {
        final entry = await _createTableCandidate(candidate, capture);
        await _replaceCapture(
          updated.copyWith(status: CaptureStatus.accepted, resultId: entry.id),
        );
        return CaptureOutcome.tableCreated(
          entry,
          usedModel: analysis.usedModel,
          warning: analysis.warning,
        );
      } on Object catch (error) {
        return _moveToReview(
          updated,
          reviewReason: '表内写入失败，原文已保留。',
          warning: error.toString(),
        );
      }
    }

    final ResultDocument document;
    try {
      document = await _createFromCandidate(candidate, capture);
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
      idempotencyKey: 'capture:${capture.id}',
      createdAt: capture.capturedAt,
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

  Future<TableEntryDocument> acceptCaptureToTable(
    CaptureRecord capture, {
    TableContentType? type,
    String? title,
  }) async {
    final library = _tables;
    if (library == null) throw StateError('表库暂不可用。');
    final candidate = ClassificationCandidate(
      type: capture.candidateType ?? ResultType.knowledge,
      title: title?.trim().isNotEmpty == true
          ? title!.trim()
          : capture.candidateTitle ?? '待整理',
      confidence: capture.confidence ?? 0,
      summary: capture.text,
      start: capture.candidateType == ResultType.event
          ? capture.candidateAt
          : null,
      due: capture.candidateType == ResultType.todo
          ? capture.candidateAt
          : null,
    );
    final entry = await _createTableCandidate(
      candidate,
      capture,
      overrideType: type,
      overrideTitle: title,
    );
    await _replaceCapture(
      capture.copyWith(
        status: CaptureStatus.accepted,
        resultId: entry.id,
        candidateTitle: entry.title,
      ),
    );
    return entry;
  }

  Future<TableEntryDocument> _createFallbackNote(
    CaptureRecord capture, {
    required String title,
  }) => _createTableEntry(
    capture,
    type: TableContentType.note,
    tableRole: TableRole.inboxEvent,
    title: title,
    body: capture.text,
  );

  Future<TableEntryDocument> _createTableCandidate(
    ClassificationCandidate candidate,
    CaptureRecord capture, {
    TableContentType? overrideType,
    String? overrideTitle,
  }) async {
    final now = _now();
    final requested = overrideType ?? _tableType(candidate, now);
    final role = switch (requested) {
      TableContentType.todo => TableRole.inboxTodo,
      TableContentType.schedule => TableRole.inboxSchedule,
      TableContentType.event || TableContentType.note => TableRole.inboxEvent,
    };
    final time = candidate.start ?? candidate.due;
    return _createTableEntry(
      capture,
      type: requested,
      tableRole: role,
      title: overrideTitle?.trim().isNotEmpty == true
          ? overrideTitle!.trim()
          : candidate.title.trim().isNotEmpty
          ? candidate.title.trim()
          : '待整理笔记',
      body: capture.text,
      tags: candidate.tags,
      due: requested == TableContentType.todo ? candidate.due : null,
      start: requested == TableContentType.schedule ? candidate.start : null,
      end: requested == TableContentType.schedule ? candidate.end : null,
      allDay: requested == TableContentType.schedule && candidate.allDay,
      recurrence: requested == TableContentType.schedule
          ? candidate.recurrence
          : null,
      occurredAt: requested == TableContentType.event ? time : null,
    );
  }

  TableContentType _tableType(ClassificationCandidate candidate, DateTime now) {
    if (candidate.type == ResultType.todo) return TableContentType.todo;
    if (candidate.type == ResultType.event) {
      final start = candidate.start;
      if (start != null && start.isAfter(now)) return TableContentType.schedule;
      return TableContentType.event;
    }
    return TableContentType.note;
  }

  Future<TableEntryDocument> _createTableEntry(
    CaptureRecord capture, {
    required TableContentType type,
    required TableRole tableRole,
    required String title,
    required String body,
    DateTime? due,
    DateTime? start,
    DateTime? end,
    bool allDay = false,
    String? recurrence,
    DateTime? occurredAt,
    List<String> tags = const [],
  }) async {
    final library = _tables;
    if (library == null) throw StateError('表库暂不可用。');
    final table = library.tables.singleWhere((item) => item.role == tableRole);
    final id = 'nt_${capture.id.replaceFirst(RegExp(r'^cap_'), '')}';
    final existing = await library.readEntry(id);
    if (existing != null) return existing;
    final now = capture.capturedAt;
    return library.createEntry(
      TableEntryDocument(
        id: id,
        type: type,
        tableId: table.id,
        title: title,
        revision: 1,
        createdAt: now,
        updatedAt: now,
        body: body,
        tags: tags,
        due: due,
        start: start,
        end: end,
        allDay: allDay,
        recurrence: recurrence,
        occurredAt: occurredAt,
      ),
    );
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
    CaptureRecord capture,
  ) {
    return _results.createFromCandidate(
      candidate,
      idempotencyKey: 'capture:${capture.id}',
      createdAt: capture.capturedAt,
    );
  }

  CaptureSourceType _sourceType(String text) {
    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme && !text.contains(RegExp(r'\s'))) {
      return CaptureSourceType.url;
    }
    return CaptureSourceType.text;
  }
}
