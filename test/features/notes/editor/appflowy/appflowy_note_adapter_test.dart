import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/editor/appflowy/appflowy_note_adapter.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_contract.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

class _OfflineClient extends Mock implements NoteSyncClient {}

String _doc(List<Map<String, dynamic>> blocks) =>
    jsonEncode({'schemaVersion': 1, 'blocks': blocks});

Map<String, dynamic> _block(
  String id,
  String type,
  String text, [
  Map<String, dynamic>? metadata,
]) => {
  'id': id,
  'type': type,
  'delta': [
    {'insert': text},
  ],
  'metadata': ?metadata,
};

void main() {
  late AppDatabase database;
  late NoteOperationsSyncService service;
  late EditorState editorState;
  late AppFlowyNoteAdapter adapter;

  Future<void> open(String documentJson) async {
    await database.noteOperationsDao.upsertNoteDocument(
      LocalNoteDocumentsCompanion.insert(
        noteId: 'n1',
        revision: 3,
        documentJson: documentJson,
        updatedAt: DateTime.utc(2026),
      ),
    );
    editorState = EditorState.blank(withInitialText: true);
    adapter = AppFlowyNoteAdapter(
      editorState: editorState,
      syncService: service,
      noteId: 'n1',
    );
    await adapter.start();
  }

  Future<List<PendingNoteOperationData>> pending() async {
    await adapter.flushNow();
    return service.getPendingOperations('n1');
  }

  setUp(() {
    database = AppDatabase.test();
    service = NoteOperationsSyncService(
      syncClient: _OfflineClient(),
      dao: database.noteOperationsDao,
      clientId: 'device',
      actorId: 'user-1',
    );
  });

  tearDown(() async {
    adapter.dispose();
    editorState.dispose();
    await database.close();
  });

  test('hydrates the editor from the stored document', () async {
    await open(
      _doc([
        _block('h', 'header1', 'Mercado'),
        _block('t', 'task', 'Leite', {'isCompleted': true}),
      ]),
    );

    final nodes = editorState.document.root.children.toList();
    expect(nodes.map((node) => node.type), [
      HeadingBlockKeys.type,
      TodoListBlockKeys.type,
    ]);
    expect(nodes.last.attributes[TodoListBlockKeys.checked], isTrue);
    expect(adapter.blocks.map((block) => block.id), ['h', 't']);
  });

  test('typing becomes a text_delta in the outbox', () async {
    await open(_doc([_block('p', 'paragraph', 'Oi')]));

    final node = editorState.getNodeAtPath([0])!;
    editorState.selection = Selection.collapsed(Position(path: [0], offset: 2));
    await editorState.insertTextAtCurrentSelection('!');

    final ops = await pending();
    expect(ops.single.kind, NoteOperationWireNames.textDelta);
    expect(ops.single.blockId, 'p');
    expect(jsonDecode(ops.single.payloadJson), {
      'ops': [
        {'retain': 2},
        {'insert': '!'},
      ],
    });
    expect(node.delta!.toPlainText(), 'Oi!');
  });

  test('Enter creates a block with a stable new id', () async {
    await open(_doc([_block('p', 'paragraph', 'Olá mundo')]));

    editorState.selection = Selection.collapsed(Position(path: [0], offset: 3));
    await editorState.insertNewLine();
    await pumpEventQueue();

    final ops = await pending();
    final create = ops.firstWhere(
      (op) => op.kind == NoteOperationWireNames.createBlock,
    );
    final newId = create.blockId!;
    expect(newId, isNot('p'));
    // The id was written into the node, so later edits keep it.
    expect(
      editorState.getNodeAtPath([1])!.attributes[NoteNodeKeys.blockId],
      newId,
    );

    editorState.selection = Selection.collapsed(Position(path: [1], offset: 0));
    await editorState.insertTextAtCurrentSelection('>');
    final after = await pending();
    expect(after.last.kind, NoteOperationWireNames.textDelta);
    expect(after.last.blockId, newId);
  });

  test('indenting a task keeps its identity', () async {
    await open(
      _doc([
        _block('t1', 'task', 'Mercado'),
        _block('t2', 'task', 'Leite', {'dueDate': '2026-09-16T09:00:00.000'}),
      ]),
    );

    // The editor's own indent command (Tab / toolbar).
    editorState.selection = Selection.collapsed(Position(path: [1], offset: 0));
    indentCommand.execute(editorState);
    await pumpEventQueue();

    final ops = await pending();
    expect(ops.map((op) => op.kind), [NoteOperationWireNames.setBlockMetadata]);
    expect(ops.single.blockId, 't2');
    expect(jsonDecode(ops.single.payloadJson), {
      // Like the previous editor, the operation carries the block's full
      // metadata, not only the changed keys.
      'metadata': {
        'indent': 1,
        'dueDate': '2026-09-16T09:00:00.000',
        'isCompleted': false,
      },
    });
  });

  test('remote text before the caret shifts the caret, no echo', () async {
    await open(_doc([_block('p', 'paragraph', 'mundo')]));
    editorState.selection = Selection.collapsed(Position(path: [0], offset: 5));

    await adapter.rebuildFromSnapshot(
      snapshot: jsonDecode(
        _doc([_block('p', 'paragraph', 'Olá mundo')]),
      ) as Map<String, dynamic>,
      pendingOps: const [],
    );

    expect(editorState.getNodeAtPath([0])!.delta!.toPlainText(), 'Olá mundo');
    expect(editorState.selection!.end.offset, 9);
    expect(await pending(), isEmpty);
  });

  test(
    'a remote new block rebuilds the tree and keeps the caret block',
    () async {
      await open(
        _doc([
          _block('a', 'paragraph', 'um'),
          _block('b', 'paragraph', 'dois'),
        ]),
      );
      editorState.selection = Selection.collapsed(
        Position(path: [1], offset: 2),
      );

      await adapter.rebuildFromSnapshot(
        snapshot: jsonDecode(
          _doc([
            _block('x', 'task', 'remoto'),
            _block('a', 'paragraph', 'um'),
            _block('b', 'paragraph', 'dois'),
          ]),
        ) as Map<String, dynamic>,
        pendingOps: const [],
      );

      expect(adapter.blocks.map((block) => block.id), ['x', 'a', 'b']);
      expect(editorState.selection!.end.path, [2]);
      expect(editorState.selection!.end.offset, 2);
      expect(await pending(), isEmpty);
    },
  );
}
