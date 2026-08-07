import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../tables/task_completions.dart';

part 'task_completions_dao.g.dart';

/// Drift accessor for the [LocalTaskCompletions] history table.
///
/// The DAO is intentionally thin — the canonical document projection
/// appends completion rows, the sync layer pulls dirty rows and pushes them,
/// and read APIs are surfaced only where needed. Keeping the surface small
/// means the schema can grow without forcing a rewrite of every consumer.
@DriftAccessor(tables: [LocalTaskCompletions])
class TaskCompletionsDao extends DatabaseAccessor<AppDatabase>
    with _$TaskCompletionsDaoMixin {
  TaskCompletionsDao(super.db);

  final Uuid _uuid = const Uuid();

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

  /// Upserts a completion for a specific occurrence. The unique
  /// constraint on `(taskId, scheduledAt)` ensures idempotent retries
  /// and CRDT convergence across devices.
  Future<void> upsertCompletion({
    required String taskId,
    required String userId,
    required DateTime scheduledAt,
    required DateTime completedAt,
  }) async {
    final occurrenceDate = scheduledAt.toUtc();
    final id = _uuid.v4();
    final companion = LocalTaskCompletionsCompanion.insert(
      id: id,
      taskId: taskId,
      userId: userId,
      completedAt: completedAt.toUtc(),
      scheduledAt: occurrenceDate,
    );
    await into(
      localTaskCompletions,
    ).insert(companion, mode: InsertMode.insertOrReplace);
  }

  /// Stores a completion row from the server projection.
  Future<void> upsertFromRemote(LocalTaskCompletionData completion) async {
    await into(localTaskCompletions).insertOnConflictUpdate(completion);
  }

  /// Returns the completion record for a specific occurrence, or null.
  Future<LocalTaskCompletionData?> getCompletion(
    String taskId,
    DateTime scheduledAt,
  ) async {
    return (select(localTaskCompletions)..where(
          (c) =>
              c.taskId.equals(taskId) &
              c.scheduledAt.equals(scheduledAt.toUtc()),
        ))
        .getSingleOrNull();
  }

  /// Checks whether a specific occurrence is completed.
  Future<bool> isOccurrenceCompleted(
    String taskId,
    DateTime scheduledAt,
  ) async {
    final row = await getCompletion(taskId, scheduledAt);
    return row != null;
  }
}
