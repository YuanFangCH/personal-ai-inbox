import 'package:yaml/yaml.dart';

import 'models.dart';

class MarkdownCodec {
  const MarkdownCodec();

  ResultDocument decode(String source) {
    final normalized = source.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---\n')) {
      throw const FormatException('Markdown frontmatter is missing');
    }

    final end = normalized.indexOf('\n---', 4);
    if (end < 0) {
      throw const FormatException('Markdown frontmatter is not closed');
    }

    final yamlText = normalized.substring(4, end);
    final loaded = loadYaml(yamlText);
    if (loaded is! YamlMap) {
      throw const FormatException('Markdown frontmatter is not a map');
    }

    final map = <String, dynamic>{};
    for (final entry in loaded.entries) {
      map[entry.key.toString()] = _normalizeYaml(entry.value);
    }

    final id = _requiredString(map, 'id');
    final type = ResultType.parse(_requiredString(map, 'type'));
    final createdAt = _requiredDate(map, 'created_at');
    final updatedAt = _requiredDate(map, 'updated_at');
    final bodyStart = end + 4;
    final body = bodyStart >= normalized.length
        ? ''
        : normalized.substring(bodyStart).trimLeft().trimRight();

    return ResultDocument(
      id: id,
      type: type,
      title: _string(map['title'], fallback: id),
      status: ResultStatus.parse(_string(map['status'], fallback: 'draft')),
      originDevice: _string(map['origin_device'], fallback: 'unknown'),
      revision: _int(map['revision'], fallback: 1),
      createdAt: createdAt,
      updatedAt: updatedAt,
      deleted: map['deleted'] == true,
      tags: _stringList(map['tags']),
      links: _stringList(map['links']),
      body: body,
      due: _optionalDate(map['due']),
      done: map['done'] == true,
      matterId: _nullableString(map['matter']),
      start: _optionalDate(map['start']),
      end: _optionalDate(map['end']),
      allDay: map['all_day'] == true,
      recurrence: _nullableString(map['recurrence']),
      sourceEventIds: _stringList(map['source_event_ids']),
      sourceHashes: _stringList(map['source_hashes']),
    );
  }

  String encode(ResultDocument document) {
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('id: ${_scalar(document.id)}')
      ..writeln('type: ${document.type.wireName}')
      ..writeln('title: ${_scalar(document.title)}')
      ..writeln('status: ${document.status.wireName}')
      ..writeln('origin_device: ${_scalar(document.originDevice)}')
      ..writeln('revision: ${document.revision}')
      ..writeln('created_at: ${_iso8601(document.createdAt)}')
      ..writeln('updated_at: ${_iso8601(document.updatedAt)}')
      ..writeln('deleted: ${document.deleted}');

    if (document.tags.isNotEmpty) {
      buffer.writeln('tags: ${_inlineList(document.tags)}');
    }
    if (document.links.isNotEmpty) {
      buffer.writeln('links: ${_inlineList(document.links)}');
    }

    switch (document.type) {
      case ResultType.matter:
        break;
      case ResultType.todo:
        if (document.due != null) {
          buffer.writeln('due: ${_iso8601(document.due!)}');
        }
        buffer.writeln('done: ${document.done}');
        if (document.matterId != null) {
          buffer.writeln('matter: ${_scalar(document.matterId!)}');
        }
        break;
      case ResultType.event:
        if (document.start != null) {
          buffer.writeln('start: ${_iso8601(document.start!)}');
        }
        if (document.end != null) {
          buffer.writeln('end: ${_iso8601(document.end!)}');
        }
        buffer.writeln('all_day: ${document.allDay}');
        if (document.recurrence != null) {
          buffer.writeln('recurrence: ${_scalar(document.recurrence!)}');
        }
        if (document.matterId != null) {
          buffer.writeln('matter: ${_scalar(document.matterId!)}');
        }
        break;
      case ResultType.knowledge:
        if (document.sourceEventIds.isNotEmpty) {
          buffer.writeln(
            'source_event_ids: ${_inlineList(document.sourceEventIds)}',
          );
        }
        if (document.sourceHashes.isNotEmpty) {
          buffer.writeln(
            'source_hashes: ${_inlineList(document.sourceHashes)}',
          );
        }
        break;
    }

    buffer
      ..writeln('---')
      ..writeln()
      ..write(document.body.trimRight())
      ..writeln();
    return buffer.toString();
  }

  dynamic _normalizeYaml(dynamic value) {
    if (value is YamlList) {
      return value.map(_normalizeYaml).toList(growable: false);
    }
    if (value is YamlMap) {
      return value.map(
        (key, nestedValue) =>
            MapEntry(key.toString(), _normalizeYaml(nestedValue)),
      );
    }
    return value;
  }

  String _requiredString(Map<String, dynamic> map, String key) {
    final value = _nullableString(map[key]);
    if (value == null || value.isEmpty) {
      throw FormatException('Markdown frontmatter key is required: $key');
    }
    return value;
  }

  DateTime _requiredDate(Map<String, dynamic> map, String key) {
    final value = _optionalDate(map[key]);
    if (value == null) {
      throw FormatException('Markdown frontmatter date is invalid: $key');
    }
    return value;
  }

  String _string(dynamic value, {required String fallback}) {
    return _nullableString(value) ?? fallback;
  }

  int _int(dynamic value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String? _nullableString(dynamic value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  DateTime? _optionalDate(dynamic value) {
    final text = _nullableString(value);
    if (text == null) {
      return null;
    }
    return DateTime.tryParse(text)?.toLocal();
  }

  List<String> _stringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
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
    final localText = hongKong.toIso8601String().replaceFirst(
      RegExp(r'Z$'),
      '',
    );
    return '$localText+08:00';
  }
}
