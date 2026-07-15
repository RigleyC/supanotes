import 'dart:convert';
import 'package:dart_crdt/dart_crdt.dart';

void main() {
  final doc1 = Doc();
  final map1 = doc1.getMap('nodes');
  
  doc1.transact((txn) {
    map1.setAttr('abc', jsonEncode({'id': 'abc', 'type': 'paragraph'}));
    final text = doc1.getText('content/abc');
    text.insertText(0, 'Hello World');
  });

  print('Doc1 map: ${map1.getAttr('abc')}');
  print('Doc1 text: ${doc1.getText('content/abc').toPlainText()}');

  final update = encodeStateAsUpdate(doc1);
  print('Update length: ${update.length}');

  final doc2 = Doc();
  applyUpdate(doc2, update);
  
  final map2 = doc2.getMap('nodes');
  print('Doc2 map: ${map2.getAttr('abc')}');
  print('Doc2 text: ${doc2.getText('content/abc').toPlainText()}');
}
