import 'dart:typed_data';
import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final doc1 = Doc();
  doc1.getText('content/1')!.insert(0, "hello");
  doc1.getMap('content/2')!.set('key', "val");

  final state = encodeStateAsUpdate(doc1);

  final doc2 = Doc();
  applyUpdate(doc2, state);

  final text1 = doc2.get('content/1');
  final map2 = doc2.get('content/2');

  print("content/1 type: ${text1.runtimeType}");
  print("content/2 type: ${map2.runtimeType}");
}
