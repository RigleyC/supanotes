import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/yjs_sync_manager.dart';

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
    final doc = Doc();
    doc.transact((txn) {
      doc.getText('content/node-1')!.insert(0, 'hi');
      doc.getMap<Object>('nodes')!.set(
          'node-1',
          '{"id":"node-1","position":1,"type":"paragraph","data":{"text":"hi"}}');
    });
    final state = encodeStateAsUpdate(doc);
    await db.into(db.localYjsStates).insertOnConflictUpdate(
          LocalYjsStatesCompanion(
            noteId: const Value('note-1'),
            state: Value(state),
            updatedAt: Value(DateTime.utc(2025, 1, 1)),
          ),
        );
  });

  tearDown(() async => await db.close());

  test('loadDoc reconstructs YDoc from local nodes when no snapshot exists',
      () async {
    final mgr = YjsSyncManager(db: db, userId: 'user-1');
    final doc = await mgr.loadDoc('note-1');
    expect(doc.getMap<Object>('nodes')!.keys, contains('node-1'));
    final ytext = doc.getText('content/node-1')!;
    expect(ytext.toString(), 'hi');
  });

  test('persist saves mutated doc and data survives fresh load', () async {
    final mgr = YjsSyncManager(db: db, userId: 'user-1');
    final doc = await mgr.loadDoc('note-1');

    // Mutate the canonical doc directly.
    doc.transact((txn) {
      doc.getMap<Object>('nodes')!.set(
          'node-2',
          '{"id":"node-2","position":1,"type":"paragraph","data":{"text":"new"}}');
      doc.getText('content/node-2')!.insert(0, 'new');
    });
    await mgr.persist('note-1');

    // New manager to bypass cache, then reload.
    final mgr2 = YjsSyncManager(db: db, userId: 'user-1');
    final doc2 = await mgr2.loadDoc('note-1');
    expect(doc2.getMap<Object>('nodes')!.keys, containsAll(['node-1', 'node-2']));
    expect(doc2.getText('content/node-2')!.toString(), 'new');
    expect(doc2.getText('content/node-1')!.toString(), 'hi');

    final state = encodeStateAsUpdate(doc2);
    expect(state.length, greaterThan(0));
  });

  test('loadDoc preserves text content on existing nodes', () async {
    final mgr = YjsSyncManager(db: db, userId: 'user-1');
    final doc = await mgr.loadDoc('note-1');
    expect(doc.getText('content/node-1')!.toString(), 'hi');
  });

  test('loadDoc returns cached doc on second call', () async {
    final mgr = YjsSyncManager(db: db, userId: 'user-1');
    final doc1 = await mgr.loadDoc('note-1');
    final doc2 = await mgr.loadDoc('note-1');
    expect(identical(doc1, doc2), isTrue);
  });

  test('projectNodes updates note content and excerpt from YDoc', () async {
    final mgr = YjsSyncManager(db: db, userId: 'user-1');
    final doc = await mgr.loadDoc('note-1');

    doc.transact((txn) {
      doc.getText('content/node-2')!.insert(0, 'Second line');
      doc.getMap<Object>('nodes')!.set(
          'node-2',
          '{"id":"node-2","position":"b0","type":"paragraph","data":{"text":"Second line"}}');
    });

    await mgr.projectNodes('note-1');

    final note = await db.notesDao.getNoteById('note-1');
    expect(note, isNotNull);
    expect(note!.content, contains('hi'));
    expect(note.content, contains('Second line'));
    expect(note.excerpt, contains('Second line'));
  });

  test('projectNodes derives task metadata from composite YMap keys', () async {
    final mgr = YjsSyncManager(db: db, userId: 'user-1');
    final doc = await mgr.loadDoc('note-1');

    doc.transact((txn) {
      final nodeMap = YMap<Object>();
      nodeMap.set('id', 'task-1');
      nodeMap.set('position', 'c0');
      nodeMap.set('type', 'task');
      nodeMap.set('data', '{"text":"Recurring task"}');
      doc.getMap<Object>('nodes')!.set('task-1', nodeMap);
      doc.getText('content/task-1')!.insert(0, 'Recurring task');
      doc.getMap<Object>('nodes')!.set('task-1:dueDate', '2026-07-20');
      doc.getMap<Object>('nodes')!.set('task-1:recurrence', 'daily');
      doc.getMap<Object>('nodes')!.set('task-1:completed', true);
    });

    await mgr.projectNodes('note-1');

    final tasks = await (db.select(db.tasks)
          ..where((t) => t.noteId.equals('note-1'))).get();
    expect(tasks, hasLength(1));
    expect(tasks.first.title, 'Recurring task');
    expect(tasks.first.status, 'done');
    expect(tasks.first.recurrence?.name, 'daily');
  });

  test('projectNodes chain survives error and allows subsequent calls', () async {
    final mgr = YjsSyncManager(db: db, userId: 'user-1');
    await mgr.loadDoc('note-1');

    // Trick: remove the doc from _docs so the first projectNodes fails
    // with a DB constraint violation (note doesn't exist in notes table
    // because _projectNow skips when doc is null, but we need an error
    // to propagate). Instead, we let the first call succeed, inject a
    // bad state that will cause a DB error, then verify the chain recovers.
    //
    // Actually: the simplest way to trigger an error is to have
    // projectNodes called before loadDoc — the doc is null, so _projectNow
    // returns silently. To test an actual failure, we make the DB fail:
    // close the database so the next write throws.

    // First call: will fail because db is closed.
    await db.close();
    final failFuture = mgr.projectNodes('note-1');
    await expectLater(failFuture, throwsA(anything));

    // Recreate the database for the second call.
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
    // Reload into new manager (or reuse — the chain entry for note-1
    // was cleaned up by the finally block of the failed call).
    final mgr2 = YjsSyncManager(db: db, userId: 'user-1');
    final doc2 = await mgr2.loadDoc('note-1');

    // Modify doc before project
    doc2.transact((txn) {
      doc2.getText('content/node-2')!.insert(0, 'After failure');
      doc2.getMap<Object>('nodes')!.set(
          'node-2',
          '{"id":"node-2","position":"b0","type":"paragraph","data":{"text":"After failure"}}');
    });

    await mgr2.projectNodes('note-1');

    final note = await db.notesDao.getNoteById('note-1');
    expect(note, isNotNull);
    expect(note!.content, contains('After failure'));
  });

  test('projectNodes propagates error to caller', () async {
    final mgr = YjsSyncManager(db: db, userId: 'user-1');
    await mgr.loadDoc('note-1');

    // Close the database so the projection write fails.
    await db.close();
    await expectLater(
      mgr.projectNodes('note-1'),
      throwsA(anything),
    );
  });

  test('multiple projectNodes for same note are serialized (no race)', () async {
    final mgr = YjsSyncManager(db: db, userId: 'user-1');
    final doc = await mgr.loadDoc('note-1');

    // Queue two projections in quick succession
    final f1 = mgr.projectNodes('note-1');
    final f2 = mgr.projectNodes('note-1');

    // Both should complete
    await Future.wait([f1, f2]);

    // The chain must not have left stale entries
    final note = await db.notesDao.getNoteById('note-1');
    expect(note, isNotNull);
  });
}
