import 'dart:typed_data';
import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final doc1 = Doc();
  doc1.getText('content/empty'); // Pre-register, but don't insert anything
  
  final update = encodeStateAsUpdate(doc1);
  final str = String.fromCharCodes(update);
  final matches = RegExp(r'content/[a-zA-Z0-9-]+').allMatches(str);
  
  print('Matches for empty YText: \${matches.length}');
}
