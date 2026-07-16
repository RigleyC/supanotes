import 'dart:typed_data';
import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final doc1 = Doc();
  final update1 = encodeStateAsUpdate(doc1); 
  
  final doc2 = Doc();
  applyUpdate(doc2, update1);
  
  doc1.getText('content/my-new-uuid');
  
  final update2 = encodeStateAsUpdate(doc1, encodeStateVector(doc2));
  
  print('Update2 length: \${update2.length}');
  print('Update2 hex: \${update2.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
}
