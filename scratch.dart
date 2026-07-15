import 'dart:convert';
import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final doc1 = Doc();
  final map1 = doc1.getMap<Object>('nodes')!;
  
  doc1.transact((txn) {
    map1.set('abc', jsonEncode({'id': 'abc', 'type': 'paragraph'}));
    final text = doc1.getText('content/abc')!;
    text.insert(0, 'Hello World');
  });

  print('Doc1 map: ${map1.get('abc')}');
  print('Doc1 text: ${doc1.getText('content/abc')!.toString()}');

  final update = encodeStateAsUpdate(doc1);
  print('Update length: ${update.length}');

  final doc2 = Doc();
  applyUpdate(doc2, update);
  
  final map2 = doc2.getMap<Object>('nodes')!;
  print('Doc2 map: ${map2.get('abc')}');
  print('Doc2 text: ${doc2.getText('content/abc')!.toString()}');
}
