import 'package:flutter_test/flutter_test.dart';
import 'package:yjs_dart/yjs_dart.dart';
import 'package:supanotes/core/utils/fractional_indexing.dart';

void main() {
  test('Fractional Indexing paste simulation', () {
    final doc = Doc();
    final nodesMap = doc.getMap<Object>('nodes')!;

    doc.transact((txn) {
      for (int i = 0; i < 5; i++) {
        final id = 'node$i';
        final prevNodeId = i > 0 ? 'node${i - 1}' : null;

        String? prevPos;
        String? nextPos;

        if (prevNodeId != null) {
          final raw = nodesMap.get(prevNodeId);
          if (raw is YMap) {
            final val = raw.get('position');
            if (val is String) prevPos = val;
          }
        }

        final pos = FractionalIndex.between(prevPos, nextPos);
        print('Insert node$i at pos $pos (prevPos=$prevPos)');

        final nodeMap = YMap<Object>();
        nodeMap.set('id', id);
        nodeMap.set('position', pos);
        nodesMap.set(id, nodeMap);
      }
    });
    
    print('Final YDoc state:');
    for (final key in nodesMap.keys) {
      final raw = nodesMap.get(key);
      if (raw is YMap) {
        print('$key: ${raw.get('position')}');
      }
    }
  });
}
