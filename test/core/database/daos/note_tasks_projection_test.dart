import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/tasks/domain/visible_note_tasks.dart';

String _document({required String paragraph, required String task}) =>
    jsonEncode({
      'schemaVersion': 1,
      'blocks': [
        {
          'id': 'p1',
          'type': 'paragraph',
          'delta': [
            {'insert': paragraph},
          ],
        },
        {
          'id': 't1',
          'type': 'task',
          'delta': [
            {'insert': task},
          ],
          'metadata': {'isCompleted': false},
        },
      ],
    });

Future<void> _createNote(AppDatabase db, String id) {
  final now = DateTime.utc(2026, 9, 15);
  return db.notesDao.createNote(
    NotesCompanion.insert(
      id: id,
      userId: 'user-1',
      content: 'Mercado',
      createdAt: now,
      updatedAt: now,
      hasRemoteCopy: const Value(true),
    ),
  );
}

Future<void> _save(AppDatabase db, String id, String json) {
  return db.noteOperationsDao.saveMaterializedDocument(
    noteId: id,
    documentJson: json,
    content: 'Mercado',
    excerpt: 'Mercado',
    updatedAt: DateTime.now().toUtc(),
  );
}

void main() {
  test('saving a document projects its task blocks', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    await _createNote(db, 'n1');

    await _save(db, 'n1', _document(paragraph: 'a', task: 'Comprar pão'));

    final rows = await db.select(db.noteTasks).get();
    expect(rows.map((row) => (row.noteId, row.blockId, row.title)), [
      ('n1', 't1', 'Comprar pão'),
    ]);
  });

  test('typing outside task blocks does not touch the projection', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    await _createNote(db, 'n1');
    await _save(db, 'n1', _document(paragraph: 'a', task: 'Comprar pão'));

    final emissions = <List<VisibleNoteTasks>>[];
    final subscription = watchVisibleNoteTasks(db, 'user-1').listen(
      emissions.add,
    );
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(emissions, hasLength(1));

    // Paragraph edits rewrite `notes` and `local_note_documents` only.
    for (final text in ['ab', 'abc', 'abcd']) {
      await _save(db, 'n1', _document(paragraph: text, task: 'Comprar pão'));
      await pumpEventQueue();
    }
    expect(emissions, hasLength(1));

    // Editing the task itself reaches the readers.
    await _save(db, 'n1', _document(paragraph: 'abcd', task: 'Comprar leite'));
    await pumpEventQueue();
    expect(emissions, hasLength(2));
    expect(emissions.last.single.tasks.single.title, 'Comprar leite');
  });

  test('deleting the local document removes its projected tasks', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    await _createNote(db, 'n1');
    await _save(db, 'n1', _document(paragraph: 'a', task: 'x'));

    await db.noteOperationsDao.deleteNoteDocument('n1');

    expect(await db.select(db.noteTasks).get(), isEmpty);
  });

  test('upgrading from v34 backfills the projection', () async {
    final dir = await Directory.systemTemp.createTemp('note_tasks_migration');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    final current = AppDatabase.test(executor: NativeDatabase(file));
    await _createNote(current, 'n1');
    await _save(current, 'n1', _document(paragraph: 'a', task: 'Pagar luz'));
    // Rewind the file to the previous schema version.
    await current.customStatement('DROP TABLE note_tasks');
    await current.customStatement('PRAGMA user_version = 34');
    await current.close();

    final upgraded = AppDatabase.test(executor: NativeDatabase(file));
    addTearDown(upgraded.close);
    final rows = await upgraded.select(upgraded.noteTasks).get();
    expect(rows.map((row) => row.title), ['Pagar luz']);
  });
}
