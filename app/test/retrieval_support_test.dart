import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/modules/conversation/retrieval_support.dart';

void main() {
  test('CJK bigrams and Latin terms produce deterministic recall terms', () {
    expect(
      retrievalTerms('考试范围 Exam Final'),
      containsAll(['考试', '试范', '范围', 'exam', 'final']),
    );
    expect(
      retrievalRelevance(query: '考试范围', title: '考试安排', body: '范围包含第三章'),
      isNotNull,
    );
  });

  test('rune slicing keeps emoji and next offsets valid', () {
    final first = retrievalTextSlice('开头😀考试范围', offset: 0, length: 3);
    expect(first.text, '开头😀');
    expect(first.nextOffset, 3);
    final second = retrievalTextSlice(
      '开头😀考试范围',
      offset: first.nextOffset!,
      length: 4,
    );
    expect(second.text, '考试范围');
    expect(second.nextOffset, isNull);
  });

  test('opaque cursor round-trips and rejects malformed payloads', () {
    final token = opaqueRetrievalCursor({
      'kind': 'test',
      'offset': 20,
      'source': retrievalDigest({'"': 'long text'}),
    });
    expect(decodeRetrievalCursor(token)['offset'], 20);
    expect(() => decodeRetrievalCursor('not-a-cursor'), throwsFormatException);
  });
}
