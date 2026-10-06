import 'models.dart';

class DeterministicParser {
  const DeterministicParser();

  ClassificationCandidate parse(String rawText, DateTime now) {
    final text = rawText.trim();
    if (text.isEmpty) {
      return const ClassificationCandidate(
        type: ResultType.knowledge,
        title: '空白捕获',
        confidence: 0,
        needsReview: true,
        reviewReason: '内容为空',
      );
    }

    final due = _parseDue(text, now);
    if (due != null) {
      return ClassificationCandidate(
        type: ResultType.todo,
        title: _titleFor(text, fallback: '待办'),
        confidence: 0.86,
        summary: text,
        due: due,
        tags: _inferTags(text),
      );
    }

    final event = _parseEvent(text, now);
    if (event != null) {
      return event;
    }

    final isUrl =
        Uri.tryParse(text)?.hasAbsolutePath == true &&
        text.contains('://') &&
        !text.contains(RegExp(r'\s'));
    final needsReview = text.length < 5 || _containsAmbiguousDate(text);

    return ClassificationCandidate(
      type: ResultType.knowledge,
      title: _titleFor(text, fallback: isUrl ? '网页摘录' : '随手记'),
      confidence: needsReview ? 0.55 : 0.78,
      summary: text,
      tags: _inferTags(text),
      needsReview: needsReview,
      reviewReason: needsReview ? '内容或时间表达需要确认' : null,
    );
  }

  ClassificationCandidate? _parseEvent(String text, DateTime now) {
    final date = _parseRelativeDate(text, now);
    if (date == null) {
      return null;
    }

    final time = _parseTime(text, fallbackToAfternoon: true);
    if (time == null) {
      return null;
    }

    final start = DateTime(date.year, date.month, date.day, time.$1, time.$2);
    final end = start.add(const Duration(hours: 1));
    final explicit = RegExp(r'\d{1,2}\s*[:：]\s*\d{1,2}').hasMatch(text);
    return ClassificationCandidate(
      type: ResultType.event,
      title: _titleFor(text, fallback: '事件'),
      confidence: explicit ? 0.94 : 0.88,
      summary: text,
      start: start,
      end: end,
      tags: _inferTags(text),
      needsReview: false,
    );
  }

  DateTime? _parseDue(String text, DateTime now) {
    final dueText = text.replaceAll('提前', '');
    final hasDueWord = RegExp(
      r'截止|到期|之前|前(?:提交|完成|送达|回复|处理|上传|发送|缴纳|确认|归档|反馈|联系)|deadline',
      caseSensitive: false,
    ).hasMatch(dueText);
    if (!hasDueWord) {
      return null;
    }
    final date = _parseRelativeDate(text, now);
    if (date == null) {
      return null;
    }
    final time = _parseTime(text, fallbackToAfternoon: false);
    return DateTime(
      date.year,
      date.month,
      date.day,
      time?.$1 ?? 18,
      time?.$2 ?? 0,
    );
  }

  DateTime? _parseRelativeDate(String text, DateTime now) {
    final absolute = RegExp(
      r'(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})\s*日?',
    ).firstMatch(text);
    if (absolute != null) {
      final year = int.parse(absolute.group(1)!);
      final month = int.parse(absolute.group(2)!);
      final day = int.parse(absolute.group(3)!);
      final value = DateTime(year, month, day);
      if (value.year == year && value.month == month && value.day == day) {
        return value;
      }
    }

    final short = RegExp(r'(\d{1,2})\s*月\s*(\d{1,2})\s*日').firstMatch(text);
    if (short != null) {
      final month = int.parse(short.group(1)!);
      final day = int.parse(short.group(2)!);
      final value = DateTime(now.year, month, day);
      if (value.year == now.year && value.month == month && value.day == day) {
        return value;
      }
    }

    var offset = 0;
    if (text.contains('后天')) {
      offset = 2;
    } else if (text.contains('明天')) {
      offset = 1;
    } else if (text.contains('今天') || text.contains('今晚')) {
      offset = 0;
    } else {
      const values = {
        '一': DateTime.monday,
        '二': DateTime.tuesday,
        '三': DateTime.wednesday,
        '四': DateTime.thursday,
        '五': DateTime.friday,
        '六': DateTime.saturday,
        '日': DateTime.sunday,
        '天': DateTime.sunday,
      };
      final nextWeek = RegExp(r'下(?:周|星期|礼拜)([一二三四五六日天])').firstMatch(text);
      if (nextWeek != null) {
        final target = values[nextWeek.group(1)!]!;
        offset = 7 - now.weekday + target;
        if (offset == 0) {
          offset = 7;
        }
      } else {
        final currentWeek = RegExp(r'(?:本周|这周|周|星期|礼拜)([一二三四五六日天])')
            .firstMatch(text);
        if (currentWeek == null) {
          return null;
        }
        final target = values[currentWeek.group(1)!]!;
        offset = (target - now.weekday + 7) % 7;
      }
    }
    final date = now.add(Duration(days: offset));
    return DateTime(date.year, date.month, date.day);
  }

  (int, int)? _parseTime(String text, {required bool fallbackToAfternoon}) {
    final standard = RegExp(
      r'(?:(早上|上午|下午|晚上|傍晚|夜里|深夜|中午|凌晨)\s*)?(\d{1,2})\s*[:：]\s*(\d{1,2})',
    ).firstMatch(text);
    if (standard != null) {
      return _normalizeTime(
        int.parse(standard.group(2)!),
        int.parse(standard.group(3)!),
        standard.group(1),
        fallbackToAfternoon: fallbackToAfternoon,
        text: text,
      );
    }

    final chinese = RegExp(
      r'(?:(早上|上午|下午|晚上|傍晚|夜里|深夜|中午|凌晨)\s*)?(\d{1,2}|[一二两三四五六七八九十零〇]{1,3})\s*点(?:\s*(\d{1,2})\s*分?|半)?',
    ).firstMatch(text);
    if (chinese == null) {
      return null;
    }
    final hour = _parseChineseNumber(chinese.group(2)!);
    final minute = chinese.group(3) == null
        ? (chinese.group(0)!.contains('半') ? 30 : 0)
        : int.parse(chinese.group(3)!);
    return _normalizeTime(
      hour,
      minute,
      chinese.group(1),
      fallbackToAfternoon: fallbackToAfternoon,
      text: text,
    );
  }

  (int, int)? _normalizeTime(
    int hour,
    int minute,
    String? marker, {
    required bool fallbackToAfternoon,
    required String text,
  }) {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    if (marker == '下午' || marker == '晚上' || marker == '傍晚') {
      if (hour < 12) {
        hour += 12;
      }
    } else if (marker == '夜里' || marker == '深夜') {
      if (hour == 12) {
        hour = 0;
      } else if (hour < 12) {
        hour += 12;
      }
    } else if (marker == '中午') {
      if (hour < 11) {
        hour += 12;
      }
    } else if (marker == '凌晨' && hour == 12) {
      hour = 0;
    } else if (marker == null &&
        fallbackToAfternoon &&
        (text.contains('今晚') || text.contains('晚上'))) {
      if (hour < 12) {
        hour += 12;
      }
    }
    return (hour, minute);
  }

  int _parseChineseNumber(String value) {
    final numeric = int.tryParse(value);
    if (numeric != null) {
      return numeric;
    }
    const digits = {
      '一': 1,
      '两': 2,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
      '零': 0,
      '〇': 0,
    };
    if (value == '十') {
      return 10;
    }
    if (value.startsWith('十')) {
      return 10 + (digits[value.substring(1)] ?? 0);
    }
    if (value.endsWith('十')) {
      return (digits[value.substring(0, 1)] ?? 1) * 10;
    }
    final parts = value.split('十');
    if (parts.length == 2) {
      return (digits[parts.first] ?? 1) * 10 + (digits[parts.last] ?? 0);
    }
    return digits[value] ?? 0;
  }

  bool _containsAmbiguousDate(String text) {
    return RegExp(r'下周|最近|有空|找时间|稍后').hasMatch(text);
  }

  String _titleFor(String text, {required String fallback}) {
    final firstLine = text
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) {
      return fallback;
    }
    final cleaned = firstLine
        .replaceFirst(RegExp(r'^(提醒我|帮我|记得|需要)\s*'), '')
        .replaceFirst(RegExp(r'^(今天|明天|后天|下周[一二三四五六日天])'), '')
        .trim();
    if (cleaned.isEmpty) {
      return fallback;
    }
    return cleaned.length <= 36 ? cleaned : '${cleaned.substring(0, 35)}…';
  }

  List<String> _inferTags(String text) {
    const candidates = {
      '工作': ['工作', '材料', '报告', '会议', '客户'],
      '学习': ['学习', '课程', '阅读', '考试', '英语'],
      '生活': ['买', '家', '旅行', '房', '健康'],
      '提醒': ['提醒', '截止', '明天', '下周'],
    };
    return candidates.entries
        .where((entry) => entry.value.any(text.contains))
        .map((entry) => entry.key)
        .take(3)
        .toList(growable: false);
  }
}
