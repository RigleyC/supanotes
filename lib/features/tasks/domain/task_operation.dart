import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:supanotes/features/tasks/domain/task_schedule_identity.dart';

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
    required Map<String, dynamic> payload,
  }) : payload = _freeze(payload),
       payloadHash = _hash(_freeze(payload)) {
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
    required bool hasTime,
    int observedRevision = 0,
    required int scheduleGeneration,
    String? operationId,
  }) => TaskOperation._(
    type: TaskOperationType.completeOccurrence,
    operationId: operationId ?? const Uuid().v4(),
    taskId: taskId,
    observedRevision: observedRevision,
    scheduleGeneration: scheduleGeneration,
    payload: {
      'scheduledAt': _canonicalScheduledAt(scheduledAt, hasTime: hasTime),
    },
  );
  factory TaskOperation.reopenOccurrence({
    required String taskId,
    required String scheduledAt,
    required bool hasTime,
    int observedRevision = 0,
    required int scheduleGeneration,
    String? operationId,
  }) => TaskOperation._(
    type: TaskOperationType.reopenOccurrence,
    operationId: operationId ?? const Uuid().v4(),
    taskId: taskId,
    observedRevision: observedRevision,
    scheduleGeneration: scheduleGeneration,
    payload: {
      'scheduledAt': _canonicalScheduledAt(scheduledAt, hasTime: hasTime),
    },
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
    'kind': type.name,
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

Map<String, dynamic> _freeze(Map<String, dynamic> value) => Map.unmodifiable({
  for (final entry in value.entries) entry.key: _freezeValue(entry.value),
});

Object? _freezeValue(Object? value) => value is Map
    ? Map.unmodifiable({
        for (final entry in value.entries)
          entry.key.toString(): _freezeValue(entry.value),
      })
    : value is Iterable
    ? List.unmodifiable(value.map(_freezeValue))
    : value;

String _canonicalScheduledAt(String value, {required bool hasTime}) {
  try {
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?$',
    ).firstMatch(value);
    if (match == null) throw const FormatException();
    final fraction = (match.group(7) ?? '').padRight(6, '0');
    final parsed = DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6) ?? '0'),
      int.parse(fraction.substring(0, 3)),
      int.parse(fraction.substring(3)),
    );
    if (parsed.year != int.parse(match.group(1)!) ||
        parsed.month != int.parse(match.group(2)!) ||
        parsed.day != int.parse(match.group(3)!) ||
        parsed.hour != int.parse(match.group(4)!) ||
        parsed.minute != int.parse(match.group(5)!) ||
        parsed.second != int.parse(match.group(6) ?? '0')) {
      throw const FormatException('scheduledAt contains invalid components');
    }
    return scheduledAtKey(parsed, hasTime: hasTime);
  } on FormatException {
    throw const FormatException('invalid scheduledAt');
  }
}
