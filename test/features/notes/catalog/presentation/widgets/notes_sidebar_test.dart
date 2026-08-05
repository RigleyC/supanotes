import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/notes_sidebar.dart';

void main() {
  final notes = [
    NoteModel(
      id: 'note-a',
      userId: 'user-1',
      title: 'Projeto desktop',
      excerpt: 'Coluna centralizada',
      favorite: true,
      archived: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
    NoteModel(
      id: 'note-b',
      userId: 'user-1',
      title: 'Compras',
      excerpt: 'Lista da semana',
      favorite: false,
      archived: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ];

  Widget app({String? selectedNoteId}) {
    return ProviderScope(
      overrides: [
        activeNotesProvider.overrideWith((ref) => Stream.value(notes)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: NotesSidebar(
              selectedNoteId: selectedNoteId,
              onNoteTap: (_) {},
              onNewNote: () {},
              onOpenSettings: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders compact navigation sections and selected note', (
    tester,
  ) async {
    await tester.pumpWidget(app(selectedNoteId: 'note-a'));
    await tester.pumpAndSettle();

    expect(find.text('SupaNotes'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Todas'), findsOneWidget);
    expect(find.text('Favoritas'), findsOneWidget);
    expect(find.text('Projeto desktop'), findsOneWidget);
    expect(find.text('Coluna centralizada'), findsOneWidget);
    expect(find.text('Configurações'), findsOneWidget);
    expect(find.byKey(const ValueKey('note-a')), findsOneWidget);
  });

  testWidgets('search and favorite filter reduce the visible notes', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Compras');
    await tester.pump();
    expect(find.byKey(const ValueKey('note-b')), findsOneWidget);
    expect(find.text('Projeto desktop'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Favoritas'));
    await tester.pump();
    expect(find.text('Projeto desktop'), findsOneWidget);
    expect(find.text('Compras'), findsNothing);
  });
}
