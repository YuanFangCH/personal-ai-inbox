/// Generates the 100-scenario realistic end-to-end matrix.
///
/// Run from `app/`:
///   dart run tool/generate_realistic_scenarios.dart
///
/// The output is deterministic: no clocks, randomness or network reads.
library;

import 'dart:convert';
import 'dart:io';

typedef Step = Map<String, Object?>;
typedef Scenario = Map<String, Object?>;

const _platformCycle = ['phone', 'phone', 'tablet', 'windows'];

Step _step(String op, [Map<String, Object?> args = const {}]) => {
  'op': op,
  if (args.isNotEmpty) 'args': args,
};

Step _assert(String kind, [Map<String, Object?> extra = const {}]) =>
    _step('assert', {'kind': kind, ...extra});

void main() {
  final scenarios = <Scenario>[];
  var index = 0;

  Scenario build(
    String category,
    String title,
    List<Step> steps, {
    String reply = '好的，已经帮你整理好了。',
    String chatScript = 'text',
    Map<String, Object?> toolPayload = const {},
  }) {
    final id = 'e2e_${(index + 1).toString().padLeft(3, '0')}';
    final platform = _platformCycle[index % _platformCycle.length];
    final theme = index % 3 == 0 ? 'dark' : 'light';
    final fontScale = const [1.0, 1.15, 1.3, 1.5][index % 4];
    index++;
    return {
      'id': id,
      'platform': platform,
      'category': category,
      'title': title,
      'theme': theme,
      'fontScale': fontScale,
      'steps': steps,
      'reply': reply,
      'chatScript': chatScript,
      if (toolPayload.isNotEmpty) 'toolPayload': toolPayload,
    };
  }

  // ---------------------------------------------------------------- capture
  const captureTexts = <(String, String)>[
    ('明天下午三点提醒我交材料', 'event'),
    ('周五前提交周报', 'todo'),
    ('下周三下午两点开组会', 'event'),
    ('10月25日上午十点体检', 'event'),
    ('后天上午九点半和客户开会，记得带合同', 'event'),
    ('截止到11月3日提交报销单', 'todo'),
    ('今天买了牛奶', 'knowledge'),
    ('随便记一下', 'knowledge'),
    ('今天心情不错', 'knowledge'),
    ('每周一早上八点跑步', 'event'),
    ('2月30日交材料', 'knowledge'),
    ('下个月5号前把护照办好', 'knowledge'),
  ];
  for (var variant = 0; variant < captureTexts.length; variant++) {
    final (text, type) = captureTexts[variant];
    scenarios.add(
      build('capture', '捕获并自动整理：$text', [
        _step('seed', {'kind': 'mixed'}),
        _step('capture', {'text': text}),
        _step('nav', {'page': 'calendar'}),
        _step('calendarMode', {'mode': variant.isEven ? 'month' : 'week'}),
        _step('quickCreate', {'kind': 'todo', 'title': '补充待办 $variant'}),
        _assert('resultCount', {'value': 6}),
        _assert('typeCount', {
          'counts': {type: 2, 'todo': type == 'todo' ? 3 : 2},
        }),
        _assert('noException'),
      ]),
    );
  }

  // ----------------------------------------------------------------- review
  const ambiguous = ['记住：英语比赛在下周三', '明天', '下周找时间和王老师聊聊论文'];
  for (var variant = 0; variant < 10; variant++) {
    final text = ambiguous[variant % ambiguous.length];
    final accept = variant.isEven;
    scenarios.add(
      build('review', accept ? '待整理项按建议生成：$text' : '待整理项忽略：$text', [
        _step('capture', {'text': text}),
        _assert('reviewCount', {'value': 1}),
        _assert('resultCount', {'value': 0}),
        _step('nav', {'page': 'pending'}),
        _step('scroll', {'times': 1}),
        _step('tapText', {'value': accept ? '按建议生成' : '忽略'}),
        _assert('reviewCount', {'value': 0}),
        _step('quickCreate', {'kind': 'todo', 'title': '收尾待办 $variant'}),
        _assert('resultCount', {'value': accept ? 2 : 1}),
        _assert('noException'),
      ]),
    );
  }

  // --------------------------------------------------------------- calendar
  for (var variant = 0; variant < 12; variant++) {
    final matter = '项目推进 ${variant + 1}';
    final modes = [
      ['year', 'month', 'week', 'day', 'agenda'],
      ['month', 'day', 'agenda', 'week', 'year'],
      ['week', 'agenda', 'month', 'year', 'day'],
    ][variant % 3];
    scenarios.add(
      build('calendar', '日历五模式与快速新建：$matter', [
        _step('seed', {'kind': 'matterTree', 'title': matter}),
        _step('nav', {'page': 'calendar'}),
        for (final mode in modes) _step('calendarMode', {'mode': mode}),
        _step('calendarSection', {'section': 'todos'}),
        _step('toggleTodo', {'title': '$matter 待办 1'}),
        _step('calendarSection', {'section': 'calendar'}),
        _step('quickCreate', {'kind': 'event', 'title': '$matter 追加会议'}),
        _assert('typeCount', {
          'counts': {'event': 2},
        }),
        _assert('todoDone', {'title': '$matter 待办 1', 'value': true}),
        _assert('noException'),
      ]),
    );
  }

  // ---------------------------------------------------------------- matters
  for (var variant = 0; variant < 8; variant++) {
    final matter = '事项聚合 ${variant + 1}';
    scenarios.add(
      build('matters', '事项详情与子项联动：$matter', [
        _step('seed', {'kind': 'matterTree', 'title': matter}),
        _step('nav', {'page': 'matters'}),
        _step('openDoc', {'title': matter, 'page': 'matters'}),
        _assert('bodyContains', {'title': matter, 'value': '的要求与背景'}),
        _step('scroll', {'times': 1}),
        _step('nav', {'page': 'calendar'}),
        _step('toggleTodo', {'title': '$matter 待办 2'}),
        _step('quickCreate', {'kind': 'event', 'title': '$matter 追加日程'}),
        _assert('todoDone', {'title': '$matter 待办 2', 'value': true}),
        _assert('typeCount', {
          'counts': {'matter': 1, 'todo': 2, 'event': 2},
        }),
        _assert('noException'),
      ]),
    );
  }

  // -------------------------------------------------------------- knowledge
  for (var variant = 0; variant < 8; variant++) {
    final keyword = '检索词${variant + 1}';
    scenarios.add(
      build('knowledge', '知识批量检索与详情：$keyword', [
        _step('seed', {
          'kind': 'knowledgeBulk',
          'count': 60,
          'prefix': '知识条目',
          'keyword': keyword,
        }),
        _step('nav', {'page': 'knowledge'}),
        _step('searchKnowledge', {'query': keyword}),
        _step('searchKnowledge', {'query': '知识条目'}),
        _step('searchKnowledge', {'query': '知识条目 7'}),
        _step('openDoc', {'title': '知识条目 7'}),
        _step('scroll', {'times': 2}),
        _assert('typeCount', {
          'counts': {'knowledge': 60},
        }),
        _assert('noException'),
      ]),
    );
  }

  // ------------------------------------------------------------------- chat
  const chatRequests = [
    '帮我记一下明天下午三点的项目评审',
    '周五前把季度报告发给我',
    '整理一下英语比赛的准备事项',
    '下周三上午十点和客户开会',
    '记一条知识：复盘要先写结论',
    '明天买牛奶',
  ];
  for (var variant = 0; variant < 12; variant++) {
    final text = chatRequests[variant % chatRequests.length];
    final mode = variant % 3;
    if (mode == 0) {
      scenarios.add(
        build('chat', '多轮会话文本回复：$text', [
          _step('newChat', {'text': text}),
          _step('scroll', {'times': 1}),
          _assert('conversationCount', {'value': 1}),
          _assert('chatReplyContains', {'value': '已经帮你整理好了'}),
          _assert('assistantStatus', {'value': 'complete'}),
          _assert('resultCount', {'value': 0}),
          _step('sync', {'seed': 'none'}),
          _assert('noException'),
        ], reply: '好的，已经帮你整理好了。'),
      );
    } else if (mode == 1) {
      scenarios.add(
        build(
          'chat',
          '工具调用自动建待办：$text',
          [
            _step('newChat', {'text': text}),
            _assert('resultCount', {'value': 1}),
            _assert('titleExists', {'value': '提交季度报告'}),
            _assert('typeCount', {
              'counts': {'todo': 1},
            }),
            _step('sync', {'seed': 'none'}),
            _assert('conflictCount', {'value': 0}),
            _assert('noException'),
          ],
          chatScript: 'tool',
          toolPayload: {
            'type': 'todo',
            'title': '提交季度报告',
            'body': '周五前提交季度报告并确认收件人。',
            'confidence': 0.92,
            'sensitive': false,
            'due': '{{future:3}}',
          },
        ),
      );
    } else {
      scenarios.add(
        build(
          'chat',
          '自动记录后撤销：$text',
          [
            _step('newChat', {'text': text}),
            _assert('resultCount', {'value': 1}),
            _step('undoAutoRecord'),
            _assert('resultCount', {'value': 0}),
            _assert('titleMissing', {'value': '提交季度报告'}),
            _step('scroll', {'times': 1}),
            _assert('noException'),
          ],
          chatScript: 'tool',
          toolPayload: {
            'type': 'todo',
            'title': '提交季度报告',
            'body': '周五前提交季度报告并确认收件人。',
            'confidence': 0.92,
            'sensitive': false,
            'due': '{{future:3}}',
          },
        ),
      );
    }
  }

  // ----------------------------------------------------------- chat failure
  for (var variant = 0; variant < 6; variant++) {
    switch (variant % 3) {
      case 0:
        scenarios.add(
          build('chatFailure', '模型请求失败保留重试入口', [
            _step('newChat', {'text': '帮我整理明天的安排'}),
            _assert('resultCount', {'value': 0}),
            _assert('assistantStatus', {'value': 'failed'}),
            _step('scroll', {'times': 1}),
            _step('retryChat'),
            _assert('resultCount', {'value': 0}),
            _assert('noException'),
          ], chatScript: 'httpError'),
        );
      case 1:
        scenarios.add(
          build(
            'chatFailure',
            '缺少完成标记不得自动记录',
            [
              _step('newChat', {'text': '周五前提交周报'}),
              _assert('resultCount', {'value': 0}),
              _assert('assistantStatus', {'value': 'failed'}),
              _assert('titleMissing', {'value': '提交周报'}),
              _step('retryChat'),
              _assert('resultCount', {'value': 0}),
              _assert('noException'),
            ],
            chatScript: 'toolNoDone',
            toolPayload: {
              'type': 'todo',
              'title': '提交周报',
              'body': '周五前提交周报。',
              'confidence': 0.95,
              'sensitive': false,
              'due': '{{future:4}}',
            },
          ),
        );
      case 2:
        scenarios.add(
          build(
            'chatFailure',
            '用户停止生成保留半成品',
            [
              _step('startChat', {'text': '帮我整理这周的全部事项'}),
              _step('stopChat'),
              _step('scroll', {'times': 1}),
              _assert('conversationCount', {'value': 1}),
              _assert('resultCount', {'value': 0}),
              _assert('assistantStatus', {'value': 'interrupted'}),
              _assert('noException'),
            ],
            chatScript: 'slow',
            reply: '这是一段用来验证停止生成的长回复内容。',
          ),
        );
    }
  }

  // ------------------------------------------------------------------- sync
  for (var variant = 0; variant < 10; variant++) {
    switch (variant % 4) {
      case 0:
        scenarios.add(
          build('sync', '空通道同步保持本地成果', [
            _step('seed', {'kind': 'mixed'}),
            _step('sync', {'seed': 'none'}),
            _assert('resultCount', {'value': 4}),
            _assert('conflictCount', {'value': 0}),
            _step('openDoc', {'title': '综合知识', 'page': 'knowledge'}),
            _step('scroll', {'times': 1}),
            _assert('noException'),
          ]),
        );
      case 1:
        scenarios.add(
          build('sync', '远端新增成果导入', [
            _step('seed', {'kind': 'mixed'}),
            _step('sync', {
              'seed': 'remoteNew',
              'title': '远端知识 ${variant + 1}',
            }),
            _assert('resultCount', {'value': 5}),
            _assert('titleExists', {'value': '远端知识 ${variant + 1}'}),
            _assert('conflictCount', {'value': 0}),
            _step('openDoc', {'title': '远端知识 ${variant + 1}'}),
            _assert('noException'),
          ]),
        );
      case 2:
        scenarios.add(
          build('sync', '双端修改产生冲突并采用远端', [
            _step('sync', {'seed': 'conflict', 'title': '冲突对象 ${variant + 1}'}),
            _assert('conflictCount', {'value': 1}),
            _step('resolveConflict', {'useRemote': true}),
            _assert('conflictCount', {'value': 0}),
            _assert('bodyContains', {
              'title': '冲突对象 ${variant + 1}',
              'value': '远端追加内容',
            }),
            _assert('noException'),
          ]),
        );
      case 3:
        scenarios.add(
          build('sync', '双端修改产生冲突并保留本地', [
            _step('sync', {'seed': 'conflict', 'title': '本地对象 ${variant + 1}'}),
            _assert('conflictCount', {'value': 1}),
            _step('resolveConflict', {'useRemote': false}),
            _assert('conflictCount', {'value': 0}),
            _assert('bodyContains', {
              'title': '本地对象 ${variant + 1}',
              'value': '本地追加内容',
            }),
            _assert('noException'),
          ]),
        );
    }
  }

  // ------------------------------------------------------------ persistence
  for (var variant = 0; variant < 6; variant++) {
    final title = '持久化知识 ${variant + 1}';
    scenarios.add(
      build('persistence', '真实文件冷启动后成果仍在', [
        _step('seed', {'kind': 'mixed'}),
        _step('capture', {'text': '今天买了一本书'}),
        _assert('resultCount', {'value': 5}),
        _step('restart'),
        _assert('resultCount', {'value': 5}),
        _step('nav', {'page': 'knowledge'}),
        _step('scroll', {'times': 1}),
        _assert('typeCount', {
          'counts': {'knowledge': 2},
        }),
        _assert('noException'),
      ]),
    );
    // Keep the local variable meaningful for readability of the generated data.
    assert(title.isNotEmpty);
  }

  // --------------------------------------------------------------- settings
  for (var variant = 0; variant < 8; variant++) {
    scenarios.add(
      build('settings', '主题与图片出网开关往返', [
        _step('nav', {'page': 'settings'}),
        _step('theme', {'value': 'dark'}),
        _assert('themeDark', {'value': true}),
        _step('scroll', {'times': 2}),
        _step('imageEgress', {'value': false}),
        _assert('imageEgress', {'value': false}),
        _step('theme', {'value': 'light'}),
        _assert('themeDark', {'value': false}),
        _assert('noException'),
      ]),
    );
  }

  // --------------------------------------------------------------- recovery
  for (var variant = 0; variant < 4; variant++) {
    scenarios.add(
      build('recovery', '整理中关闭后重启保留待确认原文', [
        _step('seed', {'kind': 'processingCapture'}),
        _step('restart'),
        _assert('reviewCount', {'value': 1}),
        _step('nav', {'page': 'inbox'}),
        _step('scroll', {'times': 1}),
        _step('quickCreate', {'kind': 'todo', 'title': '恢复后补记待办'}),
        _assert('resultCount', {'value': 1}),
        _step('restart'),
        _assert('reviewCount', {'value': 1}),
        _assert('noException'),
      ]),
    );
  }

  // ------------------------------------------------------------------ mixed
  for (var variant = 0; variant < 4; variant++) {
    final matter = '综合场景 ${variant + 1}';
    scenarios.add(
      build('mixed', '捕获、日历、同步与重启的连续流程', [
        _step('seed', {'kind': 'matterTree', 'title': matter}),
        _step('capture', {'text': '周五前提交评审材料'}),
        _assert('resultCount', {'value': 5}),
        _step('nav', {'page': 'calendar'}),
        _step('calendarMode', {'mode': 'week'}),
        _step('quickCreate', {'kind': 'todo', 'title': '$matter 追加待办'}),
        _step('sync', {'seed': 'none'}),
        _step('restart'),
        _assert('resultCount', {'value': 6}),
        _assert('noException'),
      ]),
    );
  }

  if (scenarios.length != 100) {
    throw StateError('Expected 100 scenarios, got ${scenarios.length}');
  }
  final counts = <String, int>{};
  for (final scenario in scenarios) {
    counts[scenario['platform'] as String] =
        (counts[scenario['platform'] as String] ?? 0) + 1;
  }
  if (counts['phone'] != 50 ||
      counts['tablet'] != 25 ||
      counts['windows'] != 25) {
    throw StateError('Unexpected platform distribution: $counts');
  }

  final buffer = StringBuffer()
    ..writeln('// Generated by tool/generate_realistic_scenarios.dart.')
    ..writeln('// Do not edit by hand; rerun the generator instead.')
    ..writeln('const realisticScenarioMaps = <Map<String, Object?>>[');
  for (final scenario in scenarios) {
    buffer
      ..writeln('  {')
      ..write(_renderMap(scenario, indent: '    '))
      ..writeln('  },');
  }
  buffer.writeln('];');
  final output = File('test/e2e/realistic_scenarios.g.dart');
  output.writeAsStringSync(buffer.toString());
  // Keep the generated file byte-identical to `dart format` output so the CI
  // format gate never flags a regeneration.
  final formatted = Process.runSync(Platform.resolvedExecutable, [
    'format',
    output.path,
  ]);
  if (formatted.exitCode != 0) {
    throw StateError('dart format failed: ${formatted.stderr}');
  }
  stdout.writeln(
    'Wrote ${scenarios.length} scenarios to ${output.path} '
    '(${counts['phone']} phone / ${counts['tablet']} tablet / '
    '${counts['windows']} windows)',
  );
}

String _renderMap(Map<String, Object?> map, {required String indent}) {
  final entries = <String>[];
  for (final entry in map.entries) {
    entries.add(
      '$indent${jsonEncode(entry.key)}: ${_renderValue(entry.value, indent)},',
    );
  }
  return entries.join('\n');
}

String _renderValue(Object? value, String indent) {
  if (value == null) return 'null';
  if (value is String) return jsonEncode(value);
  if (value is num || value is bool) return value.toString();
  if (value is List) {
    if (value.isEmpty) return 'const []';
    final buffer = StringBuffer('[\n');
    for (final item in value) {
      buffer.writeln('$indent  ${_renderValue(item, '$indent  ')},');
    }
    buffer.write('$indent]');
    return buffer.toString();
  }
  if (value is Map) {
    if (value.isEmpty) return 'const <String, Object?>{}';
    final buffer = StringBuffer('{\n');
    for (final entry in value.entries) {
      buffer.writeln(
        '$indent  ${jsonEncode(entry.key.toString())}: '
        '${_renderValue(entry.value, '$indent  ')},',
      );
    }
    buffer.write('$indent}');
    return buffer.toString();
  }
  throw StateError('Unsupported value: $value');
}
