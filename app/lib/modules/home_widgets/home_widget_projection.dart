import 'dart:convert';

import '../../core/table_entry_order.dart';
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
  final selectedEntries = <String, _ProjectedEntry>{};

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
          ..sort(compareTableEntriesByBusinessTime);

    for (final entry in matching.take(section.limit)) {
      selectedEntries.putIfAbsent(
        entry.id,
        () => _ProjectedEntry(
          entry: entry,
          table: table,
          fields: activeFields,
          configuredFields: section.fields,
        ),
      );
    }
  }

  final excluded = card.spec.excludedTableIds.toSet();
  bool available(TableEntryDocument entry) =>
      tablesById.containsKey(entry.tableId) &&
      !excluded.contains(entry.tableId);
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  final eventEnd = DateTime(today.year, today.month, today.day + 7);
  for (final entry in source.entries) {
    if (entry.deleted || !available(entry)) continue;
    if (card.spec.includeOpenTodos &&
        entry.type == TableContentType.todo &&
        !entry.done) {
      final table = tablesById[entry.tableId]!;
      selectedEntries.putIfAbsent(
        entry.id,
        () => _ProjectedEntry(entry: entry, table: table),
      );
    }
    if (!card.spec.includeRecentEvents ||
        (entry.type != TableContentType.schedule &&
            entry.type != TableContentType.event)) {
      continue;
    }
    final time = businessTimeOf(entry)?.toLocal();
    if (time == null || time.isBefore(today) || !time.isBefore(eventEnd)) {
      continue;
    }
    final table = tablesById[entry.tableId]!;
    selectedEntries.putIfAbsent(
      entry.id,
      () => _ProjectedEntry(entry: entry, table: table),
    );
  }

  final ordered = selectedEntries.values.toList(growable: false)
    ..sort(
      (left, right) =>
          compareTableEntriesByBusinessTime(left.entry, right.entry),
    );
  final matchingCount = ordered.length;
  final capped = ordered.take(48).toList(growable: false);
  final rows = [
    for (final item in capped)
      WidgetRow.entry(
        tableId: item.entry.tableId,
        entryId: item.entry.id,
        title: _short(item.entry.title, 80),
        detail: _entryDetail(
          item.entry,
          item.table,
          item.fields,
          item.configuredFields,
          card.visibility,
          localNow,
        ),
      ),
  ];
  final usesDateFilter =
      card.spec.includeRecentEvents ||
      plans.any((plan) => plan.spec.daysAhead != null);
  var snapshot = WidgetSnapshot(
    cardId: card.cardId,
    revision: card.revision,
    title: card.spec.title,
    theme: card.spec.theme,
    state: rows.isEmpty ? WidgetCardState.empty : WidgetCardState.ready,
    generatedAtMs: localNow.millisecondsSinceEpoch,
    dataDay: usesDateFilter ? _dataDay(localNow) : null,
    rows: rows,
    hasMore: matchingCount > capped.length,
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
    case WidgetVisibility.titleTime:
    case WidgetVisibility.fields:
      return WidgetSnapshot(
        cardId: snapshot.cardId,
        revision: snapshot.revision,
        title: snapshot.title,
        theme: snapshot.theme,
        state: snapshot.state,
        generatedAtMs: snapshot.generatedAtMs,
        dataDay: snapshot.dataDay,
        rows: visibility == WidgetVisibility.titles
            ? [for (final row in snapshot.rows) row.withoutDetail()]
            : snapshot.rows,
        hasMore: snapshot.hasMore,
      );
  }
}

class _ProjectedEntry {
  const _ProjectedEntry({
    required this.entry,
    required this.table,
    this.fields = const [],
    this.configuredFields = const [],
  });

  final TableEntryDocument entry;
  final TableDocument table;
  final List<WidgetField> fields;
  final List<WidgetField> configuredFields;
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
        if (!spec.excludedTableIds.contains(section.tableId))
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
  final businessTime = businessTimeOf(entry);
  if (businessTime == null) return false;
  final start = DateTime(localNow.year, localNow.month, localNow.day);
  final end = DateTime(localNow.year, localNow.month, localNow.day + daysAhead);
  final localBusinessTime = businessTime.toLocal();
  return !localBusinessTime.isBefore(start) && localBusinessTime.isBefore(end);
}

String? _entryDetail(
  TableEntryDocument entry,
  TableDocument table,
  List<WidgetField> fields,
  List<WidgetField> configuredFields,
  WidgetVisibility visibility,
  DateTime localNow,
) {
  if (visibility == WidgetVisibility.titles) return null;
  if (visibility == WidgetVisibility.titleTime) {
    return _formatBusinessTime(entry, localNow);
  }
  if (configuredFields.isEmpty) {
    return switch (entry.type) {
      TableContentType.note => null,
      TableContentType.todo => entry.done ? '完成' : '未完成',
      TableContentType.schedule ||
      TableContentType.event => _formatBusinessTime(entry, localNow),
    };
  }

  final definitions = {for (final field in table.fields) field.id: field};
  final values = <String>[];
  for (final field in fields) {
    final builtin = field.builtin;
    if (builtin != null) {
      switch (builtin) {
        case WidgetBuiltinField.time:
          final formatted = _formatBusinessTime(entry, localNow);
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

String? _formatBusinessTime(TableEntryDocument entry, DateTime localNow) {
  final time = businessTimeOf(entry);
  if (time == null) return null;
  final local = time.toLocal();
  final year = local.year == localNow.year ? '' : '${local.year}年';
  if (entry.allDay) return '$year${local.month}月${local.day}日';
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$year${local.month}月${local.day}日 $hour:$minute';
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
