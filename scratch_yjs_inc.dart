import 'package:dart_crdt/dart_crdt.dart';

void main() {
  final doc = Doc();
  final ytext = doc.getText('content');
  
  // Test 1: Insert "A B" and replace with "A B C"
  ytext.insertText(0, "A B");
  int oldEnd = 3;
  int start = 3;
  ytext.deleteText(start, oldEnd - start);
  ytext.insertText(start, " C");
  print('Test 1: "${ytext.toPlainText()}"'); // Should be "A B C"
  
  // Test 2: Replace "a🌍b" with "a🌍"
  final doc2 = Doc();
  final yt2 = doc2.getText('test');
  yt2.insertText(0, "a🌍b");
  // new is "a🌍" (length 3). old is "a🌍b" (length 4).
  // common prefix is "a🌍" (length 3).
  int st = 3; 
  int delLen = 4 - 3; // 1
  yt2.deleteText(st, delLen);
  print('Test 2: "${yt2.toPlainText()}"'); // Should be "a🌍"
  
  // Test 3: The exact duplication bug.
  // "Hello" -> "HelloHello" ?
  final doc3 = Doc();
  final yt3 = doc3.getText('dup');
  yt3.insertText(0, "Hello");
  
  String oldText = "Hello";
  String newText = "Hello";
  // wait if newText == oldText it returns early.
  
  newText = "Hello\n";
  int s = 5;
  int oEnd = 5;
  int nEnd = 6;
  yt3.deleteText(s, oEnd - s);
  yt3.insertText(s, "\n");
  print('Test 3: "${yt3.toPlainText()}"');
}
