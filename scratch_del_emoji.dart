import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final doc = Doc();
  final yt = doc.getText('test')!;
  yt.insert(0, "a🌍b");
  yt.delete(1, 2);
  print('Result: "${yt.toString()}"'); // Should be "ab"
}
