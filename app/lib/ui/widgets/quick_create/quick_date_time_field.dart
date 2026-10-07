import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class QuickDateTimeField extends StatelessWidget {
  const QuickDateTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.allDay,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final bool allDay;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final format = allDay ? DateFormat('MM月dd日') : DateFormat('MM月dd日 HH:mm');
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.schedule),
        ),
        child: Text(format.format(value)),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(value.year - 5),
      lastDate: DateTime(value.year + 10),
    );
    if (date == null || !context.mounted) {
      return;
    }
    if (allDay) {
      onChanged(DateTime(date.year, date.month, date.day));
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (time != null) {
      onChanged(
        DateTime(date.year, date.month, date.day, time.hour, time.minute),
      );
    }
  }
}
