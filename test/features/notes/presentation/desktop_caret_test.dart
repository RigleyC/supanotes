import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop editor uses a narrow caret', () {
    final source = File(
      'lib/features/notes/editor/presentation/widgets/note_editor.dart',
    ).readAsStringSync();

    expect(source, contains('width: 1.5'));
  });
}
