import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final doc = Doc();
  final sv = encodeStateVector(doc);
  final update = encodeStateAsUpdate(doc, sv);
  print('update length: ${update.length}');
  print('update: $update');
}
