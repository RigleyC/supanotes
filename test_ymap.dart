import 'package:dart_crdt/dart_crdt.dart';

void main() {
  final doc = Doc();
  final map = doc.getMap('test');
  
  doc.transact((txn) {
    map.setAttr('k1', 'v1');
    print('Keys after k1: ${map.attrKeys}');
    map.setAttr('k2', 'v2');
    print('Keys after k2: ${map.attrKeys}');
  });
}
