import 'package:yjs_dart/yjs_dart.dart';
import 'dart:convert';
import 'dart:typed_data';

void main() {
  final doc = Doc();
  final txt = doc.getText('test');
  txt!.insert(0, 'hello');
  txt.delete(0, 5);
  
  final sv = encodeStateVector(doc);
  final update = encodeStateAsUpdate(doc, sv);
  print('Update with own SV (has deletes): ' + update.length.toString());
}
