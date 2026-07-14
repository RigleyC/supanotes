import 'package:dart_crdt/dart_crdt.dart';

void main() {
  final doc1 = Doc();
  final map1 = doc1.getMap('nodes');
  doc1.transact((_) {
    map1.setAttr('id1', 'value1');
  });
  
  final doc2 = Doc();
  doc2.getMap('nodes');
  applyUpdate(doc2, encodeStateAsUpdate(doc1));
  print('doc2 after insert: ${doc2.getMap('nodes').getAttr('id1')}');

  doc1.transact((_) {
    map1.setAttr('id1', 'value2');
  });

  final update = encodeStateAsUpdate(doc1, encodeDocumentStateVector(doc2));
  
  // Test decoding the update we just encoded
  try {
    applyUpdate(doc2, update);
    print('doc2 after update: ${doc2.getMap('nodes').getAttr('id1')}');
  } catch (e) {
    print('Error applying update: $e');
  }
}
