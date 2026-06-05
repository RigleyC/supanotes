import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/current_user.dart';
import '../../../../core/database/database.dart';
import '../../../../core/database/daos/tasks_dao.dart';

final tasksLocalRepositoryProvider = Provider<TasksLocalRepository>((ref) {
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

  Future<void> createTask({
    required String id,
    required String noteId,
    required String title,
    String status = 'pending',
    int position = 0,
    String? recurrence,
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

  Future<void> completeTask(String id) async {
    await _dao.completeTask(id);
  }

  Future<void> reopenTask(String id) async {
    await _dao.reopenTask(id);
  }

  Future<void> softDeleteTask(String id) async {
    await _dao.softDeleteTask(id);
  }

  Future<void> deleteTask(String id) async {
    await _dao.deleteTaskById(id);
  }
}
