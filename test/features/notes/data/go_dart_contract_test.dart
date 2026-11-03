import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy_editor/appflowy_editor.dart' hide Operation;
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

void main() {
  group('Go-to-Dart Contract Integration Test', () {
    const codec = NoteDocumentCodec();

    test('deserializes Go document snapshot with task, attachment, divider and metadata', () {
      // Representation matching Go backend json.Marshal(Document)
      const goDocumentJson = '''
      {
        "schemaVersion": 1,
        "blocks": [
          {
            "id": "b-header",
            "type": "header1",
            "delta": [{"insert": "Project Notes"}],
            "metadata": {}
          },
          {
            "id": "b-task-1",
            "type": "task",
            "delta": [{"insert": "Buy milk"}],
            "metadata": {
              "isCompleted": true,
              "dueDate": "2026-07-25T10:00:00.000"
            }
          },
          {
            "id": "b-div",
            "type": "divider",
            "delta": [],
            "metadata": {}
          },
          {
            "id": "b-attach",
            "type": "attachment",
            "delta": [],
            "metadata": {
              "attachmentId": "att-123",
              "filename": "specs.pdf",
              "fileSize": 1048576,
              "mimeType": "application/pdf",
              "url": "https://example.com/specs.pdf"
            }
          }
        ]
      }
      ''';

      final decodedMap = jsonDecode(goDocumentJson) as Map<String, dynamic>;
      // The document passes the client's contract validation...
      expect(codec.parseSnapshot(decodedMap).blocks, hasLength(4));

      // ...and becomes the nodes the editor renders.
      final nodes = const NoteAppFlowyCodec()
          .toDocument(noteBlocksFromSnapshot(decodedMap))
          .root
          .children
          .toList();

      expect(nodes[0].type, HeadingBlockKeys.type);
      expect(nodes[0].attributes[HeadingBlockKeys.level], 1);
      expect(nodes[0].delta!.toPlainText(), 'Project Notes');

      expect(nodes[1].type, TodoListBlockKeys.type);
      expect(nodes[1].delta!.toPlainText(), 'Buy milk');
      expect(nodes[1].attributes[TodoListBlockKeys.checked], isTrue);
      expect(
        nodes[1].attributes[NoteNodeKeys.metadata],
        {'dueDate': '2026-07-25T10:00:00.000'},
      );

      expect(nodes[2].type, DividerBlockKeys.type);

      expect(nodes[3].type, NoteNodeTypes.attachment);
      final attachment = nodes[3].attributes[NoteNodeKeys.metadata] as Map;
      expect(attachment['attachmentId'], 'att-123');
      expect(attachment['filename'], 'specs.pdf');
      expect(attachment['fileSize'], 1048576);
      expect(attachment['url'], 'https://example.com/specs.pdf');
      expect(
        nodes.map((node) => node.attributes[NoteNodeKeys.blockId]),
        ['b-header', 'b-task-1', 'b-div', 'b-attach'],
      );
    });

    test(
      'deserializes Go operation JSON payloads including set_block_metadata',
      () {
        const goOperationJson = '''
      {
        "operationId": "e1b2c3d4-0000-0000-0000-000000000001",
        "noteId": "a1b2c3d4-0000-0000-0000-000000000001",
        "revision": 12,
        "baseRevision": 11,
        "actorId": "u1b2c3d4-0000-0000-0000-000000000001",
        "kind": "set_block_metadata",
        "blockId": "b-task-1",
        "payload": {
          "metadata": {
            "isCompleted": true
          }
        },
        "createdAt": "2026-07-21T15:00:00Z"
      }
      ''';

        final opMap = jsonDecode(goOperationJson) as Map<String, dynamic>;
        final op = Operation.fromJson(opMap);

        expect(op.operationId, 'e1b2c3d4-0000-0000-0000-000000000001');
        expect(op.noteId, 'a1b2c3d4-0000-0000-0000-000000000001');
        expect(op.revision, 12);
        expect(op.baseRevision, 11);
        expect(op.actorId, 'u1b2c3d4-0000-0000-0000-000000000001');
        expect(op.kind, 'set_block_metadata');
        expect(op.blockId, 'b-task-1');
        expect(op.payload['metadata']['isCompleted'], true);
      },
    );
  });
}
