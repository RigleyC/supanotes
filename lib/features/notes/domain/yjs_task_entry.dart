import 'dart:convert';

class YjsTaskEntry {
  final String nodeId;
  final bool completed;
  final String? title;
  final String? dueDate;
  final bool? hasTime;
  final String? recurrence;
  final String? lastCompletedAt;
  final String? reminder;

  const YjsTaskEntry({
    required this.nodeId,
    required this.completed,
    this.title,
    this.dueDate,
    this.hasTime,
    this.recurrence,
    this.lastCompletedAt,
    this.reminder,
  });

  factory YjsTaskEntry.fromJson(Map<String, dynamic> json) {
    return YjsTaskEntry(
      nodeId: json['nodeId'] as String,
      completed: json['completed'] == true,
      title: json['title'] as String?,
      dueDate: json['dueDate'] as String?,
      hasTime: json['hasTime'] as bool?,
      recurrence: json['recurrence'] as String?,
      lastCompletedAt: json['lastCompletedAt'] as String?,
      reminder: json['reminder'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'nodeId': nodeId, 'completed': completed};
    if (title != null) map['title'] = title;
    if (dueDate != null) map['dueDate'] = dueDate;
    if (hasTime != null) map['hasTime'] = hasTime;
    if (recurrence != null) map['recurrence'] = recurrence;
    if (lastCompletedAt != null) map['lastCompletedAt'] = lastCompletedAt;
    if (reminder != null) map['reminder'] = reminder;
    return map;
  }

  YjsTaskEntry copyWith({
    String? nodeId,
    bool? completed,
    String? title,
    String? dueDate,
    bool? hasTime,
    String? recurrence,
    String? lastCompletedAt,
    String? reminder,
  }) {
    return YjsTaskEntry(
      nodeId: nodeId ?? this.nodeId,
      completed: completed ?? this.completed,
      title: title ?? this.title,
      dueDate: dueDate ?? this.dueDate,
      hasTime: hasTime ?? this.hasTime,
      recurrence: recurrence ?? this.recurrence,
      lastCompletedAt: lastCompletedAt ?? this.lastCompletedAt,
      reminder: reminder ?? this.reminder,
    );
  }

  String encode() => jsonEncode(toJson());

  static YjsTaskEntry? decode(String? raw) {
    if (raw == null) return null;
    try {
      return YjsTaskEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is YjsTaskEntry &&
        other.nodeId == nodeId &&
        other.title == title &&
        other.dueDate == dueDate &&
        other.hasTime == hasTime &&
        other.recurrence == recurrence &&
        other.lastCompletedAt == lastCompletedAt &&
        other.reminder == reminder;
  }

  @override
  int get hashCode => Object.hash(
    nodeId, title, dueDate, hasTime, recurrence, lastCompletedAt, reminder,
  );
}
