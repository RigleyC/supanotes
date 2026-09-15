import 'dart:convert';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/async/keyed_async_queue.dart';
import 'package:supanotes/core/database/daos/tasks_dao.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/tasks/data/task_api.dart';
import 'package:supanotes/features/tasks/data/task_repository.dart';
import 'package:supanotes/features/tasks/domain/task.dart';
import 'package:supanotes/features/tasks/domain/task_operation.dart';

/// Serializes one task's durable mutations and applies canonical responses.
///
/// The server response is authoritative only for the operation identified by
/// its `operationId`. Later local operations stay in the outbox and are
/// rebased by [TaskRepository] over the returned canonical task.
class TaskSyncService {
  TaskSyncService({
    required TaskApi api,
    TaskRepository? repository,
    TasksDao? dao,
    String? userId,
  }) : _api = api,
       _repository = repository ?? _newRepository(dao, userId),
       _dao = dao ?? repository!.dao;

  final TaskApi _api;
  final TaskRepository _repository;
  final TasksDao _dao;
  final KeyedAsyncQueue _queue = KeyedAsyncQueue();

  String get userId => _repository.userId;

  static TaskRepository _newRepository(TasksDao? dao, String? userId) {
    if (dao == null || userId == null || userId.isEmpty) {
      throw ArgumentError('dao and userId are required without repository');
    }
    return TaskRepository(dao, userId);
  }

  Future<TaskBootstrapResponse> bootstrap() => _api.bootstrap();

  Future<void> applyBootstrapInTransaction(
    TaskBootstrapResponse snapshot,
  ) => _repository.applyRemoteTasksInTransaction(snapshot.tasks);

  Future<void> applyTaskChanged(String taskId) async {
    try {
      await _repository.applyRemoteTask(await _api.fetch(taskId));
    } on NotFoundException {
      await _repository.applyRemoteDeletion(taskId);
    }
  }

  Future<void> applyTaskDeleted(String taskId) {
    return _repository.applyRemoteDeletion(taskId);
  }

  Future<void> syncTask(String taskId) {
    return _queue.run(taskId, () => _syncTask(taskId));
  }

  Future<void> _syncTask(String taskId) async {
    final operations = (await _dao.getPendingOperations(userId, taskId))
        .where(
          (operation) =>
              operation.status == 'pending' || operation.status == 'in_flight',
        )
        .toList(growable: false);
    if (operations.isEmpty) return;

    final current = await _repository.get(taskId);
    if (current == null) {
      throw StateError('Cannot sync task without a local snapshot: $taskId');
    }
    final operation = _firstInFlightOrFirstPending(operations);
    final request = _decodeOperation(operation, current);
    final attempt = operation.attemptCount + 1;
    final attemptAt = DateTime.now().toUtc();
    await _dao.updatePendingStatus(
      operation.operationId,
      'in_flight',
      attemptCount: attempt,
      lastAttemptAt: attemptAt,
    );

    try {
      final response = await _api.mutate(request);
      if (response.operationId != operation.operationId) {
        throw StateError(
          'Task mutation confirmation does not match operationId '
          '${operation.operationId}: ${response.operationId}',
        );
      }

      // Delete only the operation named by the response. In particular, do
      // not remove the first row merely because it was sent before a retry.
      await _repository.confirmRemoteTask(
        task: response.task,
        operationId: response.operationId,
        confirmedOrdinal: operation.ordinal,
      );
    } on ApiException catch (error, stackTrace) {
      if (_isBlockedProtocolError(error)) {
        await _dao.updatePendingStatus(
          operation.operationId,
          'blocked',
          attemptCount: attempt,
          lastAttemptAt: attemptAt,
        );
        if (error.statusCode == 409 || error.statusCode == 410) return;
      } else {
        await _markPending(operation, attempt, attemptAt);
      }
      Error.throwWithStackTrace(error, stackTrace);
    } catch (error, stackTrace) {
      await _markPending(operation, attempt, attemptAt);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _markPending(
    PendingTaskOperationData operation,
    int attempt,
    DateTime attemptAt,
  ) {
    return _dao.updatePendingStatus(
      operation.operationId,
      'pending',
      attemptCount: attempt,
      lastAttemptAt: attemptAt,
    );
  }

  static PendingTaskOperationData _firstInFlightOrFirstPending(
    List<PendingTaskOperationData> operations,
  ) {
    for (final operation in operations) {
      if (operation.status == 'in_flight') return operation;
    }
    return operations.first;
  }

  static TaskOperation _decodeOperation(
    PendingTaskOperationData row,
    Task current,
  ) {
    final decoded = jsonDecode(row.payloadJson);
    if (decoded is! Map) {
      throw const FormatException('Pending task payload must be an object');
    }
    final payload = decoded.cast<String, dynamic>();
    switch (row.kind) {
      case 'create':
        return TaskOperation.create(
          operationId: row.operationId,
          taskId: row.taskId,
          observedRevision: row.observedRevision,
          scheduleGeneration: row.scheduleGeneration,
          payload: payload,
        );
      case 'upsert':
      case 'update':
        return TaskOperation.upsert(
          operationId: row.operationId,
          taskId: row.taskId,
          observedRevision: row.observedRevision,
          scheduleGeneration: row.scheduleGeneration,
          payload: payload,
        );
      case 'complete_occurrence':
      case 'completeOccurrence':
        return TaskOperation.completeOccurrence(
          operationId: row.operationId,
          taskId: row.taskId,
          observedRevision: row.observedRevision,
          scheduleGeneration: row.scheduleGeneration,
          scheduledAt: _scheduledAt(payload),
          hasTime: current.hasTime,
        );
      case 'reopen_occurrence':
      case 'reopenOccurrence':
        return TaskOperation.reopenOccurrence(
          operationId: row.operationId,
          taskId: row.taskId,
          observedRevision: row.observedRevision,
          scheduleGeneration: row.scheduleGeneration,
          scheduledAt: _scheduledAt(payload),
          hasTime: current.hasTime,
        );
      case 'delete':
        return TaskOperation.delete(
          operationId: row.operationId,
          taskId: row.taskId,
          observedRevision: row.observedRevision,
          scheduleGeneration: row.scheduleGeneration,
        );
      default:
        throw FormatException('Unknown task operation kind: ${row.kind}');
    }
  }

  static String _scheduledAt(Map<String, dynamic> payload) {
    final value = payload['scheduledAt'];
    if (value is! String || value.isEmpty) {
      throw const FormatException('Occurrence operation needs scheduledAt');
    }
    return value;
  }

  static bool _isBlockedProtocolError(ApiException error) {
    final status = error.statusCode;
    return status != null &&
        status >= 400 &&
        status < 500 &&
        status != 401 &&
        status != 408 &&
        status != 429;
  }
}
