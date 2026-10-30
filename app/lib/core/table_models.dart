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

  TableDocument copyWith({
    TableRole? role,
    String? title,
    int? revision,
    DateTime? updatedAt,
    String? body,
    bool? deleted,
    List<TableFieldDefinition>? fields,
    Map<String, Object?>? extensionFields,
  }) => TableDocument(
    id: id,
    role: role ?? this.role,
    title: title ?? this.title,
    revision: revision ?? this.revision,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    body: body ?? this.body,
    schemaVersion: schemaVersion,
    deleted: deleted ?? this.deleted,
    fields: fields ?? this.fields,
    extensionFields: extensionFields ?? this.extensionFields,
  );
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

  TableEntryDocument copyWith({
    TableContentType? type,
    String? tableId,
    String? title,
    int? revision,
    DateTime? updatedAt,
    String? body,
    bool? deleted,
    List<String>? tags,
    List<String>? links,
    Object? due = _tableUnset,
    bool? done,
    Object? start = _tableUnset,
    Object? end = _tableUnset,
    bool? allDay,
    Object? recurrence = _tableUnset,
    Object? occurredAt = _tableUnset,
    List<ScheduleChange>? affects,
    Map<String, Object?>? customValues,
    Map<String, Object?>? extensionFields,
  }) => TableEntryDocument(
    id: id,
    type: type ?? this.type,
    tableId: tableId ?? this.tableId,
    title: title ?? this.title,
    revision: revision ?? this.revision,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    body: body ?? this.body,
    schemaVersion: schemaVersion,
    deleted: deleted ?? this.deleted,
    tags: tags ?? this.tags,
    links: links ?? this.links,
    due: identical(due, _tableUnset) ? this.due : due as DateTime?,
    done: done ?? this.done,
    start: identical(start, _tableUnset) ? this.start : start as DateTime?,
    end: identical(end, _tableUnset) ? this.end : end as DateTime?,
    allDay: allDay ?? this.allDay,
    recurrence: identical(recurrence, _tableUnset)
        ? this.recurrence
        : recurrence as String?,
    occurredAt: identical(occurredAt, _tableUnset)
        ? this.occurredAt
        : occurredAt as DateTime?,
    affects: affects ?? this.affects,
    customValues: customValues ?? this.customValues,
    extensionFields: extensionFields ?? this.extensionFields,
  );
}

const _tableUnset = Object();

enum TableRecoveryScope { entry, table, scheduleChange }

enum TableRecoveryStatus {
  prepared,
  active,
  restoring,
  restored,
  expired,
  failed,
}

class TableRecoveryBatch {
  const TableRecoveryBatch({
    required this.id,
    required this.scope,
    required this.tableId,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.manifestJson,
    this.error,
  });

  final String id;
  final TableRecoveryScope scope;
  final String tableId;
  final TableRecoveryStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String manifestJson;
  final String? error;

  TableRecoveryBatch copyWith({
    TableRecoveryStatus? status,
    String? manifestJson,
    Object? error = _recoveryUnset,
  }) => TableRecoveryBatch(
    id: id,
    scope: scope,
    tableId: tableId,
    status: status ?? this.status,
    createdAt: createdAt,
    expiresAt: expiresAt,
    manifestJson: manifestJson ?? this.manifestJson,
    error: identical(error, _recoveryUnset) ? this.error : error as String?,
  );
}

const _recoveryUnset = Object();
