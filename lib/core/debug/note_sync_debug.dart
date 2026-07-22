import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';

class NoteSyncDebug {
  NoteSyncDebug._();

  static void log(
    String event, {
    String? noteId,
    Map<String, Object?> fields = const {},
  }) {
    if (!kDebugMode) return;
    final details = fields.entries
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
          return '${value['id']}:${value['type']}(${text.length},${preview(text, maxLength: 24)})';
        })
        .join('|');
  }

  static String payloadSummary(Map<String, dynamic> payload) {
    try {
      return preview(jsonEncode(payload), maxLength: 160);
    } catch (_) {
      return preview(payload.toString(), maxLength: 160);
    }
  }

  static String _format(Object? value) {
    if (value is String) return '"${preview(value)}"';
    return value?.toString() ?? 'null';
  }
}
