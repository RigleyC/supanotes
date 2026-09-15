// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tasks_dao.dart';

// ignore_for_file: type=lint
mixin _$TasksDaoMixin on DatabaseAccessor<AppDatabase> {
  $TasksTable get tasks => attachedDatabase.tasks;
  $PendingTaskOperationsTable get pendingTaskOperations =>
      attachedDatabase.pendingTaskOperations;
  TasksDaoManager get managers => TasksDaoManager(this);
}

class TasksDaoManager {
  final _$TasksDaoMixin _db;
  TasksDaoManager(this._db);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db.attachedDatabase, _db.tasks);
  $$PendingTaskOperationsTableTableManager get pendingTaskOperations =>
      $$PendingTaskOperationsTableTableManager(
        _db.attachedDatabase,
        _db.pendingTaskOperations,
      );
}
