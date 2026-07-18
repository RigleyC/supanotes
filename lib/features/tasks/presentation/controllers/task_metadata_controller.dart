import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/utils/date_time_extensions.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

class TaskMetadataState {
  final DateTime? dueDate;
  final bool hasTime;
  final TaskRecurrence? recurrence;

  const TaskMetadataState({this.dueDate, this.hasTime = false, this.recurrence});

  TaskMetadataState copyWith({
    DateTime? dueDate,
    bool? hasTime,
    TaskRecurrence? recurrence,
    bool clearDueDate = false,
    bool clearRecurrence = false,
  }) {
    return TaskMetadataState(
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      hasTime: hasTime ?? this.hasTime,
      recurrence: clearRecurrence ? null : (recurrence ?? this.recurrence),
    );
  }
}

class TaskMetadataController extends Notifier<TaskMetadataState> {
  @override
  TaskMetadataState build() {
    return const TaskMetadataState();
  }

  void init(TaskModel task) {
    // Schedule a microtask to avoid modifying state during build if called late
    Future.microtask(() {
      state = TaskMetadataState(
        dueDate: task.dueDate,
        hasTime: task.hasTime,
        recurrence: task.recurrence,
      );
    });
  }

  void setDate(DateTime date) {
    state = state.copyWith(dueDate: date, hasTime: false);
  }

  void setTime(DateTime date, {required bool hasTime}) {
    state = state.copyWith(dueDate: date, hasTime: hasTime);
  }

  void setRecurrence(TaskRecurrence? r) {
    final dueDate = state.dueDate ??
        (r != null ? DateTime.now().startOfDay : null);
    state = state.copyWith(dueDate: dueDate, recurrence: r, clearRecurrence: r == null);
  }

  void clearDate() {
    state = state.copyWith(clearDueDate: true, hasTime: false, clearRecurrence: true);
  }

  void clearTime() {
    state = state.copyWith(hasTime: false);
  }

  void clearRecurrence() {
    state = state.copyWith(clearRecurrence: true);
  }
}

final taskMetadataControllerProvider =
    NotifierProvider<TaskMetadataController, TaskMetadataState>(
  TaskMetadataController.new,
);
