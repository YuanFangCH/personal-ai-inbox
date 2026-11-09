import 'dart:convert';

import '../../core/table_models.dart';

const int widgetSchemaVersion = 1;

enum WidgetSourceMode {
  selectedTables('selected_tables'),
  allTables('all_tables');

  const WidgetSourceMode(this.wireName);

  final String wireName;

  static WidgetSourceMode parse(Object? value) => _enumByWireName(
    WidgetSourceMode.values,
    value,
    (item) => item.wireName,
    'source_mode',
  );
}

enum WidgetTheme {
  system('system'),
  light('light'),
  dark('dark');

  const WidgetTheme(this.wireName);

  final String wireName;

  static WidgetTheme parse(Object? value) => _enumByWireName(
    WidgetTheme.values,
    value,
    (item) => item.wireName,
    'theme',
  );
}

enum WidgetVisibility {
  hidden('hidden'),
  titles('titles'),
  fields('fields');

  const WidgetVisibility(this.wireName);

  final String wireName;

  static WidgetVisibility parse(Object? value) => _enumByWireName(
    WidgetVisibility.values,
    value,
    (item) => item.wireName,
    'visibility',
  );
}

enum WidgetTodoState {
  any('any'),
  open('open'),
  done('done');

  const WidgetTodoState(this.wireName);

  final String wireName;

  static WidgetTodoState parse(Object? value) => _enumByWireName(
    WidgetTodoState.values,
    value,
    (item) => item.wireName,
    'todo_state',
  );
}

enum WidgetSortKey {
  updatedAt('updated_at'),
  businessTime('business_time'),
  title('title');

  const WidgetSortKey(this.wireName);

  final String wireName;

  static WidgetSortKey parse(Object? value) => _enumByWireName(
    WidgetSortKey.values,
    value,
    (item) => item.wireName,
    'sort.key',
  );
}

enum WidgetSortDirection {
  asc('asc'),
  desc('desc');

  const WidgetSortDirection(this.wireName);

  final String wireName;

  static WidgetSortDirection parse(Object? value) => _enumByWireName(
    WidgetSortDirection.values,
    value,
    (item) => item.wireName,
    'sort.direction',
  );
}

enum WidgetBuiltinField {
  time('builtin:time'),
  type('builtin:type'),
  status('builtin:status');

  const WidgetBuiltinField(this.wireName);

  final String wireName;
}

enum WidgetCardState {
  ready('ready'),
  empty('empty'),
  blocked('blocked'),
  error('error'),
  archived('archived');

  const WidgetCardState(this.wireName);

  final String wireName;

  static WidgetCardState parse(Object? value) => _enumByWireName(
    WidgetCardState.values,
    value,
    (item) => item.wireName,
    'state',
  );
}

enum WidgetRowKind {
  section('section'),
  entry('entry');

  const WidgetRowKind(this.wireName);

  final String wireName;

  static WidgetRowKind parse(Object? value) => _enumByWireName(
    WidgetRowKind.values,
    value,
    (item) => item.wireName,
    'row.kind',
  );
}

enum CardCommandKind {
  create('create'),
  replace('replace'),
  archive('archive'),
  restore('restore'),
  setVisibility('set_visibility'),
  undo('undo');

  const CardCommandKind(this.wireName);

  final String wireName;

  static CardCommandKind parse(Object? value) => _enumByWireName(
    CardCommandKind.values,
    value,
    (item) => item.wireName,
    'operation',
  );
}

enum CardWriteStatus {
  applied('applied'),
  failed('failed');

  const CardWriteStatus(this.wireName);

  final String wireName;

  static CardWriteStatus parse(Object? value) => _enumByWireName(
    CardWriteStatus.values,
    value,
    (item) => item.wireName,
    'status',
  );
}

enum WidgetCommandError {
  invalidArgument('invalid_argument'),
  notFound('not_found'),
  revisionConflict('revision_conflict'),
  forbidden('forbidden'),
  operationConflict('operation_conflict'),
  storageError('storage_error');

  const WidgetCommandError(this.wireName);

  final String wireName;

  static WidgetCommandError parse(Object? value) => _enumByWireName(
    WidgetCommandError.values,
    value,
    (item) => item.wireName,
    'error',
  );
}

enum WidgetPublishStatus {
  pending('pending'),
  published('published'),
  failed('failed'),
  cleared('cleared'),
  blocked('blocked');

  const WidgetPublishStatus(this.wireName);

  final String wireName;

  static WidgetPublishStatus parse(Object? value) => _enumByWireName(
    WidgetPublishStatus.values,
    value,
    (item) => item.wireName,
    'publish_status',
  );
}

class WidgetContractException implements Exception {
  const WidgetContractException(this.error, this.message);

  final WidgetCommandError error;
  final String message;

  @override
  String toString() => message;
}

class WidgetField {
  const WidgetField.builtin(WidgetBuiltinField field)
    : builtin = field,
      customFieldId = null;

  factory WidgetField.custom(String fieldId) {
    _requireNonEmpty(fieldId, 'custom field id');
    return WidgetField._custom(fieldId);
  }

  const WidgetField._custom(String this.customFieldId) : builtin = null;

  final WidgetBuiltinField? builtin;
  final String? customFieldId;

  bool get isBuiltin => builtin != null;

  String get wireName => builtin?.wireName ?? 'custom:$customFieldId';

  static WidgetField parse(Object? value) {
    if (value is WidgetField) return value;
    final source = _requireString(value, 'field');
    for (final field in WidgetBuiltinField.values) {
      if (source == field.wireName) return WidgetField.builtin(field);
    }
    if (source.startsWith('custom:')) {
      return WidgetField.custom(source.substring('custom:'.length));
    }
    throw FormatException('Unsupported widget field: $source');
  }

  String toJson() => wireName;
}

class WidgetSort {
  const WidgetSort({
    this.key = WidgetSortKey.updatedAt,
    this.direction = WidgetSortDirection.desc,
  });

  const WidgetSort.updatedAtDescending()
    : key = WidgetSortKey.updatedAt,
      direction = WidgetSortDirection.desc;

  final WidgetSortKey key;
  final WidgetSortDirection direction;

  static WidgetSort parse(Object? value) {
    if (value is WidgetSort) return value;
    final json = _requireMap(value, 'sort');
    return WidgetSort(
      key: WidgetSortKey.parse(json['key']),
      direction: WidgetSortDirection.parse(json['direction']),
    );
  }

  Map<String, Object?> toJson() => {
    'key': key.wireName,
    'direction': direction.wireName,
  };
}

class SectionSpec {
  factory SectionSpec({
    required String tableId,
    String? label,
    List<TableContentType> types = const [
      TableContentType.note,
      TableContentType.todo,
      TableContentType.schedule,
      TableContentType.event,
    ],
    WidgetTodoState todoState = WidgetTodoState.any,
    int? daysAhead,
    WidgetSort sort = const WidgetSort.updatedAtDescending(),
    int limit = 4,
    List<WidgetField> fields = const [],
  }) {
    _requireNonEmpty(tableId, 'table_id');
    if (label != null && label.trim().isEmpty) {
      throw const FormatException('label must not be empty');
    }
    if (types.isEmpty) {
      throw const FormatException('types must not be empty');
    }
    if (daysAhead != null && daysAhead < 1) {
      throw const FormatException('days_ahead must be at least 1');
    }
    if (limit < 1 || limit > 10) {
      throw const FormatException('limit must be between 1 and 10');
    }
    if (fields.length > 3) {
      throw const FormatException('fields must contain at most 3 items');
    }
    return SectionSpec._(
      tableId: tableId,
      label: label,
      types: List.unmodifiable(types.toSet()),
      todoState: todoState,
      daysAhead: daysAhead,
      sort: sort,
      limit: limit,
      fields: List.unmodifiable(fields),
    );
  }

  const SectionSpec._({
    required this.tableId,
    required this.label,
    required this.types,
    required this.todoState,
    required this.daysAhead,
    required this.sort,
    required this.limit,
    required this.fields,
  });

  final String tableId;
  final String? label;
  final List<TableContentType> types;
  final WidgetTodoState todoState;
  final int? daysAhead;
  final WidgetSort sort;
  final int limit;
  final List<WidgetField> fields;

  static SectionSpec parse(Object? value) {
    if (value is SectionSpec) return value;
    final json = _requireMap(value, 'section');
    final rawTypes = json['types'];
    final types = rawTypes == null
        ? const [
            TableContentType.note,
            TableContentType.todo,
            TableContentType.schedule,
            TableContentType.event,
          ]
        : _requireList(rawTypes, 'types')
              .map(
                (item) => TableContentType.parse(_requireString(item, 'type')),
              )
              .toList(growable: false);
    return SectionSpec(
      tableId: _requireString(json['table_id'], 'table_id'),
      label: _optionalString(json['label'], 'label'),
      types: types,
      todoState: json['todo_state'] == null
          ? WidgetTodoState.any
          : WidgetTodoState.parse(json['todo_state']),
      daysAhead: _optionalInt(json['days_ahead'], 'days_ahead'),
      sort: json['sort'] == null
          ? const WidgetSort.updatedAtDescending()
          : WidgetSort.parse(json['sort']),
      limit: _optionalInt(json['limit'], 'limit') ?? 4,
      fields: json['fields'] == null
          ? const []
          : _requireList(
              json['fields'],
              'fields',
            ).map(WidgetField.parse).toList(growable: false),
    );
  }

  Map<String, Object?> toJson() => {
    'table_id': tableId,
    if (label != null) 'label': label,
    'types': types.map((item) => item.wireName).toList(growable: false),
    'todo_state': todoState.wireName,
    if (daysAhead != null) 'days_ahead': daysAhead,
    'sort': sort.toJson(),
    'limit': limit,
    'fields': fields.map((item) => item.wireName).toList(growable: false),
  };
}

class CardSpec {
  factory CardSpec({
    required String title,
    WidgetSourceMode sourceMode = WidgetSourceMode.selectedTables,
    List<SectionSpec> sections = const [],
    List<String> excludedTableIds = const [],
    bool hideEmptySections = false,
    WidgetTheme theme = WidgetTheme.system,
  }) {
    if (title.trim().isEmpty) {
      throw const FormatException('title must not be empty');
    }
    final seenTables = <String>{};
    for (final section in sections) {
      if (!seenTables.add(section.tableId)) {
        throw FormatException('Duplicate section table_id: ${section.tableId}');
      }
    }
    return CardSpec._(
      title: title,
      sourceMode: sourceMode,
      sections: List.unmodifiable(sections),
      excludedTableIds: List.unmodifiable(excludedTableIds.toSet()),
      hideEmptySections: hideEmptySections,
      theme: theme,
    );
  }

  const CardSpec._({
    required this.title,
    required this.sourceMode,
    required this.sections,
    required this.excludedTableIds,
    required this.hideEmptySections,
    required this.theme,
  });

  final String title;
  final WidgetSourceMode sourceMode;
  final List<SectionSpec> sections;
  final List<String> excludedTableIds;
  final bool hideEmptySections;
  final WidgetTheme theme;

  static CardSpec parse(Object? value) {
    if (value is CardSpec) return value;
    final json = _requireMap(value, 'spec');
    return CardSpec(
      title: _requireString(json['title'], 'title'),
      sourceMode: json['source_mode'] == null
          ? WidgetSourceMode.selectedTables
          : WidgetSourceMode.parse(json['source_mode']),
      sections: json['sections'] == null
          ? const []
          : _requireList(
              json['sections'],
              'sections',
            ).map(SectionSpec.parse).toList(growable: false),
      excludedTableIds: json['excluded_table_ids'] == null
          ? const []
          : _requireList(
              json['excluded_table_ids'],
              'excluded_table_ids',
            ).map((item) => _requireString(item, 'excluded_table_id')).toList(),
      hideEmptySections:
          _optionalBool(json['hide_empty_sections'], 'hide_empty_sections') ??
          false,
      theme: json['theme'] == null
          ? WidgetTheme.system
          : WidgetTheme.parse(json['theme']),
    );
  }

  Map<String, Object?> toJson() => {
    'title': title,
    'source_mode': sourceMode.wireName,
    'sections': sections.map((item) => item.toJson()).toList(growable: false),
    'excluded_table_ids': excludedTableIds,
    'hide_empty_sections': hideEmptySections,
    'theme': theme.wireName,
  };

  Set<String> get referencedTableIds => {
    ...sections.map((section) => section.tableId),
    ...excludedTableIds,
  };
}

class CardDefinition {
  const CardDefinition({
    required this.cardId,
    required this.revision,
    required this.archived,
    required this.spec,
    this.visibility = WidgetVisibility.titles,
    this.schemaVersion = widgetSchemaVersion,
  });

  final int schemaVersion;
  final String cardId;
  final int revision;
  final bool archived;
  final CardSpec spec;
  final WidgetVisibility visibility;

  static CardDefinition parse(Object? value) {
    if (value is CardDefinition) return value;
    final json = _requireMap(value, 'card');
    final schemaVersion = _optionalInt(
      json['schema_version'],
      'schema_version',
    );
    if (schemaVersion != widgetSchemaVersion) {
      throw FormatException('Unsupported widget schema: $schemaVersion');
    }
    final cardId = _requireString(json['card_id'], 'card_id');
    final revision = _requireInt(json['revision'], 'revision');
    if (revision < 1) {
      throw const FormatException('revision must be at least 1');
    }
    return CardDefinition(
      cardId: cardId,
      revision: revision,
      archived: _requireBool(json['archived'], 'archived'),
      spec: CardSpec.parse(json['spec']),
      visibility: json['visibility'] == null
          ? WidgetVisibility.titles
          : WidgetVisibility.parse(json['visibility']),
    );
  }

  CardDefinition copyWith({
    int? revision,
    bool? archived,
    CardSpec? spec,
    WidgetVisibility? visibility,
  }) => CardDefinition(
    cardId: cardId,
    revision: revision ?? this.revision,
    archived: archived ?? this.archived,
    spec: spec ?? this.spec,
    visibility: visibility ?? this.visibility,
  );

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'card_id': cardId,
    'revision': revision,
    'archived': archived,
    'visibility': visibility.wireName,
    'spec': spec.toJson(),
  };
}

class CardCommand {
  const CardCommand._({
    required this.kind,
    this.cardId,
    this.expectedRevision,
    this.spec,
    this.visibility,
    this.targetOperationId,
  });

  const CardCommand.create(CardSpec spec)
    : this._(kind: CardCommandKind.create, spec: spec);

  const CardCommand.replace({
    required String cardId,
    required int expectedRevision,
    required CardSpec spec,
  }) : this._(
         kind: CardCommandKind.replace,
         cardId: cardId,
         expectedRevision: expectedRevision,
         spec: spec,
       );

  const CardCommand.archive({
    required String cardId,
    required int expectedRevision,
  }) : this._(
         kind: CardCommandKind.archive,
         cardId: cardId,
         expectedRevision: expectedRevision,
       );

  const CardCommand.restore({
    required String cardId,
    required int expectedRevision,
  }) : this._(
         kind: CardCommandKind.restore,
         cardId: cardId,
         expectedRevision: expectedRevision,
       );

  const CardCommand.setVisibility({
    required String cardId,
    required int expectedRevision,
    required WidgetVisibility visibility,
  }) : this._(
         kind: CardCommandKind.setVisibility,
         cardId: cardId,
         expectedRevision: expectedRevision,
         visibility: visibility,
       );

  const CardCommand.undo({
    required String cardId,
    required int expectedRevision,
    required String targetOperationId,
  }) : this._(
         kind: CardCommandKind.undo,
         cardId: cardId,
         expectedRevision: expectedRevision,
         targetOperationId: targetOperationId,
       );

  final CardCommandKind kind;
  final String? cardId;
  final int? expectedRevision;
  final CardSpec? spec;
  final WidgetVisibility? visibility;
  final String? targetOperationId;

  static CardCommand parse(Object? value) {
    if (value is CardCommand) return value;
    final json = _requireMap(value, 'command');
    final kind = CardCommandKind.parse(json['operation']);
    final cardId = _optionalString(json['card_id'], 'card_id');
    final expectedRevision = _optionalInt(
      json['expected_revision'],
      'expected_revision',
    );
    switch (kind) {
      case CardCommandKind.create:
        return CardCommand.create(CardSpec.parse(json['spec']));
      case CardCommandKind.replace:
        _requireCommandTarget(cardId, expectedRevision);
        return CardCommand.replace(
          cardId: cardId!,
          expectedRevision: expectedRevision!,
          spec: CardSpec.parse(json['spec']),
        );
      case CardCommandKind.archive:
        _requireCommandTarget(cardId, expectedRevision);
        return CardCommand.archive(
          cardId: cardId!,
          expectedRevision: expectedRevision!,
        );
      case CardCommandKind.restore:
        _requireCommandTarget(cardId, expectedRevision);
        return CardCommand.restore(
          cardId: cardId!,
          expectedRevision: expectedRevision!,
        );
      case CardCommandKind.setVisibility:
        _requireCommandTarget(cardId, expectedRevision);
        return CardCommand.setVisibility(
          cardId: cardId!,
          expectedRevision: expectedRevision!,
          visibility: WidgetVisibility.parse(json['visibility']),
        );
      case CardCommandKind.undo:
        _requireCommandTarget(cardId, expectedRevision);
        final targetOperationId = _requireString(
          json['target_operation_id'],
          'target_operation_id',
        );
        return CardCommand.undo(
          cardId: cardId!,
          expectedRevision: expectedRevision!,
          targetOperationId: targetOperationId,
        );
    }
  }

  Map<String, Object?> toJson() => {
    'operation': kind.wireName,
    if (cardId != null) 'card_id': cardId,
    if (expectedRevision != null) 'expected_revision': expectedRevision,
    if (spec != null) 'spec': spec!.toJson(),
    if (visibility != null) 'visibility': visibility!.wireName,
    if (targetOperationId != null) 'target_operation_id': targetOperationId,
  };

  String get normalizedSignature => jsonEncode(_canonicalize(toJson()));
}

class CardSummary {
  const CardSummary({
    required this.cardId,
    required this.revision,
    required this.archived,
    required this.visibility,
    required this.spec,
  });

  final String cardId;
  final int revision;
  final bool archived;
  final WidgetVisibility visibility;
  final CardSpec spec;

  static CardSummary parse(Object? value) {
    final json = _requireMap(value, 'card summary');
    return CardSummary(
      cardId: _requireString(json['card_id'], 'card_id'),
      revision: _requireInt(json['revision'], 'revision'),
      archived: _requireBool(json['archived'], 'archived'),
      visibility: WidgetVisibility.parse(json['visibility']),
      spec: CardSpec.parse(json['spec']),
    );
  }

  Map<String, Object?> toJson() => {
    'card_id': cardId,
    'revision': revision,
    'archived': archived,
    'visibility': visibility.wireName,
    'spec': spec.toJson(),
  };
}

class WidgetRow {
  const WidgetRow.section({
    required this.tableId,
    required this.title,
    required this.count,
  }) : kind = WidgetRowKind.section,
       entryId = null,
       detail = null;

  const WidgetRow.entry({
    required this.tableId,
    required this.entryId,
    required this.title,
    this.detail,
  }) : kind = WidgetRowKind.entry,
       count = null;

  final WidgetRowKind kind;
  final String tableId;
  final String? entryId;
  final String title;
  final String? detail;
  final int? count;

  WidgetRow withoutDetail() =>
      WidgetRow.entry(tableId: tableId, entryId: entryId!, title: title);

  static WidgetRow parse(Object? value) {
    final json = _requireMap(value, 'row');
    final kind = WidgetRowKind.parse(json['kind']);
    final tableId = _requireString(json['table_id'], 'row.table_id');
    final title = _requireString(json['title'], 'row.title');
    switch (kind) {
      case WidgetRowKind.section:
        return WidgetRow.section(
          tableId: tableId,
          title: title,
          count: _requireInt(json['count'], 'row.count'),
        );
      case WidgetRowKind.entry:
        return WidgetRow.entry(
          tableId: tableId,
          entryId: _requireString(json['entry_id'], 'row.entry_id'),
          title: title,
          detail: _optionalString(json['detail'], 'row.detail'),
        );
    }
  }

  Map<String, Object?> toJson() => {
    'kind': kind.wireName,
    'table_id': tableId,
    if (entryId != null) 'entry_id': entryId,
    'title': title,
    if (detail != null) 'detail': detail,
    if (count != null) 'count': count,
  };
}

class WidgetSnapshot {
  WidgetSnapshot({
    required this.cardId,
    required this.revision,
    required this.title,
    required this.theme,
    required this.state,
    required this.generatedAtMs,
    required this.dataDay,
    required List<WidgetRow> rows,
    required this.hasMore,
  }) : rows = List.unmodifiable(rows);

  final String cardId;
  final int revision;
  final String title;
  final WidgetTheme theme;
  final WidgetCardState state;
  final int generatedAtMs;
  final String? dataDay;
  final List<WidgetRow> rows;
  final bool hasMore;

  static WidgetSnapshot parse(Object? value) {
    final json = _requireMap(value, 'snapshot card');
    return WidgetSnapshot(
      cardId: _requireString(json['card_id'], 'card_id'),
      revision: _requireInt(json['revision'], 'revision'),
      title: _requireString(json['title'], 'title'),
      theme: WidgetTheme.parse(json['theme']),
      state: WidgetCardState.parse(json['state']),
      generatedAtMs: _requireInt(json['generated_at_ms'], 'generated_at_ms'),
      dataDay: _optionalString(json['data_day'], 'data_day'),
      rows: _requireList(
        json['rows'],
        'rows',
      ).map(WidgetRow.parse).toList(growable: false),
      hasMore: _requireBool(json['has_more'], 'has_more'),
    );
  }

  Map<String, Object?> toJson() => {
    'card_id': cardId,
    'revision': revision,
    'title': title,
    'theme': theme.wireName,
    'state': state.wireName,
    'generated_at_ms': generatedAtMs,
    if (dataDay != null) 'data_day': dataDay,
    'rows': rows.map((row) => row.toJson()).toList(growable: false),
    'has_more': hasMore,
  };
}

class WidgetSnapshotEnvelope {
  WidgetSnapshotEnvelope({required List<WidgetSnapshot> cards})
    : schemaVersion = widgetSchemaVersion,
      cards = List.unmodifiable(cards);

  const WidgetSnapshotEnvelope.empty()
    : cards = const [],
      schemaVersion = widgetSchemaVersion;

  final int schemaVersion;
  final List<WidgetSnapshot> cards;

  static WidgetSnapshotEnvelope parse(Object? value) {
    if (value is WidgetSnapshotEnvelope) return value;
    final json = _requireMap(value, 'snapshot envelope');
    final schemaVersion = _optionalInt(
      json['schema_version'],
      'schema_version',
    );
    if (schemaVersion != widgetSchemaVersion) {
      throw FormatException('Unsupported widget schema: $schemaVersion');
    }
    return WidgetSnapshotEnvelope(
      cards: _requireList(
        json['cards'],
        'cards',
      ).map(WidgetSnapshot.parse).toList(growable: false),
    );
  }

  static WidgetSnapshotEnvelope parseJson(String source) =>
      WidgetSnapshotEnvelope.parse(jsonDecode(source));

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'cards': cards.map((card) => card.toJson()).toList(growable: false),
  };

  String toJsonString() => jsonEncode(toJson());
}

class CardPreview {
  CardPreview({
    required this.snapshot,
    required this.matchingCount,
    required List<String> warnings,
  }) : warnings = List.unmodifiable(warnings);

  final WidgetSnapshot snapshot;
  final int matchingCount;
  final List<String> warnings;

  static CardPreview parse(Object? value) {
    final json = _requireMap(value, 'preview');
    return CardPreview(
      snapshot: WidgetSnapshot.parse(json['sample']),
      matchingCount: _requireInt(json['matching_count'], 'matching_count'),
      warnings: _requireList(
        json['warnings'],
        'warnings',
      ).map((item) => _requireString(item, 'warning')).toList(growable: false),
    );
  }

  Map<String, Object?> toJson() => {
    'sample': snapshot.toJson(),
    'matching_count': matchingCount,
    'warnings': warnings,
  };
}

class CardWriteReceipt {
  const CardWriteReceipt({
    required this.operationId,
    required this.status,
    required this.cardId,
    required this.revision,
    required this.publishStatus,
    this.error,
    this.message,
  });

  final String operationId;
  final CardWriteStatus status;
  final String cardId;
  final int revision;
  final WidgetPublishStatus publishStatus;
  final WidgetCommandError? error;
  final String? message;

  bool get succeeded => status == CardWriteStatus.applied && error == null;

  static CardWriteReceipt parse(Object? value) {
    final json = _requireMap(value, 'receipt');
    return CardWriteReceipt(
      operationId: _requireString(json['operation_id'], 'operation_id'),
      status: CardWriteStatus.parse(json['status']),
      cardId: _requireString(json['card_id'], 'card_id'),
      revision: _requireInt(json['revision'], 'revision'),
      publishStatus: WidgetPublishStatus.parse(json['publish_status']),
      error: json['error'] == null
          ? null
          : WidgetCommandError.parse(json['error']),
      message: _optionalString(json['message'], 'message'),
    );
  }

  CardWriteReceipt copyWith({
    CardWriteStatus? status,
    WidgetPublishStatus? publishStatus,
    Object? error = _contractUnset,
    Object? message = _contractUnset,
  }) => CardWriteReceipt(
    operationId: operationId,
    status: status ?? this.status,
    cardId: cardId,
    revision: revision,
    publishStatus: publishStatus ?? this.publishStatus,
    error: identical(error, _contractUnset)
        ? this.error
        : error as WidgetCommandError?,
    message: identical(message, _contractUnset)
        ? this.message
        : message as String?,
  );

  Map<String, Object?> toJson() => {
    'operation_id': operationId,
    'status': status.wireName,
    'card_id': cardId,
    'revision': revision,
    'publish_status': publishStatus.wireName,
    if (error != null) 'error': error!.wireName,
    if (message != null) 'message': message,
  };
}

class WidgetPublishResult {
  const WidgetPublishResult({
    required this.status,
    this.error,
    this.submittedCount = 0,
    this.failedCount = 0,
  }) : assert(submittedCount >= 0),
       assert(failedCount >= 0);

  const WidgetPublishResult.published({
    this.submittedCount = 0,
    this.failedCount = 0,
  }) : status = WidgetPublishStatus.published,
       error = null,
       assert(submittedCount >= 0),
       assert(failedCount >= 0);

  const WidgetPublishResult.pending({
    this.submittedCount = 0,
    this.failedCount = 0,
  }) : status = WidgetPublishStatus.pending,
       error = null,
       assert(submittedCount >= 0),
       assert(failedCount >= 0);

  const WidgetPublishResult.failed(
    String this.error, {
    this.submittedCount = 0,
    this.failedCount = 0,
  }) : status = WidgetPublishStatus.failed,
       assert(submittedCount >= 0),
       assert(failedCount >= 0);

  const WidgetPublishResult.cleared({
    this.submittedCount = 0,
    this.failedCount = 0,
  }) : status = WidgetPublishStatus.cleared,
       error = null,
       assert(submittedCount >= 0),
       assert(failedCount >= 0);

  const WidgetPublishResult.blocked({
    this.submittedCount = 0,
    this.failedCount = 0,
  }) : status = WidgetPublishStatus.blocked,
       error = null,
       assert(submittedCount >= 0),
       assert(failedCount >= 0);

  final WidgetPublishStatus status;
  final String? error;
  final int submittedCount;
  final int failedCount;

  static WidgetPublishResult parse(Object? value) {
    final json = _requireMap(value, 'publish result');
    return WidgetPublishResult(
      status: WidgetPublishStatus.parse(json['status']),
      error: _optionalString(json['error'], 'error'),
      submittedCount:
          _optionalInt(json['submitted_count'], 'submitted_count') ?? 0,
      failedCount: _optionalInt(json['failed_count'], 'failed_count') ?? 0,
    );
  }

  Map<String, Object?> toJson() => {
    'status': status.wireName,
    if (error != null) 'error': error,
    'submitted_count': submittedCount,
    'failed_count': failedCount,
  };
}

CardSpec parseCardSpec(Object? value) => CardSpec.parse(value);

CardDefinition parseCardDefinition(Object? value) =>
    CardDefinition.parse(value);

CardCommand parseCardCommand(Object? value) => CardCommand.parse(value);

WidgetSnapshot parseWidgetSnapshot(Object? value) =>
    WidgetSnapshot.parse(value);

WidgetSnapshotEnvelope parseWidgetSnapshotEnvelope(Object? value) =>
    WidgetSnapshotEnvelope.parse(value);

WidgetSnapshotEnvelope decodeWidgetSnapshotEnvelope(String source) =>
    WidgetSnapshotEnvelope.parseJson(source);

Map<String, Object?> _requireMap(Object? value, String field) {
  Object? decoded = value;
  if (decoded is String) {
    try {
      decoded = jsonDecode(decoded);
    } on FormatException {
      throw FormatException('$field must be a JSON object');
    }
  }
  if (decoded is Map<String, Object?>) return decoded;
  if (decoded is Map) {
    return decoded.map((key, item) => MapEntry(key.toString(), item));
  }
  throw FormatException('$field must be an object');
}

List<Object?> _requireList(Object? value, String field) {
  if (value is List) return value.cast<Object?>();
  throw FormatException('$field must be a list');
}

String _requireString(Object? value, String field) {
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('$field must be a non-empty string');
}

String? _optionalString(Object? value, String field) {
  if (value == null) return null;
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('$field must be a non-empty string');
}

int _requireInt(Object? value, String field) {
  if (value is int) return value;
  throw FormatException('$field must be an integer');
}

int? _optionalInt(Object? value, String field) {
  if (value == null) return null;
  return _requireInt(value, field);
}

bool _requireBool(Object? value, String field) {
  if (value is bool) return value;
  throw FormatException('$field must be a boolean');
}

bool? _optionalBool(Object? value, String field) {
  if (value == null) return null;
  return _requireBool(value, field);
}

void _requireNonEmpty(String value, String field) {
  if (value.trim().isEmpty) {
    throw FormatException('$field must not be empty');
  }
}

void _requireCommandTarget(String? cardId, int? expectedRevision) {
  if (cardId == null || cardId.trim().isEmpty) {
    throw const FormatException('card_id is required');
  }
  if (expectedRevision == null || expectedRevision < 1) {
    throw const FormatException('expected_revision must be at least 1');
  }
}

T _enumByWireName<T>(
  Iterable<T> values,
  Object? raw,
  String Function(T value) wireName,
  String field,
) {
  final source = _requireString(raw, field);
  for (final value in values) {
    if (wireName(value) == source) return value;
  }
  throw FormatException('Unsupported $field: $source');
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: _canonicalize(value[key])};
  }
  if (value is Iterable) {
    return value.map(_canonicalize).toList(growable: false);
  }
  return value;
}

const _contractUnset = Object();
