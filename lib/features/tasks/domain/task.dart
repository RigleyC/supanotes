import 'dart:collection';

import 'package:supanotes/features/tasks/domain/task_schedule_identity.dart';

const _unset = Object();

/// The canonical independently persisted task.
class Task {
  Task({
    required this.id,
    required this.ownerUserId,
    required String title,
    DateTime? dueDate,
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
       dueDate = dueDate == null
           ? null
           : canonicalScheduledAt(dueDate, hasTime: hasTime),
       completions = UnmodifiableMapView(
         _normalizeCompletions(completions, hasTime: hasTime),
       ) {
    _requireGeneration(scheduleGeneration);
    if (revision < 0)
      throw const FormatException('revision must not be negative');
  }

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    ownerUserId:
        json['owner_user_id'] as String? ?? json['ownerUserId'] as String,
    title: json['title'] as String,
    dueDate: _parseScheduledDate(json['due_date'] ?? json['dueDate']),
    hasTime: json['has_time'] as bool? ?? json['hasTime'] as bool? ?? false,
    recurrenceRule:
        json['recurrence_rule'] as String? ?? json['recurrenceRule'] as String?,
    reminder: json['reminder'] as String?,
    completions:
        (json['completions'] as Map?)?.cast<String, Object?>() ?? const {},
    isCompleted:
        json['is_completed'] as bool? ?? json['isCompleted'] as bool? ?? false,
    lastCompletedAt: _parseInstant(
      json['last_completed_at'] ?? json['lastCompletedAt'],
    ),
    revision: (json['revision'] as num?)?.toInt() ?? 0,
    createdAt: _requiredInstant(json['created_at'] ?? json['createdAt']),
    updatedAt: _requiredInstant(json['updated_at'] ?? json['updatedAt']),
    deletedAt: _parseInstant(json['deleted_at'] ?? json['deletedAt']),
    scheduleGeneration: _parseGeneration(
      json['schedule_generation'] ?? json['scheduleGeneration'],
    ),
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
    'due_date': dueDate == null
        ? null
        : scheduledAtKey(dueDate!, hasTime: hasTime),
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
    Object? dueDate = _unset,
    bool? hasTime,
    Object? recurrenceRule = _unset,
    Object? reminder = _unset,
    Map<String, Object?>? completions,
    bool? isCompleted,
    Object? lastCompletedAt = _unset,
    int? revision,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? deletedAt = _unset,
    int? scheduleGeneration,
  }) => Task(
    id: id ?? this.id,
    ownerUserId: ownerUserId ?? this.ownerUserId,
    title: title ?? this.title,
    dueDate: identical(dueDate, _unset) ? this.dueDate : dueDate as DateTime?,
    hasTime: hasTime ?? this.hasTime,
    recurrenceRule: identical(recurrenceRule, _unset)
        ? this.recurrenceRule
        : recurrenceRule as String?,
    reminder: identical(reminder, _unset) ? this.reminder : reminder as String?,
    completions: completions ?? this.completions,
    isCompleted: isCompleted ?? this.isCompleted,
    lastCompletedAt: identical(lastCompletedAt, _unset)
        ? this.lastCompletedAt
        : lastCompletedAt as DateTime?,
    revision: revision ?? this.revision,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: identical(deletedAt, _unset)
        ? this.deletedAt
        : deletedAt as DateTime?,
    scheduleGeneration: scheduleGeneration ?? this.scheduleGeneration,
  );

  Task withSchedule({
    Object? dueDate = _unset,
    bool? hasTime,
    Object? recurrenceRule = _unset,
  }) {
    final nextHasTime = hasTime ?? this.hasTime;
    final nextDueDate = identical(dueDate, _unset)
        ? this.dueDate
        : dueDate as DateTime?;
    final nextRecurrenceRule = identical(recurrenceRule, _unset)
        ? this.recurrenceRule
        : recurrenceRule as String?;
    final changed =
        (this.dueDate == null) != (nextDueDate == null) ||
        (this.dueDate != null &&
            nextDueDate != null &&
            !sameScheduledAt(
              this.dueDate!,
              nextDueDate,
              hasTime: nextHasTime,
            )) ||
        nextHasTime != this.hasTime ||
        nextRecurrenceRule != this.recurrenceRule;
    return copyWith(
      dueDate: nextDueDate,
      hasTime: hasTime,
      recurrenceRule: nextRecurrenceRule,
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

Map<String, String> _normalizeCompletions(
  Map<String, Object?> values, {
  required bool hasTime,
}) => {
  for (final entry in values.entries)
    _canonicalScheduledKey(entry.key, hasTime: hasTime): _canonicalInstant(
      entry.value,
    ),
};

String _canonicalScheduledKey(String value, {required bool hasTime}) {
  try {
    final parsed = _parseScheduledLexically(value);
    return scheduledAtKey(parsed, hasTime: hasTime);
  } on FormatException {
    throw const FormatException('invalid scheduledAt key');
  }
}

String _canonicalInstant(Object? value) {
  try {
    final parsed = value is DateTime ? value : _parseInstant(value as String)!;
    return parsed.toUtc().toIso8601String();
  } on FormatException {
    throw const FormatException('invalid completion timestamp');
  } on TypeError {
    throw const FormatException('invalid completion timestamp');
  }
}

DateTime _parseScheduledLexically(String value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?$',
  ).firstMatch(value);
  if (match == null) {
    throw const FormatException(
      'scheduledAt must not contain a timezone offset',
    );
  }
  final fraction = (match.group(7) ?? '').padRight(6, '0');
  final result = DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6) ?? '0'),
    int.parse(fraction.substring(0, 3)),
    int.parse(fraction.substring(3)),
  );
  if (result.year != int.parse(match.group(1)!) ||
      result.month != int.parse(match.group(2)!) ||
      result.day != int.parse(match.group(3)!) ||
      result.hour != int.parse(match.group(4)!) ||
      result.minute != int.parse(match.group(5)!) ||
      result.second != int.parse(match.group(6) ?? '0')) {
    throw const FormatException('scheduledAt contains invalid components');
  }
  return result;
}

DateTime? _parseScheduledDate(Object? value) =>
    value == null ? null : _parseScheduledLexically(value as String);

DateTime? _parseInstant(Object? value) =>
    value == null ? null : _parseInstantString(value as String);

DateTime _parseInstantString(String value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?(Z|[+-]\d{2}:\d{2})$',
  ).firstMatch(value);
  if (match == null) {
    throw const FormatException('instant must include an explicit offset');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6) ?? '0');
  final offset = match.group(8)!;
  final offsetHour = offset == 'Z' ? 0 : int.parse(offset.substring(1, 3));
  final offsetMinute = offset == 'Z' ? 0 : int.parse(offset.substring(4, 6));
  final fraction = (match.group(7) ?? '').padRight(6, '0');
  final local = DateTime(
    year,
    month,
    day,
    hour,
    minute,
    second,
    int.parse(fraction.substring(0, 3)),
    int.parse(fraction.substring(3)),
  );
  if (local.year != year ||
      local.month != month ||
      local.day != day ||
      local.hour != hour ||
      local.minute != minute ||
      local.second != second ||
      offsetHour > 23 ||
      offsetMinute > 59) {
    throw const FormatException('invalid instant components');
  }
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    throw const FormatException('invalid instant');
  }
}

DateTime _requiredInstant(Object? value) {
  final parsed = _parseInstant(value);
  if (parsed == null) throw const FormatException('instant is required');
  return parsed;
}

int _parseGeneration(Object? value) {
  if (value == null) return 0;
  if (value is! int || value < 0) {
    throw const FormatException(
      'scheduleGeneration must be a non-negative integer',
    );
  }
  return value;
}

bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) =>
    a.toString() == b.toString();
