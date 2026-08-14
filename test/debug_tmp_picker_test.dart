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

    final emojiTarget = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.button == true,
          ),
        )
        .first;
    await tester.tap(emojiTarget);
    await tester.pumpAndSettle();

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
