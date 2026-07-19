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
  
  doc.onUpdate.listen((event) {
    print('Doc updated! length: ${event.update.length}');
  });
  
  print('Applying same update...');
  applyUpdate(doc, update);
  print('Done.');
}
