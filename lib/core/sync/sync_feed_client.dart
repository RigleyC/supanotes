import 'package:dio/dio.dart';
import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

final class SyncChange {
  const SyncChange({
    required this.sequence,
    required this.type,
    required this.createdAt,
    this.noteId,
    this.revision,
  });

  factory SyncChange.fromJson(Map<String, dynamic> json) {
    final sequence = json['sequence'];
    final type = json['type'];
    final createdAt = json['createdAt'];
    if (sequence is! int || type is! String || createdAt is! String) {
      throw const FormatException('Invalid sync change payload');
    }
    return SyncChange(
      sequence: sequence,
      type: type,
      noteId: json['noteId'] as String?,
      revision: json['revision'] as int?,
      createdAt: DateTime.parse(createdAt).toUtc(),
    );
  }

  final int sequence;
  final String type;
  final String? noteId;
  final int? revision;
  final DateTime createdAt;
}

final class SyncChangePage {
  const SyncChangePage({
    required this.cursor,
    required this.hasMore,
    required this.changes,
    this.watermark,
  });

  factory SyncChangePage.fromJson(Map<String, dynamic> json) {
    final cursor = json['cursor'];
    final hasMore = json['hasMore'];
    final rawChanges = json['changes'];
    if (cursor is! int || hasMore is! bool || rawChanges is! List) {
      throw const FormatException('Invalid sync change page');
    }
    return SyncChangePage(
      cursor: cursor,
      watermark: json['watermark'] as int?,
      hasMore: hasMore,
      changes: rawChanges
          .map((entry) => SyncChange.fromJson(Map<String, dynamic>.from(entry as Map)))
          .toList(growable: false),
    );
  }

  final int cursor;
  final int? watermark;
  final bool hasMore;
  final List<SyncChange> changes;
}

typedef SyncChangesFetcher = Future<SyncChangePage> Function({
  required int after,
  required int limit,
});

final class SyncFeedClient {
  const SyncFeedClient(this._api);

  final ApiClient _api;

  Future<SyncChangePage> fetchChanges({
    required int after,
    int limit = 100,
  }) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/sync/changes',
        queryParameters: {'after': after, 'limit': limit},
      );
      final data = response.data;
      if (data == null) {
        throw const FormatException('Missing sync change response');
      }
      return SyncChangePage.fromJson(data);
    } on DioException catch (error) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        throw NoteOperationsException(
          errorCode: data['error'] as String? ?? 'UNKNOWN',
          message: data['message'] as String? ?? error.message ?? 'Sync feed failed',
          statusCode: error.response?.statusCode,
        );
      }
      throw NoteOperationsException(
        errorCode: 'NETWORK_ERROR',
        message: error.message ?? 'Sync feed failed',
        statusCode: error.response?.statusCode,
      );
    }
  }
}
