import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yjs_dart/yjs_dart.dart';

void main() {
  test('Does Yjs cache strings across multiple updates?', () {
    final doc1 = Doc();
    final ytext = doc1.getText('content/1234-abcd')!;
    ytext.insert(0, 'A');
    final sv0 = encodeStateVector(doc1);
    
    ytext.insert(1, 'B');
    final update1 = encodeStateAsUpdate(doc1, sv0);
    final str1 = String.fromCharCodes(update1);
    print('Update 1 contains content/1234-abcd: ${str1.contains('content/1234-abcd')}');
    
    final doc2 = Doc();
    applyUpdate(doc2, encodeStateAsUpdate(doc1)); // full state
    
    final sv1 = encodeStateVector(doc2);
    ytext.insert(2, 'C');
    final update2 = encodeStateAsUpdate(doc1, sv1);
    final str2 = String.fromCharCodes(update2);
    print('Update 2 contains content/1234-abcd: ${str2.contains('content/1234-abcd')}');
  });
}
