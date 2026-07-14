import 'dart:convert';

class YjsTaskEntry {
  final String nodeId;
  final bool completed;
  final String? title;
  final String? dueDate;
  final String? recurrence;
  final String? lastCompletedAt;

  const YjsTaskEntry({
    required this.nodeId,
    required this.completed,
    this.title,
    this.dueDate,
    this.recurrence,
    this.lastCompletedAt,
  });

  factory YjsTaskEntry.fromJson(Map<String, dynamic> json) {
    return YjsTaskEntry(
      nodeId: json['nodeId'] as String,
      completed: json['completed'] == true,
      title: json['title'] as String?,
      dueDate: json['dueDate'] as String?,
      recurrence: json['recurrence'] as String?,
      lastCompletedAt: json['lastCompletedAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'nodeId': nodeId, 'completed': completed};
    if (title != null) map['title'] = title;
    if (dueDate != null) map['dueDate'] = dueDate;
    if (recurrence != null) map['recurrence'] = recurrence;
    if (lastCompletedAt != null) map['lastCompletedAt'] = lastCompletedAt;
    return map;
  }

  YjsTaskEntry copyWith({
    String? nodeId,
    bool? completed,
    String? title,
    String? dueDate,
    String? recurrence,
    String? lastCompletedAt,
  }) {
    return YjsTaskEntry(
      nodeId: nodeId ?? this.nodeId,
      completed: completed ?? this.completed,
      title: title ?? this.title,
      dueDate: dueDate ?? this.dueDate,
      recurrence: recurrence ?? this.recurrence,
      lastCompletedAt: lastCompletedAt ?? this.lastCompletedAt,
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
}
