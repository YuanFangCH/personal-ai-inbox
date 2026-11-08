import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/table_models.dart';
import '../../core/table_markdown_codec.dart';
import '../../data/table_repository.dart';
import '../tables/table_library.dart';
import 'content_duplicate_policy.dart';

final _tableIntakeTails = Expando<Future<void>>('content-intake-tail');

enum ContentIntakeOutcome { created, reused, augmented, conflict }

enum ContentIntakeWriteKind { create, augment }

enum ContentIntakeConflictPolicy { ask, createWithReview }

class ContentIntakeWriteAuthorization {
  const ContentIntakeWriteAuthorization({
    required this.operationId,
    required this.kind,
    required this.tableId,
    required this.tableRevision,
    this.targetId,
    this.targetRevision,
  });

  final String operationId;
  final ContentIntakeWriteKind kind;
  final String tableId;
  final int tableRevision;
  final String? targetId;
  final int? targetRevision;
}

typedef ContentIntakeAuthorizationGuard = Future<bool> Function(
  ContentIntakeWriteAuthorization authorization,
);

class ContentIntakeRequest {
  ContentIntakeRequest({
    required this.operationId,
    required this.tableId,
    required this.type,
    required this.title,
    this.body = '',
    ContentBusinessIdentity? identity,
    List<String> tags = const [],
    List<String> links = const [],
    List<ScheduleChange> affects = const [],
    Map<String, Object?> customValues = const {},
    Map<String, Object?> extensionFields = const {},
    this.due,
    this.start,
    this.end,
    this.done = false,
    this.allDay = false,
    this.recurrence,
    this.occurredAt,
    List<String> sourceRefs = const [],
    this.requestedEntryId,
    this.conflictPolicy = ContentIntakeConflictPolicy.ask,
  }) : identity = identity ?? ContentBusinessIdentity(),
       tags = List.unmodifiable(tags),
       links = List.unmodifiable(links),
       affects = List.unmodifiable(affects),
       customValues = Map.unmodifiable(Map.of(customValues)),
       extensionFields = Map.unmodifiable(Map.of(extensionFields)),
       sourceRefs = List.unmodifiable(sourceRefs) {
    if (operationId.trim().isEmpty) {
      throw ArgumentError.value(operationId, 'operationId');
    }
    if (tableId.trim().isEmpty) {
      throw ArgumentError.value(tableId, 'tableId');
    }
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title');
    }
    if (requestedEntryId != null && requestedEntryId!.trim().isEmpty) {
      throw ArgumentError.value(requestedEntryId, 'requestedEntryId');
    }
    if (type == TableContentType.schedule && start == null) {
      throw ArgumentError('日程必须有开始时间。');
    }
    if (end != null && start != null && !end!.isAfter(start!)) {
      throw ArgumentError('结束时间必须晚于开始时间。');
    }
    if (type != TableContentType.todo && due != null) {
      throw ArgumentError('截止时间只适用于待办。');
    }
    if (type != TableContentType.todo && done) {
      throw ArgumentError('完成状态只适用于待办。');
    }
    if (type != TableContentType.schedule &&
        (start != null || end != null || allDay || recurrence != null)) {
      throw ArgumentError('日程字段只适用于日程。');
    }
    if (type != TableContentType.event &&
        (occurredAt != null || affects.isNotEmpty)) {
      throw ArgumentError('事件字段只适用于事件。');
    }
  }

  final String operationId;
  final String tableId;
  final TableContentType type;
  final String title;
  final String body;
  final ContentBusinessIdentity identity;
  final List<String> tags;
  final List<String> links;
  final List<ScheduleChange> affects;
  final Map<String, Object?> customValues;
  final Map<String, Object?> extensionFields;
  final DateTime? due;
  final bool done;
  final DateTime? start;
  final DateTime? end;
  final bool allDay;
  final String? recurrence;
  final DateTime? occurredAt;
  final List<String> sourceRefs;
  final String? requestedEntryId;
  final ContentIntakeConflictPolicy conflictPolicy;
}

class ContentIntakeCoverage {
  const ContentIntakeCoverage({
    required this.tablesScanned,
    required this.entriesScanned,
    required this.semanticCandidatesChecked,
    this.semanticCandidatesTotal = 0,
    this.semanticComparisonComplete = true,
  });

  final int tablesScanned;
  final int entriesScanned;
  final int semanticCandidatesChecked;
  final int semanticCandidatesTotal;
  final bool semanticComparisonComplete;

  int get semanticCandidatesRemaining =>
      (semanticCandidatesTotal - semanticCandidatesChecked).clamp(0, 1 << 30);

  bool get exactFingerprintScopeComplete => true;
  bool get semanticUniquenessProven => false;
}

class ContentIntakeChanges {
  const ContentIntakeChanges({
    this.bodyAppended = false,
    this.fieldChanges = const {},
  });

  final bool bodyAppended;
  final Map<String, Object?> fieldChanges;
}

class ContentIntakePreparation {
  const ContentIntakePreparation({
    required this.token,
    required this.operationId,
    required this.outcome,
    required this.coverage,
    this.targetId,
    this.targetRevision,
    this.tableRevision,
    this.reason,
    this.reviewRequired = false,
  });

  final String token;
  final String operationId;
  final ContentIntakeOutcome outcome;
  final ContentIntakeCoverage coverage;
  final String? targetId;
  final int? targetRevision;
  final int? tableRevision;
  final String? reason;
  final bool reviewRequired;
}

class ContentIntakeResult {
  const ContentIntakeResult({
    required this.operationId,
    required this.outcome,
    required this.coverage,
    this.targetId,
    this.entry,
    this.oldRevision,
    this.newRevision,
    this.changes = const ContentIntakeChanges(),
    this.reason,
    this.replayed = false,
    this.reviewRequired = false,
  });

  final String operationId;
  final ContentIntakeOutcome outcome;
  final ContentIntakeCoverage coverage;
  final String? targetId;
  final TableEntryDocument? entry;
  final int? oldRevision;
  final int? newRevision;
  final ContentIntakeChanges changes;
  final String? reason;
  final bool replayed;
  final bool reviewRequired;

  String? get entryId => entry?.id;

  ContentIntakeResult copyWith({bool? replayed}) => ContentIntakeResult(
    operationId: operationId,
    outcome: outcome,
    coverage: coverage,
    targetId: targetId,
    entry: entry,
    oldRevision: oldRevision,
    newRevision: newRevision,
    changes: changes,
    reason: reason,
    replayed: replayed ?? this.replayed,
    reviewRequired: reviewRequired,
  );
}

/// Prepares a duplicate-checked content intent and commits it only after a
/// fresh scan and version check.
///
/// Exact checks cover every active table visible through [TableLibrary].
/// Semantic checks cover only the bounded candidates reported by [coverage],
/// so callers must not describe a result as whole-library semantic uniqueness.
class ContentIntake {
  ContentIntake({
    required TableLibrary tables,
    SemanticDuplicateDecisionSource? semanticDecisionSource,
    ContentDuplicatePolicy policy = const ContentDuplicatePolicy(),
    DateTime Function()? clock,
    String Function(TableContentType type)? entryIdFactory,
  }) : _tables = tables,
       _semanticDecisionSource =
           semanticDecisionSource ??
           const ConservativeSemanticDuplicateDecisionSource(),
       _policy = policy,
       _clock = clock ?? DateTime.now,
       _entryIdFactory = entryIdFactory ?? _defaultEntryId;

  final TableLibrary _tables;
  final SemanticDuplicateDecisionSource _semanticDecisionSource;
  final ContentDuplicatePolicy _policy;
  final DateTime Function() _clock;
  final String Function(TableContentType type) _entryIdFactory;
  final Map<String, _PreparedIntake> _preparedByToken = {};
  final Map<String, _OperationRecord> _operationsByKey = {};

  Future<ContentIntakePreparation> prepare(ContentIntakeRequest request) =>
      _serialize(() => _prepareUnlocked(request));

  Future<ContentIntakeResult> commit(
    ContentIntakePreparation preparation, {
    DateTime? now,
    ContentIntakeAuthorizationGuard? authorizationGuard,
    bool persistAuthorizationConflict = true,
  }) => _serialize(
    () => _commitUnlocked(
      preparation,
      now: now,
      authorizationGuard: authorizationGuard,
      persistAuthorizationConflict: persistAuthorizationConflict,
    ),
  );

  Future<ContentIntakePreparation> _prepareUnlocked(
    ContentIntakeRequest request,
  ) async {
    final requestSignature = _requestSignature(request);
    final existing = _operationsByKey[request.operationId];
    if (existing != null) {
      if (existing.requestSignature != requestSignature) {
        throw StateError('操作 ID 已绑定其他接收内容：${request.operationId}');
      }
      return existing.preparation;
    }
    final durable = await _tables.readIntakeOperation(
      request.operationId,
      requestSignature,
    );
    if (durable != null) {
      final result = _resultFromRecord(durable);
      final preparation = ContentIntakePreparation(
        token: 'intake_${const Uuid().v4()}',
        operationId: request.operationId,
        outcome: result.outcome,
        coverage: result.coverage,
        targetId: result.entryId ?? result.targetId,
        targetRevision: result.newRevision,
        reason: result.reason,
        reviewRequired: result.reviewRequired,
      );
      _preparedByToken[preparation.token] = _PreparedIntake(
        request: request,
        requestSignature: requestSignature,
        signal: _signalForRequest(request),
        preparation: preparation,
        snapshotSignature: '',
      );
      _operationsByKey[request.operationId] = _OperationRecord(
        requestSignature: requestSignature,
        preparation: preparation,
        result: result,
      );
      return preparation;
    }

    final table = await _requireActiveTable(request.tableId);
    final signal = _signalForRequest(request);
    final fingerprint = _policy.fingerprint(signal);
    final scan = await _scan();
    final exact = _policy.exactMatch(
      signal: signal,
      fingerprint: fingerprint,
      candidates: scan.candidates,
    );
    final semanticCandidates = _policy.semanticCandidates(
      signal: signal,
      candidates: scan.candidates,
    );
    final coverage = scan.coverage(
      0,
      semanticCandidates.length,
      semanticCandidates.isEmpty,
    );
    final token = 'intake_${const Uuid().v4()}';

    late final ContentIntakePreparation preparation;
    if (exact != null) {
      preparation = ContentIntakePreparation(
        token: token,
        operationId: request.operationId,
        outcome: ContentIntakeOutcome.reused,
        coverage: coverage,
        targetId: exact.entry.id,
        targetRevision: exact.entry.revision,
        tableRevision: table.revision,
      );
    } else if (semanticCandidates.isEmpty) {
      preparation = ContentIntakePreparation(
        token: token,
        operationId: request.operationId,
        outcome: ContentIntakeOutcome.created,
        coverage: coverage,
        tableRevision: table.revision,
      );
    } else {
      final evaluation = await _evaluateSemanticCandidates(
        signal: signal,
        candidates: semanticCandidates,
      );
      final evaluatedCoverage = scan.coverage(
        evaluation.candidatesChecked,
        semanticCandidates.length,
        evaluation.complete,
      );
      if (!evaluation.complete) {
        final reason = evaluation.reason ?? '查重候选未全部检查，已暂停接收。';
        preparation = _conflictOrCreateWithReview(
          request: request,
          token: token,
          coverage: evaluatedCoverage,
          tableRevision: table.revision,
          targetId: evaluation.targetId,
          reason: reason,
        );
      } else if (evaluation.conflict) {
        final reason = evaluation.reason ?? '已发现同一业务证据下的候选，不能直接新建。';
        preparation = _conflictOrCreateWithReview(
          request: request,
          token: token,
          coverage: evaluatedCoverage,
          tableRevision: table.revision,
          reason: reason,
        );
      } else if (evaluation.augment == null) {
        preparation = ContentIntakePreparation(
          token: token,
          operationId: request.operationId,
          outcome: ContentIntakeOutcome.created,
          coverage: evaluatedCoverage,
          tableRevision: table.revision,
        );
      } else {
        final decision = evaluation.augment!;
        final target = _candidateById(semanticCandidates, decision.targetId);
        final validationError = _policy.validateSemanticDecision(
          signal: signal,
          candidates: semanticCandidates,
          decision: decision,
        );
        if (target == null || validationError != null) {
          preparation = _conflictOrCreateWithReview(
            request: request,
            token: token,
            coverage: evaluatedCoverage,
            targetId: decision.targetId,
            targetRevision: decision.expectedRevision,
            tableRevision: table.revision,
            reason: validationError ?? '语义补充目标无效。',
          );
        } else {
          final targetTable = await _requireActiveTable(target.entry.tableId);
          final merge = _buildMergePlan(
            target: target.entry,
            table: targetTable,
            decision: decision,
          );
          preparation = ContentIntakePreparation(
            token: token,
            operationId: request.operationId,
            outcome: merge.error == null
                ? ContentIntakeOutcome.augmented
                : ContentIntakeOutcome.conflict,
            coverage: evaluatedCoverage,
            targetId: target.entry.id,
            targetRevision: target.entry.revision,
            tableRevision: targetTable.revision,
            reason: merge.error,
          );
          if (merge.error == null) {
            _preparedByToken[token] = _PreparedIntake(
              request: request,
              requestSignature: requestSignature,
              signal: signal,
              preparation: preparation,
              snapshotSignature: scan.signature,
              merge: merge,
            );
          }
        }
      }
    }

    if (!_preparedByToken.containsKey(token)) {
      _preparedByToken[token] = _PreparedIntake(
        request: request,
        requestSignature: requestSignature,
        signal: signal,
        preparation: preparation,
        snapshotSignature: scan.signature,
      );
    }
    _operationsByKey[request.operationId] = _OperationRecord(
      requestSignature: requestSignature,
      preparation: preparation,
    );
    return preparation;
  }

  ContentIntakePreparation _conflictOrCreateWithReview({
    required ContentIntakeRequest request,
    required String token,
    required ContentIntakeCoverage coverage,
    required int tableRevision,
    required String reason,
    String? targetId,
    int? targetRevision,
  }) {
    if (request.conflictPolicy == ContentIntakeConflictPolicy.ask) {
      return ContentIntakePreparation(
        token: token,
        operationId: request.operationId,
        outcome: ContentIntakeOutcome.conflict,
        coverage: coverage,
        targetId: targetId,
        targetRevision: targetRevision,
        tableRevision: tableRevision,
        reason: reason,
      );
    }
    return ContentIntakePreparation(
      token: token,
      operationId: request.operationId,
      outcome: ContentIntakeOutcome.created,
      coverage: coverage,
      tableRevision: tableRevision,
      reason: '未证明为同一对象，已新建独立内容并标记待核对：$reason',
      reviewRequired: true,
    );
  }

  Future<ContentIntakeResult> _commitUnlocked(
    ContentIntakePreparation preparation, {
    DateTime? now,
    ContentIntakeAuthorizationGuard? authorizationGuard,
    required bool persistAuthorizationConflict,
  }) async {
    final prepared = _preparedByToken[preparation.token];
    if (prepared == null) {
      throw StateError('接收令牌无效或已被移除。');
    }
    final operation = _operationsByKey[prepared.request.operationId];
    if (operation == null || operation.preparation.token != preparation.token) {
      throw StateError('接收令牌与操作不匹配。');
    }
    final priorResult = operation.result;
    if (priorResult != null) return priorResult.copyWith(replayed: true);
    final durable = await _tables.readIntakeOperation(
      prepared.request.operationId,
      prepared.requestSignature,
    );
    if (durable != null) {
      return _resultFromRecord(durable).copyWith(replayed: true);
    }
    if (preparation.outcome == ContentIntakeOutcome.conflict) {
      return _finish(
        prepared,
        ContentIntakeResult(
          operationId: prepared.request.operationId,
          outcome: ContentIntakeOutcome.conflict,
          coverage: preparation.coverage,
          targetId: preparation.targetId,
          reason: preparation.reason,
        ),
      );
    }

    final scan = await _scan();
    final fingerprint = _policy.fingerprint(prepared.signal);
    final exact = _policy.exactMatch(
      signal: prepared.signal,
      fingerprint: fingerprint,
      candidates: scan.candidates,
    );

    if (exact != null) {
      final semanticCandidates = _policy.semanticCandidates(
        signal: prepared.signal,
        candidates: scan.candidates,
      );
      try {
        await _tables.validateContentSnapshot(scan.signature);
      } on IntakeSnapshotConflict {
        return await _staleSnapshotResult(
          prepared,
          scan.coverage(0, semanticCandidates.length, false),
        );
      }
      return _finish(
        prepared,
        ContentIntakeResult(
          operationId: prepared.request.operationId,
          outcome: ContentIntakeOutcome.reused,
          coverage: scan.coverage(0, semanticCandidates.length, false),
          entry: exact.entry,
          oldRevision: exact.entry.revision,
          newRevision: exact.entry.revision,
        ),
      );
    }

    final semanticCandidates = _policy.semanticCandidates(
      signal: prepared.signal,
      candidates: scan.candidates,
    );
    if (scan.signature != prepared.snapshotSignature) {
      return _finish(
        prepared,
        ContentIntakeResult(
          operationId: prepared.request.operationId,
          outcome: ContentIntakeOutcome.conflict,
          coverage: scan.coverage(0, semanticCandidates.length, false),
          targetId: preparation.targetId,
          reason: await _stalePreparationReason(prepared),
        ),
      );
    }

    if (preparation.outcome == ContentIntakeOutcome.created) {
      final currentTable = await _requireActiveTableOrNull(
        prepared.request.tableId,
      );
      if (currentTable == null ||
          currentTable.revision != preparation.tableRevision) {
        return await _finish(
          prepared,
          ContentIntakeResult(
            operationId: prepared.request.operationId,
            outcome: ContentIntakeOutcome.conflict,
            coverage: preparation.coverage,
            reason: '准备后目标表或表结构版本已变化，请重新准备。',
          ),
        );
      }
      if (semanticCandidates.isNotEmpty &&
          prepared.request.conflictPolicy == ContentIntakeConflictPolicy.ask &&
          (!preparation.coverage.semanticComparisonComplete ||
              preparation.coverage.semanticCandidatesChecked !=
                  semanticCandidates.length ||
              preparation.coverage.semanticCandidatesTotal !=
                  semanticCandidates.length)) {
        return _finish(
          prepared,
          ContentIntakeResult(
            operationId: prepared.request.operationId,
            outcome: ContentIntakeOutcome.conflict,
            coverage: preparation.coverage,
            reason: '准备后发现同一业务对象候选，请重新核对。',
          ),
        );
      }
      final entry = _entryFromRequest(
        prepared.request,
        id:
            prepared.request.requestedEntryId ??
            _entryIdFactory(prepared.request.type),
        createdAt: now ?? _clock(),
      );
      final writeAuthorization = ContentIntakeWriteAuthorization(
        operationId: prepared.request.operationId,
        kind: ContentIntakeWriteKind.create,
        tableId: currentTable.id,
        tableRevision: currentTable.revision,
      );
      try {
        final created = await _tables.commitIntakeEntry(
          entry: entry,
          expectedSnapshotSignature: prepared.snapshotSignature,
          expectedTableRevision: currentTable.revision,
          authorizationGuard: authorizationGuard == null
              ? null
              : () => _requireWriteAuthorization(
                  authorizationGuard,
                  writeAuthorization,
                ),
          receipt: _receiptRecord(
            prepared,
            ContentIntakeResult(
              operationId: prepared.request.operationId,
              outcome: ContentIntakeOutcome.created,
              coverage: preparation.coverage,
              oldRevision: 0,
              newRevision: entry.revision,
              reason: preparation.reason,
              reviewRequired: preparation.reviewRequired,
            ),
          ),
        );
        return await _finish(
          prepared,
          ContentIntakeResult(
            operationId: prepared.request.operationId,
            outcome: ContentIntakeOutcome.created,
            coverage: preparation.coverage,
            entry: created,
            oldRevision: 0,
            newRevision: created.revision,
            reason: preparation.reason,
            reviewRequired: preparation.reviewRequired,
          ),
        );
      } on IntakeSnapshotConflict {
        return await _staleSnapshotResult(
          prepared,
          scan.coverage(0, semanticCandidates.length, false),
        );
      } on IntakeWriteAuthorizationDenied catch (error) {
        final result = ContentIntakeResult(
          operationId: prepared.request.operationId,
          outcome: ContentIntakeOutcome.conflict,
          coverage: preparation.coverage,
          reason: error.reason,
        );
        return persistAuthorizationConflict
            ? _finish(prepared, result)
            : result;
      }
    }

    final targetId = preparation.targetId;
    final target = targetId == null ? null : await _tables.readEntry(targetId);
    if (target == null ||
        target.revision != preparation.targetRevision ||
        target.deleted) {
      return await _finish(
        prepared,
        ContentIntakeResult(
          operationId: prepared.request.operationId,
          outcome: ContentIntakeOutcome.conflict,
          coverage: preparation.coverage,
          targetId: targetId,
          reason: '准备后目标内容版本已变化，请重新核对。',
        ),
      );
    }
    final targetTable = await _requireActiveTableOrNull(target.tableId);
    if (targetTable == null ||
        targetTable.revision != preparation.tableRevision) {
      return _finish(
        prepared,
        ContentIntakeResult(
          operationId: prepared.request.operationId,
          outcome: ContentIntakeOutcome.conflict,
          coverage: preparation.coverage,
          targetId: target.id,
          reason: '准备后目标内容所属表或字段结构已变化，请重新核对。',
        ),
      );
    }
    final targetSignal = ContentIdentitySignal.forEntry(target);
    if (!targetSignal.identity.hasEquivalentEvidenceWith(
          prepared.signal.identity,
        ) ||
        targetSignal.businessAnchor != prepared.signal.businessAnchor) {
      return _finish(
        prepared,
        ContentIntakeResult(
          operationId: prepared.request.operationId,
          outcome: ContentIntakeOutcome.conflict,
          coverage: preparation.coverage,
          targetId: target.id,
          reason: '目标内容的业务对象证据或时间已变化。',
        ),
      );
    }

    final merge = prepared.merge;
    if (merge == null) {
      return _finish(
        prepared,
        ContentIntakeResult(
          operationId: prepared.request.operationId,
          outcome: ContentIntakeOutcome.conflict,
          coverage: preparation.coverage,
          targetId: target.id,
          reason: '接收准备缺少可执行的补充计划。',
        ),
      );
    }
    final currentMerge = _buildMergePlan(
      target: target,
      table: targetTable,
      decision: merge.decision,
      now: now,
    );
    if (currentMerge.error != null) {
      return _finish(
        prepared,
        ContentIntakeResult(
          operationId: prepared.request.operationId,
          outcome: ContentIntakeOutcome.conflict,
          coverage: preparation.coverage,
          targetId: target.id,
          reason: currentMerge.error,
        ),
      );
    }
    final writeAuthorization = ContentIntakeWriteAuthorization(
      operationId: prepared.request.operationId,
      kind: ContentIntakeWriteKind.augment,
      tableId: targetTable.id,
      tableRevision: targetTable.revision,
      targetId: target.id,
      targetRevision: target.revision,
    );
    try {
      final updated = await _tables.commitIntakeEntry(
        entry: currentMerge.entry!,
        expectedRevision: target.revision,
        expectedSnapshotSignature: prepared.snapshotSignature,
        expectedTableRevision: targetTable.revision,
        authorizationGuard: authorizationGuard == null
            ? null
            : () => _requireWriteAuthorization(
                authorizationGuard,
                writeAuthorization,
              ),
        receipt: _receiptRecord(
          prepared,
          ContentIntakeResult(
            operationId: prepared.request.operationId,
            outcome: ContentIntakeOutcome.augmented,
            coverage: preparation.coverage,
            oldRevision: target.revision,
            newRevision: target.revision + 1,
            changes: currentMerge.changes,
          ),
        ),
      );
      return await _finish(
        prepared,
        ContentIntakeResult(
          operationId: prepared.request.operationId,
          outcome: ContentIntakeOutcome.augmented,
          coverage: preparation.coverage,
          entry: updated,
          oldRevision: target.revision,
          newRevision: updated.revision,
          changes: currentMerge.changes,
        ),
      );
    } on IntakeSnapshotConflict {
      return await _staleSnapshotResult(
        prepared,
        scan.coverage(0, semanticCandidates.length, false),
      );
    } on IntakeWriteAuthorizationDenied catch (error) {
      final result = ContentIntakeResult(
        operationId: prepared.request.operationId,
        outcome: ContentIntakeOutcome.conflict,
        coverage: preparation.coverage,
        targetId: target.id,
        reason: error.reason,
      );
      return persistAuthorizationConflict ? _finish(prepared, result) : result;
    }
  }

  static String _defaultEntryId(TableContentType type) {
    final prefix = switch (type) {
      TableContentType.note => 'nt',
      TableContentType.todo => 'td',
      TableContentType.schedule => 'sc',
      TableContentType.event => 'ev',
    };
    return '${prefix}_${const Uuid().v4()}';
  }

  Future<ContentIntakeResult> _finish(
    _PreparedIntake prepared,
    ContentIntakeResult result,
  ) async {
    await _tables.saveIntakeReceipt(_receiptRecord(prepared, result));
    _operationsByKey[prepared.request.operationId] = _OperationRecord(
      requestSignature: prepared.requestSignature,
      preparation: prepared.preparation,
      result: result,
    );
    return result;
  }

  Map<String, Object?> _receiptRecord(
    _PreparedIntake prepared,
    ContentIntakeResult result,
  ) => {
    'operation_id': result.operationId,
    'request_signature': prepared.requestSignature,
    'outcome': result.outcome.name,
    'target_id': result.targetId,
    'entry': result.entry == null
        ? null
        : const TableMarkdownCodec().encodeEntry(
            result.entry!,
            fields:
                _tables.findTable(result.entry!.tableId)?.fields ?? const [],
          ),
    'old_revision': result.oldRevision,
    'new_revision': result.newRevision,
    'body_appended': result.changes.bodyAppended,
    'field_changes': result.changes.fieldChanges,
    'reason': result.reason,
    'review_required': result.reviewRequired,
    'coverage': {
      'tables': result.coverage.tablesScanned,
      'entries': result.coverage.entriesScanned,
      'semantic': result.coverage.semanticCandidatesChecked,
      'semantic_total': result.coverage.semanticCandidatesTotal,
      'semantic_complete': result.coverage.semanticComparisonComplete,
    },
  };

  ContentIntakeResult _resultFromRecord(Map<String, Object?> record) {
    final coverage = record['coverage'] as Map;
    return ContentIntakeResult(
      operationId: record['operation_id'] as String,
      outcome: ContentIntakeOutcome.values.byName(record['outcome'] as String),
      entry: record['entry'] == null
          ? null
          : const TableMarkdownCodec().decodeEntry(record['entry'] as String),
      targetId: record['target_id'] as String?,
      oldRevision: record['old_revision'] as int?,
      newRevision: record['new_revision'] as int?,
      changes: ContentIntakeChanges(
        bodyAppended: record['body_appended'] as bool,
        fieldChanges: Map<String, Object?>.from(record['field_changes'] as Map),
      ),
      reason: record['reason'] as String?,
      reviewRequired: record['review_required'] == true,
      coverage: ContentIntakeCoverage(
        tablesScanned: coverage['tables'] as int,
        entriesScanned: coverage['entries'] as int,
        semanticCandidatesChecked: coverage['semantic'] as int,
        semanticCandidatesTotal:
            coverage['semantic_total'] as int? ?? coverage['semantic'] as int,
        semanticComparisonComplete:
            coverage['semantic_complete'] as bool? ?? true,
      ),
    );
  }

  Future<String?> _authorizationDenied(
    ContentIntakeAuthorizationGuard? guard,
    ContentIntakeWriteAuthorization authorization,
  ) async {
    if (guard == null) return null;
    try {
      return await guard(authorization) ? null : '写入前权限复核失败：授权已失效，操作未执行。';
    } on Object {
      return '写入前无法确认权限，操作未执行。';
    }
  }

  Future<bool?> _requireWriteAuthorization(
    ContentIntakeAuthorizationGuard guard,
    ContentIntakeWriteAuthorization authorization,
  ) async {
    final denial = await _authorizationDenied(guard, authorization);
    if (denial != null) throw IntakeWriteAuthorizationDenied(denial);
    return true;
  }

  _MergePlan _buildMergePlan({
    required TableEntryDocument target,
    required TableDocument table,
    required SemanticDuplicateDecision decision,
    DateTime? now,
  }) {
    final validationError = _policy.validateAdditions(
      target: target,
      bodyAddition: decision.bodyAddition,
      fieldAdditions: decision.fieldAdditions,
      table: table,
    );
    if (validationError != null) {
      return _MergePlan(decision: decision, error: validationError);
    }
    final addition = decision.bodyAddition.trim();
    final body = addition.isEmpty
        ? target.body
        : target.body.trim().isEmpty
        ? addition
        : '${target.body.trimRight()}\n\n$addition';
    final values = Map<String, Object?>.of(target.customValues);
    final changes = <String, Object?>{};
    for (final fieldAddition in decision.fieldAdditions.entries) {
      final current = values[fieldAddition.key];
      final merged = _mergeFieldValue(current, fieldAddition.value);
      if (_jsonEquals(current, merged)) continue;
      values[fieldAddition.key] = merged;
      changes[fieldAddition.key] = merged;
    }
    final changed = body != target.body || changes.isNotEmpty;
    if (!changed) {
      return _MergePlan(decision: decision, error: '语义补充没有产生新的内容。');
    }
    return _MergePlan(
      decision: decision,
      entry: target.copyWith(
        body: body,
        customValues: values,
        updatedAt: now ?? _clock(),
      ),
      changes: ContentIntakeChanges(
        bodyAppended: body != target.body,
        fieldChanges: Map.unmodifiable(changes),
      ),
    );
  }

  Object? _mergeFieldValue(Object? current, Object? addition) {
    if (current is List<Object?> && addition is List<Object?>) {
      final values = <Object?>[...current];
      for (final candidate in addition) {
        if (!values.any((value) => _jsonEquals(value, candidate))) {
          values.add(candidate);
        }
      }
      return List.unmodifiable(values);
    }
    if (current == null ||
        (current is String && current.trim().isEmpty) ||
        (current is Iterable && current.isEmpty)) {
      return addition;
    }
    return current;
  }

  bool _jsonEquals(Object? left, Object? right) =>
      jsonEncode(normalizeContentValue(left)) ==
      jsonEncode(normalizeContentValue(right));

  ContentIdentitySignal _signalForRequest(ContentIntakeRequest request) {
    final factEvidence = semanticFactEvidenceForContent(
      type: request.type,
      due: request.due,
      start: request.start,
      end: request.end,
      occurredAt: request.occurredAt,
      allDay: request.allDay,
      recurrence: request.recurrence,
      customValues: request.customValues,
    );
    final suppliedEvidence = <String>[
      ...request.identity.evidence,
      ...request.links.map((link) => 'entry:$link'),
      ...request.affects.map((affect) => 'entry:${affect.scheduleId}'),
    ];
    final combinedEvidence = <String>{...factEvidence, ...suppliedEvidence};
    final impliedEvidence = combinedEvidence.isNotEmpty
        ? combinedEvidence.toList()
        : <String>[
            contentObjectEvidenceKey(
              type: request.type,
              title: request.title,
              due: request.due,
              start: request.start,
              end: request.end,
              occurredAt: request.occurredAt,
              allDay: request.allDay,
              recurrence: request.recurrence,
              customValues: request.customValues,
            ),
          ];
    return ContentIdentitySignal(
      type: request.type,
      title: request.title,
      body: request.body,
      identity: ContentBusinessIdentity(evidence: impliedEvidence),
      businessAnchor: contentBusinessAnchor(
        type: request.type,
        due: request.due,
        start: request.start,
        end: request.end,
        occurredAt: request.occurredAt,
        allDay: request.allDay,
        recurrence: request.recurrence,
      ),
      tags: request.tags,
      links: request.links,
      affects: request.affects,
      customValues: request.customValues,
      allDay: request.allDay,
      recurrence: request.recurrence,
    );
  }

  TableEntryDocument _entryFromRequest(
    ContentIntakeRequest request, {
    required String id,
    required DateTime createdAt,
  }) {
    final evidence = _signalForRequest(request).identity.evidence.toList()
      ..sort();
    final safeExtensions = Map<String, Object?>.of(request.extensionFields)
      ..remove(manualDuplicateExceptionExtensionKey);
    return TableEntryDocument(
      id: id,
      type: request.type,
      tableId: request.tableId,
      title: request.title,
      revision: 1,
      createdAt: createdAt,
      updatedAt: createdAt,
      body: request.body,
      tags: request.tags,
      links: request.links,
      due: request.due,
      done: request.done,
      start: request.start,
      end: request.end,
      allDay: request.allDay,
      recurrence: request.recurrence,
      occurredAt: request.occurredAt,
      affects: request.affects,
      customValues: request.customValues,
      extensionFields: {
        ...safeExtensions,
        contentIntakeEvidenceExtensionKey: evidence,
      },
    );
  }

  Future<_ScanReport> _scan() async {
    final snapshot = await _tables.contentSnapshot();
    final candidates = <ContentDuplicateCandidate>[];
    for (final entry in snapshot.entries) {
      final signal = ContentIdentitySignal.forEntry(entry);
      candidates.add(
        ContentDuplicateCandidate(
          entry: entry,
          signal: signal,
          fingerprint: _policy.fingerprint(signal),
        ),
      );
    }
    return _ScanReport(
      tablesScanned: snapshot.tables.length,
      candidates: List.unmodifiable(candidates),
      signature: snapshot.signature,
    );
  }

  Future<ContentIntakeResult> _staleSnapshotResult(
    _PreparedIntake prepared,
    ContentIntakeCoverage coverage,
  ) => _finish(
    prepared,
    ContentIntakeResult(
      operationId: prepared.request.operationId,
      outcome: ContentIntakeOutcome.conflict,
      coverage: coverage,
      targetId: prepared.preparation.targetId,
      reason: '准备或授权等待期间本地表/内容版本已变化；未执行写入，请重新检查。',
    ),
  );

  Future<String> _stalePreparationReason(_PreparedIntake prepared) async {
    final preparation = prepared.preparation;
    if (preparation.targetId != null) {
      final target = await _tables.readEntry(preparation.targetId!);
      if (target == null ||
          target.deleted ||
          target.revision != preparation.targetRevision) {
        return '准备后目标内容版本已变化；未执行写入，请重新检查。';
      }
      final table = await _requireActiveTableOrNull(target.tableId);
      if (table == null || table.revision != preparation.tableRevision) {
        return '准备后目标内容所属表或字段结构已变化；未执行写入，请重新检查。';
      }
    } else {
      final table = await _requireActiveTableOrNull(prepared.request.tableId);
      if (table == null || table.revision != preparation.tableRevision) {
        return '准备后目标表或字段结构版本已变化；未执行写入，请重新检查。';
      }
    }
    return '查重后本地候选集合已变化；未执行写入，请重新检查。';
  }

  Future<_SemanticEvaluation> _evaluateSemanticCandidates({
    required ContentIdentitySignal signal,
    required List<ContentDuplicateCandidate> candidates,
  }) async {
    final pageSize = _policy.maxSemanticCandidates.clamp(1, 10);
    final augmentations = <SemanticDuplicateDecision>[];
    var checked = 0;
    String? conflictReason;
    for (var offset = 0; offset < candidates.length; offset += pageSize) {
      final end = (offset + pageSize).clamp(0, candidates.length);
      final page = List<ContentDuplicateCandidate>.unmodifiable(
        candidates.sublist(offset, end),
      );
      final SemanticDuplicateDecision decision;
      try {
        decision = await _semanticDecisionSource.decide(
          SemanticDuplicateRequest(signal: signal, candidates: page),
        );
      } on Object catch (error) {
        return _SemanticEvaluation(
          candidatesChecked: checked,
          complete: false,
          conflict: true,
          reason: '查重第 ${offset ~/ pageSize + 1} 批失败：$error',
        );
      }
      if (!decision.comparisonComplete) {
        return _SemanticEvaluation(
          candidatesChecked: checked,
          complete: false,
          conflict: true,
          targetId: decision.targetId,
          reason: decision.reason ?? '查重批次未完成，剩余候选未检查。',
        );
      }
      checked += page.length;
      if (decision.action == SemanticDuplicateAction.conflict) {
        conflictReason ??= decision.reason ?? '同一业务证据下存在待核对的内容。';
        continue;
      }
      if (decision.action == SemanticDuplicateAction.create) {
        continue;
      }
      final validationError = _policy.validateSemanticDecision(
        signal: signal,
        candidates: page,
        decision: decision,
      );
      if (validationError != null) {
        conflictReason ??= validationError;
        continue;
      }
      augmentations.add(decision);
    }

    if (conflictReason != null) {
      return _SemanticEvaluation(
        candidatesChecked: checked,
        complete: true,
        conflict: true,
        reason: conflictReason,
      );
    }
    if (augmentations.length > 1) {
      return _SemanticEvaluation(
        candidatesChecked: checked,
        complete: true,
        conflict: true,
        reason: '多个查重批次指向不同内容，无法唯一确定补充目标。',
      );
    }
    if (augmentations.isEmpty) {
      return _SemanticEvaluation(
        candidatesChecked: checked,
        complete: true,
        conflict: false,
      );
    }
    return _SemanticEvaluation(
      candidatesChecked: checked,
      complete: true,
      conflict: false,
      augment: augmentations.single,
    );
  }

  Future<TableDocument> _requireActiveTable(String id) async {
    final table = await _requireActiveTableOrNull(id);
    if (table == null) throw StateError('目标表不存在或已删除：$id');
    return table;
  }

  Future<TableDocument?> _requireActiveTableOrNull(String id) async {
    await _tables.refresh();
    final table = _tables.findTable(id);
    return table == null || table.deleted ? null : table;
  }

  ContentDuplicateCandidate? _candidateById(
    List<ContentDuplicateCandidate> candidates,
    String? id,
  ) {
    if (id == null) return null;
    for (final candidate in candidates) {
      if (candidate.entry.id == id) return candidate;
    }
    return null;
  }

  String _requestSignature(ContentIntakeRequest request) => jsonEncode({
    'operation_id': request.operationId,
    'table_id': request.tableId,
    'type': request.type.wireName,
    'title': normalizeContentText(request.title),
    'body': normalizeContentText(request.body),
    'evidence': request.identity.evidence.toList()..sort(),
    'tags': request.tags.map(normalizeContentText).toList()..sort(),
    'links': request.links.toList()..sort(),
    'affects':
        request.affects
            .map(
              (affect) => <String, Object?>{
                'schedule_id': affect.scheduleId,
                'summary': normalizeContentText(affect.summary ?? ''),
              },
            )
            .toList()
          ..sort(
            (left, right) => jsonEncode(left).compareTo(jsonEncode(right)),
          ),
    'custom_values': normalizeContentValue(request.customValues),
    'extension_fields': normalizeContentValue(request.extensionFields),
    'due': request.due?.toUtc().toIso8601String(),
    'done': request.done,
    'start': request.start?.toUtc().toIso8601String(),
    'end': request.end?.toUtc().toIso8601String(),
    'all_day': request.allDay,
    'recurrence': normalizeContentText(request.recurrence ?? ''),
    'occurred_at': request.occurredAt?.toUtc().toIso8601String(),
    'source_refs': request.sourceRefs.toList()..sort(),
    'requested_entry_id': request.requestedEntryId,
  });

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final previous = _tableIntakeTails[_tables] ?? Future<void>.value();
    final finished = Completer<void>();
    _tableIntakeTails[_tables] = finished.future;
    return () async {
      await previous;
      try {
        return await operation();
      } finally {
        finished.complete();
      }
    }();
  }
}

class _PreparedIntake {
  const _PreparedIntake({
    required this.request,
    required this.requestSignature,
    required this.signal,
    required this.preparation,
    required this.snapshotSignature,
    this.merge,
  });

  final ContentIntakeRequest request;
  final String requestSignature;
  final ContentIdentitySignal signal;
  final ContentIntakePreparation preparation;
  final String snapshotSignature;
  final _MergePlan? merge;
}

class _OperationRecord {
  const _OperationRecord({
    required this.requestSignature,
    required this.preparation,
    this.result,
  });

  final String requestSignature;
  final ContentIntakePreparation preparation;
  final ContentIntakeResult? result;
}

class _ScanReport {
  const _ScanReport({
    required this.tablesScanned,
    required this.candidates,
    required this.signature,
  });

  final int tablesScanned;
  final List<ContentDuplicateCandidate> candidates;
  final String signature;

  ContentIntakeCoverage coverage(
    int semanticCandidatesChecked, [
    int? semanticCandidatesTotal,
    bool complete = true,
  ]) => ContentIntakeCoverage(
    tablesScanned: tablesScanned,
    entriesScanned: candidates.length,
    semanticCandidatesChecked: semanticCandidatesChecked,
    semanticCandidatesTotal:
        semanticCandidatesTotal ?? semanticCandidatesChecked,
    semanticComparisonComplete: complete,
  );
}

class _SemanticEvaluation {
  const _SemanticEvaluation({
    required this.candidatesChecked,
    required this.complete,
    required this.conflict,
    this.augment,
    this.targetId,
    this.reason,
  });

  final int candidatesChecked;
  final bool complete;
  final bool conflict;
  final SemanticDuplicateDecision? augment;
  final String? targetId;
  final String? reason;
}

class _MergePlan {
  const _MergePlan({
    required this.decision,
    this.entry,
    this.changes = const ContentIntakeChanges(),
    this.error,
  });

  final SemanticDuplicateDecision decision;
  final TableEntryDocument? entry;
  final ContentIntakeChanges changes;
  final String? error;
}
