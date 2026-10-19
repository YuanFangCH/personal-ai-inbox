import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/models.dart';
import '../../data/result_repository.dart';

/// Application-layer-only access owned by modules that coordinate results.
///
/// UI code must use [ResultLibrary] and its immutable snapshots instead of
/// importing or calling this interface.
abstract interface class ResultLibraryInternal {
  Future<List<String>> listConflictFiles();

  Future<String?> readRaw(String path);

  Future<void> writeRaw(String path, String contents);

  Future<void> deleteRaw(String path);
}

/// Returns the application-layer access surface for [library].
///
/// This is intentionally a free function instead of a public getter on
/// [ResultLibrary], keeping raw storage behavior out of the UI-facing class.
ResultLibraryInternal resultLibraryInternal(ResultLibrary library) {
  return library._internal;
}

/// Deep application module for the Markdown-backed result library.
///
/// The module owns the immutable read model visible to the rest of the app.
/// Markdown parsing, SQLite indexing, revision handling, tombstones and raw
/// conflict files remain behind [ResultRepository].
class ResultLibrary extends ChangeNotifier {
  ResultLibrary({required ResultRepository repository})
    : _repository = repository,
      _internal = _ResultLibraryInternal(repository);

  final ResultRepository _repository;
  final ResultLibraryInternal _internal;

  List<ResultDocument> _documents = const [];
  List<ResultDocument> _canonicalDocuments = const [];
  List<ResultDocument> _draftDocuments = const [];
  List<ResultDocument> _todos = const [];
  List<ResultDocument> _events = const [];
  List<ResultDocument> _matters = const [];
  List<ResultDocument> _knowledge = const [];
  List<GlobalKnowledgeCandidate> _globalKnowledgeCandidates = const [];
  String _vaultRoot = '';

  List<ResultDocument> get documents => _documents;

  List<ResultDocument> get canonicalDocuments => _canonicalDocuments;

  List<ResultDocument> get draftDocuments => _draftDocuments;

  List<ResultDocument> get todos => _todos;

  List<ResultDocument> get events => _events;

  List<ResultDocument> get matters => _matters;

  List<ResultDocument> get knowledge => _knowledge;

  List<GlobalKnowledgeCandidate> get globalKnowledgeCandidates =>
      _globalKnowledgeCandidates;

  List<GlobalKnowledgeCandidate> get pendingGlobalKnowledgeCandidates =>
      List.unmodifiable(
        _globalKnowledgeCandidates.where(
          (candidate) =>
              candidate.status == GlobalKnowledgeCandidateStatus.pending,
        ),
      );

  String get vaultRoot => _vaultRoot;

  ResultDocument? findDocument(String id) {
    for (final document in _documents) {
      if (document.id == id) {
        return document;
      }
    }
    return null;
  }

  Future<ResultDocument?> readDocument(String id) =>
      _repository.readDocument(id);

  Future<ResultDocument?> findByIdempotencyKey({
    required ResultType type,
    required DateTime createdAt,
    required String idempotencyKey,
  }) {
    return _repository.findByIdempotencyKey(
      type: type,
      createdAt: createdAt,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<void> initialize() async {
    await _repository.initialize();
    await refresh();
    await _resumeApprovedGlobalKnowledgeChanges();
    await refresh();
  }

  Future<void> refresh() async {
    final documents = await _repository.listDocuments(includeDeleted: false);
    final frozen = List<ResultDocument>.unmodifiable(
      documents.map(_freezeDocument),
    );
    final canonical = List<ResultDocument>.unmodifiable(
      frozen.where((document) => document.status == ResultStatus.canonical),
    );

    _documents = frozen;
    _canonicalDocuments = canonical;
    _draftDocuments = List<ResultDocument>.unmodifiable(
      frozen.where((document) => document.status == ResultStatus.draft),
    );
    _todos = List<ResultDocument>.unmodifiable(
      canonical.where((document) => document.type == ResultType.todo),
    );
    _events = List<ResultDocument>.unmodifiable(
      canonical.where((document) => document.type == ResultType.event),
    );
    _matters = List<ResultDocument>.unmodifiable(
      canonical.where((document) => document.type == ResultType.matter),
    );
    _knowledge = List<ResultDocument>.unmodifiable(
      canonical.where((document) => document.type == ResultType.knowledge),
    );
    _globalKnowledgeCandidates = List<GlobalKnowledgeCandidate>.unmodifiable(
      await _repository.listGlobalKnowledgeCandidates(),
    );
    _vaultRoot = await _repository.describeVaultRoot();
    notifyListeners();
  }

  Future<ResultDocument> createManual({
    required ResultType type,
    required String title,
    String body = '',
    ResultStatus status = ResultStatus.canonical,
    DateTime? due,
    String? matterId,
    DateTime? start,
    DateTime? end,
    bool allDay = false,
    String? recurrence,
    List<String> tags = const [],
    String? idempotencyKey,
    DateTime? createdAt,
  }) async {
    final document = await _repository.create(
      type: type,
      title: title,
      body: body,
      status: status,
      due: due,
      matterId: matterId,
      start: start,
      end: end,
      allDay: allDay,
      recurrence: recurrence,
      tags: tags,
      idempotencyKey: idempotencyKey,
      createdAt: createdAt,
    );
    _publishDocument(document);
    return document;
  }

  Future<GlobalKnowledgeCandidate> proposeGlobalKnowledgeChange({
    required GlobalKnowledgeOperation operation,
    required Map<String, Object?> proposal,
    String? targetId,
    int? expectedRevision,
    String? expectedHash,
    String? sourceConversationId,
    String? sourceMessageId,
    String? candidateId,
  }) async {
    final normalized = _normalizeGlobalProposal(operation, proposal);
    final digest = _globalKnowledgeDigest(
      operation: operation,
      targetId: targetId,
      expectedRevision: expectedRevision,
      expectedHash: expectedHash,
      proposal: normalized,
    );
    final stableId =
        candidateId ??
        (sourceMessageId == null
            ? 'gkc_${const Uuid().v4().replaceAll('-', '')}'
            : 'gkc_${sha256.convert(utf8.encode('$sourceConversationId:$sourceMessageId:${operation.name}:$targetId:$digest')).toString().substring(0, 32)}');
    if (!RegExp(r'^gkc_[A-Za-z0-9_-]{1,64}$').hasMatch(stableId)) {
      throw ArgumentError.value(stableId, 'candidateId');
    }
    final existing = await _repository.findGlobalKnowledgeCandidate(stableId);
    if (existing != null) {
      if (existing.digest != digest) {
        throw StateError('全局知识候选 ID 已绑定其他内容：$stableId');
      }
      return existing;
    }
    if (operation == GlobalKnowledgeOperation.create) {
      if (targetId != null ||
          expectedRevision != null ||
          expectedHash != null) {
        throw ArgumentError('全局知识新增不能包含目标版本');
      }
    } else {
      final id = targetId;
      final revision = expectedRevision;
      final hash = expectedHash;
      if (id == null || revision == null || hash == null) {
        throw ArgumentError('全局知识修改/删除必须绑定目标 ID、revision 和 hash');
      }
      final target = await _repository.findDocument(id);
      final indexed = await _repository.findIndexed(id);
      final source = await _repository.readManagedResult(id);
      if (target == null ||
          target.type != ResultType.knowledge ||
          indexed == null ||
          source == null ||
          target.revision != revision ||
          indexed.revision != revision ||
          _repository.hashMarkdown(source) != hash ||
          indexed.localHash != hash ||
          !target.isGlobalKnowledge) {
        throw StateError('全局知识目标已变化或不符合操作范围，请重新读取：$id');
      }
    }
    final now = DateTime.now();
    final candidate = GlobalKnowledgeCandidate(
      id: stableId,
      operation: operation,
      status: GlobalKnowledgeCandidateStatus.pending,
      proposal: normalized,
      digest: digest,
      targetId: targetId,
      expectedRevision: expectedRevision,
      expectedHash: expectedHash,
      sourceConversationId: sourceConversationId,
      sourceMessageId: sourceMessageId,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.saveGlobalKnowledgeCandidate(candidate);
    _setGlobalKnowledgeCandidate(candidate);
    return candidate;
  }

  Future<GlobalKnowledgeCandidate> rejectGlobalKnowledgeChange(
    String candidateId, {
    required String displayedDigest,
  }) async {
    final candidate = await _requirePendingCandidate(
      candidateId,
      displayedDigest,
    );
    final rejected = candidate.copyWith(
      status: GlobalKnowledgeCandidateStatus.rejected,
      updatedAt: DateTime.now(),
      error: null,
    );
    await _repository.saveGlobalKnowledgeCandidate(rejected);
    _setGlobalKnowledgeCandidate(rejected);
    return rejected;
  }

  Future<ResultActionResult> confirmGlobalKnowledgeChange(
    String candidateId, {
    required String displayedDigest,
  }) async {
    final candidate = await _requirePendingCandidate(
      candidateId,
      displayedDigest,
    );
    await _verifyGlobalCandidateTarget(candidate);
    final approved = candidate.copyWith(
      status: GlobalKnowledgeCandidateStatus.approved,
      updatedAt: DateTime.now(),
      error: null,
    );
    await _repository.saveGlobalKnowledgeCandidate(approved);
    _setGlobalKnowledgeCandidate(approved);
    try {
      return await _applyApprovedGlobalCandidate(approved);
    } on StateError catch (error) {
      final current = await _repository.findGlobalKnowledgeCandidate(
        candidateId,
      );
      final completedAction = current == null
          ? null
          : await _repository.findReversibleAction('gk_${current.id}');
      if (current != null &&
          completedAction?.status == ReversibleActionStatus.applied) {
        final result = await _repository.readDocument(
          completedAction!.resultId,
        );
        if (result != null) {
          final applied = current.copyWith(
            status: GlobalKnowledgeCandidateStatus.applied,
            resultId: result.id,
            updatedAt: DateTime.now(),
            error: null,
          );
          await _repository.saveGlobalKnowledgeCandidate(applied);
          _setGlobalKnowledgeCandidate(applied);
          _publishDocument(result);
          return ResultActionResult(document: result, action: completedAction);
        }
      }
      if (current?.status == GlobalKnowledgeCandidateStatus.approved &&
          await _globalCandidateTargetChanged(current!)) {
        final stale = current.copyWith(
          status: GlobalKnowledgeCandidateStatus.stale,
          updatedAt: DateTime.now(),
          error: error.message,
        );
        await _repository.saveGlobalKnowledgeCandidate(stale);
        _setGlobalKnowledgeCandidate(stale);
      } else if (current?.status == GlobalKnowledgeCandidateStatus.approved) {
        final retryable = current!.copyWith(
          updatedAt: DateTime.now(),
          error: error.message,
        );
        await _repository.saveGlobalKnowledgeCandidate(retryable);
        _setGlobalKnowledgeCandidate(retryable);
      }
      rethrow;
    }
  }

  Future<ResultActionResult> retryApprovedGlobalKnowledgeChange(
    String candidateId,
  ) async {
    final candidate = await _repository.findGlobalKnowledgeCandidate(
      candidateId,
    );
    if (candidate == null ||
        candidate.status != GlobalKnowledgeCandidateStatus.approved) {
      throw StateError('只有已确认的全局知识变更可重试：$candidateId');
    }
    return _applyApprovedGlobalCandidate(candidate);
  }

  Future<GlobalKnowledgeCandidate> _requirePendingCandidate(
    String candidateId,
    String displayedDigest,
  ) async {
    final candidate = await _repository.findGlobalKnowledgeCandidate(
      candidateId,
    );
    if (candidate == null ||
        candidate.status != GlobalKnowledgeCandidateStatus.pending ||
        candidate.digest != displayedDigest ||
        candidate.digest !=
            _globalKnowledgeDigest(
              operation: candidate.operation,
              targetId: candidate.targetId,
              expectedRevision: candidate.expectedRevision,
              expectedHash: candidate.expectedHash,
              proposal: candidate.proposal,
            )) {
      throw StateError('全局知识候选已变化或不再等待确认：$candidateId');
    }
    return candidate;
  }

  Future<void> _verifyGlobalCandidateTarget(
    GlobalKnowledgeCandidate candidate,
  ) async {
    if (candidate.operation == GlobalKnowledgeOperation.create) return;
    if (await _globalCandidateTargetChanged(candidate)) {
      final stale = candidate.copyWith(
        status: GlobalKnowledgeCandidateStatus.stale,
        updatedAt: DateTime.now(),
        error: '目标版本已变化，请重新检索并展示新差异。',
      );
      await _repository.saveGlobalKnowledgeCandidate(stale);
      _setGlobalKnowledgeCandidate(stale);
      throw StateError(stale.error!);
    }
  }

  Future<bool> _globalCandidateTargetChanged(
    GlobalKnowledgeCandidate candidate,
  ) async {
    if (candidate.operation == GlobalKnowledgeOperation.create) return false;
    final id = candidate.targetId;
    final expectedRevision = candidate.expectedRevision;
    final expectedHash = candidate.expectedHash;
    if (id == null || expectedRevision == null || expectedHash == null) {
      return true;
    }
    final current = await _repository.readDocument(id);
    final indexed = await _repository.findIndexed(id);
    final source = await _repository.readManagedResult(id);
    return current == null ||
        indexed == null ||
        source == null ||
        current.type != ResultType.knowledge ||
        current.revision != expectedRevision ||
        indexed.revision != expectedRevision ||
        indexed.localHash != expectedHash ||
        _repository.hashMarkdown(source) != expectedHash ||
        !current.isGlobalKnowledge;
  }

  Future<ResultActionResult> _applyApprovedGlobalCandidate(
    GlobalKnowledgeCandidate candidate,
  ) async {
    if (candidate.digest !=
        _globalKnowledgeDigest(
          operation: candidate.operation,
          targetId: candidate.targetId,
          expectedRevision: candidate.expectedRevision,
          expectedHash: candidate.expectedHash,
          proposal: candidate.proposal,
        )) {
      throw StateError('全局知识审批内容与候选摘要不一致：${candidate.id}');
    }
    final proposal = candidate.proposal;
    final actionId = 'gk_${candidate.id}';
    final approvedAt = candidate.updatedAt;
    late final ResultDocument result;
    switch (candidate.operation) {
      case GlobalKnowledgeOperation.create:
        final metadata = _globalKnowledgeFields(
          proposal,
          candidate.digest,
          approvedAt,
        );
        result = await _repository.create(
          type: ResultType.knowledge,
          title: proposal['title'] as String,
          body: proposal['body'] as String,
          status: ResultStatus.canonical,
          extensionFields: metadata,
          createdAt: candidate.createdAt,
          idempotencyKey: 'global-kb:${candidate.id}',
          reversibleActionId: actionId,
          approvedGlobalCandidateId: candidate.id,
          approvedGlobalCandidateDigest: candidate.digest,
        );
        break;
      case GlobalKnowledgeOperation.update:
        final current = await _requireGlobalKnowledgeTarget(candidate);
        final next = current.copyWith(
          title: proposal['title'] as String,
          body: proposal['body'] as String,
          deleted: false,
          extensionFields: {
            ...current.extensionFields,
            ..._globalKnowledgeFields(proposal, candidate.digest, approvedAt),
          },
        );
        result = await _repository.saveWithUndo(
          document: next,
          expectedRevision: candidate.expectedRevision!,
          expectedHash: candidate.expectedHash!,
          actionId: actionId,
          approvedGlobalCandidateId: candidate.id,
          approvedGlobalCandidateDigest: candidate.digest,
        );
        break;
      case GlobalKnowledgeOperation.delete:
        await _requireGlobalKnowledgeTarget(candidate);
        result = await _repository.deleteWithUndo(
          id: candidate.targetId!,
          expectedRevision: candidate.expectedRevision!,
          expectedHash: candidate.expectedHash!,
          actionId: actionId,
          approvedGlobalCandidateId: candidate.id,
          approvedGlobalCandidateDigest: candidate.digest,
        );
        break;
    }
    final applied = candidate.copyWith(
      status: GlobalKnowledgeCandidateStatus.applied,
      resultId: result.id,
      updatedAt: DateTime.now(),
      error: null,
    );
    await _repository.saveGlobalKnowledgeCandidate(applied);
    _setGlobalKnowledgeCandidate(applied);
    _publishDocument(result);
    return ResultActionResult(
      document: result,
      action: (await _repository.findReversibleAction(actionId))!,
    );
  }

  Future<ResultDocument> _requireGlobalKnowledgeTarget(
    GlobalKnowledgeCandidate candidate,
  ) async {
    final id = candidate.targetId;
    if (id == null) throw StateError('全局知识候选缺少目标 ID');
    final target = await _repository.readDocument(id);
    if (target == null ||
        target.type != ResultType.knowledge ||
        !target.isGlobalKnowledge) {
      throw StateError('全局知识目标不存在或已不属于全局知识范围：$id');
    }
    return target;
  }

  Map<String, Object?> _globalKnowledgeFields(
    Map<String, Object?> proposal,
    String digest,
    DateTime approvedAt,
  ) => {
    globalKnowledgeScopeKey: globalKnowledgeScopeValue,
    'global_facts': proposal['facts'],
    'global_approval_digest': digest,
    'global_approved_at': approvedAt.toUtc().toIso8601String(),
    if (proposal['applies_to'] != null)
      'global_applies_to': proposal['applies_to'],
    if (proposal['valid_from'] != null)
      'global_valid_from': proposal['valid_from'],
    if (proposal['valid_until'] != null)
      'global_valid_until': proposal['valid_until'],
    if (proposal['timezone'] != null) 'global_timezone': proposal['timezone'],
  };

  Future<void> _resumeApprovedGlobalKnowledgeChanges() async {
    for (final candidate in await _repository.listGlobalKnowledgeCandidates()) {
      if (candidate.status != GlobalKnowledgeCandidateStatus.approved) continue;
      try {
        await _applyApprovedGlobalCandidate(candidate);
      } on StateError catch (error) {
        if (candidate.operation != GlobalKnowledgeOperation.create &&
            await _globalCandidateTargetChanged(candidate)) {
          final stale = candidate.copyWith(
            status: GlobalKnowledgeCandidateStatus.stale,
            updatedAt: DateTime.now(),
            error: error.message,
          );
          await _repository.saveGlobalKnowledgeCandidate(stale);
          _setGlobalKnowledgeCandidate(stale);
        }
      }
    }
  }

  void _setGlobalKnowledgeCandidate(GlobalKnowledgeCandidate candidate) {
    _globalKnowledgeCandidates = List.unmodifiable([
      candidate,
      ..._globalKnowledgeCandidates.where((item) => item.id != candidate.id),
    ]);
    notifyListeners();
  }

  Map<String, Object?> _normalizeGlobalProposal(
    GlobalKnowledgeOperation operation,
    Map<String, Object?> source,
  ) {
    if (operation == GlobalKnowledgeOperation.delete) {
      if (source.isNotEmpty) throw ArgumentError('全局知识删除候选不能携带替换正文');
      return const {};
    }
    const allowed = {
      'title',
      'body',
      'facts',
      'applies_to',
      'valid_from',
      'valid_until',
      'timezone',
    };
    final unknown = source.keys.where((key) => !allowed.contains(key));
    if (unknown.isNotEmpty) {
      throw ArgumentError('全局知识候选含不支持字段：${unknown.join('、')}');
    }
    final title = source['title'];
    final body = source['body'];
    final facts = source['facts'];
    if (title is! String || title.trim().isEmpty || title.length > 160) {
      throw ArgumentError('全局知识标题必须为 1–160 个字符');
    }
    if (body is! String || body.length > 6000) {
      throw ArgumentError('全局知识说明必须不超过 6000 个字符');
    }
    if (facts is! Map || facts.isEmpty || facts.length > 32) {
      throw ArgumentError('全局知识必须包含 1–32 个结构化事实');
    }
    final normalizedFacts = _normalizeJsonMap(facts);
    final normalized = <String, Object?>{
      'title': title.trim(),
      'body': body.trim(),
      'facts': normalizedFacts,
    };
    for (final field in const [
      'applies_to',
      'valid_from',
      'valid_until',
      'timezone',
    ]) {
      final value = source[field];
      if (value == null) continue;
      if (value is! String || value.trim().isEmpty || value.length > 120) {
        throw ArgumentError('全局知识字段 $field 格式错误');
      }
      normalized[field] = value.trim();
    }
    final from = normalized['valid_from'];
    final until = normalized['valid_until'];
    if (from != null && DateTime.tryParse(from as String) == null) {
      throw ArgumentError('生效日期格式无效');
    }
    if (until != null && DateTime.tryParse(until as String) == null) {
      throw ArgumentError('失效日期格式无效');
    }
    if (from != null &&
        until != null &&
        !DateTime.parse(until as String)
            .isAfter(DateTime.parse(from as String))) {
      throw ArgumentError('失效日期必须晚于生效日期');
    }
    if (jsonEncode(normalized).length > 8000) {
      throw ArgumentError('全局知识候选超过 8000 个字符');
    }
    return Map.unmodifiable(normalized);
  }

  Map<String, Object?> _normalizeJsonMap(Map<dynamic, dynamic> source) {
    final normalized = <String, Object?>{};
    for (final key in source.keys) {
      if (key is! String || key.trim().isEmpty || key.length > 120) {
        throw ArgumentError('全局事实名称格式错误');
      }
      normalized[key] = _normalizeJsonValue(source[key], 0);
    }
    return Map.unmodifiable(normalized);
  }

  Object? _normalizeJsonValue(Object? value, int depth) {
    if (depth > 6) throw ArgumentError('全局事实嵌套层级过深');
    if (value == null || value is String || value is bool || value is num) {
      return value;
    }
    if (value is List) {
      if (value.length > 32) throw ArgumentError('全局事实列表过长');
      return List.unmodifiable(
        value.map((item) => _normalizeJsonValue(item, depth + 1)),
      );
    }
    if (value is Map) {
      final entries = <String, Object?>{};
      for (final key in value.keys) {
        if (key is! String || key.isEmpty || key.length > 120) {
          throw ArgumentError('全局事实子字段名称格式错误');
        }
        entries[key] = _normalizeJsonValue(value[key], depth + 1);
      }
      return Map.unmodifiable(entries);
    }
    throw ArgumentError('全局事实只允许 JSON 数据类型');
  }

  String _globalKnowledgeDigest({
    required GlobalKnowledgeOperation operation,
    required String? targetId,
    required int? expectedRevision,
    required String? expectedHash,
    required Map<String, Object?> proposal,
  }) {
    final canonical = _canonicalJsonValue({
      'operation': operation.name,
      'target_id': targetId,
      'expected_revision': expectedRevision,
      'expected_hash': expectedHash,
      'proposal': proposal,
    });
    return 'sha256:${sha256.convert(utf8.encode(jsonEncode(canonical)))}';
  }

  Object? _canonicalJsonValue(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonicalJsonValue(value[key])};
    }
    if (value is List) return value.map(_canonicalJsonValue).toList();
    return value;
  }

  Future<ResultActionResult> createManualWithUndo({
    required ResultType type,
    required String title,
    required String body,
    required String actionId,
    required String idempotencyKey,
    required DateTime createdAt,
    ResultStatus status = ResultStatus.canonical,
    DateTime? due,
    String? matterId,
    DateTime? start,
    DateTime? end,
    bool allDay = false,
    String? recurrence,
    List<String> tags = const [],
  }) async {
    final document = await _repository.create(
      type: type,
      title: title,
      body: body,
      status: status,
      due: due,
      matterId: matterId,
      start: start,
      end: end,
      allDay: allDay,
      recurrence: recurrence,
      tags: tags,
      idempotencyKey: idempotencyKey,
      createdAt: createdAt,
      reversibleActionId: actionId,
    );
    final action = await _repository.findReversibleAction(actionId);
    if (action == null) throw StateError('创建操作撤销记录缺失：$actionId');
    _publishDocument(document);
    return ResultActionResult(document: document, action: action);
  }

  Future<ResultActionResult> modifyWithUndo({
    required ResultDocument document,
    required int expectedRevision,
    required String expectedHash,
    required String actionId,
  }) async {
    final saved = await _repository.saveWithUndo(
      document: document,
      expectedRevision: expectedRevision,
      expectedHash: expectedHash,
      actionId: actionId,
    );
    final action = await _repository.findReversibleAction(actionId);
    if (action == null) throw StateError('修改操作撤销记录缺失：$actionId');
    _publishDocument(saved);
    return ResultActionResult(document: saved, action: action);
  }

  Future<ResultActionResult> deleteWithUndo({
    required String id,
    required int expectedRevision,
    required String expectedHash,
    required String actionId,
  }) async {
    final deleted = await _repository.deleteWithUndo(
      id: id,
      expectedRevision: expectedRevision,
      expectedHash: expectedHash,
      actionId: actionId,
    );
    final action = await _repository.findReversibleAction(actionId);
    if (action == null) throw StateError('删除操作撤销记录缺失：$actionId');
    _publishDocument(deleted);
    return ResultActionResult(document: deleted, action: action);
  }

  Future<ResultActionResult> undoAction(
    String actionId, {
    DateTime? now,
  }) async {
    final action = await _repository.undoAction(actionId, now: now);
    final document = await _repository.readDocument(action.resultId);
    if (document == null) throw StateError('撤销成果缺失：${action.resultId}');
    _publishDocument(document);
    return ResultActionResult(document: document, action: action);
  }

  Future<void> saveDocument(ResultDocument document) async {
    final current = await _repository.readDocument(document.id);
    if (document.isGlobalKnowledge || current?.isGlobalKnowledge == true) {
      throw StateError('全局知识修改必须通过待确认候选完成');
    }
    final saved = await _repository.save(document);
    _publishDocument(saved);
  }

  Future<List<ResultDocument>> searchKnowledge({
    String query = '',
    int offset = 0,
    int limit = 50,
    bool globalOnly = false,
  }) => _repository.searchDocuments(
    query: query,
    type: ResultType.knowledge,
    offset: offset,
    limit: limit,
    globalKnowledgeOnly: globalOnly,
  );

  Future<List<ResultDocument>> searchResults({
    required String query,
    ResultType? type,
    bool globalKnowledgeOnly = false,
    int limit = 5,
  }) => _repository.searchDocuments(
    query: query,
    type: type,
    offset: 0,
    limit: limit.clamp(1, 5),
    globalKnowledgeOnly: globalKnowledgeOnly,
  );

  Future<void> toggleTodo(ResultDocument document, bool done) async {
    final saved = await _repository.markTodo(document, done);
    if (saved != null) _publishDocument(saved);
  }

  Future<void> deleteDocument(String id) async {
    final current = await _repository.readDocument(id);
    if (current?.isGlobalKnowledge == true) {
      throw StateError('全局知识删除必须通过待确认候选完成');
    }
    final deleted = await _repository.delete(id);
    if (deleted != null) _publishDocument(deleted);
  }

  /// Creates a canonical result from a captured or model-produced candidate.
  ///
  /// This is an application-layer capability for capture and auto-record
  /// coordinators. UI code should use [createManual] instead.
  Future<ResultDocument> createFromCandidate(
    ClassificationCandidate candidate, {
    String? idempotencyKey,
    DateTime? createdAt,
  }) async {
    final document = await _repository.create(
      type: candidate.type,
      title: candidate.title,
      body: candidate.summary,
      status: ResultStatus.canonical,
      tags: candidate.tags,
      due: candidate.type == ResultType.todo ? candidate.due : null,
      start: candidate.type == ResultType.event ? candidate.start : null,
      end: candidate.type == ResultType.event ? candidate.end : null,
      allDay: candidate.allDay,
      recurrence: candidate.recurrence,
      idempotencyKey: idempotencyKey,
      createdAt: createdAt,
    );
    _publishDocument(document);
    return document;
  }

  Future<IndexRebuildReport> rebuildIndex() async {
    final report = await _repository.rebuildIndex();
    await refresh();
    return report;
  }

  Future<void> shutdown() => _repository.waitForWrites();

  void _publishDocument(ResultDocument document) {
    final next = _documents.where((item) => item.id != document.id).toList();
    if (!document.deleted) next.add(_freezeDocument(document));
    next.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    _documents = List.unmodifiable(next);
    final canonical = _documents
        .where((item) => item.status == ResultStatus.canonical)
        .toList(growable: false);
    _canonicalDocuments = List.unmodifiable(canonical);
    _draftDocuments = List.unmodifiable(
      _documents.where((item) => item.status == ResultStatus.draft),
    );
    _todos = List.unmodifiable(
      canonical.where((item) => item.type == ResultType.todo),
    );
    _events = List.unmodifiable(
      canonical.where((item) => item.type == ResultType.event),
    );
    _matters = List.unmodifiable(
      canonical.where((item) => item.type == ResultType.matter),
    );
    _knowledge = List.unmodifiable(
      canonical.where((item) => item.type == ResultType.knowledge),
    );
    notifyListeners();
  }

  ResultDocument _freezeDocument(ResultDocument document) {
    return document.copyWith(
      tags: List<String>.unmodifiable(document.tags),
      links: List<String>.unmodifiable(document.links),
      sourceEventIds: List<String>.unmodifiable(document.sourceEventIds),
      sourceHashes: List<String>.unmodifiable(document.sourceHashes),
      extensionFields: Map<String, Object?>.unmodifiable(
        document.extensionFields,
      ),
    );
  }
}

class ResultActionResult {
  const ResultActionResult({required this.document, required this.action});

  final ResultDocument document;
  final ReversibleResultAction action;
}

class _ResultLibraryInternal implements ResultLibraryInternal {
  _ResultLibraryInternal(this._repository);

  final ResultRepository _repository;

  @override
  Future<List<String>> listConflictFiles() => _repository.listConflictFiles();

  @override
  Future<String?> readRaw(String path) => _repository.readRaw(path);

  @override
  Future<void> writeRaw(String path, String contents) {
    return _repository.writeRaw(path, contents);
  }

  @override
  Future<void> deleteRaw(String path) => _repository.deleteRaw(path);
}
