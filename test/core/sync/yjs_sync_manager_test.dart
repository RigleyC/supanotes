import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_crdt/dart_crdt.dart';

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
      doc.getText('content/node-1').insertText(0, 'hi');
      doc.getMap('nodes').setAttr(
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
    expect(doc.getMap('nodes').attrKeys, contains('node-1'));
    final ytext = doc.getText('content/node-1');
    expect(ytext.toPlainText(), 'hi');
  });

  test('persist saves mutated doc and data survives fresh load', () async {
    final mgr = YjsSyncManager(db: db, userId: 'user-1');
    final doc = await mgr.loadDoc('note-1');

    // Mutate the canonical doc directly.
    doc.transact((txn) {
      doc.getMap('nodes').setAttr(
          'node-2',
          '{"id":"node-2","position":1,"type":"paragraph","data":{"text":"new"}}');
      doc.getText('content/node-2').insertText(0, 'new');
    });
    await mgr.persist('note-1');

    // New manager to bypass cache, then reload.
    final mgr2 = YjsSyncManager(db: db, userId: 'user-1');
    final doc2 = await mgr2.loadDoc('note-1');
    expect(doc2.getMap('nodes').attrKeys, containsAll(['node-1', 'node-2']));
    expect(doc2.getText('content/node-2').toPlainText(), 'new');
    expect(doc2.getText('content/node-1').toPlainText(), 'hi');

    final state = encodeStateAsUpdate(doc2);
    expect(state.length, greaterThan(0));
  });

  test('loadDoc preserves text content on existing nodes', () async {
    final mgr = YjsSyncManager(db: db, userId: 'user-1');
    final doc = await mgr.loadDoc('note-1');
    expect(doc.getText('content/node-1').toPlainText(), 'hi');
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
      doc.getText('content/node-2').insertText(0, 'Second line');
      doc.getMap('nodes').setAttr(
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
}
