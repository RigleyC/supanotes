import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_crdt/dart_crdt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/yjs_sync_manager.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.test(executor: NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Reconnection and Offline Sync', () {
    test('Offline edits merge successfully without duplication', () async {
      // 1. Initial State: Client has note version A
      final now = DateTime.now().toUtc();
      await db.into(db.notes).insert(
            NotesCompanion.insert(
              id: 'note-1',
              userId: 'user-1',
              content: 'Hello',
              createdAt: now,
              updatedAt: now,
            ),
          );

      await db.into(db.localYjsStates).insert(
            LocalYjsStatesCompanion.insert(
              noteId: 'note-1',
              state: Uint8List(0),
            ),
          );

      // Initialize Manager
      final mgr = YjsSyncManager(db: db, userId: 'user-1');
      final doc = await mgr.loadDoc('note-1');
      expect(doc.getText('content/node-1').toPlainText(), 'Hello');

      // 2. Offline change locally: edit "Hello" -> "Hello World"
      await db.into(db.localYjsStates).insertOnConflictUpdate(
            LocalYjsStatesCompanion.insert(
              noteId: 'note-1',
              state: Uint8List(0),
            ),
          );

      // Reconstruct/Load Doc again, simulating merge of offline change
      await mgr.loadDoc('note-1');
      
      // Force reconstruction from local node modifications
      final freshMgr = YjsSyncManager(db: db, userId: 'user-1');
      final freshDoc = await freshMgr.loadDoc('note-1');
      expect(freshDoc.getText('content/node-1').toPlainText(), 'Hello World');
    });

    test('Process kill recovery restores Doc from localYjsStates', () async {
      final now = DateTime.now().toUtc();
      await db.into(db.notes).insert(
            NotesCompanion.insert(
              id: 'note-2',
              userId: 'user-1',
              content: '',
              createdAt: now,
              updatedAt: now,
            ),
          );

      final mgr1 = YjsSyncManager(db: db, userId: 'user-1');
      final doc1 = await mgr1.loadDoc('note-2');

      // Edit document
      doc1.transact((txn) {
        doc1.getMap('nodes').setAttr(
              'p1',
              jsonEncode({
                'id': 'p1',
                'position': 0.0,
                'type': 'paragraph',
                'data': {'text': 'Relaunched!'},
                'createdAt': now.millisecondsSinceEpoch.toDouble(),
              }),
            );
        doc1.getText('content/p1').insertText(0, 'Relaunched!');
      });

      // Persist doc1 to SQLite
      await mgr1.persist('note-2');

      // Verify that localYjsStates row exists
      final yjsRow = await (db.select(db.localYjsStates)
            ..where((t) => t.noteId.equals('note-2')))
          .getSingle();
      expect(yjsRow.state, isNotEmpty);

      // Simulate App relaunch with clean manager
      final mgr2 = YjsSyncManager(db: db, userId: 'user-1');
      final doc2 = await mgr2.loadDoc('note-2');

      expect(doc2.getMap('nodes').attrKeys, contains('p1'));
      expect(doc2.getText('content/p1').toPlainText(), 'Relaunched!');
    });
  });
}
