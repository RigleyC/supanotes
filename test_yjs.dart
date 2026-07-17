import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final docA = Doc();
  docA.getMap<Object>('nodes')!.set('node-1', 'hi');
  docA.getText('content/node-1')!.insert(0, 'hello');
  final state = encodeStateAsUpdate(docA);

  final docB = Doc();
  applyUpdate(docB, state);

  print('Map keys: ${docB.getMap<Object>('nodes')!.keys.toList()}');
  print('Text: ${docB.getText('content/node-1')!.toString()}');
}
