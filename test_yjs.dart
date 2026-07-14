import 'dart:convert';
import 'package:dart_crdt/dart_crdt.dart';
import 'package:supanotes/features/notes/domain/yjs_doc_editor_bridge.dart';

void main() {
  final doc1 = Doc();
  final nodes1 = doc1.getMap('nodes');
  
  // Simulate _serializeNode for Title
  var meta1 = {
    'id': 'n1',
    'parentId': '',
    'position': 'a0',
    'type': 'header',
    'data': {'text': 'Title', 'level': 1},
    'createdAt': 1000,
  };
  nodes1.setAttr('n1', jsonEncode(meta1));
  doc1.getText('content/n1').insertText(0, 'Title');

  // Simulate _serializeNode for Text
  var meta2 = {
    'id': 'n2',
    'parentId': '',
    'position': 'a1',
    'type': 'paragraph',
    'data': {'text': 'Text'},
    'createdAt': 1001,
  };
  nodes1.setAttr('n2', jsonEncode(meta2));
  doc1.getText('content/n2').insertText(0, 'Text');

  final update1 = encodeStateAsUpdate(doc1);

  // Device B
  final doc2 = Doc();
  applyUpdate(doc2, update1);

  // Print Device B state
  print("Device B notes:");
  final bNodes = doc2.getMap('nodes');
  for (final k in bNodes.attrKeys) {
    print("Node $k: ${bNodes.getAttr(k)}");
    print("Text $k: ${doc2.getText('content/$k').toPlainText()}");
  }

  // Device B types in Text (n2)
  doc2.getText('content/n2').insertText(4, ' B');
  var meta2b = {
    'id': 'n2',
    'parentId': '',
    'position': 'a1',
    'type': 'paragraph',
    'data': {'text': 'Text B'},
    'createdAt': 1001,
  };
  bNodes.setAttr('n2', jsonEncode(meta2b));

  final update2 = encodeStateAsUpdate(doc2);
  
  // Device A applies Device B update
  applyUpdate(doc1, update2);
  print("\nDevice A after receiving B:");
  for (final k in nodes1.attrKeys) {
    print("Node $k: ${nodes1.getAttr(k)}");
    print("Text $k: ${doc1.getText('content/$k').toPlainText()}");
  }
}
