import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supanotes/core/database/daos/tasks_dao.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/tasks/domain/task.dart';
import 'package:supanotes/features/tasks/domain/task_operation.dart';

/// Local-first repository for independent tasks.
///
/// Every public mutation writes the optimistic task and its outbox operation
/// in the same SQLite transaction. Remote sync can therefore never observe a
/// task without the operation that explains the local change.
class TaskRepository {
  TaskRepository(this._dao, this._ownerUserId);

  final TasksDao _dao;
  final String _ownerUserId;

  String get userId => _ownerUserId;

  Stream<List<TaskData>> watchTasks() => _dao.watchTasks(_ownerUserId);

  Stream<TaskData?> watchTask(String taskId) =>
      _dao.watchTask(_ownerUserId, taskId);

  Future<Task?> get(String taskId) async {
    final row = await _dao.getTask(_ownerUserId, taskId);
    return row == null ? null : _fromRow(row);
  }

  /// Applies a canonical remote snapshot while leaving every pending local
  /// operation untouched. Confirmation/removal of an outbox row belongs to
  /// the task sync service, which has the matching operation id.
  Future<void> applyRemoteTask(Task task) async {
    _assertOwner(task);
    await _dao.runInTransaction(
      () => _dao.applyRemoteTask(_toCompanion(task)),
    );
  }

  /// Creates an optimistic task. The editor owns task construction so the
  /// canonical timestamps and schedule metadata are explicit at this boundary.
  Future<Task> create(Task draft) async {
    _assertOwner(draft);
    final operation = TaskOperation.create(
      taskId: draft.id,
      observedRevision: draft.revision,
      scheduleGeneration: draft.scheduleGeneration,
      payload: _taskPayload(draft),
    );
    return _persist(draft, operation);
  }

  /// Applies a complete optimistic snapshot. When only [taskId] is supplied,
  /// the current local task is patched with the provided fields.
  Future<Task> update(Task draft) async {
    final current = await _requireTask(draft.id);
    _assertOwner(draft);
    final now = DateTime.now().toUtc();
    final updated = draft.copyWith(updatedAt: now);
    final operation = TaskOperation.upsert(
      taskId: updated.id,
      observedRevision: current.revision,
      scheduleGeneration: updated.scheduleGeneration,
      payload: _taskPayload(updated),
    );
    return _persist(updated, operation);
  }

  Future<Task> completeOccurrence({
    required String taskId,
    required String scheduledAt,
    DateTime? completedAt,
  }) async {
    final current = await _requireTask(taskId);
    _assertOwner(current);
    final operation = TaskOperation.completeOccurrence(
      taskId: taskId,
      scheduledAt: scheduledAt,
      hasTime: current.hasTime,
      observedRevision: current.revision,
      scheduleGeneration: current.scheduleGeneration,
    );
    final completed = (completedAt ?? DateTime.now()).toUtc();
    final updated = current.recurrenceRule == null
        ? current.copyWith(
            isCompleted: true,
            lastCompletedAt: completed,
            updatedAt: DateTime.now().toUtc(),
          )
        : current.copyWith(
            isCompleted: false,
            completions: {
              ...current.completions,
              operation.payload['scheduledAt'] as String: completed
                  .toIso8601String(),
            },
            updatedAt: DateTime.now().toUtc(),
          );
    return _persist(updated, operation);
  }

  Future<Task> reopenOccurrence({
    required String taskId,
    required String scheduledAt,
  }) async {
    final current = await _requireTask(taskId);
    _assertOwner(current);
    final operation = TaskOperation.reopenOccurrence(
      taskId: taskId,
      scheduledAt: scheduledAt,
      hasTime: current.hasTime,
      observedRevision: current.revision,
      scheduleGeneration: current.scheduleGeneration,
    );
    final updated = current.recurrenceRule == null
        ? current.copyWith(
            isCompleted: false,
            lastCompletedAt: null,
            updatedAt: DateTime.now().toUtc(),
          )
        : current.copyWith(
            completions: {
              ...current.completions,
            }..remove(operation.payload['scheduledAt'] as String),
            updatedAt: DateTime.now().toUtc(),
          );
    return _persist(updated, operation);
  }

  Future<Task> delete(String taskId) async {
    final current = await _requireTask(taskId);
    _assertOwner(current);
    final deleted = current.copyWith(
      deletedAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    final operation = TaskOperation.delete(
      taskId: taskId,
      observedRevision: current.revision,
      scheduleGeneration: current.scheduleGeneration,
    );
    return _persist(deleted, operation);
  }

  Future<Task> _persist(Task task, TaskOperation operation) async {
    final now = DateTime.now().toUtc();
    return _dao.runInTransaction(() async {
      final ordinal = await _dao.nextOrdinal(task.id);
      await _dao.insertOrUpdateTask(_toCompanion(task));
      await _dao.enqueueMutation(
        PendingTaskOperationsCompanion.insert(
          operationId: operation.operationId,
          taskId: task.id,
          ownerUserId: _ownerUserId,
          observedRevision: operation.observedRevision,
          scheduleGeneration: operation.scheduleGeneration,
          ordinal: ordinal,
          kind: _operationKind(operation),
          payloadJson: jsonEncode(operation.payload),
          payloadHash: operation.payloadHash,
          createdAt: now,
        ),
      );
      return task;
    });
  }

  Future<Task> _requireTask(String? taskId) async {
    if (taskId == null || taskId.isEmpty) {
      throw ArgumentError('taskId is required');
    }
    final task = await get(taskId);
    if (task == null) throw StateError('Task not found: $taskId');
    return task;
  }

  void _assertOwner(Task task) {
    if (task.ownerUserId != _ownerUserId) {
      throw StateError('Task belongs to another owner');
    }
  }

  static String _operationKind(TaskOperation operation) => switch (operation.type) {
    TaskOperationType.create => 'create',
    TaskOperationType.upsert => 'upsert',
    TaskOperationType.completeOccurrence => 'complete_occurrence',
    TaskOperationType.reopenOccurrence => 'reopen_occurrence',
    TaskOperationType.delete => 'delete',
  };

  static Map<String, dynamic> _taskPayload(Task task) {
    final json = task.toJson();
    return {
      'title': json['title'],
      'dueDate': json['due_date'],
      'hasTime': json['has_time'],
      'recurrenceRule': json['recurrence_rule'],
      'reminder': json['reminder'],
      'completions': json['completions'],
      'isCompleted': json['is_completed'],
      'lastCompletedAt': json['last_completed_at'],
    };
  }

  static TasksCompanion _toCompanion(Task task) => TasksCompanion.insert(
    id: task.id,
    ownerUserId: task.ownerUserId,
    title: task.title,
    dueDate: Value(task.dueDate),
    hasTime: Value(task.hasTime),
    recurrenceRule: Value(task.recurrenceRule),
    reminder: Value(task.reminder),
    completions: Value(jsonEncode(task.toJson()['completions'])),
    isCompleted: Value(task.isCompleted),
    lastCompletedAt: Value(task.lastCompletedAt),
    revision: Value(task.revision),
    createdAt: task.createdAt,
    updatedAt: task.updatedAt,
    deletedAt: Value(task.deletedAt),
    scheduleGeneration: Value(task.scheduleGeneration),
  );

  static Task _fromRow(TaskData row) {
    final decoded = jsonDecode(row.completions);
    if (decoded is! Map) {
      throw const FormatException('Task completions must be a JSON object');
    }
    return Task(
      id: row.id,
      ownerUserId: row.ownerUserId,
      title: row.title,
      dueDate: row.dueDate,
      hasTime: row.hasTime,
      recurrenceRule: row.recurrenceRule,
      reminder: row.reminder,
      completions: decoded.cast<String, Object?>(),
      isCompleted: row.isCompleted,
      lastCompletedAt: row.lastCompletedAt,
      revision: row.revision,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
      scheduleGeneration: row.scheduleGeneration,
    );
  }

}
