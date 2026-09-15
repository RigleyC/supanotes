import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

enum TaskOperationType {
  create,
  upsert,
  completeOccurrence,
  reopenOccurrence,
  delete,
}

class TaskOperation {
  TaskOperation._({
    required this.type,
    required this.operationId,
    required this.taskId,
    required this.observedRevision,
    required this.scheduleGeneration,
    required this.payload,
  }) : payloadHash = _hash(payload) {
    if (observedRevision < 0 || scheduleGeneration < 0) {
      throw const FormatException(
        'operation revisions and generations must not be negative',
      );
    }
  }

  factory TaskOperation.create({
    required String taskId,
    int observedRevision = 0,
    int scheduleGeneration = 0,
    required Map<String, dynamic> payload,
    String? operationId,
  }) => TaskOperation._(
    type: TaskOperationType.create,
    operationId: operationId ?? const Uuid().v4(),
    taskId: taskId,
    observedRevision: observedRevision,
    scheduleGeneration: scheduleGeneration,
    payload: payload,
  );
  factory TaskOperation.upsert({
    required String taskId,
    int observedRevision = 0,
    int scheduleGeneration = 0,
    required Map<String, dynamic> payload,
    String? operationId,
  }) => TaskOperation._(
    type: TaskOperationType.upsert,
    operationId: operationId ?? const Uuid().v4(),
    taskId: taskId,
    observedRevision: observedRevision,
    scheduleGeneration: scheduleGeneration,
    payload: payload,
  );
  factory TaskOperation.completeOccurrence({
    required String taskId,
    required String scheduledAt,
    int observedRevision = 0,
    required int scheduleGeneration,
    String? operationId,
  }) => TaskOperation._(
    type: TaskOperationType.completeOccurrence,
    operationId: operationId ?? const Uuid().v4(),
    taskId: taskId,
    observedRevision: observedRevision,
    scheduleGeneration: scheduleGeneration,
    payload: {'scheduledAt': scheduledAt},
  );
  factory TaskOperation.reopenOccurrence({
    required String taskId,
    required String scheduledAt,
    int observedRevision = 0,
    required int scheduleGeneration,
    String? operationId,
  }) => TaskOperation._(
    type: TaskOperationType.reopenOccurrence,
    operationId: operationId ?? const Uuid().v4(),
    taskId: taskId,
    observedRevision: observedRevision,
    scheduleGeneration: scheduleGeneration,
    payload: {'scheduledAt': scheduledAt},
  );
  factory TaskOperation.delete({
    required String taskId,
    int observedRevision = 0,
    int scheduleGeneration = 0,
    String? operationId,
  }) => TaskOperation._(
    type: TaskOperationType.delete,
    operationId: operationId ?? const Uuid().v4(),
    taskId: taskId,
    observedRevision: observedRevision,
    scheduleGeneration: scheduleGeneration,
    payload: const {},
  );

  final TaskOperationType type;
  final String operationId;
  final String taskId;
  final int observedRevision;
  final int scheduleGeneration;
  final Map<String, dynamic> payload;
  final String payloadHash;

  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'taskId': taskId,
    'observedRevision': observedRevision,
    'type': type.name,
    'scheduleGeneration': scheduleGeneration,
    'payload': payload,
    'payloadHash': payloadHash,
  };
}

String _hash(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(_sorted(value)))).toString();
Object? _sorted(Object? value) => value is Map
    ? {
        for (final key
            in (value.keys.map((e) => e.toString()).toList()..sort()))
          key: _sorted(value[key]),
      }
    : value is Iterable
    ? value.map((item) => _sorted(item)).toList()
    : value;
