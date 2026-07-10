import 'package:dart_crdt/dart_crdt.dart';

void main() {
  final doc = Doc();
  final ytext = doc.getText('content');
  ytext.insertText(0, "a🌍b");
  print("string length: ${"a🌍b".length}");
  print("runes length: ${"a🌍b".runes.length}");
  print("ytext length: ${ytext.toPlainText().length}");
}
