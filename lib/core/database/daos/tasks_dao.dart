import 'package:drift/drift.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/database/tables/tasks.dart';

part 'tasks_dao.g.dart';

@DriftAccessor(tables: [Tasks, PendingTaskOperations])
class TasksDao extends DatabaseAccessor<AppDatabase> with _$TasksDaoMixin {
  TasksDao(super.db);

  /// Watches only live tasks owned by [userId]. Tombstones stay queryable by
  /// sync code, but never leak into the open task list.
  Stream<List<TaskData>> watchTasks(String userId) {
    final query = select(tasks)
      ..where((task) => task.ownerUserId.equals(userId))
      ..where((task) => task.deletedAt.isNull())
      ..orderBy([
        (task) => OrderingTerm(
          expression: task.dueDate,
          mode: OrderingMode.asc,
          nulls: NullsOrder.last,
        ),
        (task) => OrderingTerm(expression: task.updatedAt),
      ]);
    return query.watch();
  }

  Stream<TaskData?> watchTask(String userId, String taskId) {
    return (select(tasks)..where(
          (task) => task.ownerUserId.equals(userId) & task.id.equals(taskId),
        ))
        .watchSingleOrNull();
  }

  Future<TaskData?> getTask(String userId, String taskId) {
    return (select(tasks)..where(
          (task) => task.ownerUserId.equals(userId) & task.id.equals(taskId),
        ))
        .getSingleOrNull();
  }

  Future<TaskData?> getTaskById(String taskId) {
    return (select(
      tasks,
    )..where((task) => task.id.equals(taskId))).getSingleOrNull();
  }

  Future<void> insertOrUpdateTask(TasksCompanion task) async {
    await into(tasks).insert(task, mode: InsertMode.insertOrReplace);
  }

  /// Applies a remote canonical snapshot without touching pending local
  /// operations. The outbox is intentionally durable until its matching
  /// operation response is received.
  Future<void> applyRemoteTask(TasksCompanion task) async {
    await insertOrUpdateTask(task);
  }

  Future<void> deleteTask(String userId, String taskId) async {
    await (delete(tasks)..where(
          (task) => task.ownerUserId.equals(userId) & task.id.equals(taskId),
        ))
        .go();
  }

  Future<int> nextOrdinal(String taskId) async {
    final ordinals =
        await (select(pendingTaskOperations)
              ..where((operation) => operation.taskId.equals(taskId)))
            .map((operation) => operation.ordinal)
            .get();
    if (ordinals.isEmpty) return 0;
    return ordinals.reduce((a, b) => a > b ? a : b) + 1;
  }

  Future<void> enqueueMutation(
    PendingTaskOperationsCompanion operation,
  ) async {
    await into(pendingTaskOperations).insert(operation);
  }

  Stream<List<PendingTaskOperationData>> watchPendingOperations(
    String userId,
    String taskId,
  ) {
    final query = select(pendingTaskOperations)
      ..where(
        (operation) =>
            operation.ownerUserId.equals(userId) &
            operation.taskId.equals(taskId),
      )
      ..orderBy([
        (operation) => OrderingTerm(expression: operation.ordinal),
      ]);
    return query.watch();
  }

  Future<List<PendingTaskOperationData>> getPendingOperations(
    String userId,
    String taskId,
  ) {
    final query = select(pendingTaskOperations)
      ..where(
        (operation) =>
            operation.ownerUserId.equals(userId) &
            operation.taskId.equals(taskId),
      )
      ..orderBy([
        (operation) => OrderingTerm(expression: operation.ordinal),
      ]);
    return query.get();
  }

  Future<List<PendingTaskOperationData>> getPendingOperationsForOwner(
    String userId,
  ) {
    final query = select(pendingTaskOperations)
      ..where((operation) => operation.ownerUserId.equals(userId))
      ..orderBy([
        (operation) => OrderingTerm(expression: operation.createdAt),
        (operation) => OrderingTerm(expression: operation.ordinal),
      ]);
    return query.get();
  }

  /// Returns task ids that still have durable work. Blocked operations are
  /// intentionally excluded; they require an explicit user-visible
  /// resolution instead of being retried by the background worker.
  Future<List<String>> getPendingTaskIds({required String ownerUserId}) async {
    final rows =
        await (select(pendingTaskOperations)
              ..where(
                (operation) =>
                    operation.ownerUserId.equals(ownerUserId) &
                    (operation.status.equals('pending') |
                        operation.status.equals('in_flight')),
              )
              ..orderBy([
                (operation) => OrderingTerm(expression: operation.taskId),
                (operation) => OrderingTerm(expression: operation.ordinal),
              ]))
            .get();
    return rows.map((row) => row.taskId).toSet().toList()..sort();
  }

  Future<void> deletePendingOperation(String operationId) async {
    await (delete(
      pendingTaskOperations,
    )..where((operation) => operation.operationId.equals(operationId))).go();
  }

  Future<void> updatePendingStatus(
    String operationId,
    String status, {
    int? attemptCount,
    DateTime? lastAttemptAt,
  }) async {
    await (update(
      pendingTaskOperations,
    )..where((operation) => operation.operationId.equals(operationId))).write(
      PendingTaskOperationsCompanion(
        status: Value(status),
        attemptCount: attemptCount == null
            ? const Value.absent()
            : Value(attemptCount),
        lastAttemptAt: lastAttemptAt == null
            ? const Value.absent()
            : Value(lastAttemptAt),
      ),
    );
  }

  Future<T> runInTransaction<T>(Future<T> Function() action) {
    return attachedDatabase.transaction(action);
  }
}
