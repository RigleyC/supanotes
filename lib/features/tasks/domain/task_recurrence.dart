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
