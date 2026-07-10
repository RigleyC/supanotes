import 'package:yjs_dart/yjs_dart.dart';

void main() {
  final doc = Doc();
  final ytext = doc.getText('content')!;
  ytext.insert(0, "a🌍b");
  print("string length: ${"a🌍b".length}");
  print("runes length: ${"a🌍b".runes.length}");
  print("ytext length: ${ytext.length}");
}
