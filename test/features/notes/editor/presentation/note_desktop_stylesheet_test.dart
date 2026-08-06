import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/features/notes/editor/presentation/note_desktop_stylesheet.dart';

void main() {
  test('uses Writer-like desktop editor metrics', () {
    expect(DesktopNoteStyleConfig.bodySize, 16);
    expect(DesktopNoteStyleConfig.bodyLineHeight, 1.8);
    expect(DesktopNoteStyleConfig.h1Size, 25.6);
    expect(DesktopNoteStyleConfig.h2Size, 22.4);
    expect(DesktopNoteStyleConfig.h3Size, 19.2);
    expect(DesktopNoteStyleConfig.letterSpacing, -0.48);
    expect(DesktopNoteStyleConfig.headingTopPadding, 16);
    expect(DesktopNoteStyleConfig.paragraphTopPadding, 0);
  });
}
