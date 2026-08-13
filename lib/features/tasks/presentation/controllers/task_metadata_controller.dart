import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/utils/date_time_extensions.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_reminder_option.dart';

import 'task_metadata_draft.dart';

class TaskMetadataState {
  const TaskMetadataState({
    this.dueDate,
    this.hasTime = false,
    this.recurrence,
    this.reminder,
    this.isSaving = false,
    this.error,
  });

  final DateTime? dueDate;
  final bool hasTime;
  final TaskRecurrence? recurrence;
  final TaskReminderOption? reminder;
  final bool isSaving;
  final Object? error;

  TaskMetadataState copyWith({
    DateTime? dueDate,
    bool clearDueDate = false,
    bool? hasTime,
    TaskRecurrence? recurrence,
    bool clearRecurrence = false,
    TaskReminderOption? reminder,
    bool clearReminder = false,
    bool? isSaving,
    Object? error,
    bool clearError = false,
  }) {
    return TaskMetadataState(
      dueDate: clearDueDate ? null : dueDate ?? this.dueDate,
      hasTime: hasTime ?? this.hasTime,
      recurrence: clearRecurrence ? null : recurrence ?? this.recurrence,
      reminder: clearReminder ? null : reminder ?? this.reminder,
      isSaving: isSaving ?? this.isSaving,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class TaskMetadataController extends Notifier<TaskMetadataState> {
  TaskMetadataController(this.taskId);

  final String taskId;
  void Function()? _releaseSheetKeepAlive;

  @override
  TaskMetadataState build() {
    return const TaskMetadataState();
  }

  void initialize(TaskMetadataDraft draft) {
    _releaseSheetKeepAlive ??= ref.keepAlive().close;
    state = TaskMetadataState(
      dueDate: draft.scheduleAnchor,
      hasTime: draft.hasTime,
      recurrence: draft.recurrence,
      reminder: draft.reminder,
      isSaving: false,
    );
  }

  void releaseSheet() {
    _releaseSheetKeepAlive?.call();
    _releaseSheetKeepAlive = null;
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
    state = TaskMetadataState(
      dueDate: value,
      hasTime: current.hasTime,
      recurrence: current.recurrence,
      reminder: current.reminder,
      error: current.error,
    );
  }

  void clearDueDate() {
    state = const TaskMetadataState();
  }

  void setTime(DateTime dueDate, {required bool hasTime}) {
    final current = state;
    state = TaskMetadataState(
      dueDate: dueDate,
      hasTime: hasTime,
      recurrence: current.recurrence,
      reminder: current.reminder,
      error: current.error,
    );
  }

  void clearTime() {
    final current = state;
    state = TaskMetadataState(
      dueDate: current.dueDate,
      hasTime: false,
      recurrence: current.recurrence,
      reminder: state.reminder?.toAllDayFallback(),
      error: current.error,
    );
  }

  void setRecurrence(TaskRecurrence? recurrence) {
    final current = state;
    state = TaskMetadataState(
      dueDate:
          state.dueDate ??
          (recurrence == null ? null : DateTime.now().startOfDay),
      hasTime: current.hasTime,
      recurrence: recurrence,
      reminder: current.reminder,
      error: current.error,
    );
  }

  void setReminder(TaskReminderOption? reminder) {
    final current = state;
    state = TaskMetadataState(
      dueDate:
          current.dueDate ??
          (reminder == null ? null : DateTime.now().startOfDay),
      hasTime: current.hasTime,
      recurrence: current.recurrence,
      reminder: reminder,
      error: current.error,
    );
  }

  Future<bool> save(
    Future<void> Function(TaskMetadataState state) persist,
  ) async {
    if (state.isSaving) return false;
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await persist(state);
      state = state.copyWith(isSaving: false);
      return true;
    } catch (error) {
      state = state.copyWith(isSaving: false, error: error);
      return false;
    }
  }
}

final taskMetadataProvider = NotifierProvider.autoDispose
    .family<TaskMetadataController, TaskMetadataState, String>(
      TaskMetadataController.new,
    );
