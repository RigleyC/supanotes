import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/catalog/data/note_catalog_sync.dart';
import 'package:supanotes/features/notes/catalog/model/note_icon.dart';
import 'package:supanotes/features/notes/catalog/model/remote_note_metadata.dart';
import 'package:supanotes/features/notes/editor/sync/note_session_activity_tracker.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

class _MockNoteSyncClient extends Mock implements NoteSyncClient {}

Future<void> _noopNoteIconUpdate(
  String noteId,
  NoteIcon? icon,
  DateTime? expectedUpdatedAt,
) async {}

void main() {
  test('materializes a clean remote document for offline task reads', () async {
    final database = AppDatabase.test();
    final client = _MockNoteSyncClient();
    final sync = NoteCatalogSync(
      syncClient: client,
      database: database,
      activityTracker: NoteSessionActivityTracker(),
      updateNoteIcon: _noopNoteIconUpdate,
    );
    addTearDown(database.close);

    when(client.listNotes).thenAnswer(
      (_) async => [
        {
          'id': 'task-note',
          'user_id': 'owner-user',
          'created_at': '2026-08-10T11:00:00.000Z',
          'updated_at': '2026-08-10T12:00:00.000Z',
        },
      ],
    );
    const document = {
      'schemaVersion': 1,
      'blocks': [
        {
          'id': 'task-1',
          'type': 'task',
          'delta': [
            {'insert': 'Review task'},
          ],
          'metadata': {
            'dueDate': '2026-08-12T09:00:00.000',
            'hasTime': true,
            'reminder': 'at_time',
          },
        },
      ],
    };
    when(() => client.getDocument('task-note')).thenAnswer(
      (_) async => NoteDocumentResponse(
        noteId: 'task-note',
        revision: 4,
        document: document,
        serverTime: DateTime.utc(2026, 8, 10, 12),
      ),
    );

    await sync.pullRemoteNotes('owner-user');

    final saved = await (database.select(
      database.localNoteDocuments,
    )..where((row) => row.noteId.equals('task-note'))).getSingle();
    expect(jsonDecode(saved.documentJson), document);
    expect(jsonDecode(saved.materializedDocumentJson!), document);
    expect(saved.materializedUpdatedAt?.toUtc(), DateTime.utc(2026, 8, 10, 12));
  });

  test(
    'pushes an active dirty note icon without changing document dirtiness',
    () async {
      final database = AppDatabase.test();
      final client = _MockNoteSyncClient();
      final updates = <(String, NoteIcon?)>[];
      final activityTracker = NoteSessionActivityTracker()
        ..markActive('icon-note');
      final sync = NoteCatalogSync(
        syncClient: client,
        database: database,
        activityTracker: activityTracker,
        updateNoteIcon: (noteId, icon, _) async => updates.add((noteId, icon)),
      );
      addTearDown(database.close);

      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: 'icon-note',
              userId: 'user-a',
              content: 'Note',
              createdAt: DateTime.utc(2026, 7, 31),
              updatedAt: DateTime.utc(2026, 7, 31, 12),
              isDirty: const Value(false),
              noteIconDirty: const Value(true),
              noteIconJson: Value(jsonEncode({'kind': 'emoji', 'value': '🙂'})),
            ),
          );

      await sync.pushDirtyNoteIcons();

      expect(updates, hasLength(1));
      expect(updates.single.$1, 'icon-note');
      expect(updates.single.$2?.toJson(), {'kind': 'emoji', 'value': '🙂'});
      final saved = await database.notesDao.getNoteById('icon-note');
      expect(saved!.noteIconDirty, isFalse);
      expect(saved.isDirty, isFalse);
    },
  );

  test(
    'preserves a local icon while refreshing active share metadata',
    () async {
      final database = AppDatabase.test();
      final client = _MockNoteSyncClient();
      final activityTracker = NoteSessionActivityTracker()
        ..markActive('active-icon-note');
      final sync = NoteCatalogSync(
        syncClient: client,
        database: database,
        activityTracker: activityTracker,
        updateNoteIcon: _noopNoteIconUpdate,
      );
      addTearDown(database.close);

      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: 'active-icon-note',
              userId: 'owner-user',
              content: 'Local content',
              createdAt: DateTime.utc(2026, 7, 31),
              updatedAt: DateTime.utc(2026, 7, 31),
              isDirty: const Value(false),
              hasRemoteCopy: const Value(true),
              permission: const Value('view'),
              noteIconDirty: const Value(true),
              noteIconJson: Value(jsonEncode({'kind': 'emoji', 'value': '🙂'})),
            ),
          );
      when(client.listNotes).thenAnswer(
        (_) async => [
          {
            'id': 'active-icon-note',
            'user_id': 'owner-user',
            'permission': 'view',
            'shared_by_email': 'owner@example.com',
            'shared_by_name': 'Owner',
            'note_icon': {'kind': 'emoji', 'value': '🔥'},
            'created_at': '2026-07-31T12:00:00.000Z',
            'updated_at': '2026-07-31T12:01:00.000Z',
          },
        ],
      );

      await sync.pullRemoteNotes('viewer-user');

      final saved = await database.notesDao.getNoteById('active-icon-note');
      expect(saved!.noteIconDirty, isTrue);
      expect(jsonDecode(saved.noteIconJson!), {'kind': 'emoji', 'value': '🙂'});
    },
  );

  test('applies an active owner icon update without share fields', () async {
    final database = AppDatabase.test();
    final client = _MockNoteSyncClient();
    final activityTracker = NoteSessionActivityTracker()
      ..markActive('active-owner-icon');
    final sync = NoteCatalogSync(
      syncClient: client,
      database: database,
      activityTracker: activityTracker,
      updateNoteIcon: _noopNoteIconUpdate,
    );
    addTearDown(database.close);

    await database
        .into(database.notes)
        .insert(
          NotesCompanion.insert(
            id: 'active-owner-icon',
            userId: 'owner-user',
            content: 'Local content',
            createdAt: DateTime.utc(2026, 7, 31),
            updatedAt: DateTime.utc(2026, 7, 31),
            isDirty: const Value(false),
            hasRemoteCopy: const Value(true),
            noteIconJson: Value(jsonEncode({'kind': 'emoji', 'value': '🙂'})),
          ),
        );
    when(client.listNotes).thenAnswer(
      (_) async => [
        {
          'id': 'active-owner-icon',
          'user_id': 'owner-user',
          'note_icon': {'kind': 'emoji', 'value': '🔥'},
          'created_at': '2026-07-31T12:00:00.000Z',
          'updated_at': '2026-07-31T12:01:00.000Z',
        },
      ],
    );

    await sync.pullRemoteNotes('owner-user');

    final saved = await database.notesDao.getNoteById('active-owner-icon');
    expect(jsonDecode(saved!.noteIconJson!), {'kind': 'emoji', 'value': '🔥'});
    verifyNever(() => client.getDocument('active-owner-icon'));
  });

  test(
    'keeps the newer remote icon instead of pushing a stale local value',
    () async {
      final database = AppDatabase.test();
      final client = _MockNoteSyncClient();
      final activityTracker = NoteSessionActivityTracker()
        ..markActive('remote-wins-icon');
      final pushed = <NoteIcon?>[];
      final sync = NoteCatalogSync(
        syncClient: client,
        database: database,
        activityTracker: activityTracker,
        updateNoteIcon: (noteId, icon, expectedUpdatedAt) async {
          pushed.add(icon);
        },
      );
      addTearDown(database.close);

      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: 'remote-wins-icon',
              userId: 'owner-user',
              content: 'Local content',
              createdAt: DateTime.utc(2026, 7, 31),
              updatedAt: DateTime.utc(2026, 7, 31, 12),
              isDirty: const Value(false),
              hasRemoteCopy: const Value(true),
              noteIconDirty: const Value(true),
              noteIconJson: Value(jsonEncode({'kind': 'emoji', 'value': '🙂'})),
            ),
          );
      when(client.listNotes).thenAnswer(
        (_) async => [
          {
            'id': 'remote-wins-icon',
            'user_id': 'owner-user',
            'note_icon': {'kind': 'emoji', 'value': '🔥'},
            'created_at': '2026-07-31T12:00:00.000Z',
            'updated_at': '2026-07-31T12:01:00.000Z',
          },
        ],
      );

      await sync.pullRemoteNotes('owner-user');
      await sync.pushDirtyNoteIcons();

      final saved = await database.notesDao.getNoteById('remote-wins-icon');
      expect(jsonDecode(saved!.noteIconJson!), {
        'kind': 'emoji',
        'value': '🔥',
      });
      expect(saved.noteIconDirty, isFalse);
      expect(pushed, isEmpty);
    },
  );

  test('applies a remote icon clear when no local icon is pending', () async {
    final database = AppDatabase.test();
    final client = _MockNoteSyncClient();
    final sync = NoteCatalogSync(
      syncClient: client,
      database: database,
      activityTracker: NoteSessionActivityTracker(),
      updateNoteIcon: _noopNoteIconUpdate,
    );
    addTearDown(database.close);

    await database
        .into(database.notes)
        .insert(
          NotesCompanion.insert(
            id: 'remote-icon-clear',
            userId: 'owner-user',
            content: 'Local content',
            createdAt: DateTime.utc(2026, 7, 31),
            updatedAt: DateTime.utc(2026, 7, 31),
            isDirty: const Value(false),
            hasRemoteCopy: const Value(true),
            noteIconJson: Value(jsonEncode({'kind': 'emoji', 'value': '🙂'})),
          ),
        );
    when(client.listNotes).thenAnswer(
      (_) async => [
        {
          'id': 'remote-icon-clear',
          'user_id': 'owner-user',
          'note_icon': null,
          'created_at': '2026-07-31T12:00:00.000Z',
          'updated_at': '2026-07-31T12:01:00.000Z',
        },
      ],
    );
    when(() => client.getDocument('remote-icon-clear')).thenAnswer(
      (_) async => NoteDocumentResponse(
        noteId: 'remote-icon-clear',
        revision: 2,
        document: const {
          'schemaVersion': 1,
          'blocks': [
            {
              'id': 'paragraph',
              'type': 'paragraph',
              'delta': [
                {'insert': 'Remote content'},
              ],
              'metadata': {},
            },
          ],
        },
        serverTime: DateTime.utc(2026, 7, 31, 12, 2),
      ),
    );

    await sync.pullRemoteNotes('owner-user');

    final saved = await database.notesDao.getNoteById('remote-icon-clear');
    expect(saved!.noteIconJson, isNull);
    expect(saved.noteIconDirty, isFalse);
  });

  test('surfaces an invalid remote icon for the next sync retry', () async {
    final database = AppDatabase.test();
    final client = _MockNoteSyncClient();
    final sync = NoteCatalogSync(
      syncClient: client,
      database: database,
      activityTracker: NoteSessionActivityTracker(),
      updateNoteIcon: _noopNoteIconUpdate,
    );
    addTearDown(database.close);

    when(client.listNotes).thenAnswer(
      (_) async => [
        {
          'id': 'invalid-remote-icon',
          'user_id': 'owner-user',
          'note_icon': {
            'kind': 'catalog',
            'value': 'not-a-catalog-icon',
            'color_key': 'blue',
          },
          'created_at': '2026-07-31T12:00:00.000Z',
          'updated_at': '2026-07-31T12:01:00.000Z',
        },
      ],
    );

    await expectLater(
      sync.pullRemoteNotes('owner-user'),
      throwsA(isA<FormatException>()),
    );
    verifyNever(() => client.getDocument('invalid-remote-icon'));
  });

  test(
    'hydrates remote content while preserving a pending local icon',
    () async {
      final database = AppDatabase.test();
      final client = _MockNoteSyncClient();
      final sync = NoteCatalogSync(
        syncClient: client,
        database: database,
        activityTracker: NoteSessionActivityTracker(),
        updateNoteIcon: _noopNoteIconUpdate,
      );
      addTearDown(database.close);

      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: 'dirty-icon-content',
              userId: 'owner-user',
              content: 'Old content',
              createdAt: DateTime.utc(2026, 7, 31),
              updatedAt: DateTime.utc(2026, 7, 31),
              isDirty: const Value(false),
              hasRemoteCopy: const Value(true),
              noteIconDirty: const Value(true),
              noteIconJson: Value(jsonEncode({'kind': 'emoji', 'value': '🙂'})),
            ),
          );
      when(client.listNotes).thenAnswer(
        (_) async => [
          {
            'id': 'dirty-icon-content',
            'user_id': 'owner-user',
            'note_icon': {'kind': 'emoji', 'value': '🔥'},
            'created_at': '2026-07-31T12:00:00.000Z',
            'updated_at': '2026-07-31T12:01:00.000Z',
          },
        ],
      );
      when(() => client.getDocument('dirty-icon-content')).thenAnswer(
        (_) async => NoteDocumentResponse(
          noteId: 'dirty-icon-content',
          revision: 2,
          document: const {
            'schemaVersion': 1,
            'blocks': [
              {
                'id': 'paragraph',
                'type': 'paragraph',
                'delta': [
                  {'insert': 'Remote content'},
                ],
                'metadata': {},
              },
            ],
          },
          serverTime: DateTime.utc(2026, 7, 31, 12, 2),
        ),
      );

      await sync.pullRemoteNotes('owner-user');

      final saved = await database.notesDao.getNoteById('dirty-icon-content');
      expect(saved!.content, 'Remote content');
      expect(jsonDecode(saved.noteIconJson!), {'kind': 'emoji', 'value': '🙂'});
      expect(saved.noteIconDirty, isTrue);
      expect(saved.updatedAt.toUtc(), DateTime.utc(2026, 7, 31));
    },
  );

  test(
    'removes a remote note that disappeared from the server catalog',
    () async {
      final database = AppDatabase.test();
      final client = _MockNoteSyncClient();
      final sync = NoteCatalogSync(
        syncClient: client,
        database: database,
        activityTracker: NoteSessionActivityTracker(),
        updateNoteIcon: _noopNoteIconUpdate,
      );
      addTearDown(database.close);

      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: 'remote-note',
              userId: 'user-a',
              content: 'Deleted elsewhere',
              createdAt: DateTime.utc(2026, 7, 31),
              updatedAt: DateTime.utc(2026, 7, 31),
              isDirty: const Value(false),
              hasRemoteCopy: const Value(true),
            ),
          );
      when(client.listNotes).thenAnswer((_) async => const []);

      await sync.pullRemoteNotes('user-a');

      expect(await database.notesDao.getNoteById('remote-note'), isNull);
    },
  );

  test('hydrates every remote catalog page before completing', () async {
    final database = AppDatabase.test();
    final client = _MockNoteSyncClient();
    final sync = NoteCatalogSync(
      syncClient: client,
      database: database,
      activityTracker: NoteSessionActivityTracker(),
      updateNoteIcon: _noopNoteIconUpdate,
    );
    addTearDown(database.close);

    final firstPage = List.generate(100, (index) {
      final id = 'remote-${index.toString().padLeft(3, '0')}';
      return <String, dynamic>{
        'id': id,
        'user_id': 'user-a',
        'created_at': '2026-07-31T12:00:00.000Z',
        'updated_at': '2026-07-31T12:00:00.000Z',
      };
    });
    final secondPage = [
      <String, dynamic>{
        'id': 'remote-100',
        'user_id': 'user-a',
        'created_at': '2026-07-31T12:00:00.000Z',
        'updated_at': '2026-07-31T12:00:00.000Z',
      },
    ];

    when(
      () => client.listNotes(
        limit: any(named: 'limit'),
        cursorUpdatedAt: any(named: 'cursorUpdatedAt'),
        cursorId: any(named: 'cursorId'),
      ),
    ).thenAnswer((invocation) async {
      final cursorId = invocation.namedArguments[#cursorId] as String?;
      return cursorId == null ? firstPage : secondPage;
    });
    when(() => client.getDocument(any())).thenAnswer((invocation) async {
      final noteId = invocation.positionalArguments.single as String;
      return NoteDocumentResponse(
        noteId: noteId,
        revision: 1,
        document: const {'schemaVersion': 1, 'blocks': []},
        serverTime: DateTime.utc(2026, 7, 31, 12),
      );
    });

    await sync.pullRemoteNotes('user-a');

    expect(await database.notesDao.getNoteById('remote-000'), isNotNull);
    expect(await database.notesDao.getNoteById('remote-100'), isNotNull);
    verify(
      () => client.listNotes(
        limit: any(named: 'limit'),
        cursorUpdatedAt: any(named: 'cursorUpdatedAt'),
        cursorId: any(named: 'cursorId'),
      ),
    ).called(2);
    verify(() => client.getDocument(any())).called(101);
  });

  test('pushes a local tombstone before removing the note locally', () async {
    final database = AppDatabase.test();
    final client = _MockNoteSyncClient();
    final sync = NoteCatalogSync(
      syncClient: client,
      database: database,
      activityTracker: NoteSessionActivityTracker(),
      updateNoteIcon: _noopNoteIconUpdate,
    );
    addTearDown(database.close);

    await database
        .into(database.notes)
        .insert(
          NotesCompanion.insert(
            id: 'deleted-note',
            userId: 'user-a',
            content: 'Deleted here',
            createdAt: DateTime.utc(2026, 7, 31),
            updatedAt: DateTime.utc(2026, 7, 31),
            deletedAt: Value(DateTime.utc(2026, 7, 31, 12)),
            isDirty: const Value(true),
            hasRemoteCopy: const Value(true),
          ),
        );
    when(() => client.deleteNote('deleted-note')).thenAnswer((_) async {});

    await sync.pushDeletedNotes();

    verify(() => client.deleteNote('deleted-note')).called(1);
    expect(await database.notesDao.getNoteById('deleted-note'), isNull);
  });

  test(
    'hard-deletes a local-only tombstone without sending a remote delete',
    () async {
      final database = AppDatabase.test();
      final client = _MockNoteSyncClient();
      final sync = NoteCatalogSync(
        syncClient: client,
        database: database,
        activityTracker: NoteSessionActivityTracker(),
        updateNoteIcon: _noopNoteIconUpdate,
      );
      addTearDown(database.close);

      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: 'local-only-deleted-note',
              userId: 'user-a',
              content: 'Never synced',
              createdAt: DateTime.utc(2026, 7, 31),
              updatedAt: DateTime.utc(2026, 7, 31),
              deletedAt: Value(DateTime.utc(2026, 7, 31, 12)),
              isDirty: const Value(true),
              hasRemoteCopy: const Value(false),
            ),
          );

      await sync.pushDeletedNotes();

      verifyNever(() => client.deleteNote('local-only-deleted-note'));
      expect(
        await database.notesDao.getNoteById('local-only-deleted-note'),
        isNull,
      );
    },
  );

  test('keeps a remote tombstone after failure and retries it later', () async {
    final database = AppDatabase.test();
    final client = _MockNoteSyncClient();
    final sync = NoteCatalogSync(
      syncClient: client,
      database: database,
      activityTracker: NoteSessionActivityTracker(),
      updateNoteIcon: _noopNoteIconUpdate,
    );
    addTearDown(database.close);

    await database
        .into(database.notes)
        .insert(
          NotesCompanion.insert(
            id: 'retry-deleted-note',
            userId: 'user-a',
            content: 'Retry me',
            createdAt: DateTime.utc(2026, 7, 31),
            updatedAt: DateTime.utc(2026, 7, 31),
            deletedAt: Value(DateTime.utc(2026, 7, 31, 12)),
            isDirty: const Value(true),
            hasRemoteCopy: const Value(true),
          ),
        );
    var attempts = 0;
    when(() => client.deleteNote('retry-deleted-note')).thenAnswer((_) async {
      attempts++;
      if (attempts == 1) {
        throw StateError('offline');
      }
    });

    await expectLater(sync.pushDeletedNotes(), throwsA(isA<StateError>()));
    expect(
      await database.notesDao.getNoteById('retry-deleted-note'),
      isNotNull,
    );

    await sync.pushDeletedNotes();

    verify(() => client.deleteNote('retry-deleted-note')).called(2);
    expect(await database.notesDao.getNoteById('retry-deleted-note'), isNull);
  });

  test(
    'does not remove a note opened while remote deletion was in flight',
    () async {
      final database = AppDatabase.test();
      final client = _MockNoteSyncClient();
      final activityTracker = NoteSessionActivityTracker();
      final sync = NoteCatalogSync(
        syncClient: client,
        database: database,
        activityTracker: activityTracker,
        updateNoteIcon: _noopNoteIconUpdate,
      );
      addTearDown(database.close);

      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: 'race-deleted-note',
              userId: 'user-a',
              content: 'Keep the active session',
              createdAt: DateTime.utc(2026, 7, 31),
              updatedAt: DateTime.utc(2026, 7, 31),
              deletedAt: Value(DateTime.utc(2026, 7, 31, 12)),
              isDirty: const Value(true),
              hasRemoteCopy: const Value(true),
            ),
          );
      when(() => client.deleteNote('race-deleted-note')).thenAnswer((_) async {
        activityTracker.markActive('race-deleted-note');
      });

      await sync.pushDeletedNotes();

      expect(
        await database.notesDao.getNoteById('race-deleted-note'),
        isNotNull,
      );
    },
  );

  test(
    'keeps a missing remote note while its editor session is active',
    () async {
      final database = AppDatabase.test();
      final client = _MockNoteSyncClient();
      final activityTracker = NoteSessionActivityTracker()
        ..markActive('open-note');
      final sync = NoteCatalogSync(
        syncClient: client,
        database: database,
        activityTracker: activityTracker,
        updateNoteIcon: _noopNoteIconUpdate,
      );
      addTearDown(database.close);

      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: 'open-note',
              userId: 'user-a',
              content: 'Open elsewhere',
              createdAt: DateTime.utc(2026, 7, 31),
              updatedAt: DateTime.utc(2026, 7, 31),
              isDirty: const Value(false),
              hasRemoteCopy: const Value(true),
            ),
          );
      when(client.listNotes).thenAnswer((_) async => const []);

      await sync.pullRemoteNotes('user-a');

      expect(await database.notesDao.getNoteById('open-note'), isNotNull);
    },
  );

  test('persists shared permission metadata from the remote catalog', () async {
    final database = AppDatabase.test();
    final client = _MockNoteSyncClient();
    final sync = NoteCatalogSync(
      syncClient: client,
      database: database,
      activityTracker: NoteSessionActivityTracker(),
      updateNoteIcon: _noopNoteIconUpdate,
    );
    addTearDown(database.close);

    when(client.listNotes).thenAnswer(
      (_) async => [
        {
          'id': 'shared-view-note',
          'user_id': 'owner-user',
          'permission': 'view',
          'shared_by_email': 'owner@example.com',
          'shared_by_name': 'Owner',
          'created_at': '2026-07-31T12:00:00.000Z',
          'updated_at': '2026-07-31T12:00:00.000Z',
        },
      ],
    );
    when(() => client.getDocument('shared-view-note')).thenAnswer(
      (_) async => NoteDocumentResponse(
        noteId: 'shared-view-note',
        revision: 2,
        document: const {
          'schemaVersion': 1,
          'blocks': [
            {
              'id': 'block-1',
              'type': 'paragraph',
              'delta': [
                {'insert': 'Shared'},
              ],
              'metadata': {},
            },
            {
              'id': 'task-1',
              'type': 'task',
              'delta': [
                {'insert': 'Review offline behavior'},
              ],
              'metadata': {'isCompleted': false},
            },
          ],
        },
        serverTime: DateTime.utc(2026, 7, 31, 12),
      ),
    );

    await sync.pullRemoteNotes('viewer-user');

    final note = await database.notesDao.getNoteById('shared-view-note');
    expect(note, isNotNull);
    expect(note!.permission, 'view');
    expect(note.content, 'Shared\nReview offline behavior');
    expect(note.excerpt, 'Shared\nReview offline behavior');
    expect(note.sharedByEmail, 'owner@example.com');
    expect(note.sharedByName, 'Owner');
    final query = await database.notesDao.getNoteWithPrefsById(
      'shared-view-note',
      'viewer-user',
    );
    expect(query!.title, 'Shared');
    final document =
        await (database.select(database.localNoteDocuments)
              ..where((document) => document.noteId.equals('shared-view-note')))
            .getSingle();
    expect(document.revision, 2);
  });

  test(
    'does not replace a local edit made while the remote document loads',
    () async {
      final database = AppDatabase.test();
      final client = _MockNoteSyncClient();
      final sync = NoteCatalogSync(
        syncClient: client,
        database: database,
        activityTracker: NoteSessionActivityTracker(),
        updateNoteIcon: _noopNoteIconUpdate,
      );
      addTearDown(database.close);

      await database.notesDao.createNote(
        NotesCompanion.insert(
          id: 'race-note',
          userId: 'user-a',
          content: 'Old content',
          createdAt: DateTime.utc(2026, 7, 31),
          updatedAt: DateTime.utc(2026, 7, 31),
          isDirty: const Value(false),
          hasRemoteCopy: const Value(true),
        ),
      );
      await database.noteOperationsDao.upsertNoteDocument(
        LocalNoteDocumentsCompanion.insert(
          noteId: 'race-note',
          revision: 1,
          documentJson: '{"blocks":[]}',
          updatedAt: DateTime.utc(2026, 7, 31),
        ),
      );

      when(client.listNotes).thenAnswer(
        (_) async => [
          {
            'id': 'race-note',
            'user_id': 'user-a',
            'created_at': '2026-07-31T12:00:00.000Z',
            'updated_at': '2026-08-03T13:00:00.000Z',
            'collapse_images': false,
          },
        ],
      );
      when(() => client.getDocument('race-note')).thenAnswer((_) async {
        await (database.update(
          database.notes,
        )..where((note) => note.id.equals('race-note'))).write(
          NotesCompanion(
            content: const Value('Offline edit'),
            updatedAt: Value(DateTime.utc(2026, 8, 3, 12)),
            isDirty: const Value(true),
          ),
        );
        return NoteDocumentResponse(
          noteId: 'race-note',
          revision: 2,
          document: const {
            'blocks': [
              {
                'id': 'remote-block',
                'type': 'paragraph',
                'delta': [
                  {'insert': 'Remote replacement'},
                ],
              },
            ],
          },
          serverTime: DateTime.utc(2026, 8, 3, 13),
        );
      });

      await sync.pullRemoteNotes('user-a');

      final note = await database.notesDao.getNoteById('race-note');
      expect(note!.content, 'Offline edit');
      expect(note.isDirty, isTrue);
      final document = await (database.select(
        database.localNoteDocuments,
      )..where((document) => document.noteId.equals('race-note'))).getSingle();
      expect(document.revision, 1);
    },
  );

  test(
    'does not hydrate a note that becomes active while the document loads',
    () async {
      final database = AppDatabase.test();
      final client = _MockNoteSyncClient();
      final activityTracker = NoteSessionActivityTracker();
      final sync = NoteCatalogSync(
        syncClient: client,
        database: database,
        activityTracker: activityTracker,
        updateNoteIcon: _noopNoteIconUpdate,
      );
      addTearDown(database.close);

      await database.notesDao.createNote(
        NotesCompanion.insert(
          id: 'active-during-load',
          userId: 'user-a',
          content: 'Keep this content',
          createdAt: DateTime.utc(2026, 7, 31),
          updatedAt: DateTime.utc(2026, 7, 31),
          isDirty: const Value(false),
          hasRemoteCopy: const Value(true),
        ),
      );
      when(client.listNotes).thenAnswer(
        (_) async => [
          {
            'id': 'active-during-load',
            'user_id': 'user-a',
            'created_at': '2026-07-31T12:00:00.000Z',
            'updated_at': '2026-08-03T13:00:00.000Z',
          },
        ],
      );
      when(() => client.getDocument('active-during-load')).thenAnswer((
        _,
      ) async {
        activityTracker.markActive('active-during-load');
        return NoteDocumentResponse(
          noteId: 'active-during-load',
          revision: 2,
          document: const {
            'blocks': [
              {
                'id': 'remote-block',
                'type': 'paragraph',
                'delta': [
                  {'insert': 'Must not replace active content'},
                ],
              },
            ],
          },
          serverTime: DateTime.utc(2026, 8, 3, 13),
        );
      });

      await sync.pullRemoteNotes('user-a');

      final note = await database.notesDao.getNoteById('active-during-load');
      expect(note!.content, 'Keep this content');
    },
  );

  test(
    'reopens the hydrated note from local storage without network access',
    () async {
      final file = File(
        '${Directory.systemTemp.path}/supanotes-note-${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      final firstDatabase = AppDatabase.test(executor: NativeDatabase(file));
      final client = _MockNoteSyncClient();
      final sync = NoteCatalogSync(
        syncClient: client,
        database: firstDatabase,
        activityTracker: NoteSessionActivityTracker(),
        updateNoteIcon: _noopNoteIconUpdate,
      );

      when(client.listNotes).thenAnswer(
        (_) async => [
          {
            'id': 'offline-reopen-note',
            'user_id': 'user-a',
            'created_at': '2026-07-31T12:00:00.000Z',
            'updated_at': '2026-07-31T12:00:00.000Z',
            'collapse_images': false,
          },
        ],
      );
      when(() => client.getDocument('offline-reopen-note')).thenAnswer(
        (_) async => NoteDocumentResponse(
          noteId: 'offline-reopen-note',
          revision: 1,
          document: const {
            'blocks': [
              {
                'id': 'block-1',
                'type': 'paragraph',
                'delta': [
                  {'insert': 'Saved before restart'},
                ],
              },
            ],
          },
          serverTime: DateTime.utc(2026, 7, 31, 12),
        ),
      );

      await sync.pullRemoteNotes('user-a');
      await firstDatabase.close();

      final reopenedDatabase = AppDatabase.test(executor: NativeDatabase(file));
      addTearDown(() async {
        await reopenedDatabase.close();
        if (file.existsSync()) await file.delete();
      });

      final note = await reopenedDatabase.notesDao.getNoteById(
        'offline-reopen-note',
      );
      expect(note!.content, 'Saved before restart');
      expect(note.excerpt, 'Saved before restart');
    },
  );

  test(
    'refreshes active share permission without replacing active content',
    () async {
      final database = AppDatabase.test();
      final client = _MockNoteSyncClient();
      final activityTracker = NoteSessionActivityTracker()
        ..markActive('active-shared-note');
      final sync = NoteCatalogSync(
        syncClient: client,
        database: database,
        activityTracker: activityTracker,
        updateNoteIcon: _noopNoteIconUpdate,
      );
      addTearDown(database.close);

      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: 'active-shared-note',
              userId: 'owner-user',
              content: 'local active content',
              createdAt: DateTime.utc(2026, 7, 31),
              updatedAt: DateTime.utc(2026, 7, 31),
              permission: const Value('edit'),
              isDirty: const Value(true),
              hasRemoteCopy: const Value(true),
            ),
          );
      when(client.listNotes).thenAnswer(
        (_) async => [
          {
            'id': 'active-shared-note',
            'user_id': 'owner-user',
            'permission': 'view',
            'shared_by_email': 'owner@example.com',
            'shared_by_name': 'Owner',
            'created_at': '2026-07-31T12:00:00.000Z',
            'updated_at': '2026-08-03T12:00:00.000Z',
            'collapse_images': false,
          },
        ],
      );

      await sync.pullRemoteNotes('viewer-user');

      final note = await database.notesDao.getNoteById('active-shared-note');
      expect(note!.permission, 'view');
      expect(note.content, 'local active content');
      expect(note.isDirty, isTrue);
      verifyNever(() => client.getDocument('active-shared-note'));
    },
  );

  test(
    'hydrates an authenticated share handoff with its REST/OT revision',
    () async {
      final database = AppDatabase.test();
      final client = _MockNoteSyncClient();
      final sync = NoteCatalogSync(
        syncClient: client,
        database: database,
        activityTracker: NoteSessionActivityTracker(),
        updateNoteIcon: _noopNoteIconUpdate,
      );
      addTearDown(database.close);

      when(() => client.getDocument('handoff-note')).thenAnswer(
        (_) async => NoteDocumentResponse(
          noteId: 'handoff-note',
          revision: 17,
          document: const {
            'schemaVersion': 1,
            'blocks': [
              {
                'id': 'handoff-block',
                'type': 'paragraph',
                'delta': [
                  {'insert': 'Authenticated handoff'},
                ],
              },
            ],
          },
          serverTime: DateTime.utc(2026, 8, 10, 12),
        ),
      );

      await sync.hydrateRemoteNote(
        userId: 'viewer-user',
        metadata: RemoteNoteMetadata.fromJson(const {
          'id': 'handoff-note',
          'user_id': 'owner-user',
          'permission': 'view',
          'shared_by_email': 'owner@example.com',
          'created_at': '2026-08-10T11:00:00.000Z',
          'updated_at': '2026-08-10T12:00:00.000Z',
        }),
      );

      final note = await database.notesDao.getNoteById('handoff-note');
      expect(note?.permission, 'view');
      expect(note?.content, 'Authenticated handoff');
      final document = await (database.select(
        database.localNoteDocuments,
      )..where((row) => row.noteId.equals('handoff-note'))).getSingle();
      expect(document.revision, 17);
      verify(() => client.getDocument('handoff-note')).called(1);
    },
  );

  test(
    'refreshes share permission when clean content has the same timestamp',
    () async {
      final database = AppDatabase.test();
      final client = _MockNoteSyncClient();
      final sync = NoteCatalogSync(
        syncClient: client,
        database: database,
        activityTracker: NoteSessionActivityTracker(),
        updateNoteIcon: _noopNoteIconUpdate,
      );
      addTearDown(database.close);

      final updatedAt = DateTime.utc(2026, 8, 10, 12);
      await database.notesDao.createNote(
        NotesCompanion.insert(
          id: 'permission-refresh-note',
          userId: 'owner-user',
          content: 'Cached content',
          createdAt: updatedAt,
          updatedAt: updatedAt,
          permission: const Value('edit'),
          hasRemoteCopy: const Value(true),
          isDirty: const Value(false),
        ),
      );
      await database.noteOperationsDao.upsertNoteDocument(
        LocalNoteDocumentsCompanion.insert(
          noteId: 'permission-refresh-note',
          revision: 9,
          documentJson: '{"schemaVersion":1,"blocks":[]}',
          updatedAt: updatedAt,
        ),
      );
      when(client.listNotes).thenAnswer(
        (_) async => [
          {
            'id': 'permission-refresh-note',
            'user_id': 'owner-user',
            'permission': 'view',
            'shared_by_email': 'owner@example.com',
            'created_at': '2026-08-10T11:00:00.000Z',
            'updated_at': '2026-08-10T12:00:00.000Z',
          },
        ],
      );

      await sync.pullRemoteNotes('viewer-user');

      final note = await database.notesDao.getNoteById(
        'permission-refresh-note',
      );
      expect(note!.permission, 'view');
      expect(note.sharedByEmail, 'owner@example.com');
      expect(note.content, 'Cached content');
      verifyNever(() => client.getDocument('permission-refresh-note'));
    },
  );

  test(
    'serializes mandatory hydration with the periodic catalog pull',
    () async {
      final database = AppDatabase.test();
      final client = _MockNoteSyncClient();
      final sync = NoteCatalogSync(
        syncClient: client,
        database: database,
        activityTracker: NoteSessionActivityTracker(),
        updateNoteIcon: _noopNoteIconUpdate,
      );
      addTearDown(database.close);

      final fetchStarted = Completer<void>();
      final releaseFetch = Completer<void>();
      final response = NoteDocumentResponse(
        noteId: 'serialized-note',
        revision: 3,
        document: const {
          'schemaVersion': 1,
          'blocks': [
            {
              'id': 'serialized-block',
              'type': 'paragraph',
              'delta': [
                {'insert': 'Serialized handoff'},
              ],
            },
          ],
        },
        serverTime: DateTime.utc(2026, 8, 10, 12),
      );
      when(() => client.getDocument('serialized-note')).thenAnswer((_) async {
        fetchStarted.complete();
        await releaseFetch.future;
        return response;
      });
      when(client.listNotes).thenAnswer(
        (_) async => [
          {
            'id': 'serialized-note',
            'user_id': 'owner-user',
            'permission': 'view',
            'shared_by_email': 'owner@example.com',
            'created_at': '2026-08-10T11:00:00.000Z',
            'updated_at': '2026-08-10T12:00:00.000Z',
          },
        ],
      );

      final metadata = RemoteNoteMetadata.fromJson(const {
        'id': 'serialized-note',
        'user_id': 'owner-user',
        'permission': 'view',
        'shared_by_email': 'owner@example.com',
        'created_at': '2026-08-10T11:00:00.000Z',
        'updated_at': '2026-08-10T12:00:00.000Z',
      });
      final hydration = sync.hydrateRemoteNote(
        userId: 'viewer-user',
        metadata: metadata,
      );
      await fetchStarted.future;
      final periodicPull = sync.pullRemoteNotes('viewer-user');

      releaseFetch.complete();
      await Future.wait([hydration, periodicPull]);

      verify(() => client.getDocument('serialized-note')).called(1);
      final note = await database.notesDao.getNoteById('serialized-note');
      expect(note?.content, 'Serialized handoff');
      expect(note?.permission, 'view');
    },
  );

  test('clears stale share metadata when the owner opens the note', () async {
    final database = AppDatabase.test();
    final client = _MockNoteSyncClient();
    final sync = NoteCatalogSync(
      syncClient: client,
      database: database,
      activityTracker: NoteSessionActivityTracker(),
      updateNoteIcon: _noopNoteIconUpdate,
    );
    addTearDown(database.close);

    final updatedAt = DateTime.utc(2026, 8, 10, 12);
    await database.notesDao.createNote(
      NotesCompanion.insert(
        id: 'owner-metadata-refresh-note',
        userId: 'owner-user',
        content: 'Owner content',
        createdAt: updatedAt,
        updatedAt: updatedAt,
        permission: const Value('view'),
        sharedByEmail: const Value('owner@example.com'),
        hasRemoteCopy: const Value(true),
        isDirty: const Value(false),
      ),
    );
    await database.noteOperationsDao.upsertNoteDocument(
      LocalNoteDocumentsCompanion.insert(
        noteId: 'owner-metadata-refresh-note',
        revision: 4,
        documentJson: '{"schemaVersion":1,"blocks":[]}',
        updatedAt: updatedAt,
      ),
    );
    when(client.listNotes).thenAnswer(
      (_) async => [
        {
          'id': 'owner-metadata-refresh-note',
          'created_at': '2026-08-10T11:00:00.000Z',
          'updated_at': '2026-08-10T12:00:00.000Z',
        },
      ],
    );

    await sync.pullRemoteNotes('owner-user');

    final note = await database.notesDao.getNoteById(
      'owner-metadata-refresh-note',
    );
    expect(note!.permission, isNull);
    expect(note.sharedByEmail, isNull);
    verifyNever(() => client.getDocument('owner-metadata-refresh-note'));
  });

  test('pushes the complete dirty preference row and clears its matching version', () async {
    final database = AppDatabase.test();
    final client = _MockNoteSyncClient();
    final sync = NoteCatalogSync(
      syncClient: client,
      database: database,
      activityTracker: NoteSessionActivityTracker(),
      updateNoteIcon: _noopNoteIconUpdate,
    );
    addTearDown(database.close);
    final timestamp = DateTime.utc(2026, 8, 10, 12);
    await database.notesDao.createNote(
      NotesCompanion.insert(
        id: 'preference-note',
        userId: 'owner-user',
        content: 'content',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
    await database.userNotePreferencesDao.setPreferences(
      userId: 'owner-user',
      noteId: 'preference-note',
      favorite: true,
      archived: false,
      hideCompleted: true,
      collapseImages: true,
    );
    when(
      () => client.updatePreferences(
        noteId: 'preference-note',
        favorite: true,
        archived: false,
        hideCompleted: true,
        collapseImages: true,
      ),
    ).thenAnswer(
      (_) async => NotePreferencesResponse(
        favorite: true,
        archived: false,
        hideCompleted: true,
        collapseImages: true,
        updatedAt: timestamp,
      ),
    );

    await sync.pushDirtyPreferences();

    verify(
      () => client.updatePreferences(
        noteId: 'preference-note',
        favorite: true,
        archived: false,
        hideCompleted: true,
        collapseImages: true,
      ),
    ).called(1);
    expect(
      (await database.userNotePreferencesDao.getPreference(
        'owner-user',
        'preference-note',
      ))!.isDirty,
      isFalse,
    );
  });

  test('keeps dirty preferences when the remote push fails', () async {
    final database = AppDatabase.test();
    final client = _MockNoteSyncClient();
    final sync = NoteCatalogSync(
      syncClient: client,
      database: database,
      activityTracker: NoteSessionActivityTracker(),
      updateNoteIcon: _noopNoteIconUpdate,
    );
    addTearDown(database.close);
    await database.notesDao.createNote(
      NotesCompanion.insert(
        id: 'failed-preference-note',
        userId: 'owner-user',
        content: 'content',
        createdAt: DateTime.utc(2026, 8, 10),
        updatedAt: DateTime.utc(2026, 8, 10),
      ),
    );
    await database.userNotePreferencesDao.setFavorite(
      'owner-user',
      'failed-preference-note',
      true,
    );
    when(
      () => client.updatePreferences(
        noteId: 'failed-preference-note',
        favorite: true,
        archived: false,
        hideCompleted: false,
        collapseImages: false,
      ),
    ).thenThrow(StateError('offline'));

    expect(sync.pushDirtyPreferences, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(
      (await database.userNotePreferencesDao.getPreference(
        'owner-user',
        'failed-preference-note',
      ))!.isDirty,
      isTrue,
    );
  });
}
