import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/current_user.dart';
import '../../../../core/database/database.dart';
import '../../../../core/database/daos/tasks_dao.dart';

final tasksLocalRepositoryProvider = Provider.autoDispose<TasksLocalRepository>(
  (ref) {
    final db = ref.watch(appDatabaseProvider);
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      throw StateError(
        'tasksLocalRepositoryProvider read while unauthenticated',
      );
    }
    return TasksLocalRepository(db.tasksDao, userId);
  },
);

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
}
