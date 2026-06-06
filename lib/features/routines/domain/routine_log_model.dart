/// One row of the routine execution history.
///
/// The backend records every cron tick that triggered a brief, plus
/// the resulting LLM output and whether the run succeeded. The UI
/// uses this to render the "histórico" screen.
library;

import 'package:flutter/foundation.dart';

@immutable
class RoutineLogModel {
  const RoutineLogModel({
    required this.id,
    required this.routineId,
    required this.status,
    required this.content,
    required this.errorMsg,
    required this.createdAt,
  });

  final String id;
  final String routineId;

  /// One of `success` / `failed` (see `routines/runner.go`). Kept as
  /// a raw string so unknown statuses render verbatim instead of
  /// throwing.
  final String status;

  /// Markdown body produced by the LLM. May be empty if [status] is
  /// not `success`.
  final String content;

  /// Human-readable error message when [status] is `failed`.
  final String? errorMsg;

  final DateTime createdAt;

  /// Whether the run completed without error. Mirrors [status] being
  /// `success`; the UI uses this to decide whether to show the
  /// output (vs. the error message).
  bool get isSuccess => status == 'success';

  factory RoutineLogModel.fromJson(Map<String, dynamic> json) {
    return RoutineLogModel(
      id: (json['id'] ?? '') as String,
      routineId: (json['routine_id'] ?? '') as String,
      status: (json['status'] ?? '') as String,
      content: (json['content'] ?? '') as String,
      errorMsg: json['error_msg'] as String?,
      createdAt: _parseTimestamp(json['created_at']),
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
