import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'table_models.dart';

/// Markdown codec for tables and table-owned entries. Legacy documents remain
/// handled by [MarkdownCodec] until the explicit migration is implemented.
class TableMarkdownCodec {
  const TableMarkdownCodec();

  static const _schemaVersion = 1;
  static const _tableKeys = {
    'schema_version',
    'id',
    'type',
    'role',
    'title',
    'revision',
    'created_at',
    'updated_at',
    'deleted',
    'field_definitions',
  };
  static const _entryKeys = {
    'schema_version',
    'id',
    'type',
    'table_id',
    'title',
    'revision',
    'created_at',
    'updated_at',
    'deleted',
    'tags',
    'links',
    'due',
    'done',
    'start',
    'end',
    'all_day',
    'recurrence',
    'occurred_at',
    'affects',
    'custom_values',
  };

  TableDocument decodeTable(String source) {
    final map = _frontmatter(source, _tableKeys);
    _validateVersion(map);
    if (_requiredString(map, 'type') != 'table') {
      throw const FormatException('Expected a table Markdown document');
    }
    final fieldsValue = map['field_definitions'] ?? const [];
    if (fieldsValue is! List) {
      throw const FormatException('field_definitions must be a list');
    }
    final fields = fieldsValue.map(_fieldFromJson).toList(growable: false);
    _assertUnique(fields.map((field) => field.id), 'field id');
    for (final field in fields) {
      _validateField(field);
    }
    return TableDocument(
      id: _requiredString(map, 'id'),
      role: TableRole.parse(_requiredString(map, 'role')),
      title: _requiredString(map, 'title'),
      revision: _revision(map),
      createdAt: _requiredDate(map, 'created_at'),
      updatedAt: _requiredDate(map, 'updated_at'),
      body: _body(source),
      schemaVersion: map['schema_version'] as int,
      deleted: _optionalBool(map, 'deleted') ?? false,
      fields: fields,
      extensionFields: _extensions(map, _tableKeys),
    );
  }

  TableEntryDocument decodeEntry(String source) {
    final map = _frontmatter(source, _entryKeys);
    _validateVersion(map);
    if (_requiredString(map, 'type') == 'table') {
      throw const FormatException('Expected a table-owned content document');
    }
    final affectsValue = map['affects'] ?? const [];
    if (affectsValue is! List) {
      throw const FormatException('affects must be a list');
    }
    final affects = affectsValue.map(_scheduleChangeFromJson).toList();
    final values = map['custom_values'] ?? const {};
    if (values is! Map || values.keys.any((key) => key is! String)) {
      throw const FormatException('custom_values must be a string-keyed map');
    }
    final type = TableContentType.parse(_requiredString(map, 'type'));
    final due = _optionalDate(map, 'due');
    final start = _optionalDate(map, 'start');
    final end = _optionalDate(map, 'end');
    final occurredAt = _optionalDate(map, 'occurred_at');
    if (type == TableContentType.schedule && start == null) {
      throw const FormatException('A schedule requires start');
    }
    if (start != null && end != null && !end.isAfter(start)) {
      throw const FormatException('end must be after start');
    }
    if (type != TableContentType.todo &&
        (map.containsKey('due') || map.containsKey('done'))) {
      throw const FormatException('due and done are only valid on todos');
    }
    if (type != TableContentType.schedule &&
        (map.containsKey('start') ||
            map.containsKey('end') ||
            map.containsKey('all_day') ||
            map.containsKey('recurrence'))) {
      throw const FormatException(
        'schedule fields are only valid on schedules',
      );
    }
    if (type != TableContentType.event &&
        (map.containsKey('occurred_at') || map.containsKey('affects'))) {
      throw const FormatException('event fields are only valid on events');
    }
    return TableEntryDocument(
      id: _requiredString(map, 'id'),
      type: type,
      tableId: _requiredString(map, 'table_id'),
      title: _requiredString(map, 'title'),
      revision: _revision(map),
      createdAt: _requiredDate(map, 'created_at'),
      updatedAt: _requiredDate(map, 'updated_at'),
      body: _body(source),
      schemaVersion: map['schema_version'] as int,
      deleted: _optionalBool(map, 'deleted') ?? false,
      tags: _stringList(map, 'tags'),
      links: _stringList(map, 'links'),
      due: due,
      done: _optionalBool(map, 'done') ?? false,
      start: start,
      end: end,
      allDay: _optionalBool(map, 'all_day') ?? false,
      recurrence: _optionalString(map, 'recurrence'),
      occurredAt: occurredAt,
      affects: affects,
      customValues: Map<String, Object?>.from(values),
      extensionFields: _extensions(map, _entryKeys),
    );
  }

  String encodeTable(TableDocument table) {
    _validateWritableVersion(table.schemaVersion);
    _validateIdentity(table.id, table.title, table.revision);
    _assertUnique(table.fields.map((field) => field.id), 'field id');
    for (final field in table.fields) {
      _validateField(field);
    }
    final fields = table.fields.map(_fieldToJson).toList(growable: false);
    return _encode({
      'schema_version': table.schemaVersion,
      'id': table.id,
      'type': 'table',
      'role': table.role.wireName,
      'title': table.title,
      'revision': table.revision,
      'created_at': _iso(table.createdAt),
      'updated_at': _iso(table.updatedAt),
      'deleted': table.deleted,
      'field_definitions': fields,
      ..._serializedExtensions(table.extensionFields, _tableKeys),
    }, table.body);
  }

  String encodeEntry(
    TableEntryDocument entry, {
    List<TableFieldDefinition> fields = const [],
  }) {
    _validateWritableVersion(entry.schemaVersion);
    _validateIdentity(entry.id, entry.title, entry.revision);
    if (entry.tableId.trim().isEmpty) {
      throw const FormatException('table_id is required');
    }
    if (entry.type == TableContentType.schedule && entry.start == null) {
      throw const FormatException('A schedule requires start');
    }
    if (entry.start != null &&
        entry.end != null &&
        !entry.end!.isAfter(entry.start!)) {
      throw const FormatException('end must be after start');
    }
    if (entry.type != TableContentType.todo && entry.due != null) {
      throw const FormatException('due is only valid on todos');
    }
    if (entry.type != TableContentType.todo && entry.done) {
      throw const FormatException('done is only valid on todos');
    }
    if (entry.type != TableContentType.schedule &&
        (entry.start != null ||
            entry.end != null ||
            entry.allDay ||
            entry.recurrence != null)) {
      throw const FormatException(
        'schedule fields are only valid on schedules',
      );
    }
    if (entry.type != TableContentType.event &&
        (entry.occurredAt != null || entry.affects.isNotEmpty)) {
      throw const FormatException('event fields are only valid on events');
    }
    _assertUnique(fields.map((field) => field.id), 'field id');
    for (final field in fields) {
      _validateField(field);
    }
    _validateValues(fields, entry.customValues);
    final values = <String, Object?>{
      'schema_version': entry.schemaVersion,
      'id': entry.id,
      'type': entry.type.wireName,
      'table_id': entry.tableId,
      'title': entry.title,
      'revision': entry.revision,
      'created_at': _iso(entry.createdAt),
      'updated_at': _iso(entry.updatedAt),
      'deleted': entry.deleted,
    };
    if (entry.tags.isNotEmpty) values['tags'] = entry.tags;
    if (entry.links.isNotEmpty) values['links'] = entry.links;
    switch (entry.type) {
      case TableContentType.note:
        break;
      case TableContentType.todo:
        values['done'] = entry.done;
        if (entry.due != null) values['due'] = _iso(entry.due!);
      case TableContentType.schedule:
        values['start'] = _iso(entry.start!);
        if (entry.end != null) values['end'] = _iso(entry.end!);
        values['all_day'] = entry.allDay;
        if (entry.recurrence != null) values['recurrence'] = entry.recurrence;
      case TableContentType.event:
        if (entry.occurredAt != null) {
          values['occurred_at'] = _iso(entry.occurredAt!);
        }
        if (entry.affects.isNotEmpty) {
          values['affects'] = entry.affects.map(_scheduleChangeToJson).toList();
        }
    }
    if (entry.customValues.isNotEmpty) {
      values['custom_values'] = entry.customValues;
    }
    values.addAll(_serializedExtensions(entry.extensionFields, _entryKeys));
    return _encode(values, entry.body);
  }

  Map<String, dynamic> _frontmatter(String source, Set<String> knownKeys) {
    final normalized = source.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---\n')) {
      throw const FormatException('Markdown frontmatter is missing');
    }
    final end = normalized.indexOf('\n---', 4);
    if (end < 0) {
      throw const FormatException('Markdown frontmatter is not closed');
    }
    final loaded = loadYaml(normalized.substring(4, end));
    if (loaded is! YamlMap) {
      throw const FormatException('Frontmatter must be a map');
    }
    final map = <String, dynamic>{};
    for (final item in loaded.entries) {
      final key = item.key.toString();
      map[key] = _normalize(item.value);
    }
    return map;
  }

  Map<String, Object?> _extensions(
    Map<String, dynamic> values,
    Set<String> knownKeys,
  ) => {
    for (final entry in values.entries)
      if (!knownKeys.contains(entry.key)) entry.key: entry.value,
  };

  Map<String, Object?> _serializedExtensions(
    Map<String, Object?> extensions,
    Set<String> knownKeys,
  ) {
    for (final key in extensions.keys) {
      if (knownKeys.contains(key)) {
        throw FormatException('Extension field shadows a known field: $key');
      }
    }
    return extensions;
  }

  Object? _normalize(Object? value) {
    if (value is YamlList) return value.map(_normalize).toList(growable: false);
    if (value is YamlMap) {
      return value.map(
        (key, value) => MapEntry(key.toString(), _normalize(value)),
      );
    }
    return value;
  }

  void _validateVersion(Map<String, dynamic> map) {
    final value = map['schema_version'] ?? 1;
    if (value is! int || value < 1 || value > _schemaVersion) {
      throw FormatException(
        'Unsupported table Markdown schema_version: $value',
      );
    }
    map['schema_version'] = value;
  }

  void _validateWritableVersion(int value) {
    if (value < 1 || value > _schemaVersion) {
      throw FormatException(
        'Unsupported table Markdown schema_version: $value',
      );
    }
  }

  void _validateIdentity(String id, String title, int revision) {
    if (id.trim().isEmpty || title.trim().isEmpty || revision < 1) {
      throw const FormatException(
        'id and title are required; revision must be positive',
      );
    }
  }

  String _requiredString(Map<String, dynamic> map, String key) {
    final value = _optionalString(map, key);
    if (value == null) {
      throw FormatException('Required Markdown field is missing: $key');
    }
    return value;
  }

  String? _optionalString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! String) throw FormatException('$key must be a string');
    return value.trim().isEmpty ? null : value.trim();
  }

  int _revision(Map<String, dynamic> map) {
    final value = map['revision'] ?? 1;
    if (value is! int || value < 1) {
      throw const FormatException('revision must be positive');
    }
    return value;
  }

  DateTime _requiredDate(Map<String, dynamic> map, String key) {
    final value = _optionalDate(map, key);
    if (value == null) throw FormatException('$key must be an ISO 8601 date');
    return value;
  }

  DateTime? _optionalDate(Map<String, dynamic> map, String key) {
    if (!map.containsKey(key) || map[key] == null) return null;
    final value = map[key];
    final text = value is DateTime ? value.toIso8601String() : value;
    if (text is! String || DateTime.tryParse(text) == null) {
      throw FormatException('$key must be an ISO 8601 date');
    }
    return DateTime.parse(text).toLocal();
  }

  bool? _optionalBool(Map<String, dynamic> map, String key) {
    if (!map.containsKey(key) || map[key] == null) return null;
    final value = map[key];
    if (value is! bool) throw FormatException('$key must be a boolean');
    return value;
  }

  List<String> _stringList(Map<String, dynamic> map, String key) {
    final value = map[key] ?? const [];
    if (value is! List || value.any((item) => item is! String)) {
      throw FormatException('$key must be a list of strings');
    }
    return value.cast<String>();
  }

  TableFieldDefinition _fieldFromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('field definition must be a map');
    }
    final options = value['options'] ?? const [];
    if (options is! List) {
      throw const FormatException('field options must be a list');
    }
    final parsedOptions = options
        .map((item) {
          if (item is! Map ||
              item['id'] is! String ||
              item['label'] is! String) {
            throw const FormatException(
              'field option requires string id and label',
            );
          }
          return TableFieldOption(
            id: item['id'] as String,
            label: item['label'] as String,
          );
        })
        .toList(growable: false);
    _assertUnique(parsedOptions.map((item) => item.id), 'field option id');
    final required = value['required'] ?? false;
    if (required is! bool) {
      throw const FormatException('field required must be a boolean');
    }
    final id = value['id'];
    final name = value['name'];
    final type = value['type'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.isEmpty ||
        type is! String) {
      throw const FormatException(
        'field definition requires id, name, and type',
      );
    }
    return TableFieldDefinition(
      id: id,
      name: name,
      type: CustomFieldType.parse(type),
      options: parsedOptions,
      required: required,
      defaultValue: value['default'],
    );
  }

  Map<String, Object?> _fieldToJson(TableFieldDefinition field) {
    final result = <String, Object?>{
      'id': field.id,
      'name': field.name,
      'type': field.type.wireName,
      'required': field.required,
    };
    if (field.options.isNotEmpty) {
      result['options'] = field.options
          .map((option) => {'id': option.id, 'label': option.label})
          .toList(growable: false);
    }
    if (field.defaultValue != null) result['default'] = field.defaultValue;
    return result;
  }

  void _validateField(TableFieldDefinition field) {
    if (field.id.trim().isEmpty || field.name.trim().isEmpty) {
      throw const FormatException('field id and name are required');
    }
    _assertUnique(field.options.map((option) => option.id), 'field option id');
    if (field.type != CustomFieldType.singleSelect &&
        field.type != CustomFieldType.multiSelect &&
        field.options.isNotEmpty) {
      throw const FormatException('Only select fields may define options');
    }
    if (field.defaultValue != null) {
      _validateValues([field], {field.id: field.defaultValue});
    }
  }

  ScheduleChange _scheduleChangeFromJson(Object? value) {
    if (value is! Map || value['schedule_id'] is! String) {
      throw const FormatException('affects entry requires schedule_id');
    }
    final summary = value['summary'];
    if (summary != null && summary is! String) {
      throw const FormatException('affects summary must be a string');
    }
    return ScheduleChange(
      scheduleId: value['schedule_id'] as String,
      summary: summary as String?,
    );
  }

  Map<String, Object?> _scheduleChangeToJson(ScheduleChange value) => {
    'schedule_id': value.scheduleId,
    if (value.summary != null) 'summary': value.summary,
  };

  void _validateValues(
    List<TableFieldDefinition> fields,
    Map<String, Object?> values,
  ) {
    final byId = {for (final field in fields) field.id: field};
    for (final entry in values.entries) {
      final field = byId[entry.key];
      if (field == null) {
        throw FormatException('Unknown custom field id: ${entry.key}');
      }
      final value = entry.value;
      if (value == null) continue;
      switch (field.type) {
        case CustomFieldType.text:
          if (value is! String) {
            throw FormatException('${field.name} must be text');
          }
        case CustomFieldType.number:
          if (value is! num || !value.isFinite) {
            throw FormatException('${field.name} must be finite numeric');
          }
        case CustomFieldType.date:
          if (value is! String || DateTime.tryParse(value) == null) {
            throw FormatException('${field.name} must be an ISO 8601 date');
          }
        case CustomFieldType.singleSelect:
          if (value is! String ||
              !field.options.any((option) => option.id == value)) {
            throw FormatException(
              '${field.name} must select an existing option id',
            );
          }
        case CustomFieldType.multiSelect:
          if (value is! List ||
              value.any(
                (item) =>
                    item is! String ||
                    !field.options.any((option) => option.id == item),
              )) {
            throw FormatException(
              '${field.name} must contain existing option ids',
            );
          }
          if (value.toSet().length != value.length) {
            throw FormatException('${field.name} cannot repeat option ids');
          }
        case CustomFieldType.checkbox:
          if (value is! bool) {
            throw FormatException('${field.name} must be a checkbox value');
          }
      }
    }
    for (final field in fields) {
      if (field.required &&
          (!values.containsKey(field.id) || values[field.id] == null)) {
        throw FormatException('${field.name} is required');
      }
    }
  }

  void _assertUnique(Iterable<String> ids, String label) {
    final values = ids.toList(growable: false);
    if (values.any((value) => value.isEmpty) ||
        values.toSet().length != values.length) {
      throw FormatException('$label must be non-empty and unique');
    }
  }

  String _body(String source) {
    final normalized = source.replaceAll('\r\n', '\n');
    final end = normalized.indexOf('\n---', 4);
    if (end < 0) {
      throw const FormatException('Markdown frontmatter is not closed');
    }
    return normalized.substring(end + 4).trim();
  }

  String _encode(Map<String, Object?> values, String body) {
    final buffer = StringBuffer('---\n');
    for (final entry in values.entries) {
      buffer.writeln('${entry.key}: ${_yamlValue(entry.value)}');
    }
    buffer
      ..writeln('---')
      ..writeln()
      ..writeln(body.trimRight());
    return buffer.toString();
  }

  String _yamlValue(Object? value) {
    if (value is String) return _scalar(value);
    if (value is DateTime) return _scalar(_iso(value));
    return jsonEncode(_jsonSafeValue(value));
  }

  Object? _jsonSafeValue(Object? value) {
    if (value is DateTime) return _iso(value);
    if (value is List) {
      return value.map(_jsonSafeValue).toList(growable: false);
    }
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const FormatException('Extension keys must be strings');
        }
        result[entry.key as String] = _jsonSafeValue(entry.value);
      }
      return result;
    }
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    throw FormatException('Unsupported Markdown value: ${value.runtimeType}');
  }

  String _scalar(String value) => "'${value.replaceAll("'", "''")}'";

  String _iso(DateTime value) => value.toIso8601String();
}
