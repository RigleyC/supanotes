void main() {
  _updateYTextIncrementally("hello", "helo");
  _updateYTextIncrementally("aba", "a");
  _updateYTextIncrementally("aba", "aca");
  print("All passed!");
}

void _updateYTextIncrementally(String oldText, String newText) {
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
  print("old: $oldText, new: $newText -> start: $start, oldEnd: $oldEnd, newEnd: $newEnd");
  if (deleteLen > 0) {
    print("  deleteText($start, $deleteLen)");
  }

  if (newEnd > start) {
    final insertText = newText.substring(start, newEnd);
    print("  insertText($start, $insertText)");
  }
}
