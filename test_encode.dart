import 'dart:convert';
import 'package:dart_crdt/dart_crdt.dart';

void main() {
  final doc = Doc();
  final tasksMap = doc.getMap('tasks');
  
  final entry = {'nodeId': '123', 'completed': true};
  tasksMap.setAttr('123', jsonEncode(entry));
  
  final update = encodeStateAsUpdate(doc);
  print('Update: ${update.length} bytes');
  
  final doc2 = Doc();
  try {
    applyUpdate(doc2, update);
    print('Success!');
  } catch (e, st) {
    print('Failed: $e\n$st');
  }
}
