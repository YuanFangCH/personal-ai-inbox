import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/calendar.dart';
import '../../../core/models.dart';

enum QuickCreateRepeatFrequency { none, daily, weekly, monthly }

enum QuickCreateRepeatEnd { until, count }

class QuickCreateFormModel {
  QuickCreateFormModel({
    required ResultType initialType,
    required DateTime initialDate,
    DateTime? initialStart,
  }) {
    type = initialType == ResultType.todo ? ResultType.todo : ResultType.event;
    final now = DateTime.now();
    final initial =
        initialStart ??
        DateTime(
          initialDate.year,
          initialDate.month,
          initialDate.day,
          now.hour,
          now.minute,
        );
    start = initial;
    end = initial.add(const Duration(hours: 1));
    due = initial;
    repeatUntil = initial.add(const Duration(days: 90));
    repeatFrequency = QuickCreateRepeatFrequency.none;
    title = TextEditingController();
    tags = TextEditingController();
    body = TextEditingController();
    repeatCount = TextEditingController(text: '10');
  }

  late final TextEditingController title;
  late final TextEditingController tags;
  late final TextEditingController body;
  late final TextEditingController repeatCount;
  late ResultType type;
  late DateTime start;
  late DateTime end;
  late DateTime due;
  late DateTime repeatUntil;
  late QuickCreateRepeatFrequency repeatFrequency;
  QuickCreateRepeatEnd repeatEnd = QuickCreateRepeatEnd.until;
  ResultStatus status = ResultStatus.canonical;
  String? matterId;
  bool allDay = false;
  bool expanded = false;
  bool saving = false;

  void setType(ResultType value) {
    type = value;
  }

  void setAllDay(bool value) {
    allDay = value;
    if (value) {
      start = DateTime(start.year, start.month, start.day);
      end = start.add(const Duration(days: 1));
    }
  }

  void setStart(DateTime value) {
    start = value;
    if (!end.isAfter(start)) {
      end = start.add(const Duration(hours: 1));
    }
  }

  void setEnd(DateTime value) {
    end = value;
  }

  void setDue(DateTime value) {
    due = value;
  }

  void setRepeatFrequency(QuickCreateRepeatFrequency value) {
    repeatFrequency = value;
  }

  void setRepeatEnd(QuickCreateRepeatEnd value) {
    repeatEnd = value;
  }

  void setRepeatUntil(DateTime value) {
    repeatUntil = value;
  }

  void setStatus(ResultStatus value) {
    status = value;
  }

  void setMatterId(String? value) {
    matterId = value;
  }

  void toggleExpanded() {
    expanded = !expanded;
  }

  void setSaving(bool value) {
    saving = value;
  }

  List<String> parsedTags() {
    return tags.text
        .split(RegExp(r'[,，\s]+'))
        .map((tag) => tag.trim().replaceFirst('#', ''))
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }

  String? recurrenceRule() {
    final parts = <String>[];
    switch (repeatFrequency) {
      case QuickCreateRepeatFrequency.none:
        return null;
      case QuickCreateRepeatFrequency.daily:
        parts.add('FREQ=DAILY');
      case QuickCreateRepeatFrequency.weekly:
        parts
          ..add('FREQ=WEEKLY')
          ..add('BYDAY=${recurrenceWeekdayCode(start.weekday)}');
      case QuickCreateRepeatFrequency.monthly:
        parts.add('FREQ=MONTHLY');
    }
    switch (repeatEnd) {
      case QuickCreateRepeatEnd.until:
        parts.add('UNTIL=${DateFormat('yyyyMMdd').format(repeatUntil)}');
      case QuickCreateRepeatEnd.count:
        final count = int.tryParse(repeatCount.text.trim());
        parts.add('COUNT=${count != null && count > 0 ? count : 10}');
    }
    return parts.join(';');
  }

  void dispose() {
    title.dispose();
    tags.dispose();
    body.dispose();
    repeatCount.dispose();
  }
}
