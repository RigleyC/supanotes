enum TaskReminderOption {
  atTime('at_time', isRelative: true, label: 'No horário da task'),
  fiveMinsBefore('5m_before', isRelative: true, label: '5 minutos antes'),
  oneHourBefore('1h_before', isRelative: true, label: '1 hora antes'),
  oneDayBeforeRelative('1d_before', isRelative: true, label: '1 dia antes'),

  at9Am('9am', isRelative: false, label: '9:00 AM'),
  at12Pm('12pm', isRelative: false, label: '12:00 PM'),
  at6Pm('6pm', isRelative: false, label: '6:00 PM'),
  oneDayBeforeAbsolute('1d_before_9am', isRelative: false, label: '1 dia antes, 9:00 AM');

  final String value;
  final bool isRelative;
  final String label;

  const TaskReminderOption(this.value, {required this.isRelative, required this.label});

  /// When the task loses its time (e.g. user clears time or picks date-only),
  /// relative reminders become meaningless. This transitions to a safe default.
  TaskReminderOption toAllDayFallback() {
    if (!isRelative) return this;
    return TaskReminderOption.at9Am;
  }

  static TaskReminderOption? fromValue(String? value) {
    if (value == null) return null;
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => TaskReminderOption.at9Am,
    );
  }
}
