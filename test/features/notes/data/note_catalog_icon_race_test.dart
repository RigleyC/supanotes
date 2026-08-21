import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/catalog/data/note_catalog_sync.dart';
import 'package:supanotes/features/notes/editor/sync/note_session_activity_tracker.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

class _MockNoteSyncClient extends Mock implements NoteSyncClient {}

void main() {
  test('keeps a newer local icon dirty when the push is in flight', () async {
    final database = AppDatabase.test();
    final client = _MockNoteSyncClient();
    final started = Completer<void>();
    final release = Completer<void>();
    final sync = NoteCatalogSync(
      syncClient: client,
      database: database,
      activityTracker: NoteSessionActivityTracker(),
      updateNoteIcon: (noteId, icon, expectedUpdatedAt) async {
        started.complete();
        await release.future;
      },
    );
    addTearDown(database.close);

    final firstUpdatedAt = DateTime.utc(2026, 7, 31, 12);
    final secondUpdatedAt = firstUpdatedAt.add(const Duration(seconds: 1));
    await database
        .into(database.notes)
        .insert(
          NotesCompanion.insert(
            id: 'racing-icon',
            userId: 'owner-user',
            content: 'Note',
            createdAt: firstUpdatedAt,
            updatedAt: firstUpdatedAt,
            isDirty: const Value(false),
            noteIconDirty: const Value(true),
            noteIconJson: Value(jsonEncode({'kind': 'emoji', 'value': '🙂'})),
          ),
        );

    final pushing = sync.pushDirtyNoteIcons();
    await started.future;
    await (database.update(
      database.notes,
    )..where((row) => row.id.equals('racing-icon'))).write(
      NotesCompanion(
        updatedAt: Value(secondUpdatedAt),
        noteIconDirty: const Value(true),
        noteIconJson: Value(jsonEncode({'kind': 'emoji', 'value': '🔥'})),
      ),
    );
    release.complete();
    await pushing;

    final saved = await database.notesDao.getNoteById('racing-icon');
    expect(jsonDecode(saved!.noteIconJson!), {'kind': 'emoji', 'value': '🔥'});
    expect(saved.noteIconDirty, isTrue);
  });
}
