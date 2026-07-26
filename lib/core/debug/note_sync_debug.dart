import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';

typedef NoteSyncLogSink =
    void Function(String event, String? noteId, Map<String, Object?> fields);

class NoteSyncDebug {
  NoteSyncDebug._();

  @visibleForTesting
  static NoteSyncLogSink? logSink;

  static void log(
    String event, {
    String? noteId,
    Map<String, Object?> fields = const {},
  }) {
    final safeFields = fields.map(
      (key, value) => MapEntry(key, _sanitizeField(key, value)),
    );
    logSink?.call(event, noteId, safeFields);
    if (!kDebugMode) return;
    final details = safeFields.entries
        .map((entry) => '${entry.key}=${_format(entry.value)}')
        .join(' ');
    dev.log(
      '[NOTE_SYNC_DEBUG] event=$event${noteId == null ? '' : ' note=$noteId'} $details',
      name: 'NoteSyncDebug',
    );
  }

  static String preview(String text, {int maxLength = 80}) {
    final normalized = text.replaceAll('\n', '\\n');
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength)}...';
  }

  static String documentSummary(Map<String, dynamic> document) {
    final blocks = document['blocks'] as List<dynamic>? ?? const [];
    return blocks
        .map((block) {
          final value = block as Map;
          final delta = value['delta'] as List<dynamic>? ?? const [];
          final text = delta
              .whereType<Map>()
              .map((op) => op['insert'] is String ? op['insert'] as String : '')
              .join();
          return '${value['id']}:${value['type']}(chars=${text.length})';
        })
        .join('|');
  }

  static String payloadSummary(Map<String, dynamic> payload) {
    final keys = payload.keys.toList()..sort();
    final opCount = payload['ops'] is List
        ? (payload['ops'] as List).length
        : null;
    return 'keys=${keys.join(',')}${opCount == null ? '' : ' ops=$opCount'}';
  }

  static String errorClass(Object error) => error.runtimeType.toString();

  static String urlSummary(String rawUrl) {
    final parsed = Uri.tryParse(rawUrl);
    if (parsed == null || parsed.host.isEmpty) return 'invalid-url';
    return '${parsed.scheme}://${parsed.host}';
  }

  static String _format(Object? value) {
    if (value is String) return '"${preview(value)}"';
    return value?.toString() ?? 'null';
  }

  static Object? _sanitizeField(String key, Object? value) {
    final lower = key.toLowerCase();
    if (lower.contains('token') ||
        lower.contains('authorization') ||
        lower.contains('secret')) {
      return '<redacted>';
    }
    if (lower == 'url' || lower.endsWith('url')) {
      return value is String ? urlSummary(value) : '<redacted-url>';
    }
    if (lower.contains('payload')) {
      if (value is Map<String, dynamic>) return payloadSummary(value);
      return '<payload>';
    }
    if (lower.contains('document') && value is Map<String, dynamic>) {
      return documentSummary(value);
    }
    return value;
  }
}
