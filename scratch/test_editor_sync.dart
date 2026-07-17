import 'dart:convert';
import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final doc = Doc();
  final nodesMap = doc.getMap<Object>('nodes')!;
  
  // Simulate bridge serializing a node
  final id = 'test-id';
  final nodeMap = YMap<Object>();
  nodesMap.set(id, nodeMap);
  nodeMap.set('id', id);
  nodeMap.set('type', 'paragraph');
  nodeMap.set('data', jsonEncode({'text': 'Hello world'}));
  
  final text = doc.getText('content/$id')!;
  text.insert(0, 'Hello world');
  
  print('Text: ${doc.getText('content/$id')!.toString()}');
}
