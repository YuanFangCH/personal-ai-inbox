import 'dart:convert';

import '../../core/table_models.dart';
import '../tables/table_library.dart';
import 'content_duplicate_policy.dart';

enum ManualDuplicateChoice { reuse, keepBoth }

class ManualContentReview {
  const ManualContentReview({
    required this.entry,
    required this.tableRevision,
    required this.matches,
    required this.exactIds,
    this.expectedRevision,
  });

  final TableEntryDocument entry;
  final int tableRevision;
  final int? expectedRevision;
  final List<TableEntryDocument> matches;
  final Set<String> exactIds;
}

/// Manual writes use the same exact fingerprint as automatic intake. Semantic
/// candidates are only shown locally and require a fresh user choice to keep.
class ManualContentIntake {
  ManualContentIntake(this._tables, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final TableLibrary _tables;
  final DateTime Function() _clock;
  static const _policy = ContentDuplicatePolicy();

  Future<ManualContentReview> review(
    TableEntryDocument entry, {
    int? expectedRevision,
  }) async {
    await _tables.refresh();
    final table = _tables.findTable(entry.tableId);
    if (table == null || table.deleted) throw StateError('目标表不存在。');
    if (expectedRevision != null) {
      final current = _tables.entries.where(
        (candidate) => candidate.id == entry.id,
      );
      if (current.length != 1 ||
          current.single.revision != expectedRevision ||
          current.single.tableId != entry.tableId) {
        throw StateError('编辑内容已变化，请重新打开后再保存。');
      }
    }
    final matches = _matches(entry, _tables.entries);
    final fingerprint = _fingerprint(entry);
    return ManualContentReview(
      entry: entry,
      tableRevision: table.revision,
      expectedRevision: expectedRevision,
      matches: matches,
      exactIds: Set.unmodifiable(
        matches
            .where((match) => _fingerprint(match) == fingerprint)
            .map((match) => match.id),
      ),
    );
  }

  Future<TableEntryDocument> commit(
    ManualContentReview review, {
    ManualDuplicateChoice? choice,
  }) {
    if (review.matches.isNotEmpty && choice == null) {
      throw StateError('请先选择如何处理相似内容。');
    }
    if (choice == ManualDuplicateChoice.reuse &&
        (review.expectedRevision != null || review.exactIds.isEmpty)) {
      throw StateError('只有新建的完全相同内容可以复用。');
    }
    final extensionFields = Map<String, Object?>.of(
      review.entry.extensionFields,
    )..remove(manualDuplicateExceptionExtensionKey);
    if (choice == ManualDuplicateChoice.keepBoth && review.matches.isNotEmpty) {
      extensionFields[manualDuplicateExceptionExtensionKey] = {
        'schema_version': 1,
        'decision': 'keep_both',
        'reason': '用户在手工编辑器明确选择保留两条',
        'created_at': _clock().toUtc().toIso8601String(),
        'input_fingerprint': _fingerprint(review.entry),
        'target_table_id': review.entry.tableId,
        'target_table_revision': review.tableRevision,
        'candidates': [
          for (final match in review.matches)
            {
              'id': match.id,
              'table_id': match.tableId,
              'revision': match.revision,
              'fingerprint': _fingerprint(match),
            },
        ],
      };
    }
    final proposed = review.entry.copyWith(extensionFields: extensionFields);
    return _tables.saveReviewedEntry(
      entry: proposed,
      expectedRevision: review.expectedRevision,
      expectedTableRevision: review.tableRevision,
      selectReuse: (entries) {
        final current = _matches(review.entry, entries);
        if (_signature(current) != _signature(review.matches)) {
          throw StateError('相似内容已变化，请重新检查后保存。');
        }
        if (choice != ManualDuplicateChoice.reuse) return null;
        final currentExactIds = current
            .where((match) => _fingerprint(match) == _fingerprint(review.entry))
            .map((match) => match.id)
            .toSet();
        if (!currentExactIds.containsAll(review.exactIds)) {
          throw StateError('完全相同内容已变化，请重新检查后保存。');
        }
        return review.exactIds.first;
      },
    );
  }

  List<TableEntryDocument> _matches(
    TableEntryDocument entry,
    Iterable<TableEntryDocument> entries,
  ) {
    final signal = ContentIdentitySignal.forEntry(entry);
    final fingerprint = _fingerprint(entry);
    final matches = entries.where((candidate) {
      if (candidate.id == entry.id ||
          candidate.deleted ||
          candidate.type != entry.type) {
        return false;
      }
      final candidateSignal = ContentIdentitySignal.forEntry(candidate);
      return _fingerprint(candidate) == fingerprint ||
          (candidateSignal.businessAnchor == signal.businessAnchor &&
              (normalizeContentText(candidate.title) ==
                      normalizeContentText(entry.title) ||
                  candidateSignal.sharesVerifiableSemanticEvidenceWith(
                    signal,
                  )));
    }).toList()..sort((left, right) => left.id.compareTo(right.id));
    return List.unmodifiable(matches);
  }

  String _fingerprint(TableEntryDocument entry) =>
      _policy.fingerprint(ContentIdentitySignal.forEntry(entry)).digest;

  String _signature(List<TableEntryDocument> entries) => jsonEncode([
    for (final entry in entries)
      [entry.id, entry.tableId, entry.revision, _fingerprint(entry)],
  ]);
}
