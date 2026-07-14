import 'dart:convert';
import 'package:dart_crdt/dart_crdt.dart';
import 'dart:typed_data';

void main() async {
  final doc = Doc();
  final tasksMap = doc.getMap('tasks');
  
  final updates = <Uint8List>[];
  doc.onUpdate.listen((update) {
    updates.add(update);
  });
  
  final entry = {'nodeId': '123', 'completed': true};
  doc.transact((txn) {
    tasksMap.setAttr('123', jsonEncode(entry));
  });
  
  print('Generated ${updates.length} updates');
  
  final doc2 = Doc();
  for (final update in updates) {
    print('Update len: ${update.length}');
    try {
      applyUpdate(doc2, update);
      print('Success!');
    } catch (e, st) {
      print('Failed: $e\n$st');
    }
  }
}
