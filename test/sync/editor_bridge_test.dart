import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:super_editor/super_editor.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/domain/note_sync_coordinator.dart';
import 'package:supanotes/features/notes/domain/yjs_doc_editor_bridge.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.test(executor: NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('YjsDocEditorBridge', () {
    test('Typing in editor updates Yjs Doc', () async {
      final doc = Doc();
      final mutableDoc = MutableDocument.empty();
      final editor = Editor(
        editContext: EditContext(
          editorLayoutKey: GlobalKey(),
          document: mutableDoc,
          composer: DocumentComposer(),
          commonOps: CommonEditorOperations(
            editor: Editor(),
            document: mutableDoc,
            composer: DocumentComposer(),
          ),
        ),
      );

      final coordinator = NoteSyncCoordinator(
        database: db,
        noteId: 'note-1',
        userId: 'user-1',
        document: mutableDoc,
        editor: editor,
      );

      final updates = <Uint8List>[];
      final bridge = YjsDocEditorBridge(
        doc: doc,
        coordinator: coordinator,
        sendUpdate: (u) => updates.add(u),
      );

      // Simulate inserting a node locally via editor
      editor.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 0,
          newNode: ParagraphNode(id: 'p1', text: AttributedText('Hello World')),
        ),
      ]);

      // Flush local coordinator state manually to trigger bridge sync
      bridge.onLocalFlush(coordinator.locallyDirtyNodeIds.map((id) {
        final node = mutableDoc.getNodeById(id)!;
        return InsertOp(id: id, node: node, index: 0);
      }).toList());

      // Verify that YDoc map got the node serialized and the text updated
      final nodesMap = doc.getMap('nodes')!;
      expect(nodesMap.keys, contains('p1'));

      final meta = jsonDecode(nodesMap.get('p1') as String) as Map<String, dynamic>;
      expect(meta['id'], 'p1');
      expect(meta['type'], 'paragraph');

      final ytext = doc.getText('content/p1')!;
      expect(ytext.toString(), 'Hello World');
      expect(updates, isNotEmpty);

      bridge.dispose();
    });

    test('Selection preservation and clamping during remote sync', () async {
      final mutableDoc = MutableDocument(nodes: [
        ParagraphNode(id: 'p1', text: AttributedText('Hello')),
      ]);
      final composer = DocumentComposer(
        initialSelection: const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'p1',
            nodePosition: TextNodePosition(offset: 3),
          ),
        ),
      );
      final editor = Editor(
        editContext: EditContext(
          editorLayoutKey: GlobalKey(),
          document: mutableDoc,
          composer: composer,
          commonOps: CommonEditorOperations(
            editor: Editor(),
            document: mutableDoc,
            composer: composer,
          ),
        ),
      );

      final coordinator = NoteSyncCoordinator(
        database: db,
        noteId: 'note-1',
        userId: 'user-1',
        document: mutableDoc,
        editor: editor,
      );

      // 1. Remote update with longer text -> selection offset 3 must be preserved
      coordinator.updateNodesIncrementally([
        NoteNode(
          id: 'p1',
          noteId: 'note-1',
          position: 1.0,
          type: 'paragraph',
          data: jsonEncode({'text': 'Hello World', 'spans': []}),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          isDirty: false,
        ),
      ]);

      expect(composer.selection, isNotNull);
      expect(composer.selection!.base.nodeId, 'p1');
      expect((composer.selection!.base.nodePosition as TextNodePosition).offset, 3);

      // 2. Remote update with shorter text -> selection offset must be clamped
      coordinator.updateNodesIncrementally([
        NoteNode(
          id: 'p1',
          noteId: 'note-1',
          position: 1.0,
          type: 'paragraph',
          data: jsonEncode({'text': 'Hi', 'spans': []}),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          isDirty: false,
        ),
      ]);

      expect(composer.selection, isNotNull);
      expect(composer.selection!.base.nodeId, 'p1');
      expect((composer.selection!.base.nodePosition as TextNodePosition).offset, 2); // Clamped to Hi's length
    });
  });
}
