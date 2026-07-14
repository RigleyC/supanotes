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
    );
  }

  /// Streams the completion history for a single task, newest first.
  Stream<List<LocalTaskCompletionData>> watchCompletionsForTask(String taskId) {
    return (select(localTaskCompletions)
          ..where((c) => c.taskId.equals(taskId))
          ..orderBy([
            (c) => OrderingTerm(
              expression: c.completedAt,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  /// Deletes the most recent completion record for [taskId].
  Future<void> undoLastCompletion(String taskId) async {
    final lastCompletion = await (select(localTaskCompletions)
          ..where((c) => c.taskId.equals(taskId))
          ..orderBy([
            (c) => OrderingTerm(
              expression: c.completedAt,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(1))
        .getSingleOrNull();

    if (lastCompletion != null) {
      await (delete(localTaskCompletions)
            ..where((c) => c.id.equals(lastCompletion.id)))
          .go();
    }
  }

  /// Stores a completion row from the server projection.
  Future<void> upsertFromRemote(LocalTaskCompletionData completion) async {
    await into(localTaskCompletions).insertOnConflictUpdate(completion);
  }
}
