import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_style.dart';

void main() {
  test('a note link opens the note by id', () {
    String? opened;
    final handler = NoteLinkHandler(onNoteTap: (id) => opened = id);

    expect(handler.open('note://n-42'), isTrue);
    expect(opened, 'n-42');
  });

  test('note links are ignored where internal links are not allowed', () {
    String? opened;
    final handler = NoteLinkHandler(
      onNoteTap: (id) => opened = id,
      allowInternalNoteLinks: false,
    );

    expect(handler.open('note://n-42'), isFalse);
    expect(opened, isNull);
  });

  test('a public page only follows web links', () {
    const handler = NoteLinkHandler(webOnly: true);

    expect(handler.open('mailto:a@b.dev'), isFalse);
    expect(handler.open('note://n-1'), isFalse);
  });
}
