import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'models.dart';

class MarkdownCodec {
  const MarkdownCodec();

  static const _schemaVersion = 1;
  static const _knownFrontmatterFields = {
    'schema_version',
    'id',
    'type',
    'title',
    'status',
    'origin_device',
    'revision',
    'created_at',
    'updated_at',
    'deleted',
    'tags',
    'links',
    'due',
    'done',
    'matter',
    'start',
    'end',
    'all_day',
    'recurrence',
    'source_event_ids',
    'source_hashes',
  };

  ResultDocument decode(String source) {
    final normalized = source.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---\n')) {
      throw const FormatException('Markdown frontmatter is missing');
    }

    final frontmatterEnd = normalized.indexOf('\n---', 4);
    if (frontmatterEnd < 0) {
      throw const FormatException('Markdown frontmatter is not closed');
    }

    final yamlText = normalized.substring(4, frontmatterEnd);
    final loaded = loadYaml(yamlText);
    if (loaded is! YamlMap) {
      throw const FormatException('Markdown frontmatter is not a map');
    }

    final map = <String, dynamic>{};
    for (final entry in loaded.entries) {
      map[entry.key.toString()] = _normalizeYaml(entry.value);
    }

    final schemaVersion = map['schema_version'] ?? 1;
    if (schemaVersion is! int || schemaVersion < 1) {
      throw const FormatException('Markdown schema_version is invalid');
    }
    if (schemaVersion > _schemaVersion) {
      throw FormatException(
        'Unsupported Markdown schema_version: $schemaVersion',
      );
    }
    final id = _requiredString(map, 'id');
    final type = ResultType.parse(_requiredString(map, 'type'));
    final createdAt = _requiredDate(map, 'created_at');
    final updatedAt = _requiredDate(map, 'updated_at');
    final title = _optionalString(map, 'title') ?? id;
    final statusName = _optionalString(map, 'status') ?? 'draft';
    final status = ResultStatus.values.where(
      (value) => value.wireName == statusName,
    );
    if (status.isEmpty) {
      throw FormatException('Markdown status is invalid: $statusName');
    }
    final revision = _optionalInt(map, 'revision') ?? 1;
    if (revision < 1) {
      throw const FormatException('Markdown revision must be positive');
    }
    final originDevice = _optionalString(map, 'origin_device') ?? 'unknown';
    final deleted = _optionalBool(map, 'deleted') ?? false;
    final tags = _strictStringList(map, 'tags');
    final links = _strictStringList(map, 'links');
    final done = _optionalBool(map, 'done') ?? false;
    final allDay = _optionalBool(map, 'all_day') ?? false;
    final matterId = _optionalString(map, 'matter');
    final recurrence = _optionalString(map, 'recurrence');
    final due = _optionalDate(map, 'due');
    final start = _optionalDate(map, 'start');
    final eventEnd = _optionalDate(map, 'end');
    final sourceEventIds = _strictStringList(map, 'source_event_ids');
    final sourceHashes = _strictStringList(map, 'source_hashes');
    if (type == ResultType.event &&
        start != null &&
        eventEnd != null &&
        !eventEnd.isAfter(start)) {
      throw const FormatException('Markdown event end must be after start');
    }
    final extensions = <String, Object?>{
      for (final entry in map.entries)
        if (!_knownFrontmatterFields.contains(entry.key))
          entry.key: entry.value,
    };
    final bodyStart = frontmatterEnd + 4;
    final body = bodyStart >= normalized.length
        ? ''
        : normalized.substring(bodyStart).trimLeft().trimRight();

    return ResultDocument(
      id: id,
      type: type,
      title: title,
      status: status.first,
      originDevice: originDevice,
      revision: revision,
      createdAt: createdAt,
      updatedAt: updatedAt,
      schemaVersion: schemaVersion,
      extensionFields: Map.unmodifiable(extensions),
      deleted: deleted,
      tags: tags,
      links: links,
      body: body,
      due: due,
      done: done,
      matterId: matterId,
      start: start,
      end: eventEnd,
      allDay: allDay,
      recurrence: recurrence,
      sourceEventIds: sourceEventIds,
      sourceHashes: sourceHashes,
    );
  }

  String encode(ResultDocument document) {
    if (document.schemaVersion > _schemaVersion) {
      throw FormatException(
        'Refusing to write unsupported Markdown schema_version: '
        '${document.schemaVersion}',
      );
    }
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('schema_version: ${document.schemaVersion}')
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

    for (final entry in document.extensionFields.entries) {
      if (_knownFrontmatterFields.contains(entry.key)) {
        throw FormatException(
          'Extension field shadows a known Markdown field: ${entry.key}',
        );
      }
      buffer.writeln('${_scalar(entry.key)}: ${_yamlValue(entry.value)}');
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
    final value = _optionalString(map, key);
    if (value == null || value.isEmpty) {
      throw FormatException('Markdown frontmatter key is required: $key');
    }
    return value;
  }

  String? _optionalString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException(
        'Markdown frontmatter field must be a string: $key',
      );
    }
    return value.trim().isEmpty ? null : value.trim();
  }

  DateTime _requiredDate(Map<String, dynamic> map, String key) {
    final value = _optionalDate(map, key);
    if (value == null) {
      throw FormatException('Markdown frontmatter date is invalid: $key');
    }
    return value;
  }

  DateTime? _optionalDate(Map<String, dynamic> map, String key) {
    if (!map.containsKey(key) || map[key] == null) return null;
    final value = map[key];
    final text = value is DateTime ? value.toIso8601String() : value;
    if (text is! String) {
      throw FormatException('Markdown frontmatter date must be a string: $key');
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      throw FormatException('Markdown frontmatter date is invalid: $key');
    }
    return parsed.toLocal();
  }

  int? _optionalInt(Map<String, dynamic> map, String key) {
    if (!map.containsKey(key) || map[key] == null) return null;
    final value = map[key];
    if (value is! int) {
      throw FormatException(
        'Markdown frontmatter field must be an integer: $key',
      );
    }
    return value;
  }

  bool? _optionalBool(Map<String, dynamic> map, String key) {
    if (!map.containsKey(key) || map[key] == null) return null;
    final value = map[key];
    if (value is! bool) {
      throw FormatException(
        'Markdown frontmatter field must be a boolean: $key',
      );
    }
    return value;
  }

  List<String> _strictStringList(Map<String, dynamic> map, String key) {
    if (!map.containsKey(key) || map[key] == null) return const [];
    final value = map[key];
    if (value is! List || value.any((item) => item is! String)) {
      throw FormatException(
        'Markdown frontmatter field must be a string list: $key',
      );
    }
    return value
        .cast<String>()
        .map((item) => item.trim())
        .toList(growable: false);
  }

  String _yamlValue(Object? value) {
    if (value is DateTime) return _iso8601(value);
    if (value is List) {
      return jsonEncode(value.map(_jsonSafeValue).toList(growable: false));
    }
    if (value is Map) {
      final normalized = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const FormatException(
            'Markdown extension keys must be strings',
          );
        }
        normalized[entry.key as String] = _jsonSafeValue(entry.value);
      }
      return jsonEncode(normalized);
    }
    return jsonEncode(value);
  }

  Object? _jsonSafeValue(Object? value) {
    if (value is DateTime) return _iso8601(value);
    if (value is List) return value.map(_jsonSafeValue).toList(growable: false);
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const FormatException(
            'Markdown extension keys must be strings',
          );
        }
        result[entry.key as String] = _jsonSafeValue(entry.value);
      }
      return result;
    }
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    throw FormatException(
      'Unsupported Markdown extension value: ${value.runtimeType}',
    );
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
