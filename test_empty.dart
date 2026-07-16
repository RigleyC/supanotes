import 'dart:convert';
import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final doc1 = Doc();
  final t = doc1.getText('content/xyz-123');
  
  final update = encodeStateAsUpdate(doc1);
  final str = String.fromCharCodes(update);
  
  final r1 = RegExp(r'content/[a-zA-Z0-9-]+');
  final matches1 = r1.allMatches(str);
  print('Matches when empty: ${matches1.length}');
  
  t!.insert(0, 'hello');
  
  final hex2 = '0008bb90cbd40e0400797a047f72f20103f690e6820e0502f10190020293020296020299020291eff1a40d050001020407020a020d01b1c0aff008020001a20102d7c2f8e905030001023a3d08f6fbfabf021b000a59019a0101a20102c10101c5011ae801c3e709e9e9098882028bec0baa22b88e0cc20d9a9c0c8d01d69d0cb801ac9f0cfa02e7a20cf503bda70c57f5a80c75cbaa0cf60af7b50cef0beec10c80018ec30c75b2c40ca001f0c50ce20293c90c9203b1cc0c3fd1cd0c3ff1ce0c5dafd00c34a6d1b89002020063642cd6bd9348020001023a';
  final bytes2 = <int>[];
  for (int i = 0; i < hex2.length; i += 2) {
    bytes2.add(int.parse(hex2.substring(i, i + 2), radix: 16));
  }
  final str2 = String.fromCharCodes(bytes2);
  print('Does hex2 contain f6bd? ${str2.contains('f6bd')}');
}
