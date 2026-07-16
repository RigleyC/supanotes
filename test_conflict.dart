import 'dart:typed_data';
import 'package:yjs_dart/yjs_dart.dart';

void main() {
  // Simulate Go Backend: Creates YMap for 'content/x'
  final docGo = Doc();
  final mapGo = docGo.getMap('content/x')!;
  mapGo.set('foo', 'bar');
  final updateGo = encodeStateAsUpdate(docGo);
  
  // Simulate Flutter: Pre-registers YText for 'content/x'
  final docFlutter = Doc();
  docFlutter.getText('content/x');
  
  print('Applying update from Go to Flutter...');
  try {
    applyUpdate(docFlutter, updateGo);
    print('Applied successfully!');
    
    // Now try to access it as YText!
    try {
      final t = docFlutter.getText('content/x');
      print('Got YText! length = \${t?.length}');
    } catch (e) {
      print('getText error: \$e');
    }
  } catch (e) {
    print('applyUpdate error: \$e');
  }
}
