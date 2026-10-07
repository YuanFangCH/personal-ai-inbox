import 'package:flutter/material.dart';

import '../../../core/calendar.dart';
import '../../../core/models.dart';
import '../common.dart';
import 'calendar_agenda_item.dart';

class CalendarDayPanel extends StatelessWidget {
  const CalendarDayPanel({
    super.key,
    required this.day,
    required this.occurrences,
    required this.onOpenDocument,
  });

  final DateTime day;
  final List<CalendarOccurrence> occurrences;
  final ValueChanged<ResultDocument> onOpenDocument;

  @override
  Widget build(BuildContext context) {
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            title: monthDayHeader(day),
            trailing: Text('${occurrences.length} 项'),
          ),
          const SizedBox(height: 6),
          if (occurrences.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('这一天没有事件或待办')),
            )
          else
            for (var index = 0; index < occurrences.length; index++) ...[
              CalendarAgendaItem(
                item: occurrences[index],
                onTap: () => onOpenDocument(occurrences[index].document),
              ),
              if (index != occurrences.length - 1) const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}
