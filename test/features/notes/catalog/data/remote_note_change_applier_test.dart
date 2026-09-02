import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/catalog/data/note_catalog_sync.dart';
import 'package:supanotes/features/notes/catalog/data/remote_note_change_applier.dart';
import 'package:supanotes/features/notes/catalog/model/remote_note_metadata.dart';

class _MockNoteCatalogSync extends Mock implements NoteCatalogSync {}

void main() {
  final metadata = RemoteNoteMetadata(
    id: 'note-1',
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 2),
    favorite: true,
    archived: false,
    hideCompleted: true,
    collapseImages: true,
    access: RemoteNoteAccess.owner,
    sharedByEmail: null,
    sharedByName: null,
    noteIcon: null,
  );

  setUpAll(() {
    registerFallbackValue(metadata);
  });

  test('existing versioned note refreshes metadata without replacing document', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final catalog = _MockNoteCatalogSync();
    when(
      () => catalog.hydrateRemoteNote(
        userId: any(named: 'userId'),
        metadata: any(named: 'metadata'),
      ),
    ).thenAnswer((_) async {});

    await db.notesDao.createNote(
      NotesCompanion.insert(
        id: 'note-1',
        userId: 'user-1',
        content: 'local pending',
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
        hasRemoteCopy: const Value(true),
      ),
    );
    await db.noteOperationsDao.upsertNoteDocument(
      LocalNoteDocumentsCompanion.insert(
        noteId: 'note-1',
        revision: 4,
        documentJson: '{"schemaVersion":1,"blocks":[]}',
        updatedAt: DateTime.utc(2026, 9, 1),
        materializedDocumentJson: const Value(
          '{"schemaVersion":1,"blocks":[{"id":"pending-local"}]}',
        ),
      ),
    );

    final applier = RemoteNoteChangeApplier(
      database: db,
      catalogSync: catalog,
      userId: 'user-1',
    );
    await applier.apply(metadata);

    final document = await db.noteOperationsDao.watchNoteDocument('note-1').first;
    expect(document!.revision, 4);
    expect(document.materializedDocumentJson, contains('pending-local'));
    final preference = await db.userNotePreferencesDao.getPreference(
      'user-1',
      'note-1',
    );
    expect(preference!.favorite, isTrue);
    expect(preference.hideCompleted, isTrue);
    expect(preference.collapseImages, isTrue);
    verifyNever(
      () => catalog.hydrateRemoteNote(
        userId: any(named: 'userId'),
        metadata: any(named: 'metadata'),
      ),
    );
  });

  test('missing note is hydrated from full remote snapshot', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final catalog = _MockNoteCatalogSync();
    when(
      () => catalog.hydrateRemoteNote(
        userId: any(named: 'userId'),
        metadata: any(named: 'metadata'),
      ),
    ).thenAnswer((_) async {});

    final applier = RemoteNoteChangeApplier(
      database: db,
      catalogSync: catalog,
      userId: 'user-1',
    );
    await applier.apply(metadata);

    verify(
      () => catalog.hydrateRemoteNote(
        userId: 'user-1',
        metadata: metadata,
      ),
    ).called(1);
  });
}
