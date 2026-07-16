import 'package:flutter_test/flutter_test.dart';
import 'package:yjs_dart/yjs_dart.dart';

void main() {
  test('Nested YMap reads immediately', () {
    final doc = Doc();
    final nodesMap = doc.getMap<Object>('nodes')!;
    
    doc.transact((txn) {
      final nodeMap = YMap<Object>();
      nodeMap.set('position', 'a0');
      nodesMap.set('node1', nodeMap);
      
      final raw = nodesMap.get('node1');
      print('raw type: ${raw.runtimeType}');
      
      if (raw is YMap) {
        print('position: ${raw.get('position')}');
      } else {
        print('raw is not YMap!');
      }
    });
  });
}
