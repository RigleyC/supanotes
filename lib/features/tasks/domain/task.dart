import 'dart:collection';

import 'package:supanotes/features/tasks/domain/task_reminder_option.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_schedule_identity.dart';

/// The canonical independently persisted task.
class Task {
  Task({
    required this.id,
    required this.ownerUserId,
    required String title,
    this.dueDate,
    this.hasTime = false,
    this.recurrenceRule,
    this.reminder,
    Map<String, Object?> completions = const {},
    this.isCompleted = false,
    this.lastCompletedAt,
    this.revision = 0,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.scheduleGeneration = 0,
  }) : title = _requireTitle(title),
       completions = UnmodifiableMapView(_normalizeCompletions(completions)) {
    _requireGeneration(scheduleGeneration);
    if (revision < 0)
      throw const FormatException('revision must not be negative');
  }

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    ownerUserId:
        json['owner_user_id'] as String? ?? json['ownerUserId'] as String,
    title: json['title'] as String,
    dueDate: _parseDate(json['due_date'] ?? json['dueDate']),
    hasTime: json['has_time'] as bool? ?? json['hasTime'] as bool? ?? false,
    recurrenceRule:
        json['recurrence_rule'] as String? ?? json['recurrenceRule'] as String?,
    reminder: json['reminder'] as String?,
    completions:
        (json['completions'] as Map?)?.cast<String, Object?>() ?? const {},
    isCompleted:
        json['is_completed'] as bool? ?? json['isCompleted'] as bool? ?? false,
    lastCompletedAt: _parseDate(
      json['last_completed_at'] ?? json['lastCompletedAt'],
    ),
    revision: (json['revision'] as num?)?.toInt() ?? 0,
    createdAt: _requiredDate(json['created_at'] ?? json['createdAt']),
    updatedAt: _requiredDate(json['updated_at'] ?? json['updatedAt']),
    deletedAt: _parseDate(json['deleted_at'] ?? json['deletedAt']),
    scheduleGeneration:
        (json['schedule_generation'] ?? json['scheduleGeneration'] as num?)
            is num
        ? ((json['schedule_generation'] ?? json['scheduleGeneration']) as num)
              .toInt()
        : 0,
  );

  final String id;
  final String ownerUserId;
  final String title;
  final DateTime? dueDate;
  final bool hasTime;
  final String? recurrenceRule;
  final String? reminder;
  final Map<String, String> completions;
  final bool isCompleted;
  final DateTime? lastCompletedAt;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int scheduleGeneration;

  Map<String, dynamic> toJson() => {
    'id': id,
    'owner_user_id': ownerUserId,
    'title': title,
    'due_date': dueDate?.toUtc().toIso8601String(),
    'has_time': hasTime,
    'recurrence_rule': recurrenceRule,
    'reminder': reminder,
    'completions': SplayTreeMap<String, String>.from(completions),
    'is_completed': isCompleted,
    'last_completed_at': lastCompletedAt?.toUtc().toIso8601String(),
    'revision': revision,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
    'schedule_generation': scheduleGeneration,
  };

  Task copyWith({
    String? id,
    String? ownerUserId,
    String? title,
    DateTime? dueDate,
    bool? hasTime,
    String? recurrenceRule,
    String? reminder,
    Map<String, Object?>? completions,
    bool? isCompleted,
    DateTime? lastCompletedAt,
    int? revision,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? scheduleGeneration,
  }) => Task(
    id: id ?? this.id,
    ownerUserId: ownerUserId ?? this.ownerUserId,
    title: title ?? this.title,
    dueDate: dueDate ?? this.dueDate,
    hasTime: hasTime ?? this.hasTime,
    recurrenceRule: recurrenceRule ?? this.recurrenceRule,
    reminder: reminder ?? this.reminder,
    completions: completions ?? this.completions,
    isCompleted: isCompleted ?? this.isCompleted,
    lastCompletedAt: lastCompletedAt ?? this.lastCompletedAt,
    revision: revision ?? this.revision,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
    scheduleGeneration: scheduleGeneration ?? this.scheduleGeneration,
  );

  Task withSchedule({
    DateTime? dueDate,
    bool? hasTime,
    String? recurrenceRule,
  }) {
    final nextHasTime = hasTime ?? this.hasTime;
    final changed =
        (this.dueDate == null) != (dueDate == null) ||
        (this.dueDate != null &&
            dueDate != null &&
            !sameScheduledAt(this.dueDate!, dueDate, hasTime: nextHasTime)) ||
        nextHasTime != this.hasTime ||
        recurrenceRule != this.recurrenceRule;
    return copyWith(
      dueDate: dueDate,
      hasTime: hasTime,
      recurrenceRule: recurrenceRule,
      completions: changed ? const {} : completions,
      scheduleGeneration: changed ? scheduleGeneration + 1 : scheduleGeneration,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Task && _mapsEqual(toJson(), other.toJson());

  @override
  int get hashCode => toJson().toString().hashCode;
}

String _requireTitle(String value) {
  if (value.trim().isEmpty)
    throw const FormatException('title must not be empty');
  return value;
}

void _requireGeneration(int value) {
  if (value < 0)
    throw const FormatException('scheduleGeneration must not be negative');
}

Map<String, String> _normalizeCompletions(Map<String, Object?> values) => {
  for (final entry in values.entries)
    entry.key: entry.value is DateTime
        ? (entry.value! as DateTime).toUtc().toIso8601String()
        : entry.value.toString(),
};

DateTime? _parseDate(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
DateTime _requiredDate(Object? value) => _parseDate(value)!;

bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) =>
    a.toString() == b.toString();
