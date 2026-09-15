import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/sync/sync_feed_client.dart';

class _MockApiClient extends Mock implements ApiClient {}

void main() {
  test('decodes optional change fields when present or absent', () {
    final page = SyncChangePage.fromJson({
      'cursor': 4,
      'watermark': 7,
      'hasMore': false,
      'changes': [
        {
          'sequence': 4,
          'type': 'note_changed',
          'createdAt': '2026-09-02T12:00:00Z',
          'noteId': 'note-1',
          'revision': 3,
        },
        {
          'sequence': 5,
          'type': 'note_deleted',
          'createdAt': '2026-09-02T12:00:01Z',
        },
        {
          'sequence': 6,
          'type': 'task_changed',
          'taskId': 'task-1',
          'createdAt': '2026-09-02T12:00:02Z',
        },
      ],
    });

    expect(page.changes[0].noteId, 'note-1');
    expect(page.changes[0].revision, 3);
    expect(page.changes[1].noteId, isNull);
    expect(page.changes[1].revision, isNull);
    expect(page.changes[2].taskId, 'task-1');
    expect(page.changes[2].noteId, isNull);
  });

  test('sends scope=all only when the caller opts into task events', () async {
    final api = _MockApiClient();
    final response = Response<Map<String, dynamic>>(
      requestOptions: RequestOptions(path: '/sync/changes'),
      data: const {
        'cursor': 0,
        'watermark': 0,
        'hasMore': false,
        'changes': <dynamic>[],
      },
    );
    when(
      () => api.get<Map<String, dynamic>>(
        '/sync/changes',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) async => response);
    final client = SyncFeedClient(api);

    await client.fetchChanges(after: 4, limit: 10);
    verify(
      () => api.get<Map<String, dynamic>>(
        '/sync/changes',
        queryParameters: {'after': 4, 'limit': 10},
      ),
    ).called(1);

    await client.fetchChanges(
      after: 4,
      limit: 10,
      scope: SyncFeedScope.all,
    );
    verify(
      () => api.get<Map<String, dynamic>>(
        '/sync/changes',
        queryParameters: {'after': 4, 'limit': 10, 'scope': 'all'},
      ),
    ).called(1);
  });

  test(
    'rejects malformed optional fields instead of throwing a type error',
    () {
      expect(
        () => SyncChange.fromJson({
          'sequence': 1,
          'type': 'note_changed',
          'createdAt': '2026-09-02T12:00:00Z',
          'revision': '3',
        }),
        throwsFormatException,
      );
    },
  );

  test('rejects non-object change entries', () {
    expect(
      () => SyncChangePage.fromJson({
        'cursor': 1,
        'watermark': 1,
        'hasMore': false,
        'changes': [null],
      }),
      throwsFormatException,
    );
  });
}
