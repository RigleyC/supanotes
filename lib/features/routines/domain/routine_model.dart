/// Domain types for the Routines feature.
///
/// The backend stores brief schedules as 5-field cron expressions
/// (`minute hour day-of-month month day-of-week`) using the
/// `robfig/cron/v3` convention where the day-of-week field treats
/// `0` and `7` as Sunday and `1..6` as Monday..Saturday. The UI never
/// asks the user to type cron directly — instead it surfaces a
/// multi-select day picker + a time picker, and translates to/from
/// cron here.
library;

import 'package:flutter/material.dart';

/// Which kind of brief a [RoutineModel] represents.
enum BriefType {
  daily,
  weekly;

  /// Pretty label shown on the schedule cards.
  String get displayName {
    switch (this) {
      case BriefType.daily:
        return 'Brief diário';
      case BriefType.weekly:
        return 'Brief semanal';
    }
  }

  /// Path fragment used for the matching `/test` endpoint.
  String get testPath {
    switch (this) {
      case BriefType.daily:
        return 'daily';
      case BriefType.weekly:
        return 'weekly';
    }
  }

  static BriefType fromJson(String value) {
    switch (value) {
      case 'daily':
        return BriefType.daily;
      case 'weekly':
        return BriefType.weekly;
      default:
        throw ArgumentError('Unknown brief type: $value');
    }
  }
}

/// A user-friendly schedule: which days the brief fires, and at what
/// local time. `daysOfWeek` follows the ISO convention used in
/// [DateTime.weekday], i.e. `1 = Monday … 7 = Sunday`.
@immutable
class RoutineSchedule {
  const RoutineSchedule({
    required this.daysOfWeek,
    required this.hour,
    required this.minute,
  });

  /// Days the brief fires. Always 1..7 (Monday..Sunday).
  final List<int> daysOfWeek;

  /// 0..23, in the user's local timezone.
  final int hour;

  /// 0..59.
  final int minute;

  /// Returns a [TimeOfDay] suitable for [showTimePicker].
  TimeOfDay get timeOfDay => TimeOfDay(hour: hour, minute: minute);
}

/// Builds a 5-field cron expression for the robfig/cron/v3 parser
/// from a [RoutineSchedule].
///
/// Format produced: `M H * * d1,d2,...` where day numbers are
/// translated to robfig's convention (0=Sun, 1=Mon, …, 6=Sat). The
/// day-of-month and month fields are always `*` because the UI does
/// not expose them.
String buildCronExpr({
  required List<int> daysOfWeek,
  required int hour,
  required int minute,
}) {
  assert(daysOfWeek.isNotEmpty, 'Cron expression needs at least one day');
  for (final d in daysOfWeek) {
    assert(d >= 1 && d <= 7, 'daysOfWeek must be 1..7 (Mon..Sun)');
  }
  assert(hour >= 0 && hour <= 23, 'hour must be 0..23');
  assert(minute >= 0 && minute <= 59, 'minute must be 0..59');

  final cronDays = daysOfWeek.map((d) => d == 7 ? 0 : d).toList()..sort();
  return '$minute $hour * * ${cronDays.join(',')}';
}

/// Parses a 5-field cron expression produced by [buildCronExpr] back
/// into a [RoutineSchedule]. Returns `null` if the expression uses
/// any feature the UI does not produce (L/W modifiers, ranges in
/// day-of-month, named months, etc.) so the caller can fall back to a
/// safe default.
RoutineSchedule? scheduleFromCronExpr(String cronExpr) {
  final parts = cronExpr.trim().split(RegExp(r'\s+'));
  if (parts.length != 5) return null;

  final minute = int.tryParse(parts[0]);
  final hour = int.tryParse(parts[1]);
  if (minute == null || hour == null) return null;
  if (minute < 0 || minute > 59) return null;
  if (hour < 0 || hour > 23) return null;

  // We never produce anything other than `*` in the day-of-month and
  // month fields. Bail if the backend handed us something fancier.
  if (parts[2] != '*' || parts[3] != '*') return null;

  final dow = parts[4];
  if (dow == '*' || dow.isEmpty) return null;

  final days = <int>{};
  for (final piece in dow.split(',')) {
    final token = piece.trim();
    if (token.isEmpty) return null;

    if (token.contains('-')) {
      final range = token.split('-');
      if (range.length != 2) return null;
      final start = int.tryParse(range[0]);
      final end = int.tryParse(range[1]);
      if (start == null || end == null) return null;
      if (start < 0 || start > 7 || end < 0 || end > 7) return null;
      if (start > end) return null;
      for (var i = start; i <= end; i++) {
        days.add(_cronDayToClientDay(i));
      }
    } else {
      final v = int.tryParse(token);
      if (v == null) return null;
      if (v < 0 || v > 7) return null;
      days.add(_cronDayToClientDay(v));
    }
  }

  if (days.isEmpty) return null;
  final sorted = days.toList()..sort();
  return RoutineSchedule(
    daysOfWeek: sorted,
    hour: hour,
    minute: minute,
  );
}

int _cronDayToClientDay(int cronDay) {
  // robfig: 0=Sun, 1=Mon, ..., 6=Sat, 7=Sun (alias).
  return cronDay == 0 ? 7 : cronDay;
}

/// A configured brief schedule owned by the signed-in user.
@immutable
class RoutineModel {
  const RoutineModel({
    required this.id,
    required this.briefType,
    required this.cronExpr,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final BriefType briefType;
  final String cronExpr;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Localized display name (the backend does not store one).
  String get name => briefType.displayName;

  /// The backend has no `last_run_at` column today; this is wired
  /// into the model so the UI can render the field the moment the
  /// backend starts exposing it without a model change.
  DateTime? get lastRunAt => null;

  /// Parses [cronExpr] back into a [RoutineSchedule]. Returns `null`
  /// when the expression is not in the format [buildCronExpr]
  /// produces — the UI uses that signal to disable day/time editing.
  RoutineSchedule? get schedule => scheduleFromCronExpr(cronExpr);

  /// Returns a copy of this routine with the fields in [patch]
  /// replaced. Only the user-mutable fields are exposed.
  RoutineModel copyWith({
    String? cronExpr,
    bool? enabled,
  }) {
    return RoutineModel(
      id: id,
      briefType: briefType,
      cronExpr: cronExpr ?? this.cronExpr,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  factory RoutineModel.fromJson(Map<String, dynamic> json) {
    return RoutineModel(
      id: (json['id'] ?? '') as String,
      briefType: BriefType.fromJson((json['type'] ?? '') as String),
      cronExpr: (json['cron_expr'] ?? '') as String,
      enabled: (json['enabled'] ?? false) as bool,
      createdAt: _parseTimestamp(json['created_at']),
      updatedAt: _parseTimestamp(json['updated_at']),
    );
  }
}

DateTime _parseTimestamp(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    return DateTime.parse(raw).toUtc();
  }
  if (raw is DateTime) return raw.toUtc();
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
