import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yjs_dart/yjs_dart.dart';

void main() {
  test('Does Yjs serialize an empty type?', () {
    final doc1 = Doc();
    // Instantiate it but don't add anything
    doc1.getText('content/1234');
    
    final update = encodeStateAsUpdate(doc1);
    final str = String.fromCharCodes(update);
    
    print('Update length: ${update.length}');
    print('Contains content/1234: ${str.contains('content/1234')}');
  });
}
