import 'dart:convert';

import '../../core/table_models.dart';
import '../../data/table_repository.dart';
import 'home_widget_contract.dart';

WidgetSnapshot projectCard(
  CardDefinition card, {
  required TableContentSnapshot source,
  required DateTime localNow,
}) => projectCardDetails(card, source: source, localNow: localNow).snapshot;

class WidgetProjection {
  WidgetProjection({
    required this.snapshot,
    required this.matchingCount,
    required List<String> warnings,
  }) : warnings = List.unmodifiable(warnings);

  final WidgetSnapshot snapshot;
  final int matchingCount;
  final List<String> warnings;
}

WidgetProjection projectCardDetails(
  CardDefinition card, {
  required TableContentSnapshot source,
  required DateTime localNow,
}) {
  if (card.archived) {
    return WidgetProjection(
      snapshot: WidgetSnapshot(
        cardId: card.cardId,
        revision: card.revision,
        title: card.spec.title,
        theme: card.spec.theme,
        state: WidgetCardState.archived,
        generatedAtMs: localNow.millisecondsSinceEpoch,
        dataDay: null,
        rows: const [],
        hasMore: false,
      ),
      matchingCount: 0,
      warnings: const [],
    );
  }

  final tablesById = {
    for (final table in source.tables)
      if (!table.deleted) table.id: table,
  };
  final entriesByTable = <String, List<TableEntryDocument>>{};
  for (final entry in source.entries) {
    if (entry.deleted) continue;
    (entriesByTable[entry.tableId] ??= []).add(entry);
  }

  final plans = _sectionPlans(card.spec, source, tablesById);
  final warnings = <String>[];
  final rows = <WidgetRow>[];
  var matchingCount = 0;

  for (final plan in plans) {
    final section = plan.spec;
    final table = plan.table;
    if (table == null) {
      warnings.add('数据表 ${section.tableId} 已删除或不可用。');
      continue;
    }

    final invalidFields = <WidgetField>[];
    final fieldDefinitions = {
      for (final field in table.fields) field.id: field,
    };
    for (final field in section.fields) {
      final customFieldId = field.customFieldId;
      if (customFieldId != null &&
          !fieldDefinitions.containsKey(customFieldId)) {
        invalidFields.add(field);
        warnings.add('字段 custom:$customFieldId 在数据表 ${table.id} 中不可用。');
      }
    }
    final activeFields = section.fields
        .where((field) => !invalidFields.contains(field))
        .toList(growable: false);

    final matching =
        (entriesByTable[table.id] ?? const <TableEntryDocument>[])
            .where((entry) => _matchesSection(entry, section, localNow))
            .toList(growable: false)
          ..sort((left, right) => _compareEntries(left, right, section.sort));
    matchingCount += matching.length;

    if (matching.isEmpty && card.spec.hideEmptySections) continue;
    rows.add(
      WidgetRow.section(
        tableId: table.id,
        title: section.label ?? table.title,
        count: matching.length,
      ),
    );
    for (final entry in matching.take(section.limit)) {
      rows.add(
        WidgetRow.entry(
          tableId: table.id,
          entryId: entry.id,
          title: _short(entry.title, 80),
          detail: _entryDetail(entry, table, activeFields, section.fields),
        ),
      );
    }
  }

  final usesDateFilter = plans.any((plan) => plan.spec.daysAhead != null);
  final allRows = List<WidgetRow>.unmodifiable(rows);
  final cappedRows = allRows.length > 48
      ? _retainSectionHeaders(allRows, 48)
      : allRows;
  var snapshot = WidgetSnapshot(
    cardId: card.cardId,
    revision: card.revision,
    title: card.spec.title,
    theme: card.spec.theme,
    state: rows.isEmpty ? WidgetCardState.empty : WidgetCardState.ready,
    generatedAtMs: localNow.millisecondsSinceEpoch,
    dataDay: usesDateFilter ? _dataDay(localNow) : null,
    rows: cappedRows,
    hasMore: allRows.length > 48,
  );
  snapshot = _applyVisibility(snapshot, card.visibility);
  return WidgetProjection(
    snapshot: snapshot,
    matchingCount: matchingCount,
    warnings: warnings,
  );
}

WidgetSnapshot _applyVisibility(
  WidgetSnapshot snapshot,
  WidgetVisibility visibility,
) {
  switch (visibility) {
    case WidgetVisibility.hidden:
      return WidgetSnapshot(
        cardId: snapshot.cardId,
        revision: snapshot.revision,
        title: '桌面小组件',
        theme: snapshot.theme,
        state: WidgetCardState.empty,
        generatedAtMs: snapshot.generatedAtMs,
        dataDay: null,
        rows: const [],
        hasMore: false,
      );
    case WidgetVisibility.titles:
      return WidgetSnapshot(
        cardId: snapshot.cardId,
        revision: snapshot.revision,
        title: snapshot.title,
        theme: snapshot.theme,
        state: snapshot.state,
        generatedAtMs: snapshot.generatedAtMs,
        dataDay: snapshot.dataDay,
        rows: [
          for (final row in snapshot.rows)
            if (row.kind == WidgetRowKind.entry) row.withoutDetail() else row,
        ],
        hasMore: snapshot.hasMore,
      );
    case WidgetVisibility.fields:
      return snapshot;
  }
}

class _SectionPlan {
  const _SectionPlan({required this.spec, required this.table});

  final SectionSpec spec;
  final TableDocument? table;
}

List<_SectionPlan> _sectionPlans(
  CardSpec spec,
  TableContentSnapshot source,
  Map<String, TableDocument> tablesById,
) {
  if (spec.sourceMode == WidgetSourceMode.selectedTables) {
    return [
      for (final section in spec.sections)
        _SectionPlan(spec: section, table: tablesById[section.tableId]),
    ];
  }

  final excluded = spec.excludedTableIds.toSet();
  final configured = <String>{};
  final plans = <_SectionPlan>[];
  for (final section in spec.sections) {
    if (excluded.contains(section.tableId) ||
        !configured.add(section.tableId)) {
      continue;
    }
    plans.add(_SectionPlan(spec: section, table: tablesById[section.tableId]));
  }

  final remaining =
      source.tables
          .where(
            (table) =>
                !table.deleted &&
                !excluded.contains(table.id) &&
                !configured.contains(table.id),
          )
          .toList(growable: false)
        ..sort((left, right) {
          final title = left.title.toLowerCase().compareTo(
            right.title.toLowerCase(),
          );
          return title != 0 ? title : left.id.compareTo(right.id);
        });
  for (final table in remaining) {
    plans.add(
      _SectionPlan(
        spec: SectionSpec(tableId: table.id),
        table: table,
      ),
    );
  }
  return plans;
}

bool _matchesSection(
  TableEntryDocument entry,
  SectionSpec section,
  DateTime localNow,
) {
  if (!section.types.contains(entry.type)) return false;
  if (entry.type == TableContentType.todo) {
    if (section.todoState == WidgetTodoState.open && entry.done) return false;
    if (section.todoState == WidgetTodoState.done && !entry.done) return false;
  }
  final daysAhead = section.daysAhead;
  if (daysAhead == null) return true;
  final businessTime = _businessTime(entry);
  if (businessTime == null) return false;
  final start = DateTime(localNow.year, localNow.month, localNow.day);
  final end = DateTime(localNow.year, localNow.month, localNow.day + daysAhead);
  final localBusinessTime = businessTime.toLocal();
  return !localBusinessTime.isBefore(start) && localBusinessTime.isBefore(end);
}

int _compareEntries(
  TableEntryDocument left,
  TableEntryDocument right,
  WidgetSort sort,
) {
  if (sort.key == WidgetSortKey.businessTime) {
    final leftTime = _businessTime(left);
    final rightTime = _businessTime(right);
    if (leftTime == null && rightTime != null) return 1;
    if (leftTime != null && rightTime == null) return -1;
    if (leftTime != null && rightTime != null) {
      final comparison = leftTime.compareTo(rightTime);
      final directed = sort.direction == WidgetSortDirection.asc
          ? comparison
          : -comparison;
      if (directed != 0) return directed;
    }
    return left.id.compareTo(right.id);
  }
  final comparison = switch (sort.key) {
    WidgetSortKey.updatedAt => left.updatedAt.compareTo(right.updatedAt),
    WidgetSortKey.businessTime => 0,
    WidgetSortKey.title => left.title.compareTo(right.title),
  };
  final directed = sort.direction == WidgetSortDirection.asc
      ? comparison
      : -comparison;
  if (directed != 0) return directed;
  return left.id.compareTo(right.id);
}

DateTime? _businessTime(TableEntryDocument entry) {
  return switch (entry.type) {
    TableContentType.note => null,
    TableContentType.todo => entry.due,
    TableContentType.schedule => entry.start,
    TableContentType.event => entry.occurredAt,
  };
}

String? _entryDetail(
  TableEntryDocument entry,
  TableDocument table,
  List<WidgetField> fields,
  List<WidgetField> configuredFields,
) {
  if (configuredFields.isEmpty) {
    return switch (entry.type) {
      TableContentType.note => null,
      TableContentType.todo => entry.done ? '完成' : '未完成',
      TableContentType.schedule ||
      TableContentType.event => _formatBusinessTime(entry),
    };
  }

  final definitions = {for (final field in table.fields) field.id: field};
  final values = <String>[];
  for (final field in fields) {
    final builtin = field.builtin;
    if (builtin != null) {
      switch (builtin) {
        case WidgetBuiltinField.time:
          final formatted = _formatBusinessTime(entry);
          if (formatted != null) values.add(formatted);
        case WidgetBuiltinField.type:
          values.add(entry.type.wireName);
        case WidgetBuiltinField.status:
          if (entry.type == TableContentType.todo) {
            values.add(entry.done ? '完成' : '未完成');
          }
      }
      continue;
    }
    final customFieldId = field.customFieldId;
    final definition = definitions[customFieldId];
    final value = entry.customValues[customFieldId];
    if (definition == null || value == null) continue;
    values.add('${definition.name}: ${_formatCustomValue(value)}');
  }
  return values.isEmpty ? null : _short(values.join(' · '), 120);
}

String? _formatBusinessTime(TableEntryDocument entry) {
  final time = _businessTime(entry);
  if (time == null) return null;
  final local = time.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  if (entry.allDay) return '${local.year}-$month-$day';
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}

String _formatCustomValue(Object value) {
  if (value is List) {
    return value
        .map<String>((item) => _formatCustomValue(item as Object))
        .join('、');
  }
  if (value is DateTime) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
  return value.toString();
}

String _short(String value, int codeUnits) {
  final runes = value.runes.toList(growable: false);
  if (runes.length <= codeUnits) return value;
  return String.fromCharCodes(runes.take(codeUnits));
}

String _dataDay(DateTime localNow) {
  final local = localNow.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

WidgetSnapshotEnvelope constrainWidgetSnapshots(
  List<WidgetSnapshot> snapshots,
) {
  final constrained = [
    for (final snapshot in snapshots)
      if (snapshot.rows.length <= 48)
        snapshot
      else
        WidgetSnapshot(
          cardId: snapshot.cardId,
          revision: snapshot.revision,
          title: snapshot.title,
          theme: snapshot.theme,
          state: snapshot.state,
          generatedAtMs: snapshot.generatedAtMs,
          dataDay: snapshot.dataDay,
          rows: _retainSectionHeaders(snapshot.rows, 48),
          hasMore: true,
        ),
  ];
  var envelope = WidgetSnapshotEnvelope(cards: constrained);
  while (utf8.encode(envelope.toJsonString()).length > 512 * 1024) {
    var trimmed = false;
    for (var index = envelope.cards.length - 1; index >= 0; index--) {
      final card = envelope.cards[index];
      final rowIndex = card.rows.lastIndexWhere(
        (row) => row.kind == WidgetRowKind.entry,
      );
      if (rowIndex >= 0) {
        final rows = card.rows.toList()..removeAt(rowIndex);
        final cards = envelope.cards.toList()
          ..[index] = WidgetSnapshot(
            cardId: card.cardId,
            revision: card.revision,
            title: card.title,
            theme: card.theme,
            state: card.state,
            generatedAtMs: card.generatedAtMs,
            dataDay: card.dataDay,
            rows: rows,
            hasMore: true,
          );
        envelope = WidgetSnapshotEnvelope(cards: cards);
        trimmed = true;
        break;
      }
    }
    if (trimmed) continue;
    for (var index = envelope.cards.length - 1; index >= 0; index--) {
      final card = envelope.cards[index];
      if (card.rows.isEmpty) continue;
      final cards = envelope.cards.toList()
        ..[index] = WidgetSnapshot(
          cardId: card.cardId,
          revision: card.revision,
          title: card.title,
          theme: card.theme,
          state: card.state,
          generatedAtMs: card.generatedAtMs,
          dataDay: card.dataDay,
          rows: card.rows.take(card.rows.length - 1).toList(growable: false),
          hasMore: true,
        );
      envelope = WidgetSnapshotEnvelope(cards: cards);
      trimmed = true;
      break;
    }
    if (!trimmed) break;
  }
  return envelope;
}

List<WidgetRow> _retainSectionHeaders(List<WidgetRow> rows, int limit) {
  final sectionCount = rows
      .where((row) => row.kind == WidgetRowKind.section)
      .length;
  if (sectionCount >= limit) {
    return List.unmodifiable(
      rows.where((row) => row.kind == WidgetRowKind.section).take(limit),
    );
  }

  final retained = <WidgetRow>[];
  var remainingHeaders = sectionCount;
  for (final row in rows) {
    if (row.kind == WidgetRowKind.section) {
      retained.add(row);
      remainingHeaders--;
      continue;
    }
    if (retained.length < limit - remainingHeaders) retained.add(row);
  }
  return List.unmodifiable(retained);
}
