import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/markdown_codec.dart';
import 'package:personal_ai_inbox/core/models.dart';

void main() {
  const codec = MarkdownCodec();

  test('round trips a canonical event document', () {
    final document = ResultDocument(
      id: 'ev_20261004_abcd1234',
      type: ResultType.event,
      title: '交材料',
      status: ResultStatus.canonical,
      originDevice: 'test-device',
      revision: 3,
      createdAt: DateTime.parse('2026-10-04T09:12:00+08:00'),
      updatedAt: DateTime.parse('2026-10-04T09:40:00+08:00'),
      body: '## 要求\n\n带上身份证。',
      tags: const ['工作', '材料'],
      start: DateTime.parse('2026-10-05T15:00:00+08:00'),
      end: DateTime.parse('2026-10-05T16:00:00+08:00'),
      matterId: 'mt_20261004_12345678',
      recurrence: 'FREQ=WEEKLY;BYDAY=MO',
    );

    final markdown = codec.encode(document);
    final decoded = codec.decode(markdown);

    expect(decoded.id, document.id);
    expect(decoded.type, document.type);
    expect(decoded.title, document.title);
    expect(decoded.status, document.status);
    expect(decoded.revision, document.revision);
    expect(decoded.tags, document.tags);
    expect(decoded.start!.isAtSameMomentAs(document.start!), isTrue);
    expect(decoded.end!.isAtSameMomentAs(document.end!), isTrue);
    expect(decoded.matterId, document.matterId);
    expect(decoded.recurrence, document.recurrence);
    expect(decoded.body, document.body);
    expect(markdown, isNot(contains('content_hash')));
    expect(markdown, contains('+08:00'));
  });

  test('rejects markdown without closed frontmatter', () {
    expect(() => codec.decode('---\nid: broken\n'), throwsFormatException);
  });
}
