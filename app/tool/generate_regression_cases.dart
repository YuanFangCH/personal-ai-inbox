import 'dart:convert';
import 'dart:io';

void main() {
  const now = '2026-10-04T10:30:00';
  final cases = <Map<String, Object?>>[];
  var sequence = 0;

  void addCase({
    required String scenario,
    required String timeSlot,
    required String requirement,
    required String prompt,
    required String expectedType,
    required bool expectReview,
    String? expectedStart,
    String? expectedDue,
    required String titleHint,
  }) {
    sequence++;
    final size = _sizeFor(sequence);
    cases.add({
      'id': 'case_${sequence.toString().padLeft(3, '0')}',
      'device': _deviceFor(sequence),
      'scenario': scenario,
      'timeSlot': timeSlot,
      'requirement': requirement,
      'size': size.name,
      'text': _expand(prompt, size, sequence),
      'expectedType': expectedType,
      'expectReview': expectReview,
      'expectedStart': expectedStart,
      'expectedDue': expectedDue,
      'titleHint': titleHint,
    });
  }

  final scenarios = _scenarios;
  final absoluteTimes = _absoluteTimes;
  for (final scenario in scenarios) {
    for (final time in absoluteTimes) {
      addCase(
        scenario: scenario.name,
        timeSlot: time.name,
        requirement: 'absolute_event',
        prompt:
            '${scenario.trigger}：请于${time.expression}${scenario.action}，${scenario.detail}',
        expectedType: 'event',
        expectReview: false,
        expectedStart: _iso(
          time.startHour,
          time.startMinute,
          time.month,
          time.day,
        ),
        titleHint: scenario.action,
      );
    }
  }

  final relativeTimes = _relativeTimes;
  for (final scenario in scenarios) {
    for (final time in relativeTimes) {
      addCase(
        scenario: scenario.name,
        timeSlot: time.name,
        requirement: 'relative_event',
        prompt:
            '${scenario.trigger}：${time.expression}${scenario.action}，${scenario.detail}',
        expectedType: 'event',
        expectReview: false,
        expectedStart: _iso(
          time.startHour,
          time.startMinute,
          time.month,
          time.day,
        ),
        titleHint: scenario.action,
      );
    }
  }

  final weekdayTimes = _weekdayTimes;
  for (final scenario in scenarios) {
    for (final time in weekdayTimes) {
      addCase(
        scenario: scenario.name,
        timeSlot: time.name,
        requirement: 'weekday_event',
        prompt:
            '${time.expression}${scenario.action}，${scenario.detail}，${scenario.trigger}',
        expectedType: 'event',
        expectReview: false,
        expectedStart: _iso(
          time.startHour,
          time.startMinute,
          time.month,
          time.day,
        ),
        titleHint: scenario.action,
      );
    }
  }

  final dueTimes = _dueTimes;
  for (final scenario in scenarios) {
    for (final time in dueTimes) {
      addCase(
        scenario: scenario.name,
        timeSlot: time.name,
        requirement: 'todo_deadline',
        prompt:
            '${time.expression}${scenario.action}，${scenario.detail}，${scenario.trigger}',
        expectedType: 'todo',
        expectReview: false,
        expectedDue: _iso(
          time.startHour,
          time.startMinute,
          time.month,
          time.day,
        ),
        titleHint: scenario.action,
      );
    }
  }

  final ambiguousTimes = _ambiguousTimes;
  for (final scenario in scenarios) {
    for (final time in ambiguousTimes) {
      addCase(
        scenario: scenario.name,
        timeSlot: time.name,
        requirement: 'ambiguous_review',
        prompt: '${time.expression}${scenario.action}，${scenario.detail}，先记下来',
        expectedType: 'knowledge',
        expectReview: true,
        titleHint: scenario.action,
      );
    }
  }

  if (cases.length != 200) {
    throw StateError('Expected 200 cases, got ${cases.length}');
  }

  final output = const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'generatedAt': '2026-10-04T10:30:00+08:00',
    'now': now,
    'cases': cases,
  });
  final file = File('test/fixtures/regression_cases.json');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('$output\n');
  stdout.writeln('Wrote ${cases.length} cases to ${file.path}');
}

String _deviceFor(int sequence) {
  return switch (sequence % 3) {
    0 => 'desktop',
    1 => 'phone',
    _ => 'tablet',
  };
}

_CaseSize _sizeFor(int sequence) {
  return switch (sequence % 4) {
    0 => _CaseSize.xlarge,
    1 => _CaseSize.small,
    2 => _CaseSize.medium,
    _ => _CaseSize.large,
  };
}

String _expand(String prompt, _CaseSize size, int sequence) {
  final marker = 'CASE-${sequence.toString().padLeft(3, '0')}';
  return switch (size) {
    _CaseSize.small => prompt,
    _CaseSize.medium => '$prompt\n备注：$marker；补充联系人和上下文，保留原始要求，不自动删除。',
    _CaseSize.large =>
      '$prompt\n背景：$marker 这是一段用于验证长文本输入、标题截断和 Markdown 保存的内容。'
          '${'请在处理时保留关键事实、日期、金额、地点和参与人。' * 18}',
    _CaseSize.xlarge =>
      '$prompt\n$marker 超长输入开始。\n'
          '${'这一段用于压力测试超大文本在不同端上的捕获、索引、编辑和滚动表现。' * 140}\n'
          '超长输入结束。',
  };
}

String _iso(int hour, int minute, int month, int day) {
  return '2026-${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}T'
      '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}:00';
}

enum _CaseSize { small, medium, large, xlarge }

class _Scenario {
  const _Scenario(this.name, this.trigger, this.action, this.detail);

  final String name;
  final String trigger;
  final String action;
  final String detail;
}

class _TimeSlot {
  const _TimeSlot(
    this.name,
    this.expression,
    this.startHour,
    this.startMinute, {
    this.month = 10,
    this.day = 4,
  });

  final String name;
  final String expression;
  final int startHour;
  final int startMinute;
  final int month;
  final int day;
}

const _scenarios = [
  _Scenario('work', '工作', '提交项目材料', '地点在会议室A'),
  _Scenario('study', '学习', '复习英语口语', '准备第二天的课堂展示'),
  _Scenario('health', '健康', '预约牙科检查', '带医保卡和既往报告'),
  _Scenario('finance', '财务', '核对报销单', '重点检查金额和发票编号'),
  _Scenario('travel', '出行', '前往机场接人', '提前确认航班动态'),
  _Scenario('family', '家庭', '陪家人采购', '清单里包括牛奶和水果'),
  _Scenario('shopping', '购物', '领取快递', '取件码以短信为准'),
  _Scenario('admin', '行政', '更新居住证材料', '需要身份证和租房合同'),
  _Scenario('maintenance', '维护', '检查服务器备份', '记录异常和恢复耗时'),
  _Scenario('social', '社交', '参加读书会', '带上正在读的书和笔记'),
];

const _absoluteTimes = [
  _TimeSlot('morning', '2026年10月05日 09:30', 9, 30, month: 10, day: 5),
  _TimeSlot('noon', '2026/10/06 12:15', 12, 15, month: 10, day: 6),
  _TimeSlot('evening', '2026-10-07 19:00', 19, 0, month: 10, day: 7),
  _TimeSlot('lateNight', '2026年10月08日 23:30', 23, 30, month: 10, day: 8),
];

const _relativeTimes = [
  _TimeSlot('todayAfternoon', '今天14:00', 14, 0, month: 10, day: 4),
  _TimeSlot('tomorrowAfternoon', '明天下午3点', 15, 0, month: 10, day: 5),
  _TimeSlot('dayAfterTomorrowMorning', '后天上午8点', 8, 0, month: 10, day: 6),
  _TimeSlot('tonight', '今晚8点半', 20, 30, month: 10, day: 4),
];

const _weekdayTimes = [
  _TimeSlot('friday', '周五上午10点', 10, 0, month: 10, day: 9),
  _TimeSlot('nextMonday', '下周一14:00', 14, 0, month: 10, day: 5),
  _TimeSlot('saturday', '星期六晚上7点', 19, 0, month: 10, day: 10),
  _TimeSlot('nextSunday', '下周日下午3点', 15, 0, month: 10, day: 11),
];

const _dueTimes = [
  _TimeSlot('absoluteDue', '10月8日之前', 18, 0, month: 10, day: 8),
  _TimeSlot('tomorrowDue', '明天下午5点前提交', 17, 0, month: 10, day: 5),
  _TimeSlot('fridayDue', '本周五18:00截止', 18, 0, month: 10, day: 9),
  _TimeSlot('nextMondayDue', '下周一上午9点截止', 9, 0, month: 10, day: 5),
];

const _ambiguousTimes = [
  _TimeSlot('nextWeek', '下周找时间', 0, 0),
  _TimeSlot('later', '稍后处理', 0, 0),
  _TimeSlot('recent', '最近安排', 0, 0),
  _TimeSlot('free', '有空再看看', 0, 0),
];
