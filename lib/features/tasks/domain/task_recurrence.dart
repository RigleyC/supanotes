import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum TaskRecurrence {
  daily,
  weekdays,
  weekly,
  monthly;

  static TaskRecurrence? parse(String? value) {
    if (value == null) return null;
    for (final e in TaskRecurrence.values) {
      if (e.name == value) return e;
    }
    return null;
  }
}

extension TaskRecurrenceUI on TaskRecurrence {
  String get label {
    switch (this) {
      case TaskRecurrence.daily:
        return 'Diariamente';
      case TaskRecurrence.weekdays:
        return 'Dias úteis';
      case TaskRecurrence.weekly:
        return 'Semanalmente';
      case TaskRecurrence.monthly:
        return 'Mensalmente';
    }
  }

  String getLocalizedLabel(DateTime? dueDate) {
    if (dueDate == null) return label;
    switch (this) {
      case TaskRecurrence.daily:
      case TaskRecurrence.weekdays:
        return label;
      case TaskRecurrence.weekly:
        final weekday = DateFormat.EEEE('pt_BR').format(dueDate);
        return 'Semanalmente ($weekday)';
      case TaskRecurrence.monthly:
        final day = DateFormat('d').format(dueDate);
        return 'Mensalmente (dia $day)';
    }
  }

  IconData get icon {
    switch (this) {
      case TaskRecurrence.daily:
        return Icons.today_rounded;
      case TaskRecurrence.weekdays:
        return Icons.work_outline;
      case TaskRecurrence.weekly:
        return Icons.calendar_view_week_outlined;
      case TaskRecurrence.monthly:
        return Icons.calendar_month_outlined;
    }
  }
}
