import 'dart:convert';
import 'dart:io';

import '../test/large_scenario_20_cases.g.dart';

void main() {
  final outputRoot = Directory('build/manual-review-vault');
  if (outputRoot.existsSync()) {
    outputRoot.deleteSync(recursive: true);
  }

  final createdAt = DateTime.parse('2026-10-05T23:59:00+08:00');
  var generated = 0;
  for (
    var scenarioIndex = 0;
    scenarioIndex < largeScenarioMaps.length;
    scenarioIndex++
  ) {
    final scenario = largeScenarioMaps[scenarioIndex];
    final messages = scenario['messages'] as List<Object?>;
    var callIndex = 0;
    for (final messageValue in messages) {
      final message = (messageValue! as Map).cast<String, Object?>();
      final calls = message['calls'] as List<Object?>;
      for (final callValue in calls) {
        final call = (callValue! as Map).cast<String, Object?>();
        if (call['expect'] != 'created') {
          callIndex++;
          continue;
        }
        final type = call['type']! as String;
        final id =
            '${_prefix(type)}_review_'
            '${(scenarioIndex + 1).toString().padLeft(2, '0')}'
            '${callIndex.toString().padLeft(2, '0')}';
        final markdown = _encodeMarkdown(
          id: id,
          type: type,
          title: call['title']! as String,
          originDevice: 'manual-review-honor-90',
          createdAt: createdAt,
          body: call['body']! as String,
          tags: (call['tags']! as List<Object?>).cast<String>(),
          due: call['due'] == null
              ? null
              : DateTime.parse(call['due']! as String),
          start: call['start'] == null
              ? null
              : DateTime.parse(call['start']! as String),
          end: call['end'] == null
              ? null
              : DateTime.parse(call['end']! as String),
          allDay: call['all_day'] == true,
        );
        final file = File(
          '${outputRoot.path}/vault/${_directory(type)}/$id.md',
        );
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(markdown);
        generated++;
        callIndex++;
      }
    }
  }

  final acceptanceFile = File('test/fixtures/device_acceptance_100_cases.json');
  final acceptanceData =
      jsonDecode(acceptanceFile.readAsStringSync()) as Map<String, dynamic>;
  final acceptanceCases = acceptanceData['cases'] as List<dynamic>;
  for (var index = 0; index < acceptanceCases.length; index++) {
    final item = (acceptanceCases[index] as Map).cast<String, Object?>();
    final id = 'kn_acceptance_${(index + 1).toString().padLeft(3, '0')}';
    final markdown = _encodeMarkdown(
      id: id,
      type: 'knowledge',
      title: '[验收] ${item['description']}',
      originDevice: 'manual-review-honor-90',
      createdAt: createdAt,
      body: [
        '用例编号: ${item['id']}',
        '目标设备: ${item['target']}',
        '设备档位: ${item['device']}',
        '主题: ${item['theme']}',
        '字体缩放: ${item['fontScale']}',
        '页面: ${item['page']}',
        '动作: ${item['action']}',
        '预期文本: ${item['expectedText'] ?? '无'}',
      ].join('\n'),
      tags: const ['测试验收', '设备用例'],
      due: null,
      start: null,
      end: null,
      allDay: false,
    );
    final file = File('${outputRoot.path}/vault/knowledge/$id.md');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(markdown);
    generated++;
  }

  stdout.writeln('Wrote $generated review documents to ${outputRoot.path}');
}

String _prefix(String type) {
  return switch (type) {
    'matter' => 'mt',
    'todo' => 'td',
    'event' => 'ev',
    'knowledge' => 'kn',
    _ => throw ArgumentError.value(type, 'type'),
  };
}

String _directory(String type) {
  return switch (type) {
    'matter' => 'matters',
    'todo' => 'todos',
    'event' => 'calendar',
    'knowledge' => 'knowledge',
    _ => throw ArgumentError.value(type, 'type'),
  };
}

String _encodeMarkdown({
  required String id,
  required String type,
  required String title,
  required String originDevice,
  required DateTime createdAt,
  required String body,
  required List<String> tags,
  required DateTime? due,
  required DateTime? start,
  required DateTime? end,
  required bool allDay,
}) {
  final buffer = StringBuffer()
    ..writeln('---')
    ..writeln('id: ${_scalar(id)}')
    ..writeln('type: $type')
    ..writeln('title: ${_scalar(title)}')
    ..writeln('status: canonical')
    ..writeln('origin_device: ${_scalar(originDevice)}')
    ..writeln('revision: 1')
    ..writeln('created_at: ${_iso8601(createdAt)}')
    ..writeln('updated_at: ${_iso8601(createdAt)}')
    ..writeln('deleted: false');
  if (tags.isNotEmpty) {
    buffer.writeln('tags: ${_inlineList(tags)}');
  }
  switch (type) {
    case 'todo':
      if (due != null) {
        buffer.writeln('due: ${_iso8601(due)}');
      }
      buffer.writeln('done: false');
    case 'event':
      if (start != null) {
        buffer.writeln('start: ${_iso8601(start)}');
      }
      if (end != null) {
        buffer.writeln('end: ${_iso8601(end)}');
      }
      buffer.writeln('all_day: $allDay');
    case 'matter':
    case 'knowledge':
      break;
  }
  buffer
    ..writeln('---')
    ..writeln()
    ..write(body.trimRight())
    ..writeln();
  return buffer.toString();
}

String _inlineList(List<String> values) {
  return '[${values.map(_scalar).join(', ')}]';
}

String _scalar(String value) {
  if (value.isEmpty) {
    return "''";
  }
  final safe = RegExp(r'^[A-Za-z0-9_./:+@-]+$').hasMatch(value);
  if (safe &&
      !RegExp(
        r'^(true|false|null|yes|no|on|off)$',
        caseSensitive: false,
      ).hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", "''")}'";
}

String _iso8601(DateTime value) {
  final hongKong = value.toUtc().add(const Duration(hours: 8));
  final localText = hongKong.toIso8601String().replaceFirst(RegExp(r'Z$'), '');
  return '$localText+08:00';
}
