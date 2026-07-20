import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/utils/date_time_extensions.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_reminder_option.dart';

typedef TaskMetadataState = ({
  DateTime? dueDate,
  bool hasTime,
  TaskRecurrence? recurrence,
  TaskReminderOption? reminder,
});

class TaskMetadataController extends Notifier<TaskMetadataState> {
  TaskMetadataController(this.taskId);

  final String taskId;

  @override
  TaskMetadataState build() {
    return _emptyState;
  }

  void initialize(TaskModel task) {
    state = (
      dueDate: task.dueDate,
      hasTime: task.hasTime,
      recurrence: task.recurrence,
      reminder: TaskReminderOption.fromYjsValue(task.reminder),
    );
  }

  void setDueDate(DateTime dueDate) {
    final current = state;
    final currentDueDate = current.dueDate;
    final value = current.hasTime && currentDueDate != null
        ? DateTime(
            dueDate.year,
            dueDate.month,
            dueDate.day,
            currentDueDate.hour,
            currentDueDate.minute,
          )
        : dueDate;
    state = (
      dueDate: value,
      hasTime: current.hasTime,
      recurrence: current.recurrence,
      reminder: current.reminder,
    );
  }

  void clearDueDate() {
    state = _emptyState;
  }

  void setTime(DateTime dueDate, {required bool hasTime}) {
    final current = state;
    state = (
      dueDate: dueDate,
      hasTime: hasTime,
      recurrence: current.recurrence,
      reminder: current.reminder,
    );
  }

  void clearTime() {
    final current = state;
    state = (
      dueDate: current.dueDate,
      hasTime: false,
      recurrence: current.recurrence,
      reminder: state.reminder?.toAllDayFallback(),
    );
  }

  void setRecurrence(TaskRecurrence? recurrence) {
    final current = state;
    state = (
      dueDate:
          state.dueDate ??
          (recurrence == null ? null : DateTime.now().startOfDay),
      hasTime: current.hasTime,
      recurrence: recurrence,
      reminder: current.reminder,
    );
  }

  void setReminder(TaskReminderOption? reminder) {
    final current = state;
    state = (
      dueDate: current.dueDate,
      hasTime: current.hasTime,
      recurrence: current.recurrence,
      reminder: reminder,
    );
  }
}

const _emptyState = (
  dueDate: null,
  hasTime: false,
  recurrence: null,
  reminder: null,
);

final taskMetadataProvider =
    NotifierProvider.family<TaskMetadataController, TaskMetadataState, String>(
      TaskMetadataController.new,
    );
