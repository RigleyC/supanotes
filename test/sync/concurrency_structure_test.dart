import 'package:flutter_test/flutter_test.dart';
import 'package:yjs_dart/yjs_dart.dart';

void main() {
  group('Multi-Device Convergence & Structure', () {
    test('Concurrent edits on separate Yjs Docs converge', () {
      final docA = Doc();
      final docB = Doc();

      // Initial empty vector sync to pair them
      final stateB = encodeStateAsUpdate(docB);
      applyUpdate(docA, stateB);

      final stateA = encodeStateAsUpdate(docA);
      applyUpdate(docB, stateA);

      // Device A inserts "Hello " at 0
      docA.transact((t) {
        docA.getText('text')!.insert(0, 'Hello ');
      });

      // Device B inserts "World" at 0 concurrently
      docB.transact((t) {
        docB.getText('text')!.insert(0, 'World');
      });

      // Sync changes from A -> B
      final updateA = encodeStateAsUpdate(docA);
      applyUpdate(docB, updateA);

      // Sync changes from B -> A
      final updateB = encodeStateAsUpdate(docB);
      applyUpdate(docA, updateB);

      // Both documents must converge on exactly the same text!
      final textA = docA.getText('text').toString();
      final textB = docB.getText('text').toString();

      expect(textA, textB);
      expect(textA, isNotEmpty);
      expect(textA.contains('Hello '), isTrue);
      expect(textA.contains('World'), isTrue);
    });

    test('Fractional index position reordering converges', () {
      final docA = Doc();
      final docB = Doc();

      // Setup initial node list in both
      docA.transact((t) {
        docA.getMap('nodes')!.set('node-1', '{"id":"node-1","position":10.0}');
        docA.getMap('nodes')!.set('node-2', '{"id":"node-2","position":20.0}');
      });

      // Sync A -> B
      applyUpdate(docB, encodeStateAsUpdate(docA));

      // Device A moves node-2 before node-1 (fractional index position = 5.0)
      docA.transact((t) {
        docA.getMap('nodes')!.set('node-2', '{"id":"node-2","position":5.0}');
      });

      // Device B concurrently moves node-1 after node-2 (fractional index position = 25.0)
      docB.transact((t) {
        docB.getMap('nodes')!.set('node-1', '{"id":"node-1","position":25.0}');
      });

      // Exchange updates
      applyUpdate(docB, encodeStateAsUpdate(docA));
      applyUpdate(docA, encodeStateAsUpdate(docB));

      // Confirm both devices ended up with the same configuration
      final nodesA = docA.getMap('nodes')!;
      final nodesB = docB.getMap('nodes')!;

      expect(nodesA.get('node-1'), nodesB.get('node-1'));
      expect(nodesA.get('node-2'), nodesB.get('node-2'));
    });
  });
}
