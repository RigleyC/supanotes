import 'dart:typed_data';
import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final doc1 = Doc();
  final update1 = encodeStateAsUpdate(doc1); // empty
  
  final doc2 = Doc();
  applyUpdate(doc2, update1);
  
  // Now create a new root type in doc1
  doc1.getText('content/my-new-uuid');
  
  // Get the delta update
  final update2 = encodeStateAsUpdate(doc1, encodeStateVector(doc2));
  
  final str = String.fromCharCodes(update2);
  final matches = RegExp(r'content/[a-zA-Z0-9-]+').allMatches(str);
  print('Matches in delta: \${matches.length}');
  for (final m in matches) {
    print(m.group(0));
  }
}
