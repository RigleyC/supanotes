import 'dart:typed_data';
import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final doc = Doc();
  final t = doc.getText('content/bfb40215-e06e-48bd-bee5-8aeeac49f546')!;
  t.insert(0, 'hello');
  
  final update = encodeStateAsUpdate(doc);
  final str = String.fromCharCodes(update);
  
  final matches = RegExp(r'content/[a-zA-Z0-9-]+').allMatches(str);
  print('Matches in state vector: \${matches.length}');
  for (final m in matches) {
    print(m.group(0));
  }
}
