import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/note_icon_picker.dart';

void main() {
  testWidgets('selecting an emoji closes the picker sheet', (tester) async {
    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showNoteIconPicker(
                context: context,
                note: _note(),
                onSelected: (_) async {
                  selected = true;
                },
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Selecionar ícone'), findsOneWidget);

    await tester.tap(find.text('Usar emoji'));
    await tester.pumpAndSettle();

    expect(find.text('Escolher emoji'), findsOneWidget);
    expect(find.byType(NoteEmojiPickerPage), findsOneWidget);

    final inkWells = find
        .descendant(
          of: find.byType(NoteEmojiPickerPage),
          matching: find.byType(InkWell),
        );
    debugPrint('inkWellCount=${inkWells.evaluate().length}');
    for (final e in inkWells.evaluate().take(8)) {
      final box = (e.renderObject as RenderBox).localToGlobal(Offset.zero);
      debugPrint('  inkWell at ${e.renderObject} dy=${box.dy}');
    }
    final first = inkWells.first;
    debugPrint('firstInkWellRect=${tester.getRect(first)}');
    await tester.tapAt(const Offset(100, 340));
    await tester.pumpAndSettle();

    debugPrint('selected=$selected emojiPageStillPresent=${find.byType(NoteEmojiPickerPage).evaluate().length}');

    expect(selected, isTrue);
    expect(find.byType(NoteEmojiPickerPage), findsNothing);
    expect(find.text('Selecionar ícone'), findsNothing);
  });
}

NoteModel _note() {
  final now = DateTime.utc(2026, 6, 11);
  return NoteModel(
    id: 'note-1',
    userId: 'user-1',
    content: '',
    title: 'Nota',
    favorite: false,
    archived: false,
    createdAt: now,
    updatedAt: now,
    hasRemoteCopy: false,
    isEmptyDraft: true,
  );
}