import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

bool _isCjk(int rune) =>
    (rune >= 0x3400 && rune <= 0x4dbf) ||
    (rune >= 0x4e00 && rune <= 0x9fff) ||
    (rune >= 0xf900 && rune <= 0xfaff);

String normalizeRetrievalText(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Produces deterministic retrieval terms without pretending they are
/// semantic similarity. CJK text uses overlapping bigrams; Latin text uses
/// whitespace/punctuation-delimited words.
List<String> retrievalTerms(String query) {
  final normalized = normalizeRetrievalText(query);
  if (normalized.isEmpty) return const [];
  final terms = <String>{};
  for (final match in RegExp(
    r'[a-z0-9_]+|[\u3400-\u9fff]+',
    caseSensitive: false,
  ).allMatches(normalized)) {
    final value = match.group(0)!;
    final runes = value.runes.toList(growable: false);
    if (runes.length == 1 || !_isCjk(runes.first)) {
      terms.add(value);
      continue;
    }
    for (var index = 0; index < runes.length - 1; index++) {
      terms.add(String.fromCharCodes(runes.skip(index).take(2)));
    }
  }
  return terms.toList(growable: false)..sort((left, right) {
    final byLength = right.runes.length.compareTo(left.runes.length);
    return byLength != 0 ? byLength : left.compareTo(right);
  });
}

/// Ranking is only a retrieval order. A positive score never authorizes
/// deduplication or merging.
double? retrievalRelevance({
  required String query,
  required String title,
  required String body,
  String extra = '',
}) {
  final normalizedQuery = normalizeRetrievalText(query);
  if (normalizedQuery.isEmpty) return 0;
  final normalizedTitle = normalizeRetrievalText(title);
  final normalizedBody = normalizeRetrievalText(body);
  final normalizedExtra = normalizeRetrievalText(extra);
  final terms = retrievalTerms(query);
  if (terms.isEmpty) return null;

  final matchedTitle = terms.where(normalizedTitle.contains).length;
  final matchedBody = terms.where(normalizedBody.contains).length;
  final matchedExtra = terms.where(normalizedExtra.contains).length;
  if (matchedTitle + matchedBody + matchedExtra == 0) return null;

  var score = 0.0;
  if (normalizedTitle == normalizedQuery) {
    score += 1000000;
  } else if (normalizedTitle.contains(normalizedQuery)) {
    score += 400000;
  }
  if (normalizedBody.contains(normalizedQuery)) {
    score += 200000;
  } else if (normalizedExtra.contains(normalizedQuery)) {
    score += 100000;
  }
  score += matchedTitle * 10000;
  score += matchedBody * 1000;
  score += matchedExtra * 500;
  score += (matchedTitle + matchedBody + matchedExtra) / terms.length;
  return score;
}

class RetrievalExcerpt {
  const RetrievalExcerpt({
    required this.text,
    required this.offset,
    required this.truncated,
  });

  final String text;
  final int offset;
  final bool truncated;
}

RetrievalExcerpt relevantRetrievalExcerpt(
  String source,
  String query,
  int limit,
) {
  final runes = source.runes.toList(growable: false);
  if (runes.length <= limit) {
    return RetrievalExcerpt(text: source, offset: 0, truncated: false);
  }
  final safeLimit = limit.clamp(1, runes.length).toInt();
  final normalized = source.toLowerCase();
  final candidates = <int>[];
  final normalizedQuery = normalizeRetrievalText(query);
  if (normalizedQuery.isNotEmpty) {
    final phrase = normalized.indexOf(normalizedQuery);
    if (phrase >= 0) candidates.add(phrase);
    for (final term in retrievalTerms(query)) {
      final index = normalized.indexOf(term);
      if (index >= 0) candidates.add(index);
    }
  }
  candidates.sort();
  final utf16Start = candidates.isEmpty ? 0 : candidates.first;
  final runeStart = source.substring(0, utf16Start).runes.length;
  final centered =
      runeStart - math.max(0, (safeLimit - normalizedQuery.length) ~/ 3);
  final start = centered.clamp(0, runes.length - safeLimit).toInt();
  final hasPrefix = start > 0;
  final hasSuffix = start + safeLimit < runes.length;
  final reserve = (hasPrefix ? 1 : 0) + (hasSuffix ? 1 : 0);
  final contentLength = math.max(1, safeLimit - reserve).toInt();
  final textStart = hasPrefix ? start + 1 : start;
  final content = String.fromCharCodes(
    runes.skip(textStart).take(contentLength),
  );
  return RetrievalExcerpt(
    text: '${hasPrefix ? '…' : ''}$content${hasSuffix ? '…' : ''}',
    offset: start,
    truncated: true,
  );
}

class RetrievalTextSlice {
  const RetrievalTextSlice({
    required this.text,
    required this.offset,
    required this.length,
    required this.totalLength,
    required this.nextOffset,
  });

  final String text;
  final int offset;
  final int length;
  final int totalLength;
  final int? nextOffset;
}

RetrievalTextSlice retrievalTextSlice(
  String source, {
  int offset = 0,
  required int length,
}) {
  final runes = source.runes.toList(growable: false);
  final safeOffset = offset.clamp(0, runes.length).toInt();
  final safeLength = length.clamp(1, math.max(1, runes.length)).toInt();
  final end = math.min(runes.length, safeOffset + safeLength).toInt();
  return RetrievalTextSlice(
    text: String.fromCharCodes(runes.skip(safeOffset).take(end - safeOffset)),
    offset: safeOffset,
    length: math.max(0, end - safeOffset).toInt(),
    totalLength: runes.length,
    nextOffset: end < runes.length ? end : null,
  );
}

String opaqueRetrievalCursor(Map<String, Object?> payload) {
  return base64Url.encode(utf8.encode(jsonEncode({'v': 1, ...payload})));
}

Map<String, Object?> decodeRetrievalCursor(String cursor) {
  final decoded = utf8.decode(base64Url.decode(base64Url.normalize(cursor)));
  final value = jsonDecode(decoded);
  if (value is! Map || value['v'] != 1) {
    throw const FormatException('检索游标格式无效。');
  }
  return Map<String, Object?>.from(value);
}

String retrievalDigest(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

bool retrievalValueEquals(Object? left, Object? right) =>
    jsonEncode(left) == jsonEncode(right);
