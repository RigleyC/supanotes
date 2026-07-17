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
        return 'Diariamente';
      case TaskRecurrence.weekdays:
        return 'Dias úteis';
      case TaskRecurrence.weekly:
        final weekday = DateFormat.EEEE('pt_BR').format(dueDate);
        // 1=Mon..5=Fri usam «às»; 6=Sáb,7=Dom usam «aos»
        final prep = dueDate.weekday <= 5 ? 'às' : 'aos';
        return 'Semanalmente, $prep $weekday';
      case TaskRecurrence.monthly:
        final day = DateFormat('d').format(dueDate);
        return 'Mensalmente, em $day';
    }
  }

  /// Rótulo curto para badges no editor: ex. "Semanalmente," / "Mensalmente"
  String get shortLabel {
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
