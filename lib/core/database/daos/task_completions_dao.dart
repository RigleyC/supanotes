import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../tables/task_completions.dart';

part 'task_completions_dao.g.dart';

/// Drift accessor for the [LocalTaskCompletions] history table.
///
/// The DAO is intentionally thin — the [TasksDao.completeTask] workflow
/// appends a row, the sync layer pulls dirty rows and pushes them, and
/// read APIs are surfaced only where needed. Keeping the surface small
/// means the schema can grow without forcing a rewrite of every consumer.
@DriftAccessor(tables: [LocalTaskCompletions])
class TaskCompletionsDao extends DatabaseAccessor<AppDatabase>
    with _$TaskCompletionsDaoMixin {
  TaskCompletionsDao(super.db);

  final Uuid _uuid = const Uuid();

  /// Records a completion of [taskId] by [userId] at the given
  /// [completedAt] (defaults to "now"). The new row is marked dirty so
  /// the next sync round pushes it to the backend.
  Future<LocalTaskCompletionData> recordCompletion({
    required String taskId,
    required String userId,
    DateTime? completedAt,
  }) async {
    final when = (completedAt ?? DateTime.now()).toUtc();
    final id = _uuid.v4();
    final companion = LocalTaskCompletionsCompanion.insert(
      id: id,
      taskId: taskId,
      userId: userId,
      completedAt: when,
    );
    await into(localTaskCompletions).insert(companion);
    return LocalTaskCompletionData(
      id: id,
      taskId: taskId,
      userId: userId,
      completedAt: when,
      isDirty: true,
    );
  }

  /// Streams the completion history for a single task, newest first.
  Stream<List<LocalTaskCompletionData>> watchCompletionsForTask(String taskId) {
    return (select(localTaskCompletions)
          ..where((c) => c.taskId.equals(taskId))
          ..orderBy([
            (c) =>
                OrderingTerm(expression: c.completedAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  /// Returns every row still pending sync.
  Future<List<LocalTaskCompletionData>> getDirtyCompletions() {
    return (select(localTaskCompletions)
          ..where((c) => c.isDirty.equals(true)))
        .get();
  }

  /// Flips the dirty flag off after a successful push.
  Future<void> clearDirtyFlag(String id) async {
    await (update(localTaskCompletions)..where((c) => c.id.equals(id)))
        .write(const LocalTaskCompletionsCompanion(isDirty: Value(false)));
  }

  /// Stores a completion row that came back from the backend. Uses
  /// `insertOnConflictUpdate` so a re-pulled row replaces the local copy
  /// in place, and always sets [isDirty] to `false` so the row does not
  /// get pushed back to the server.
  Future<void> upsertFromRemote(LocalTaskCompletionData completion) async {
    final incoming = completion.copyWith(isDirty: false);
    await into(localTaskCompletions).insertOnConflictUpdate(incoming);
  }
}
