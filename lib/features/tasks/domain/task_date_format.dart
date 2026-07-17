import 'package:intl/intl.dart';
import 'package:supanotes/core/utils/date_time_extensions.dart';

/// Formats a due date + optional time into a human-readable label.
///
/// Rules:
///   - Today    → "Hoje" / "Hoje ⋅ 14:30"
///   - Tomorrow → "Amanhã" / "Amanhã ⋅ 09:00"
///   - Other    → "18 Jul, Sáb" / "18 Jul, Sáb ⋅ 10:00"
///   - Overdue (not completed) → "Atrasada · 10 Jul, Qui"
///   - Overdue (completed)    → "10 Jul, Qui"
String formatDueDate(
  DateTime dueDate, {
  bool hasTime = false,
  bool isOverdue = false,
  bool isCompleted = false,
  DateTime? now,
}) {
  final today = (now ?? DateTime.now()).startOfDay;
  final tomorrow = today.add(const Duration(days: 1));
  final date = dueDate.startOfDay;
  final timeStr = hasTime ? ' \u22c5 ${DateFormat('HH:mm').format(dueDate)}' : '';

  if (date.isSameDayAs(today)) return 'Hoje$timeStr';
  if (date.isSameDayAs(tomorrow)) return 'Amanhã$timeStr';

  final dateStr = DateFormat('d MMM, EEE', 'pt_BR').format(dueDate);

  if (date.isBefore(today) && !isCompleted) {
    return 'Atrasada · $dateStr$timeStr';
  }
  return '$dateStr$timeStr';
}
