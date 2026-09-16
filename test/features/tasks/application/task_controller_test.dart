import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/features/tasks/application/task_controller.dart';
import 'package:supanotes/features/tasks/data/task_repository.dart';
import 'package:supanotes/features/tasks/domain/task.dart';

class _MockTaskRepository extends Mock implements TaskRepository {}

Task _task() {
  final now = DateTime.utc(2026, 9, 15, 10);
  return Task(
    id: 'task-1',
    ownerUserId: 'user-1',
    title: 'Ler',
    dueDate: DateTime(2026, 9, 15),
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  setUpAll(() => registerFallbackValue(_task()));

  late _MockTaskRepository repository;
  late TaskController controller;
  final task = _task();

  setUp(() {
    repository = _MockTaskRepository();
    controller = TaskController(repository);
    when(() => repository.create(task)).thenAnswer((_) async => task);
    when(() => repository.update(task)).thenAnswer((_) async => task);
    when(
      () => repository.completeOccurrence(
        taskId: 'task-1',
        scheduledAt: '2026-09-15T00:00:00.000',
        completedAt: null,
      ),
    ).thenAnswer((_) async => task);
    when(
      () => repository.reopenOccurrence(
        taskId: 'task-1',
        scheduledAt: '2026-09-15T00:00:00.000',
      ),
    ).thenAnswer((_) async => task);
    when(() => repository.delete('task-1')).thenAnswer((_) async => task);
    when(() => repository.get('task-1')).thenAnswer((_) async => task);
  });

  test('delegates create and update to the repository', () async {
    await controller.create(task);
    await controller.update(task);

    verify(() => repository.create(task)).called(1);
    verify(() => repository.update(task)).called(1);
  });

  test('delegates completion, reopening and deletion', () async {
    await controller.complete(
      'task-1',
      scheduledAt: '2026-09-15T00:00:00.000',
    );
    await controller.reopen(
      'task-1',
      scheduledAt: '2026-09-15T00:00:00.000',
    );
    await controller.delete('task-1');

    verify(
      () => repository.completeOccurrence(
        taskId: 'task-1',
        scheduledAt: '2026-09-15T00:00:00.000',
        completedAt: null,
      ),
    ).called(1);
    verify(
      () => repository.reopenOccurrence(
        taskId: 'task-1',
        scheduledAt: '2026-09-15T00:00:00.000',
      ),
    ).called(1);
    verify(() => repository.delete('task-1')).called(1);
  });

  test('completes an unscheduled task as a whole task', () async {
    final unscheduled = task.copyWith(dueDate: null);
    when(() => repository.get('task-1')).thenAnswer((_) async => unscheduled);
    when(() => repository.update(any())).thenAnswer((_) async => unscheduled);

    await controller.complete('task-1');

    final updated =
        verify(
              () => repository.update(captureAny()),
            ).captured.single
            as Task;
    expect(updated.dueDate, isNull);
    expect(updated.isCompleted, isTrue);
    expect(updated.lastCompletedAt, isNotNull);
    verifyNever(
      () => repository.completeOccurrence(
        taskId: any(named: 'taskId'),
        scheduledAt: any(named: 'scheduledAt'),
        completedAt: any(named: 'completedAt'),
      ),
    );
  });
}
