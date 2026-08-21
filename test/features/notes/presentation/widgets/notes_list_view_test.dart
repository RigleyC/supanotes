import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/notes_list_view.dart';

void main() {
  group('NotesListView share indicator', () {
    testWidgets('does not show share indicator for owner notes', (
      tester,
    ) async {
      final note = NoteModel(
        id: '1',
        userId: 'user1',
        content: 'My Note',
        title: 'My Note',
        favorite: false,
        archived: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        hasRemoteCopy: true,
        isEmptyDraft: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotesListView(
              notes: [note],
              onTap: (_) {},
              onDelete: (_) {},
              onToggleFavorite: (_) {},
              onEditIcon: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.person_outline), findsNothing);
    });

    testWidgets('shows share indicator for shared notes', (tester) async {
      final note = NoteModel(
        id: '2',
        userId: 'user2',
        content: 'Shared Note',
        title: 'Shared Note',
        favorite: false,
        archived: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        hasRemoteCopy: true,
        isEmptyDraft: false,
        sharedByEmail: 'owner@example.com',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotesListView(
              notes: [note],
              onTap: (_) {},
              onDelete: (_) {},
              onToggleFavorite: (_) {},
              onEditIcon: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      expect(find.text('De: owner@example.com'), findsOneWidget);
    });
  });

  group('NotesListView favorite icon', () {
    testWidgets('shows favorite icon when favorited', (tester) async {
      final note = NoteModel(
        id: '3',
        userId: 'user1',
        content: 'Favorite Note',
        title: 'Favorite Note',
        favorite: true,
        archived: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        hasRemoteCopy: true,
        isEmptyDraft: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotesListView(
              notes: [note],
              onTap: (_) {},
              onDelete: (_) {},
              onToggleFavorite: (_) {},
              onEditIcon: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star_rate_rounded), findsOneWidget);
    });

    testWidgets('does not show favorite icon when not favorited', (
      tester,
    ) async {
      final note = NoteModel(
        id: '4',
        userId: 'user1',
        content: 'Non-favorite Note',
        title: 'Non-favorite Note',
        favorite: false,
        archived: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        hasRemoteCopy: true,
        isEmptyDraft: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotesListView(
              notes: [note],
              onTap: (_) {},
              onDelete: (_) {},
              onToggleFavorite: (_) {},
              onEditIcon: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star_rate_rounded), findsNothing);
    });
  });

  group('NotesListView interactions', () {
    testWidgets('calls onTap when note tile is tapped', (tester) async {
      NoteModel? tappedNote;
      final note = NoteModel(
        id: '5',
        userId: 'user1',
        content: 'Interactive Note',
        title: 'Interactive Note',
        favorite: false,
        archived: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        hasRemoteCopy: true,
        isEmptyDraft: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotesListView(
              notes: [note],
              onTap: (n) => tappedNote = n,
              onDelete: (_) {},
              onToggleFavorite: (_) {},
              onEditIcon: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Interactive Note'));
      expect(tappedNote?.id, '5');
    });

    testWidgets('calls onEditIcon when note tile is long pressed', (
      tester,
    ) async {
      NoteModel? editedNote;
      final note = NoteModel(
        id: '6',
        userId: 'user1',
        content: 'Icon Note',
        title: 'Icon Note',
        favorite: false,
        archived: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        hasRemoteCopy: true,
        isEmptyDraft: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotesListView(
              notes: [note],
              onTap: (_) {},
              onDelete: (_) {},
              onToggleFavorite: (_) {},
              onEditIcon: (n) => editedNote = n,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Icon Note'));
      expect(editedNote?.id, '6');
    });
  });
}
