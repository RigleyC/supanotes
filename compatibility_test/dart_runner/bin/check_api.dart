import 'package:yjs_dart/yjs_dart.dart';

void main() {
  print('Doc class: $Doc');
  
  final doc = Doc();
  final update = encodeStateAsUpdate(doc);
  final sv = encodeStateVector(doc);
  print('update length: ${update.length}');
  print('state vector length: ${sv.length}');
  
  final snap = snapshot(doc);
  print('Snapshot: $snap');
}
