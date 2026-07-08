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
    await db.into(db.noteNodes).insert(NoteNodesCompanion.insert(
          id: 'node-1',
          noteId: 'note-1',
          position: 0.0,
          type: 'paragraph',
          data: '{"text":"hi"}',
          createdAt: DateTime.utc(2025, 1, 1),
          updatedAt: DateTime.utc(2025, 1, 1),
          isDirty: const Value(false),
        ));
  });

  tearDown(() async => await db.close());

  test('loadDoc reconstructs YDoc from local nodes when no snapshot exists',
      () async {
    final mgr = YjsSyncManager(db: db);
    final doc = await mgr.loadDoc('note-1');
    expect(doc.getMap('nodes')!.keys, contains('node-1'));
    final ytext = doc.getText('content_node-1');
    expect(ytext.toString(), 'hi');
  });

  test('saveState persists and merged data survives reload', () async {
    final mgr = YjsSyncManager(db: db);
    await mgr.loadDoc('note-1');

    final incoming = Doc();
    incoming.getMap('nodes')!.set(
        'node-2',
        '{"id":"node-2","position":1,"type":"paragraph","data":{"text":"new"}}');
    incoming.getText('content_node-2')!.insert(0, 'new');
    final update = encodeStateAsUpdate(incoming);
    await mgr.saveState('note-1', update);

    // Reload — verify YMap keys
    mgr.unloadDoc('note-1');
    final doc2 = await mgr.loadDoc('note-1');
    expect(doc2.getMap('nodes')!.keys, containsAll(['node-1', 'node-2']));

    // Verify state is persisted (non-empty)
    final state = encodeStateAsUpdate(doc2);
    expect(state.length, greaterThan(0));
  });

  test('loadDoc preserves text content on existing nodes', () async {
    final mgr = YjsSyncManager(db: db);
    final doc = await mgr.loadDoc('note-1');
    expect(doc.getText('content_node-1').toString(), 'hi');
  });

  test('docFor throws when loadDoc has not been called', () async {
    final mgr = YjsSyncManager(db: db);
    expect(
      () => mgr.docFor('note-1'),
      throwsStateError,
    );
  });

  test('loadDoc returns cached doc on second call', () async {
    final mgr = YjsSyncManager(db: db);
    final doc1 = await mgr.loadDoc('note-1');
    final doc2 = await mgr.loadDoc('note-1');
    expect(identical(doc1, doc2), isTrue);
  });
}
