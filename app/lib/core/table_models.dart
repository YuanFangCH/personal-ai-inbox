import 'dart:collection';

enum TableRole {
  inboxTodo('inbox_todo'),
  inboxSchedule('inbox_schedule'),
  inboxEvent('inbox_event'),
  custom('custom');

  const TableRole(this.wireName);
  final String wireName;

  static TableRole parse(String value) => TableRole.values.firstWhere(
    (role) => role.wireName == value,
    orElse: () => throw FormatException('Unsupported table role: $value'),
  );
}

enum TableContentType {
  note('note'),
  todo('todo'),
  schedule('schedule'),
  event('event');

  const TableContentType(this.wireName);
  final String wireName;

  static TableContentType parse(String value) =>
      TableContentType.values.firstWhere(
        (type) => type.wireName == value,
        orElse: () =>
            throw FormatException('Unsupported table content type: $value'),
      );
}

enum CustomFieldType {
  text('text'),
  number('number'),
  date('date'),
  singleSelect('single_select'),
  multiSelect('multi_select'),
  checkbox('checkbox');

  const CustomFieldType(this.wireName);
  final String wireName;

  static CustomFieldType parse(String value) =>
      CustomFieldType.values.firstWhere(
        (type) => type.wireName == value,
        orElse: () => throw FormatException('Unsupported field type: $value'),
      );
}

class TableFieldOption {
  const TableFieldOption({required this.id, required this.label});

  final String id;
  final String label;
}

class TableFieldDefinition {
  TableFieldDefinition({
    required this.id,
    required this.name,
    required this.type,
    List<TableFieldOption> options = const [],
    this.required = false,
    this.defaultValue,
  }) : options = List.unmodifiable(options);

  final String id;
  final String name;
  final CustomFieldType type;
  final List<TableFieldOption> options;
  final bool required;
  final Object? defaultValue;
}

class TableDocument {
  TableDocument({
    required this.id,
    required this.role,
    required this.title,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    required this.body,
    this.schemaVersion = 1,
    this.deleted = false,
    Map<String, Object?> extensionFields = const {},
    List<TableFieldDefinition> fields = const [],
  }) : fields = List.unmodifiable(fields),
       extensionFields = Map.unmodifiable(Map.of(extensionFields));

  final String id;
  final TableRole role;
  final String title;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String body;
  final int schemaVersion;
  final bool deleted;
  final List<TableFieldDefinition> fields;
  final Map<String, Object?> extensionFields;
}

class ScheduleChange {
  const ScheduleChange({required this.scheduleId, this.summary});

  final String scheduleId;
  final String? summary;
}

class TableEntryDocument {
  TableEntryDocument({
    required this.id,
    required this.type,
    required this.tableId,
    required this.title,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    required this.body,
    this.schemaVersion = 1,
    this.deleted = false,
    Map<String, Object?> extensionFields = const {},
    List<String> tags = const [],
    List<String> links = const [],
    this.due,
    this.done = false,
    this.start,
    this.end,
    this.allDay = false,
    this.recurrence,
    this.occurredAt,
    List<ScheduleChange> affects = const [],
    Map<String, Object?> customValues = const {},
  }) : affects = List.unmodifiable(affects),
       customValues = UnmodifiableMapView(Map.of(customValues)),
       tags = List.unmodifiable(tags),
       links = List.unmodifiable(links),
       extensionFields = Map.unmodifiable(Map.of(extensionFields));

  final String id;
  final TableContentType type;
  final String tableId;
  final String title;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String body;
  final int schemaVersion;
  final bool deleted;
  final List<String> tags;
  final List<String> links;
  final DateTime? due;
  final bool done;
  final DateTime? start;
  final DateTime? end;
  final bool allDay;
  final String? recurrence;
  final DateTime? occurredAt;
  final List<ScheduleChange> affects;
  final Map<String, Object?> customValues;
  final Map<String, Object?> extensionFields;
}
