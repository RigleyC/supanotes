import 'package:dio/dio.dart';
import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

/// Resources included in the account change feed.
///
/// The notes-only value intentionally maps to the absence of a query
/// parameter. This keeps requests from clients that predate standalone tasks
/// indistinguishable from the historical API contract.
enum SyncFeedScope {
  notes,
  all,
}

extension SyncFeedScopeQuery on SyncFeedScope {
  String get queryValue => switch (this) {
    SyncFeedScope.notes => 'notes',
    SyncFeedScope.all => 'all',
  };
}

final class SyncChange {
  const SyncChange({
    required this.sequence,
    required this.type,
    required this.createdAt,
    this.noteId,
    this.taskId,
    this.revision,
  });

  factory SyncChange.fromJson(Map<String, dynamic> json) {
    final sequence = json['sequence'];
    final type = json['type'];
    final createdAt = json['createdAt'];
    final String? noteId = switch (json['noteId']) {
      null => null,
      String value => value,
      _ => throw const FormatException('Invalid sync change payload'),
    };
    final String? taskId = switch (json['taskId']) {
      null => null,
      String value => value,
      _ => throw const FormatException('Invalid sync change payload'),
    };
    final int? revision = switch (json['revision']) {
      null => null,
      int value => value,
      _ => throw const FormatException('Invalid sync change payload'),
    };
    if (sequence is! int || type is! String || createdAt is! String) {
      throw const FormatException('Invalid sync change payload');
    }
    return SyncChange(
      sequence: sequence,
      type: type,
      noteId: noteId,
      taskId: taskId,
      revision: revision,
      createdAt: DateTime.parse(createdAt).toUtc(),
    );
  }

  final int sequence;
  final String type;
  final String? noteId;
  final String? taskId;
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
    final int? watermark = switch (json['watermark']) {
      null => null,
      int value => value,
      _ => throw const FormatException('Invalid sync change page'),
    };
    final hasMore = json['hasMore'];
    final rawChanges = json['changes'];
    if (cursor is! int || hasMore is! bool || rawChanges is! List) {
      throw const FormatException('Invalid sync change page');
    }
    return SyncChangePage(
      cursor: cursor,
      watermark: watermark,
      hasMore: hasMore,
      changes: rawChanges
          .map((entry) => SyncChange.fromJson(_asJsonObject(entry)))
          .toList(growable: false),
    );
  }

  final int cursor;
  final int? watermark;
  final bool hasMore;
  final List<SyncChange> changes;
}

Map<String, dynamic> _asJsonObject(Object? value) {
  if (value is! Map) {
    throw const FormatException('Invalid sync change entry');
  }
  final object = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw const FormatException('Invalid sync change entry');
    }
    object[key] = entry.value;
  }
  return object;
}

typedef SyncChangesFetcher =
    Future<SyncChangePage> Function({
      required int after,
      required int limit,
      SyncFeedScope scope,
    });

final class SyncFeedClient {
  const SyncFeedClient(this._api);

  final ApiClient _api;

  Future<SyncChangePage> fetchChanges({
    required int after,
    int limit = 100,
    SyncFeedScope scope = SyncFeedScope.notes,
  }) async {
    try {
      final queryParameters = <String, dynamic>{
        'after': after,
        'limit': limit,
        if (scope == SyncFeedScope.all) 'scope': scope.queryValue,
      };
      final response = await _api.get<Map<String, dynamic>>(
        '/sync/changes',
        queryParameters: queryParameters,
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
          message:
              data['message'] as String? ?? error.message ?? 'Sync feed failed',
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
