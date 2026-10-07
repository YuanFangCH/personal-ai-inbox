import 'package:flutter/material.dart';

import '../../core/models.dart';
import 'quick_create/quick_create_sheet_view.dart';

Future<ResultDocument?> showQuickCreateSheet(
  BuildContext context, {
  required DateTime initialDate,
  ResultType type = ResultType.event,
  DateTime? initialStart,
}) {
  return showModalBottomSheet<ResultDocument?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => QuickCreateSheetView(
      initialDate: initialDate,
      initialType: type,
      initialStart: initialStart,
    ),
  );
}
