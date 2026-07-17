import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/utils/date_time_extensions.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

@immutable
class TaskMetadataState {
  final DateTime? dueDate;
  final bool hasTime;
  final TaskRecurrence? recurrence;

  const TaskMetadataState({this.dueDate, this.hasTime = false, this.recurrence});
}

final taskMetadataTaskProvider = Provider.autoDispose<TaskModel>((ref) {
  throw UnimplementedError('Override this provider in a ProviderScope');
});

class TaskMetadataController extends Notifier<TaskMetadataState> {
  @override
  TaskMetadataState build() {
    final task = ref.watch(taskMetadataTaskProvider);
    return TaskMetadataState(
      dueDate: task.dueDate,
      hasTime: task.hasTime,
      recurrence: task.recurrence,
    );
  }

  void setDate(DateTime date) {
    state = TaskMetadataState(dueDate: date);
  }

  void setTime(DateTime date, {required bool hasTime}) {
    state = TaskMetadataState(dueDate: date, hasTime: hasTime);
  }

  void setRecurrence(TaskRecurrence? r) {
    final dueDate = state.dueDate ??
        (r != null ? DateTime.now().startOfDay : null);
    state = TaskMetadataState(dueDate: dueDate, recurrence: r);
  }

  void clearDate() {
    state = const TaskMetadataState();
  }

  void clearTime() {
    state = TaskMetadataState(dueDate: state.dueDate);
  }

  void clearRecurrence() {
    state = TaskMetadataState(dueDate: state.dueDate, hasTime: state.hasTime);
  }
}

final taskMetadataControllerProvider =
    NotifierProvider<TaskMetadataController, TaskMetadataState>(
  TaskMetadataController.new,
);
