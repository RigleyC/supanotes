import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/features/notes/domain/yjs_note_schema.dart';

void main() {
  group('YjsNoteSchema normalization', () {
    test('normalization preserves legacy text and moves task metadata inside node map', () {
      final doc = Doc();
      doc.transact((txn) {
        final nodesMap = doc.getMap<Object>('nodes')!;

        // Create a legacy node with composite keys and JSON string data
        final nodeMap = YMap<Object>();
        nodeMap.set('id', 'task-1');
        nodeMap.set('type', 'task');
        nodeMap.set('position', 'a0');
        nodeMap.set('data', jsonEncode({
          'text': 'Buy milk',
          'completed': false,
        }));
        nodeMap.set('createdAt', DateTime.now().millisecondsSinceEpoch.toDouble());
        nodesMap.set('task-1', nodeMap);

        // Legacy composite keys
        nodesMap.set('task-1:completed', false);
        nodesMap.set('task-1:dueDate', '2026-07-19T09:00');
        nodesMap.set('task-1:recurrence', 'daily');
        nodesMap.set('task-1:reminder', '9am');
      });

      // Create YText
      doc.getText('content/task-1')!.insert(0, 'Buy milk');

      // Normalize
      YjsNoteSchema.normalizeNode(doc, 'task-1');

      final node = YjsNoteSchema.requireNode(doc, 'task-1');

      // Task metadata should be inside node map
      expect(node.get('dueDate'), '2026-07-19T09:00');
      expect(node.get('recurrence'), 'daily');
      expect(node.get('reminder'), '9am');
      expect(node.get('completed'), false);

      // Composite keys should be cleaned up
      final nodesMap = doc.getMap<Object>('nodes')!;
      expect(nodesMap.get('task-1:dueDate'), isNull);
      expect(nodesMap.get('task-1:recurrence'), isNull);
      expect(nodesMap.get('task-1:reminder'), isNull);

      // Text content preserved in YText
      expect(doc.getText('content/task-1')!.toString(), 'Buy milk');
    });

    test('normalizeNode converts JSON string node to YMap', () {
      final doc = Doc();
      doc.transact((txn) {
        final nodesMap = doc.getMap<Object>('nodes')!;
        // Store as JSON string (legacy format)
        nodesMap.set('json-node', jsonEncode({
          'id': 'json-node',
          'type': 'paragraph',
          'position': 'a0',
          'data': {'text': 'JSON content'},
          'createdAt': 1000.0,
        }));
      });

      expect(doc.getMap<Object>('nodes')!.get('json-node'), isA<String>());

      YjsNoteSchema.normalizeNode(doc, 'json-node');

      final raw = doc.getMap<Object>('nodes')!.get('json-node');
      expect(raw, isA<YMap>());

      final node = YjsNoteSchema.requireNode(doc, 'json-node');
      expect(node.get('id'), 'json-node');
      expect(node.get('type'), 'paragraph');
      expect(node.get('position'), 'a0');
    });

    test('canonical writeNode stores task fields inside node map (not composite keys)', () {
      final doc = Doc();
      final document = MutableDocument(nodes: [
        TaskNode(id: 't1', text: AttributedText('Task item'), isComplete: true),
      ]);

      doc.transact((txn) {
        YjsNoteSchema.writeNode(doc, document.first, position: 'a0');
      });

      final node = YjsNoteSchema.requireNode(doc, 't1');
      expect(node.get('completed'), isTrue);
      expect(node.get('id'), 't1');
      expect(node.get('type'), 'task');

      // No composite keys
      final nodesMap = doc.getMap<Object>('nodes')!;
      expect(nodesMap.get('t1:completed'), isNull);

      // Text content in YText
      expect(doc.getText('content/t1')!.toString(), 'Task item');
    });

    test('readNode reads task fields correctly from canonical YMap', () {
      final doc = Doc();
      doc.transact((txn) {
        final nodeMap = YMap<Object>();
        nodeMap.set('id', 't1');
        nodeMap.set('type', 'task');
        nodeMap.set('position', 'a0');
        nodeMap.set('data', jsonEncode({'text': 'Read test', 'completed': false}));
        nodeMap.set('createdAt', 2000.0);
        nodeMap.set('completed', true);
        nodeMap.set('dueDate', '2026-08-01');
        nodeMap.set('recurrence', 'weekly');
        doc.getMap<Object>('nodes')!.set('t1', nodeMap);
      });
      doc.getText('content/t1')!.insert(0, 'Read test');

      final noteNode = YjsNoteSchema.readNode(doc, 't1');

      expect(noteNode.id, 't1');
      expect(noteNode.type, 'task');
      expect(noteNode.data['text'], 'Read test');
      expect(noteNode.data['completed'], isTrue);
      expect(noteNode.data['dueDate'], '2026-08-01');
      expect(noteNode.data['recurrence'], 'weekly');
    });
  });
}
