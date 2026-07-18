import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/utils/date_time_extensions.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_reminder_option.dart';

class TaskMetadataState {
  final DateTime? dueDate;
  final bool hasTime;
  final TaskRecurrence? recurrence;
  final TaskReminderOption? reminder;

  const TaskMetadataState({
    this.dueDate,
    this.hasTime = false,
    this.recurrence,
    this.reminder,
  });

  TaskMetadataState copyWith({
    DateTime? dueDate,
    bool? hasTime,
    TaskRecurrence? recurrence,
    TaskReminderOption? reminder,
    bool clearDueDate = false,
    bool clearRecurrence = false,
    bool clearReminder = false,
  }) {
    return TaskMetadataState(
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      hasTime: hasTime ?? this.hasTime,
      recurrence: clearRecurrence ? null : (recurrence ?? this.recurrence),
      reminder: clearReminder ? null : (reminder ?? this.reminder),
    );
  }
}

class TaskMetadataController extends Notifier<TaskMetadataState> {
  @override
  TaskMetadataState build() {
    return const TaskMetadataState();
  }

  void init(TaskModel task) {
    Future.microtask(() {
      state = TaskMetadataState(
        dueDate: task.dueDate,
        hasTime: task.hasTime,
        recurrence: task.recurrence,
        reminder: TaskReminderOption.fromYjsValue(task.reminder),
      );
    });
  }

  void setDate(DateTime date) {
    state = state.copyWith(
      dueDate: date,
      hasTime: false,
      reminder: state.reminder?.toAllDayFallback(),
    );
  }

  void setTime(DateTime date, {required bool hasTime}) {
    state = state.copyWith(dueDate: date, hasTime: hasTime);
  }

  void setRecurrence(TaskRecurrence? r) {
    final dueDate = state.dueDate ??
        (r != null ? DateTime.now().startOfDay : null);
    state = state.copyWith(dueDate: dueDate, recurrence: r, clearRecurrence: r == null);
  }

  void setReminder(TaskReminderOption? reminder) {
    state = state.copyWith(reminder: reminder, clearReminder: reminder == null);
  }

  void clearDate() {
    state = state.copyWith(clearDueDate: true, hasTime: false, clearRecurrence: true, clearReminder: true);
  }

  void clearTime() {
    state = state.copyWith(
      hasTime: false,
      reminder: state.reminder?.toAllDayFallback(),
    );
  }

  void clearRecurrence() {
    state = state.copyWith(clearRecurrence: true);
  }
}

final taskMetadataControllerProvider =
    NotifierProvider<TaskMetadataController, TaskMetadataState>(
  TaskMetadataController.new,
);
