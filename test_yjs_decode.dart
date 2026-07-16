import 'dart:convert';
import 'dart:typed_data';
import 'package:yjs_dart/yjs_dart.dart';

void applyUpdateSafe(Doc doc, Uint8List update) {
  final str = String.fromCharCodes(update);
  final matches = RegExp(r'content/[a-zA-Z0-9-_]+').allMatches(str);
  for (final match in matches) {
    doc.getText(match.group(0)!);
  }
  applyUpdate(doc, update);
}

void main() {
  // 1. Create a document, insert into a YText
  final doc1 = Doc();
  final t = doc1.getText('content/f6bd7597-48c7-470a-8d3d-a3b53f51f00c');
  t!.insert(0, 'hello');
  
  final update1 = encodeStateAsUpdate(doc1);
  
  // 2. Another device decodes it WITHOUT pre-registering (simulating the old bug)
  final doc2 = Doc();
  applyUpdate(doc2, update1);
  
  // It is now a YMap!
  try {
    doc2.getText('content/f6bd7597-48c7-470a-8d3d-a3b53f51f00c');
  } catch (e) {
    print('doc2 threw: $e'); // This should throw!
  }
  
  // 3. The other device encodes its state
  final update2 = encodeStateAsUpdate(doc2);
  
  // 4. We decode it WITH applyUpdateSafe
  final doc3 = Doc();
  applyUpdateSafe(doc3, update2);
  
  // Does it throw?!
  try {
    doc3.getText('content/f6bd7597-48c7-470a-8d3d-a3b53f51f00c');
    print('doc3 succeeded!');
  } catch (e) {
    print('doc3 threw: $e');
  }
}
