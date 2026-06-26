import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/current_user.dart';
import '../../../../core/database/database.dart';
import '../../../../core/database/daos/tasks_dao.dart';
import '../../domain/task_recurrence.dart';

final tasksLocalRepositoryProvider = Provider.autoDispose<TasksLocalRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    throw StateError(
      'tasksLocalRepositoryProvider read while unauthenticated',
    );
  }
  return TasksLocalRepository(db.tasksDao, userId);
});

class TasksLocalRepository {
  TasksLocalRepository(this._dao, this._userId);

  final TasksDao _dao;
  final String _userId;

  String get userId => _userId;

  Stream<List<TaskData>> watchTodayTasks() {
    return _dao.watchTodayTasks();
  }

  Stream<List<TaskData>> watchOpenTasks() {
    return _dao.watchOpenTasks(userId: _userId);
  }

  Stream<List<TaskData>> watchNoteTasks(String noteId) {
    return _dao.watchNoteTasks(noteId);
  }

  Future<List<TaskData>> getNoteTasks(String noteId) {
    return _dao.getNoteTasks(noteId);
  }

  Future<void> createTask({
    required String id,
    required String noteId,
    required String title,
    String status = 'open',
    int position = 0,
    TaskRecurrence? recurrence,
    DateTime? dueDate,
  }) async {
    final now = DateTime.now().toUtc();
    await _dao.insertTask(TaskData(
      id: id,
      userId: _userId,
      noteId: noteId,
      title: title,
      status: status,
      position: position,
      recurrence: recurrence,
      dueDate: dueDate,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      isDirty: true,
    ));
  }

  Future<void> updateTask(TasksCompanion companion) async {
    await _dao.updateTask(companion);
  }

  Future<DateTime?> completeTask(String id) async {
    return await _dao.completeTask(id);
  }

  Future<void> reopenTask(String id) async {
    await _dao.reopenTask(id);
  }

  Future<void> softDeleteTask(String id) async {
    await _dao.softDeleteTask(id);
  }

  Future<void> reorderTasksBatch(List<String> orderedIds) async {
    await _dao.reorderTasksBatch(orderedIds);
  }

  Future<void> deleteTask(String id) async {
    await _dao.deleteTaskById(id);
  }

  /// Runs [action] inside a Drift [Transaction] so that all batched
  /// task writes in a single save are either committed or rolled
  /// back together.
  Future<void> runInTransaction(Future<void> Function() action) async {
    await _dao.runInTransaction(action);
  }
}
