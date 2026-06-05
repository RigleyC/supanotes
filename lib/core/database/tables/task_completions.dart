import 'package:drift/drift.dart';

/// Append-only history of task completions.
///
/// Each row records the fact that a given [taskId] was completed at
/// [completedAt] by [userId]. The row is marked [isDirty] until the next
/// successful sync round, after which [TaskCompletionsDao.clearDirtyFlag]
/// flips it to `false`.
///
/// Repeated completions of a recurring task create multiple rows — the
/// table intentionally does not enforce a unique constraint on
/// `(taskId, completedAt)` so that a task completed twice on the same
/// wall-clock second still produces two distinct history entries.
@DataClassName('LocalTaskCompletionData')
class LocalTaskCompletions extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text()();
  TextColumn get userId => text()();
  DateTimeColumn get completedAt => dateTime()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}
