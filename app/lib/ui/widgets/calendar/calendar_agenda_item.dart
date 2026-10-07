import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/calendar.dart';

class CalendarAgendaItem extends StatelessWidget {
  const CalendarAgendaItem({
    super.key,
    required this.item,
    required this.onTap,
  });

  final CalendarOccurrence item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = item.allDay ? '全天' : DateFormat('HH:mm').format(item.start);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 38,
              decoration: BoxDecoration(
                color: item.kind == CalendarItemKind.event
                    ? scheme.primary
                    : scheme.secondary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              item.kind == CalendarItemKind.event
                  ? Icons.event_outlined
                  : item.done
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.document.title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  decoration: item.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              time,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
