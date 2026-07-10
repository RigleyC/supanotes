import 'package:dart_crdt/dart_crdt.dart';

void main() {
  final doc = Doc();
  final yt = doc.getText('test');
  yt.insertText(0, "a🌍b");
  yt.deleteText(1, 2);
  print('Result: "${yt.toPlainText()}"'); // Should be "ab"
}
