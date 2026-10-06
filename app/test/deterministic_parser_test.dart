import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ai_inbox/core/deterministic_parser.dart';
import 'package:personal_ai_inbox/core/models.dart';

void main() {
  const parser = DeterministicParser();
  final now = DateTime(2026, 10, 4, 10, 30);

  test('parses a clear relative event', () {
    final result = parser.parse('明天下午三点提醒我交材料', now);

    expect(result.type, ResultType.event);
    expect(result.start, DateTime(2026, 10, 5, 15));
    expect(result.needsReview, isFalse);
    expect(result.confidence, greaterThan(0.8));
  });

  test('parses a deadline as a todo', () {
    final result = parser.parse('10月8日之前完成报告', now);

    expect(result.type, ResultType.todo);
    expect(result.due, DateTime(2026, 10, 8, 18));
  });

  test('keeps ambiguous scheduling out of automatic writes', () {
    final result = parser.parse('下周找时间看房子', now);

    expect(result.type, ResultType.knowledge);
    expect(result.needsReview, isTrue);
  });

  test('parses the nearest upcoming weekday without a week prefix', () {
    final result = parser.parse('周五下午两点和客户开会', now);

    expect(result.type, ResultType.event);
    expect(result.start, DateTime(2026, 10, 9, 14));
    expect(result.needsReview, isFalse);
  });
}
