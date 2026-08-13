import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_reminder_option.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_metadata_controller.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_metadata_draft.dart';

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

    final state = container.read(taskMetadataProvider('task-1'));
    expect(state.dueDate, isNull);
    expect(state.hasTime, isFalse);
    expect(state.recurrence, isNull);
    expect(state.reminder, isNull);
  });

  test('save persists once and returns success', () async {
    final controller = container.read(taskMetadataProvider('task-1').notifier)
      ..initialize(_task(reminder: TaskReminderOption.atTime.value));
    var saveCalls = 0;

    final saved = await controller.save((state) async {
      saveCalls++;
      expect(state.reminder, TaskReminderOption.atTime);
    });

    expect(saved, isTrue);
    expect(saveCalls, 1);
    expect(container.read(taskMetadataProvider('task-1')).isSaving, isFalse);
    expect(container.read(taskMetadataProvider('task-1')).error, isNull);
  });

  test('save failure keeps values and retry can succeed', () async {
    final controller = container.read(taskMetadataProvider('task-1').notifier)
      ..initialize(_task(reminder: TaskReminderOption.atTime.value));
    var shouldFail = true;

    final failed = await controller.save((_) async {
      if (shouldFail) throw StateError('failed');
    });

    expect(failed, isFalse);
    var state = container.read(taskMetadataProvider('task-1'));
    expect(state.reminder, TaskReminderOption.atTime);
    expect(state.error.toString(), contains('failed'));

    shouldFail = false;
    final retried = await controller.save((_) async {});

    expect(retried, isTrue);
    state = container.read(taskMetadataProvider('task-1'));
    expect(state.error, isNull);
    expect(state.reminder, TaskReminderOption.atTime);
  });
}

TaskMetadataDraft _task({String? reminder}) {
  final now = DateTime.utc(2026, 7, 20, 10);
  return TaskMetadataDraft(
    scheduleAnchor: now,
    recurrence: TaskRecurrence.weekly,
    hasTime: true,
    reminder: TaskReminderOption.fromValue(reminder),
  );
}
