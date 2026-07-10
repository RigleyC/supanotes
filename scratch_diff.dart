void main() {
  testDiff("ab", "abab");
  testDiff("aba", "ababa");
  testDiff("a", "aa");
  testDiff("a", "");
  testDiff("", "a");
  testDiff("hello", "hello");
  testDiff("hello", "helo");
  testDiff("hello", "hello world");
  testDiff("hello world", "hello");
}

void testDiff(String oldText, String newText) {
  int start = 0;
  int oldEnd = oldText.length;
  int newEnd = newText.length;

  while (start < oldEnd && start < newEnd && oldText.codeUnitAt(start) == newText.codeUnitAt(start)) {
    start++;
  }

  while (oldEnd > start && newEnd > start && oldText.codeUnitAt(oldEnd - 1) == newText.codeUnitAt(newEnd - 1)) {
    oldEnd--;
    newEnd--;
  }

  final deleteLen = oldEnd - start;
  String result = oldText;
  if (deleteLen > 0) {
    result = result.substring(0, start) + result.substring(start + deleteLen);
  }
  if (newEnd > start) {
    result = result.substring(0, start) + newText.substring(start, newEnd) + result.substring(start);
  }
  
  if (result != newText) {
    print("FAILED: old='$oldText', new='$newText', got='$result'");
  } else {
    print("OK: '$oldText' -> '$newText'");
  }
}
