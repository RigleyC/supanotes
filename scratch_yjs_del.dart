import 'package:dart_crdt/dart_crdt.dart';

void main() {
  final doc = Doc();
  final ytext = doc.getText('content');
  ytext.insertText(0, "Hello");
  print("before: ${ytext.toPlainText()}");
  
  if (ytext.toPlainText().length > 0) {
    ytext.deleteText(0, ytext.toPlainText().length);
  }
  
  ytext.insertText(0, "World");
  print("after: ${ytext.toPlainText()}");
}
