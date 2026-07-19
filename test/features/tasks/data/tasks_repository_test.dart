import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/data/local/tasks_local_repository.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/core/database/database.dart';

void main() {
  group('TasksRepository Catch-Up Integration', () {
    test('TasksRepository constructor calls catchUpRecurringTasks on local repository', () async {
      final local = FakeTasksLocalRepository();
      expect(local.catchUpCalledCount, 0);

      // Constructing repository should trigger catchUpRecurringTasks (fire-and-forget)
      TasksRepository(local);

      // Since catchUpRecurringTasks is async but called in constructor, let's wait a microtask or a frame
      await Future.delayed(Duration.zero);

      expect(local.catchUpCalledCount, 1);
    });

    test('ITasksRepository exposes catchUpRecurringTasks and delegates to local repository', () async {
      final local = FakeTasksLocalRepository();
      final repo = TasksRepository(local);
      
      expect(local.catchUpCalledCount, 1); // From constructor
      
      await repo.catchUpRecurringTasks();
      
      expect(local.catchUpCalledCount, 2);
    });
  });
}

class FakeTasksLocalRepository implements TasksLocalRepository {
  int catchUpCalledCount = 0;

  @override
  String get userId => 'test-user';

  @override
  Future<void> catchUpRecurringTasks() async {
    catchUpCalledCount++;
  }

  @override
  Stream<List<TaskData>> watchTodayTasks() => const Stream.empty();

  @override
  Stream<List<TaskData>> watchOpenTasks({String? userId}) =>
      const Stream.empty();

  @override
  Stream<List<TaskData>> watchNoteTasks(String noteId) =>
      const Stream.empty();

  @override
  Future<List<TaskData>> getNoteTasks(String noteId) async => [];

  @override
  Future<void> createTask({
    required String id,
    required String noteId,
    required String title,
    String status = 'pending',
    String position = 'a0',
    TaskRecurrence? recurrence,
    DateTime? dueDate,
  }) async {}

  @override
  Future<void> reorderTasksBatch(List<String> orderedIds) async {}

  @override
  Future<void> updateTask(TasksCompanion companion) async {
    throw UnimplementedError();
  }

  @override
  Future<({DateTime? nextDue, DateTime? previousDue, bool previousHasTime})> completeTask(String id) async => (nextDue: null, previousDue: null, previousHasTime: false);

  @override
  Future<void> reopenTask(String id, {DateTime? originalDueDate}) async {}

  @override
  Future<void> softDeleteTask(String id) async {}

  @override
  Future<void> deleteTask(String id) async {}

  @override
  Future<void> runInTransaction(Future<void> Function() action) async {
    await action();
  }
}
