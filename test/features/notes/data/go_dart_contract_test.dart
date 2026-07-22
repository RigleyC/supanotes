import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/data/note_sync_client.dart';
import 'package:supanotes/features/notes/domain/attachment_nodes.dart';
import 'package:supanotes/features/notes/domain/note_document_codec.dart';

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
              "dueDate": "2026-07-25T10:00:00Z"
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
      final blocks = decodedMap['blocks'] as List<dynamic>;

      final headerNode = codec.decodeNode(blocks[0] as Map<String, dynamic>);
      expect(headerNode, isA<ParagraphNode>());
      expect((headerNode as ParagraphNode).text.toPlainText(), 'Project Notes');
      expect(headerNode.metadata['blockType'], header1Attribution);

      final taskNode = codec.decodeNode(blocks[1] as Map<String, dynamic>);
      expect(taskNode, isA<TaskNode>());
      final task = taskNode as TaskNode;
      expect(task.text.toPlainText(), 'Buy milk');
      expect(task.isComplete, true);
      expect(task.metadata['dueDate'], '2026-07-25T10:00:00Z');

      final dividerNode = codec.decodeNode(blocks[2] as Map<String, dynamic>);
      expect(dividerNode, isA<HorizontalRuleNode>());

      final attachNode = codec.decodeNode(blocks[3] as Map<String, dynamic>);
      expect(attachNode, isA<DocumentAttachmentNode>());
      final attach = attachNode as DocumentAttachmentNode;
      expect(attach.metadata['attachmentId'], 'att-123');
      expect(attach.metadata['filename'], 'specs.pdf');
      expect(attach.metadata['fileSize'], 1048576);
      expect(attach.metadata['url'], 'https://example.com/specs.pdf');
    });

    test('deserializes Go operation JSON payloads including set_block_metadata', () {
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
    });
  });
}
