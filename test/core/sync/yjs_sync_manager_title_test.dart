import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/yjs_sync_manager.dart';
import 'package:supanotes/features/notes/domain/note_strings.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.test(executor: NativeDatabase.memory());
    await db.into(db.notes).insert(NotesCompanion.insert(
          id: 'note-1',
          userId: 'user-1',
          content: '',
          createdAt: DateTime.utc(2025, 1, 1),
          updatedAt: DateTime.utc(2025, 1, 1),
          isDirty: const Value(false),
          hasRemoteCopy: const Value(true),
        ));
  });

  tearDown(() async => await db.close());

  test('projectNodes makes title available through note query', () async {
    final doc = Doc();
    doc.transact((txn) {
      doc.getText('content/node-1')!.insert(0, 'My Trip');
      doc.getMap<Object>('nodes')!.set(
          'node-1',
          '{"id":"node-1","position":"a0","type":"paragraph","data":{"text":"My Trip"}}');
    });
    final state = encodeStateAsUpdate(doc);
    await db.into(db.localYjsStates).insertOnConflictUpdate(
          LocalYjsStatesCompanion(
            noteId: const Value('note-1'),
            state: Value(state),
            updatedAt: Value(DateTime.utc(2025, 1, 1)),
          ),
        );

    final mgr = YjsSyncManager(db: db, userId: 'user-1');
    await mgr.loadDoc('note-1');
    await mgr.projectNodes('note-1');

    final notes = await db.notesDao.watchAllActiveNotes('user-1').first;
    expect(notes, hasLength(1));
    expect(notes.first.title, 'My Trip');
  });

  test('projectNodes reads from content when content_fixed is empty', () async {
    final doc = Doc();
    doc.transact((txn) {
      // Simulate a doc where content_fixed exists but is empty, while
      // content holds the actual text. This can happen after certain merges
      // or when the fallback shared type was created before the primary one.
      doc.getText('content_fixed/node-1')!.insert(0, '');
      doc.getText('content/node-1')!.insert(0, 'My Trip');
      doc.getMap<Object>('nodes')!.set(
          'node-1',
          '{"id":"node-1","position":"a0","type":"paragraph","data":{"text":"My Trip"}}');
    });
    final state = encodeStateAsUpdate(doc);
    await db.into(db.localYjsStates).insertOnConflictUpdate(
          LocalYjsStatesCompanion(
            noteId: const Value('note-1'),
            state: Value(state),
            updatedAt: Value(DateTime.utc(2025, 1, 1)),
          ),
        );

    final mgr = YjsSyncManager(db: db, userId: 'user-1');
    await mgr.loadDoc('note-1');
    await mgr.projectNodes('note-1');

    final notes = await db.notesDao.watchAllActiveNotes('user-1').first;
    expect(notes, hasLength(1));
    // The title should come from the actual text, not the empty fallback.
    expect(notes.first.title, 'My Trip');
  });

  test('title falls back to Sem título when YDoc has no text nodes', () async {
    final doc = Doc();
    doc.transact((txn) {
      doc.getMap<Object>('nodes')!.set(
          'node-1',
          '{"id":"node-1","position":"a0","type":"paragraph","data":{"text":""}}');
    });
    final state = encodeStateAsUpdate(doc);
    await db.into(db.localYjsStates).insertOnConflictUpdate(
          LocalYjsStatesCompanion(
            noteId: const Value('note-1'),
            state: Value(state),
            updatedAt: Value(DateTime.utc(2025, 1, 1)),
          ),
        );

    final mgr = YjsSyncManager(db: db, userId: 'user-1');
    await mgr.loadDoc('note-1');
    await mgr.projectNodes('note-1');

    final notes = await db.notesDao.watchAllActiveNotes('user-1').first;
    expect(notes, hasLength(1));
    expect(notes.first.title, NoteStrings.fallbackTitle);
  });

  test('projectNodes reads text from data when content shared types are missing',
      () async {
    // Backend can project text from data["text"] when content shared types are
    // absent. Flutter should behave the same way to avoid "Sem título" flashes.
    final doc = Doc();
    doc.transact((txn) {
      doc.getMap<Object>('nodes')!.set(
          'node-1',
          '{"id":"node-1","position":"a0","type":"paragraph","data":{"text":"My Trip"}}');
    });
    final state = encodeStateAsUpdate(doc);
    await db.into(db.localYjsStates).insertOnConflictUpdate(
          LocalYjsStatesCompanion(
            noteId: const Value('note-1'),
            state: Value(state),
            updatedAt: Value(DateTime.utc(2025, 1, 1)),
          ),
        );

    final mgr = YjsSyncManager(db: db, userId: 'user-1');
    await mgr.loadDoc('note-1');
    await mgr.projectNodes('note-1');

    final notes = await db.notesDao.watchAllActiveNotes('user-1').first;
    expect(notes, hasLength(1));
    expect(notes.first.title, 'My Trip');
  });
}
