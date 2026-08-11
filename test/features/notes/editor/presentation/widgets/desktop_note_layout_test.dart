import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/desktop_editor_viewport.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/desktop_note_chrome.dart';
import 'package:supanotes/features/notes/preferences/application/note_preferences_mutation_controller.dart';
import 'package:supanotes/shared/theme/desktop_layout_tokens.dart';

void main() {
  testWidgets('desktop editor viewport caps the readable column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopEditorViewport(
            child: ColoredBox(
              key: const ValueKey('editor-viewport-child'),
              color: Colors.transparent,
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('editor-viewport-child'))).width,
      DesktopLayoutTokens.editorMaxWidth +
          (DesktopLayoutTokens.editorSidePaddingMax * 2),
    );
    final layout = tester.widget<DesktopEditorLayoutScope>(
      find.byType(DesktopEditorLayoutScope),
    );
    expect(layout.documentPadding.left, 64);
    expect(layout.documentPadding.right, 64);
    expect(layout.documentPadding.top, DesktopLayoutTokens.editorTopPadding);
    expect(
      layout.documentPadding.bottom,
      DesktopLayoutTokens.editorBottomPaddingForHeight(800),
    );
  });

  testWidgets('desktop note chrome keeps note actions above the editor', (
    tester,
  ) async {
    final note = NoteModel(
      id: 'note-1',
      userId: 'user-1',
      title: 'Nota desktop',
      excerpt: 'Conteúdo',
      favorite: false,
      archived: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      hasRemoteCopy: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopNoteChrome(
            note: note,
            preferenceStatus: NotePreferenceMutationStatus.idle,
            editorFocusNode: null,
            onMenuSelected: (_) {},
            onExitFocus: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('desktop-note-chrome')), findsOneWidget);
    expect(find.text('Nota desktop'), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('desktop-note-chrome'))).height,
      DesktopLayoutTokens.chromeHeight,
    );
  });
}
