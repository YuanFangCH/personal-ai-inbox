import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/table_models.dart';

/// Evidence that two records describe the same business object.
///
/// A title, similarity score, source channel, or creation time is not evidence
/// by itself. Callers should attach stable domain keys such as a course/session
/// key or an explicit reference to the same object.
class ContentBusinessIdentity {
  ContentBusinessIdentity({Iterable<String> evidence = const []})
    : evidence = Set.unmodifiable(
        evidence
            .map(normalizeContentIdentityEvidence)
            .where((value) => value.isNotEmpty),
      );

  final Set<String> evidence;

  Set<String> get explicitSemanticEvidence => evidence
      .where((value) => !isDerivedContentIdentityEvidence(value))
      .toSet();

  bool get hasExplicitBusinessEvidence => explicitSemanticEvidence.isNotEmpty;

  bool sharesExplicitBusinessEntityWith(ContentBusinessIdentity other) =>
      _explicitEvidenceCompatible(
        explicitSemanticEvidence,
        other.explicitSemanticEvidence,
      );

  bool hasConflictingExplicitEvidenceWith(ContentBusinessIdentity other) =>
      _explicitEvidenceConflicts(
        explicitSemanticEvidence,
        other.explicitSemanticEvidence,
      );

  Set<String> sharedExplicitSemanticEvidenceWith(
    ContentBusinessIdentity other,
  ) => explicitSemanticEvidence.intersection(other.explicitSemanticEvidence);

  bool hasEquivalentEvidenceWith(ContentBusinessIdentity other) =>
      evidence.isNotEmpty &&
      evidence.length == other.evidence.length &&
      evidence.containsAll(other.evidence);
}

/// Stable content facts used to distinguish records at intake time.
class ContentIdentitySignal {
  ContentIdentitySignal({
    required this.type,
    required this.title,
    required this.body,
    required this.identity,
    required this.businessAnchor,
    List<String> tags = const [],
    List<String> links = const [],
    List<ScheduleChange> affects = const [],
    Map<String, Object?> customValues = const {},
    this.allDay = false,
    this.recurrence,
  }) : tags = List.unmodifiable(tags),
       links = List.unmodifiable(links),
       affects = List.unmodifiable(affects),
       customValues = Map.unmodifiable(Map.of(customValues));

  factory ContentIdentitySignal.forEntry(TableEntryDocument entry) =>
      ContentIdentitySignal(
        type: entry.type,
        title: entry.title,
        body: entry.body,
        identity: ContentBusinessIdentity(evidence: _entryEvidence(entry)),
        businessAnchor: contentBusinessAnchorForEntry(entry),
        tags: entry.tags,
        links: entry.links,
        affects: entry.affects,
        customValues: entry.customValues,
        allDay: entry.allDay,
        recurrence: entry.recurrence,
      );

  final TableContentType type;
  final String title;
  final String body;
  final ContentBusinessIdentity identity;
  final String businessAnchor;
  final List<String> tags;
  final List<String> links;
  final List<ScheduleChange> affects;
  final Map<String, Object?> customValues;
  final bool allDay;
  final String? recurrence;

  Set<String> get explicitSemanticEvidence => identity.explicitSemanticEvidence;

  bool get hasExplicitBusinessEvidence => identity.hasExplicitBusinessEvidence;

  bool sharesExplicitBusinessEntityWith(ContentIdentitySignal other) =>
      identity.sharesExplicitBusinessEntityWith(other.identity);

  bool hasConflictingExplicitEvidenceWith(ContentIdentitySignal other) =>
      identity.hasConflictingExplicitEvidenceWith(other.identity);

  Set<String> sharedExplicitSemanticEvidenceWith(ContentIdentitySignal other) =>
      identity.sharedExplicitSemanticEvidenceWith(other.identity);

  Set<String> sharedSemanticTextEvidenceWith(ContentIdentitySignal other) =>
      _sharedSemanticTextEvidence(body, other.body);

  Set<String> sharedVerifiableSemanticEvidenceWith(
    ContentIdentitySignal other,
  ) {
    if (hasConflictingExplicitEvidenceWith(other)) return const {};
    return {
      ...sharedExplicitSemanticEvidenceWith(other),
      ...sharedSemanticTextEvidenceWith(other),
    };
  }

  bool sharesVerifiableSemanticEvidenceWith(ContentIdentitySignal other) =>
      sharedVerifiableSemanticEvidenceWith(other).isNotEmpty;
}

class ContentFingerprint {
  const ContentFingerprint({required this.canonical, required this.digest});

  final String canonical;
  final String digest;
}

class ContentDuplicateCandidate {
  ContentDuplicateCandidate({
    required this.entry,
    required this.signal,
    required this.fingerprint,
  });

  final TableEntryDocument entry;
  final ContentIdentitySignal signal;
  final ContentFingerprint fingerprint;
}

enum SemanticDuplicateAction { create, augment, conflict }

/// Vendor-neutral result from an injected semantic duplicate evaluator.
class SemanticDuplicateDecision {
  SemanticDuplicateDecision({
    required this.action,
    this.targetId,
    this.expectedRevision,
    List<String> evidence = const [],
    this.bodyAddition = '',
    Map<String, Object?> fieldAdditions = const {},
    this.reason,
    this.comparisonComplete = true,
  }) : evidence = List.unmodifiable(evidence),
       fieldAdditions = Map.unmodifiable(Map.of(fieldAdditions));

  final SemanticDuplicateAction action;
  final String? targetId;
  final int? expectedRevision;
  final List<String> evidence;
  final String bodyAddition;
  final Map<String, Object?> fieldAdditions;
  final String? reason;

  /// False when this page could not be fully compared (permission, budget,
  /// cancellation, configuration, or transport prevented a decision).
  final bool comparisonComplete;
}

class SemanticDuplicateRequest {
  SemanticDuplicateRequest({
    required this.signal,
    required List<ContentDuplicateCandidate> candidates,
  }) : candidates = List.unmodifiable(candidates);

  final ContentIdentitySignal signal;
  final List<ContentDuplicateCandidate> candidates;
}

/// Adapter boundary for a later model-backed comparison.
///
/// This module deliberately contains no provider, prompt, or network client.
abstract interface class SemanticDuplicateDecisionSource {
  Future<SemanticDuplicateDecision> decide(SemanticDuplicateRequest request);
}

class ConservativeSemanticDuplicateDecisionSource
    implements SemanticDuplicateDecisionSource {
  const ConservativeSemanticDuplicateDecisionSource();

  @override
  Future<SemanticDuplicateDecision> decide(
    SemanticDuplicateRequest request,
  ) async => SemanticDuplicateDecision(
    action: SemanticDuplicateAction.conflict,
    reason: request.candidates.isEmpty ? null : '同一业务证据下已有内容，需核对是否补充。',
  );
}

class ContentDuplicatePolicy {
  const ContentDuplicatePolicy({this.maxSemanticCandidates = 10});

  final int maxSemanticCandidates;

  ContentFingerprint fingerprint(ContentIdentitySignal signal) {
    final canonicalValue = <String, Object?>{
      'type': signal.type.wireName,
      'title': normalizeContentText(signal.title),
      'body': normalizeContentText(signal.body),
      'business_anchor': signal.businessAnchor,
      'tags': (signal.tags.map(normalizeContentText).toList()..sort()),
      'links': (signal.links.map(normalizeContentIdentityEvidence).toList()
        ..sort()),
      'affects':
          (signal.affects
              .map(
                (affect) => <String, Object?>{
                  'schedule_id': affect.scheduleId,
                  'summary': normalizeContentText(affect.summary ?? ''),
                },
              )
              .toList()
            ..sort(
              (left, right) => jsonEncode(left).compareTo(jsonEncode(right)),
            )),
      'custom_values': normalizeContentValue(signal.customValues),
      'all_day': signal.allDay,
      'recurrence': normalizeContentText(signal.recurrence ?? ''),
    };
    final canonical = jsonEncode(canonicalValue);
    return ContentFingerprint(
      canonical: canonical,
      digest: sha256.convert(utf8.encode(canonical)).toString(),
    );
  }

  ContentDuplicateCandidate? exactMatch({
    required ContentIdentitySignal signal,
    required ContentFingerprint fingerprint,
    required Iterable<ContentDuplicateCandidate> candidates,
  }) {
    for (final candidate in candidates) {
      if (candidate.fingerprint.digest == fingerprint.digest) {
        return candidate;
      }
    }
    return null;
  }

  List<ContentDuplicateCandidate> semanticCandidates({
    required ContentIdentitySignal signal,
    required Iterable<ContentDuplicateCandidate> candidates,
  }) {
    final eligible = candidates
        .where(
          (candidate) =>
              candidate.entry.type == signal.type &&
              candidate.signal.businessAnchor == signal.businessAnchor &&
              candidate.signal.sharesVerifiableSemanticEvidenceWith(signal),
        )
        .toList();
    eligible.sort((left, right) {
      final leftShared = left.signal
          .sharedVerifiableSemanticEvidenceWith(signal)
          .length;
      final rightShared = right.signal
          .sharedVerifiableSemanticEvidenceWith(signal)
          .length;
      final byEvidence = rightShared.compareTo(leftShared);
      if (byEvidence != 0) return byEvidence;
      final byUpdate = right.entry.updatedAt.compareTo(left.entry.updatedAt);
      return byUpdate != 0 ? byUpdate : left.entry.id.compareTo(right.entry.id);
    });
    return List.unmodifiable(eligible);
  }

  String? validateSemanticDecision({
    required ContentIdentitySignal signal,
    required List<ContentDuplicateCandidate> candidates,
    required SemanticDuplicateDecision decision,
  }) {
    if (decision.action == SemanticDuplicateAction.create) return null;
    if (decision.action == SemanticDuplicateAction.conflict) return null;
    final targetId = decision.targetId;
    if (targetId == null || targetId.isEmpty) {
      return '语义补充没有绑定目标内容。';
    }
    ContentDuplicateCandidate? target;
    for (final candidate in candidates) {
      if (candidate.entry.id == targetId) {
        target = candidate;
        break;
      }
    }
    if (target == null) {
      return '语义补充目标不在本次已检查候选中。';
    }
    if (decision.expectedRevision != target.entry.revision) {
      return '语义补充目标版本与已检查版本不一致。';
    }
    if (target.signal.businessAnchor != signal.businessAnchor) {
      return '候选与输入不是同一业务时间或周期。';
    }
    if (!target.signal.sharesVerifiableSemanticEvidenceWith(signal)) {
      return '候选与输入没有可本地核对的共同事实证据。';
    }
    final allowed = target.signal.sharedVerifiableSemanticEvidenceWith(signal);
    final supplied = decision.evidence
        .map(normalizeContentIdentityEvidence)
        .where(
          (value) =>
              value.isNotEmpty && !isDerivedContentIdentityEvidence(value),
        )
        .toSet();
    if (supplied.isEmpty || !allowed.containsAll(supplied)) {
      return '语义补充没有提供可本地核对的对象证据。';
    }
    return null;
  }

  String? validateAdditions({
    required TableEntryDocument target,
    required String bodyAddition,
    required Map<String, Object?> fieldAdditions,
    required TableDocument table,
  }) {
    final normalizedAddition = normalizeContentText(bodyAddition);
    if (normalizedAddition.isEmpty && fieldAdditions.isEmpty) {
      return '语义补充没有提供新的正文或字段内容。';
    }
    if (normalizedAddition.isNotEmpty &&
        normalizeContentText(target.body).contains(normalizedAddition)) {
      return '语义补充正文已存在于目标内容中。';
    }
    final fieldsById = {for (final field in table.fields) field.id: field};
    for (final entry in fieldAdditions.entries) {
      final field = fieldsById[entry.key];
      if (field == null) {
        return '语义补充包含目标表未定义的字段：${entry.key}';
      }
      final current = target.customValues[entry.key];
      if (!_canAddFieldValue(
        field: field,
        current: current,
        addition: entry.value,
      )) {
        return '字段 ${entry.key} 已有不同值，不能自动覆盖。';
      }
    }
    return null;
  }

  bool _canAddFieldValue({
    required TableFieldDefinition field,
    required Object? current,
    required Object? addition,
  }) {
    if (!_isValidFieldValue(field, addition)) return false;
    if (_isEmptyValue(addition) || _valuesEqual(current, addition)) return true;
    if (_isEmptyValue(current)) return true;
    return field.type == CustomFieldType.multiSelect;
  }

  bool _isValidFieldValue(TableFieldDefinition field, Object? value) {
    if (value == null) return true;
    return switch (field.type) {
      CustomFieldType.text => value is String,
      CustomFieldType.number => value is num && value.isFinite,
      CustomFieldType.date =>
        value is String && DateTime.tryParse(value) != null,
      CustomFieldType.singleSelect =>
        value is String && field.options.any((option) => option.id == value),
      CustomFieldType.multiSelect =>
        value is List<Object?> &&
            value.every(
              (item) =>
                  item is String &&
                  field.options.any((option) => option.id == item),
            ) &&
            value.length == value.toSet().length,
      CustomFieldType.checkbox => value is bool,
    };
  }

  bool _valuesEqual(Object? left, Object? right) =>
      jsonEncode(normalizeContentValue(left)) ==
      jsonEncode(normalizeContentValue(right));

  bool _isEmptyValue(Object? value) =>
      value == null ||
      (value is String && normalizeContentText(value).isEmpty) ||
      (value is Iterable && value.isEmpty);
}

String contentBusinessAnchorForEntry(TableEntryDocument entry) =>
    contentBusinessAnchor(
      type: entry.type,
      due: entry.due,
      start: entry.start,
      end: entry.end,
      occurredAt: entry.occurredAt,
      allDay: entry.allDay,
      recurrence: entry.recurrence,
    );

String contentBusinessAnchor({
  required TableContentType type,
  DateTime? due,
  DateTime? start,
  DateTime? end,
  DateTime? occurredAt,
  bool allDay = false,
  String? recurrence,
}) {
  final common = <String, Object?>{
    'all_day': allDay,
    'recurrence': normalizeContentText(recurrence ?? ''),
  };
  return switch (type) {
    TableContentType.note => 'note',
    TableContentType.todo => jsonEncode({
      ...common,
      'due': _normalizeDate(due),
    }),
    TableContentType.schedule => jsonEncode({
      ...common,
      'start': allDay ? _normalizeCalendarDate(start) : _normalizeDate(start),
      'end': allDay ? _normalizeCalendarDate(end) : _normalizeDate(end),
    }),
    TableContentType.event => jsonEncode({
      ...common,
      'occurred_at': allDay
          ? _normalizeCalendarDate(occurredAt)
          : _normalizeDate(occurredAt),
    }),
  };
}

Set<String> extractStoredContentEvidence(TableEntryDocument entry) {
  final values = <String>[];
  final stored = entry.extensionFields[contentIntakeEvidenceExtensionKey];
  if (stored is String) values.add(stored);
  if (stored is Iterable) {
    values.addAll(stored.whereType<String>());
  }
  values
    ..addAll(entry.links.map((link) => 'entry:$link'))
    ..addAll(entry.affects.map((affect) => 'entry:${affect.scheduleId}'));
  return values
      .map(normalizeContentIdentityEvidence)
      .where((value) => value.isNotEmpty)
      .toSet();
}

Set<String> _entryEvidence(TableEntryDocument entry) {
  final stored = extractStoredContentEvidence(entry);
  return {
    ...semanticFactEvidenceForContent(
      type: entry.type,
      due: entry.due,
      start: entry.start,
      end: entry.end,
      occurredAt: entry.occurredAt,
      allDay: entry.allDay,
      recurrence: entry.recurrence,
      customValues: entry.customValues,
    ),
    ...stored,
    if (stored.isEmpty)
      contentObjectEvidenceKey(
        type: entry.type,
        title: entry.title,
        due: entry.due,
        start: entry.start,
        end: entry.end,
        occurredAt: entry.occurredAt,
        allDay: entry.allDay,
        recurrence: entry.recurrence,
        customValues: entry.customValues,
      ),
  };
}

Set<String> semanticFactEvidenceForContent({
  required TableContentType type,
  DateTime? due,
  DateTime? start,
  DateTime? end,
  DateTime? occurredAt,
  bool allDay = false,
  String? recurrence,
  Map<String, Object?> customValues = const {},
}) {
  final evidence = <String>{};
  switch (type) {
    case TableContentType.note:
      break;
    case TableContentType.todo:
      if (due != null) evidence.add('due:${_normalizeDate(due)}');
    case TableContentType.schedule:
      if (start != null) {
        evidence.add('schedule-start:${_normalizeDate(start)}');
      }
      if (end != null) evidence.add('schedule-end:${_normalizeDate(end)}');
      if (allDay) evidence.add('schedule-all-day');
      if (recurrence != null && recurrence.trim().isNotEmpty) {
        evidence.add('recurrence:${normalizeContentText(recurrence)}');
      }
    case TableContentType.event:
      if (occurredAt != null) {
        evidence.add('occurred-at:${_normalizeDate(occurredAt)}');
      }
      if (allDay) evidence.add('event-all-day');
      if (recurrence != null && recurrence.trim().isNotEmpty) {
        evidence.add('recurrence:${normalizeContentText(recurrence)}');
      }
  }
  final sortedKeys = customValues.keys.toList()..sort();
  for (final key in sortedKeys) {
    final value = customValues[key];
    if (value == null) continue;
    final normalized = normalizeContentValue(value);
    if (normalized is String && normalized.isEmpty) continue;
    if (normalized is Iterable && normalized.isEmpty) continue;
    evidence.add('field:$key=${jsonEncode(normalized)}');
  }
  return Set.unmodifiable(evidence);
}

String contentObjectEvidenceKey({
  required TableContentType type,
  required String title,
  DateTime? due,
  DateTime? start,
  DateTime? end,
  DateTime? occurredAt,
  bool allDay = false,
  String? recurrence,
  Map<String, Object?> customValues = const {},
}) {
  final canonical = jsonEncode({
    'type': type.wireName,
    'title': normalizeContentText(title),
    'business_anchor': contentBusinessAnchor(
      type: type,
      due: due,
      start: start,
      end: end,
      occurredAt: occurredAt,
      allDay: allDay,
      recurrence: recurrence,
    ),
    'custom_values': normalizeContentValue(customValues),
  });
  return 'legacy-content-create:'
      '${sha256.convert(utf8.encode(canonical))}';
}

const contentIntakeEvidenceExtensionKey = 'content_intake_evidence';
const manualDuplicateExceptionExtensionKey = 'manual_duplicate_exception';
const derivedContentIdentityEvidencePrefix = 'legacy-content-create:';

bool isDerivedContentIdentityEvidence(String value) =>
    normalizeContentIdentityEvidence(value)
        .startsWith(derivedContentIdentityEvidencePrefix);

bool _explicitEvidenceCompatible(Set<String> left, Set<String> right) {
  if (left.isEmpty || right.isEmpty) return false;
  if (left.intersection(right).isEmpty) return false;
  return !_explicitEvidenceConflicts(left, right);
}

bool _explicitEvidenceConflicts(Set<String> left, Set<String> right) {
  if (left.isEmpty || right.isEmpty) return false;
  final leftByNamespace = _evidenceByNamespace(left);
  final rightByNamespace = _evidenceByNamespace(right);
  for (final namespace in leftByNamespace.keys) {
    if (namespace == 'field') continue;
    final rightValues = rightByNamespace[namespace];
    if (rightValues == null) continue;
    if (leftByNamespace[namespace]!.intersection(rightValues).isEmpty) {
      return true;
    }
  }
  return false;
}

Set<String> _sharedSemanticTextEvidence(String left, String right) {
  final leftText = normalizeContentText(left);
  final rightText = normalizeContentText(right);
  if (leftText.runes.length < 2 || rightText.runes.length < 2) {
    return const {};
  }
  final phrases = <String>{};
  if (leftText.contains(rightText)) {
    phrases.add('text:$rightText');
  } else if (rightText.contains(leftText)) {
    phrases.add('text:$leftText');
  }

  final leftRunes = leftText.runes.toList(growable: false);
  final rightRunes = rightText.runes.toList(growable: false);
  var prefixLength = 0;
  while (prefixLength < leftRunes.length &&
      prefixLength < rightRunes.length &&
      leftRunes[prefixLength] == rightRunes[prefixLength]) {
    prefixLength++;
  }
  if (prefixLength >= 2) {
    phrases.add('text:${String.fromCharCodes(leftRunes.take(prefixLength))}');
  }
  var suffixLength = 0;
  while (suffixLength < leftRunes.length &&
      suffixLength < rightRunes.length &&
      leftRunes[leftRunes.length - suffixLength - 1] ==
          rightRunes[rightRunes.length - suffixLength - 1]) {
    suffixLength++;
  }
  if (suffixLength >= 2) {
    phrases.add(
      'text:${String.fromCharCodes(leftRunes.skip(leftRunes.length - suffixLength))}',
    );
  }
  return phrases.take(4).toSet();
}

Map<String, Set<String>> _evidenceByNamespace(Iterable<String> evidence) {
  final values = <String, Set<String>>{};
  for (final token in evidence) {
    final separator = token.indexOf(':');
    final namespace = separator < 0 ? token : token.substring(0, separator);
    final value = separator < 0 ? '' : token.substring(separator + 1);
    values.putIfAbsent(namespace, () => <String>{}).add(value);
  }
  return values;
}

String normalizeContentText(String value) {
  final folded = StringBuffer();
  for (final rune in value.runes) {
    if (rune >= 0xff01 && rune <= 0xff5e) {
      folded.writeCharCode(rune - 0xfee0);
    } else if (rune == 0x3000) {
      folded.write(' ');
    } else if (rune == 0x200b || rune == 0x200c || rune == 0x200d) {
      continue;
    } else {
      folded.writeCharCode(rune);
    }
  }
  return folded
      .toString()
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String normalizeContentIdentityEvidence(String value) =>
    normalizeContentText(value);

Object? normalizeContentValue(Object? value) {
  if (value == null || value is num || value is bool) return value;
  if (value is DateTime) return _normalizeDate(value);
  if (value is String) return normalizeContentText(value);
  if (value is Iterable) {
    final normalized = value.map(normalizeContentValue).toList();
    normalized.sort(
      (left, right) => jsonEncode(left).compareTo(jsonEncode(right)),
    );
    return normalized;
  }
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: normalizeContentValue(value[key]),
    };
  }
  return '$value';
}

String? _normalizeDate(DateTime? value) =>
    value?.toUtc().toIso8601String() ?? '';

String _normalizeCalendarDate(DateTime? value) {
  final local = value?.toLocal();
  if (local == null) return '';
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}
