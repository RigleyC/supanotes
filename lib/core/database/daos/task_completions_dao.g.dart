// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_completions_dao.dart';

// ignore_for_file: type=lint
mixin _$TaskCompletionsDaoMixin on DatabaseAccessor<AppDatabase> {
  $LocalTaskCompletionsTable get localTaskCompletions =>
      attachedDatabase.localTaskCompletions;
  TaskCompletionsDaoManager get managers => TaskCompletionsDaoManager(this);
}

class TaskCompletionsDaoManager {
  final _$TaskCompletionsDaoMixin _db;
  TaskCompletionsDaoManager(this._db);
  $$LocalTaskCompletionsTableTableManager get localTaskCompletions =>
      $$LocalTaskCompletionsTableTableManager(
          _db.attachedDatabase, _db.localTaskCompletions);
}
