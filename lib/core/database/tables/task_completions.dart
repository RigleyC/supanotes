import 'package:drift/drift.dart';

/// History of task completions, keyed per occurrence.
///
/// Each row records that a given [taskId] had its occurrence at
/// [scheduledAt] completed at [completedAt] by [userId].
///
/// A recurring task's template stays unchanged; only per-occurrence
/// completion events are recorded. The unique constraint on
/// `(taskId, scheduledAt)` ensures idempotent retries and CRDT
/// convergence across devices.
@DataClassName('LocalTaskCompletionData')
class LocalTaskCompletions extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text()();
  TextColumn get userId => text()();
  DateTimeColumn get completedAt => dateTime()();
  DateTimeColumn get scheduledAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => const ['UNIQUE(task_id, scheduled_at)'];
}
