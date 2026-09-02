import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/core/sync/sync_feed_client.dart';

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
      ],
    });

    expect(page.changes[0].noteId, 'note-1');
    expect(page.changes[0].revision, 3);
    expect(page.changes[1].noteId, isNull);
    expect(page.changes[1].revision, isNull);
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
