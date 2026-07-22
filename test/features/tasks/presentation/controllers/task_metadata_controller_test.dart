import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_reminder_option.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_metadata_controller.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  test('clearing time preserves metadata and converts relative reminders', () {
    final controller = container.read(taskMetadataProvider('task-1').notifier)
      ..initialize(_task(reminder: TaskReminderOption.fiveMinsBefore.value));

    controller.clearTime();

    expect(container.read(taskMetadataProvider('task-1')).hasTime, isFalse);
    expect(
      container.read(taskMetadataProvider('task-1')).reminder,
      TaskReminderOption.at9Am,
    );
    expect(
      container.read(taskMetadataProvider('task-1')).recurrence,
      TaskRecurrence.weekly,
    );
  });

  test('clearing due date resets dependent metadata', () {
    final controller = container.read(taskMetadataProvider('task-1').notifier)
      ..initialize(_task(reminder: TaskReminderOption.atTime.value));

    controller.clearDueDate();

    expect(container.read(taskMetadataProvider('task-1')), _emptyTaskMetadata);
  });
}

TaskModel _task({String? reminder}) {
  final now = DateTime.utc(2026, 7, 20, 10);
  return TaskModel(
    id: 'task-1',
    userId: 'user-1',
    noteId: 'note-1',
    title: 'Tarefa',
    status: 'open',
    position: 'a0',
    dueDate: now,
    completedAt: null,
    recurrence: TaskRecurrence.weekly,
    hasTime: true,
    reminder: reminder,
    createdAt: now,
    updatedAt: now,
  );
}

const _emptyTaskMetadata = (
  dueDate: null,
  hasTime: false,
  recurrence: null,
  reminder: null,
);
