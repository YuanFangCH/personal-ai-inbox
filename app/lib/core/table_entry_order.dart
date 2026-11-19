import 'table_models.dart';

DateTime? businessTimeOf(TableEntryDocument entry) => switch (entry.type) {
  TableContentType.todo => entry.due,
  TableContentType.schedule => entry.start,
  TableContentType.event => entry.occurredAt,
  TableContentType.note => null,
};

List<TableEntryDocument> visibleTableEntriesByBusinessTime(
  Iterable<TableEntryDocument> entries,
) {
  final visible =
      entries
          .where((entry) => entry.type != TableContentType.todo || !entry.done)
          .toList()
        ..sort(compareTableEntriesByBusinessTime);
  return List.unmodifiable(visible);
}

int compareTableEntriesByBusinessTime(
  TableEntryDocument left,
  TableEntryDocument right,
) {
  final leftTime = businessTimeOf(left);
  final rightTime = businessTimeOf(right);
  if (leftTime != null && rightTime == null) return -1;
  if (leftTime == null && rightTime != null) return 1;
  if (leftTime != null && rightTime != null) {
    final byTime = leftTime.compareTo(rightTime);
    if (byTime != 0) return byTime;
  } else {
    final byUpdate = right.updatedAt.compareTo(left.updatedAt);
    if (byUpdate != 0) return byUpdate;
  }
  return left.id.compareTo(right.id);
}
