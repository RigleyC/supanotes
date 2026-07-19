import 'package:yjs_dart/yjs_dart.dart';
import 'dart:convert';
import 'dart:typed_data';

void main() {
  final doc = Doc();
  final txt = doc.getText('test');
  txt!.insert(0, 'hello');
  
  final update = encodeStateAsUpdate(doc);
  final sv = encodeStateVector(doc);
  
  print('Update from own sv: ' + encodeStateAsUpdate(doc, sv).length.toString());
}
