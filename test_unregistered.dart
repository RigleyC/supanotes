import 'dart:typed_data';
import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final docGo = Doc();
  final mapGo = docGo.getMap('content/x')!;
  mapGo.set('foo', 'bar');
  final updateGo = encodeStateAsUpdate(docGo);
  
  final docFlutter = Doc();
  // DO NOT pre-register!
  
  applyUpdate(docFlutter, updateGo);
  
  try {
    docFlutter.getText('content/x');
  } catch (e) {
    print('Error: \$e');
  }
}
