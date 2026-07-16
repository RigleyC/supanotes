import 'dart:typed_data';
import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final doc1 = Doc();
  final t = doc1.getText('content/x')!;
  t.insert(0, 'hello world');
  final update1 = encodeStateAsUpdate(doc1);
  
  final doc2 = Doc();
  // DO NOT pre-register! doc2 will instantiate it as YMap
  applyUpdate(doc2, update1);
  
  // Now encode doc2 and decode back to doc3 WITH pre-register
  final update2 = encodeStateAsUpdate(doc2);
  
  final doc3 = Doc();
  doc3.getText('content/x');
  applyUpdate(doc3, update2);
  
  print('doc3 text: \${doc3.getText("content/x")?.toString()}');
}
