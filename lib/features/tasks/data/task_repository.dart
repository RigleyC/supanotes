import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supanotes/core/database/daos/tasks_dao.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/tasks/domain/task.dart';
import 'package:supanotes/features/tasks/domain/task_operation.dart';
import 'package:supanotes/features/tasks/domain/task_schedule_identity.dart';

/// A pending operation that could not be rebased because its schedule was
/// based on a different generation than the remote snapshot.
class TaskRebaseConflict {
  const TaskRebaseConflict({
    required this.operationId,
    required this.operationKind,
    required this.operationScheduleGeneration,
    required this.currentScheduleGeneration,
  });

  /// Durable outbox identifier for the conflicting operation.
  final String operationId;

  /// Serialized operation kind, such as `upsert` or `complete_occurrence`.
  final String operationKind;

  /// Generation recorded by the pending operation.
  final int operationScheduleGeneration;

  /// Generation observed while rebasing the remote snapshot.
  final int currentScheduleGeneration;
}

/// Read-only result of the most recent remote rebase.
///
/// Conflicting operations remain in the durable outbox with `blocked` status;
/// this value gives the sync layer a lightweight explanation without changing
/// the canonical task representation.
class TaskRebaseDiagnostic {
  const TaskRebaseDiagnostic({
    required this.taskId,
    required this.remoteScheduleGeneration,
    required this.conflicts,
  });

  /// Task whose snapshot was rebased.
  final String taskId;

  /// Generation from the remote snapshot before local operations were tested.
  final int remoteScheduleGeneration;

  /// Pending operations that were left blocked by the generation mismatch.
  final List<TaskRebaseConflict> conflicts;

  /// Whether at least one pending operation was incompatible.
  bool get hasConflicts => conflicts.isNotEmpty;
}

/// Local-first repository for independent tasks.
///
/// Every public mutation writes the optimistic task and its outbox operation
/// in the same SQLite transaction. Remote sync can therefore never observe a
/// task without the operation that explains the local change.
class TaskRepository {
  TaskRepository(this._dao, this._ownerUserId);

  final TasksDao _dao;
  final String _ownerUserId;
  TaskRebaseDiagnostic? _lastRebaseDiagnostic;

  String get userId => _ownerUserId;

  /// Describes incompatible operations from the latest remote rebase, if any.
  TaskRebaseDiagnostic? get lastRebaseDiagnostic => _lastRebaseDiagnostic;

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
    final conflicts = <TaskRebaseConflict>[];
    await _dao.runInTransaction(
      () async {
        var rebased = task;
        final pending = await _dao.getPendingOperations(
          _ownerUserId,
          task.id,
        );
        var blockedByScheduleConflict = false;
        for (final operation in pending) {
          if (blockedByScheduleConflict) {
            conflicts.add(
              TaskRebaseConflict(
                operationId: operation.operationId,
                operationKind: operation.kind,
                operationScheduleGeneration: operation.scheduleGeneration,
                currentScheduleGeneration: rebased.scheduleGeneration,
              ),
            );
            await _dao.updatePendingStatus(operation.operationId, 'blocked');
            continue;
          }
          final fields = _decodePendingPayload(operation);
          final isScheduleOperation = _isScheduleOperation(
            rebased,
            operation,
            fields,
          );
          if (!_isCompatibleWithScheduleGeneration(
            rebased,
            operation,
            fields,
          )) {
            conflicts.add(
              TaskRebaseConflict(
                operationId: operation.operationId,
                operationKind: operation.kind,
                operationScheduleGeneration: operation.scheduleGeneration,
                currentScheduleGeneration: rebased.scheduleGeneration,
              ),
            );
            await _dao.updatePendingStatus(operation.operationId, 'blocked');
            if (isScheduleOperation) {
              blockedByScheduleConflict = true;
            }
            continue;
          }
          rebased = _reapplyPendingOperation(rebased, operation, fields);
        }
        await _dao.applyRemoteTask(_toCompanion(rebased));
      },
    );
    _lastRebaseDiagnostic = conflicts.isEmpty
        ? null
        : TaskRebaseDiagnostic(
            taskId: task.id,
            remoteScheduleGeneration: task.scheduleGeneration,
            conflicts: List.unmodifiable(conflicts),
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
    final updated = current
        .withSchedule(
          dueDate: draft.dueDate,
          hasTime: draft.hasTime,
          recurrenceRule: draft.recurrenceRule,
        )
        .copyWith(
          title: draft.title,
          reminder: draft.reminder,
          isCompleted: draft.isCompleted,
          lastCompletedAt: draft.lastCompletedAt,
          updatedAt: now,
        );
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

  static String _operationKind(TaskOperation operation) =>
      switch (operation.type) {
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

  static Map<String, dynamic> _decodePendingPayload(
    PendingTaskOperationData operation,
  ) {
    final payload = jsonDecode(operation.payloadJson);
    if (payload is! Map) {
      throw const FormatException('Pending task payload must be a JSON object');
    }
    return payload.cast<String, dynamic>();
  }

  static Task _reapplyPendingOperation(
    Task current,
    PendingTaskOperationData operation,
    Map<String, dynamic> fields,
  ) {
    switch (operation.kind) {
      case 'create':
      case 'upsert':
        return _reapplyPatch(current, fields, operation);
      case 'complete_occurrence':
      case 'completeOccurrence':
        return _reapplyCompletion(current, fields, operation, complete: true);
      case 'reopen_occurrence':
      case 'reopenOccurrence':
        return _reapplyCompletion(current, fields, operation, complete: false);
      case 'delete':
        return current.copyWith(
          deletedAt: operation.createdAt,
          updatedAt: operation.createdAt,
        );
      default:
        throw FormatException(
          'Unknown pending task operation: ${operation.kind}',
        );
    }
  }

  static bool _isCompatibleWithScheduleGeneration(
    Task current,
    PendingTaskOperationData operation,
    Map<String, dynamic> fields,
  ) {
    final isPatch = operation.kind == 'create' || operation.kind == 'upsert';
    if (!isPatch) {
      return operation.scheduleGeneration == current.scheduleGeneration;
    }

    final hasTime = fields['hasTime'] as bool? ?? current.hasTime;
    final dueDate = _parseWallClock(fields['dueDate'], hasTime: hasTime);
    final recurrence = fields.containsKey('recurrenceRule')
        ? fields['recurrenceRule'] as String?
        : current.recurrenceRule;
    final scheduleChanged =
        !sameScheduledAtOrNull(current.dueDate, dueDate, hasTime: hasTime) ||
        current.hasTime != hasTime ||
        current.recurrenceRule != recurrence;

    // A schedule patch stores the generation after its local increment. All
    // other operations store the generation they observed. This distinguishes
    // a compatible local schedule edit from one based on another device's
    // already-advanced schedule.
    return scheduleChanged
        ? operation.scheduleGeneration == current.scheduleGeneration + 1
        : operation.scheduleGeneration == current.scheduleGeneration;
  }

  static bool _isScheduleOperation(
    Task current,
    PendingTaskOperationData operation,
    Map<String, dynamic> fields,
  ) {
    final isPatch = operation.kind == 'create' || operation.kind == 'upsert';
    if (!isPatch) return false;

    final hasTime = fields['hasTime'] as bool? ?? current.hasTime;
    final dueDate = _parseWallClock(fields['dueDate'], hasTime: hasTime);
    final recurrence = fields.containsKey('recurrenceRule')
        ? fields['recurrenceRule'] as String?
        : current.recurrenceRule;
    return !sameScheduledAtOrNull(current.dueDate, dueDate, hasTime: hasTime) ||
        current.hasTime != hasTime ||
        current.recurrenceRule != recurrence;
  }

  static Task _reapplyPatch(
    Task current,
    Map<String, dynamic> fields,
    PendingTaskOperationData operation,
  ) {
    final hasTime = fields['hasTime'] as bool? ?? current.hasTime;
    final dueDate = _parseWallClock(fields['dueDate'], hasTime: hasTime);
    final recurrence = fields.containsKey('recurrenceRule')
        ? fields['recurrenceRule'] as String?
        : current.recurrenceRule;
    final scheduleChanged =
        !sameScheduledAtOrNull(current.dueDate, dueDate, hasTime: hasTime) ||
        current.hasTime != hasTime ||
        current.recurrenceRule != recurrence;
    final decodedCompletions = fields['completions'];
    final completions = scheduleChanged
        ? const <String, Object?>{}
        : decodedCompletions is Map
        ? decodedCompletions.cast<String, Object?>()
        : current.completions;
    return current.copyWith(
      title: fields['title'] as String? ?? current.title,
      dueDate: dueDate,
      hasTime: hasTime,
      recurrenceRule: recurrence,
      reminder: fields.containsKey('reminder')
          ? fields['reminder'] as String?
          : current.reminder,
      completions: completions,
      isCompleted: fields['isCompleted'] as bool? ?? current.isCompleted,
      lastCompletedAt: fields.containsKey('lastCompletedAt')
          ? _parseInstant(fields['lastCompletedAt'])
          : current.lastCompletedAt,
      updatedAt: operation.createdAt,
      scheduleGeneration: scheduleChanged
          ? operation.scheduleGeneration
          : current.scheduleGeneration,
    );
  }

  static Task _reapplyCompletion(
    Task current,
    Map<String, dynamic> fields,
    PendingTaskOperationData operation, {
    required bool complete,
  }) {
    final scheduledAt = fields['scheduledAt'] as String?;
    if (scheduledAt == null || scheduledAt.isEmpty) {
      throw const FormatException('Occurrence operation needs scheduledAt');
    }
    if (current.recurrenceRule == null) {
      return current.copyWith(
        isCompleted: complete,
        lastCompletedAt: complete ? operation.createdAt.toUtc() : null,
        updatedAt: operation.createdAt,
      );
    }
    final completions = {...current.completions};
    if (complete) {
      completions[scheduledAt] = operation.createdAt.toUtc().toIso8601String();
    } else {
      completions.remove(scheduledAt);
    }
    return current.copyWith(
      isCompleted: false,
      completions: completions,
      updatedAt: operation.createdAt,
    );
  }

  static DateTime? _parseWallClock(Object? value, {required bool hasTime}) {
    if (value == null) return null;
    if (value is! String) throw const FormatException('Invalid task dueDate');
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw const FormatException('Invalid task dueDate');
    return canonicalScheduledAt(parsed, hasTime: hasTime);
  }

  static DateTime? _parseInstant(Object? value) {
    if (value == null) return null;
    if (value is! String) {
      throw const FormatException('Invalid task completion instant');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw const FormatException('Invalid task completion instant');
    }
    return parsed.toUtc();
  }

  static bool sameScheduledAtOrNull(
    DateTime? left,
    DateTime? right, {
    required bool hasTime,
  }) {
    if (left == null || right == null) return left == right;
    return sameScheduledAt(left, right, hasTime: hasTime);
  }

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
