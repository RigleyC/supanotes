import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/model/note_strings.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/notes_list_view.dart';

void main() {
  group('NotesListView shared notes', () {
    testWidgets('labels owner notes with their title only', (
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
      expect(find.bySemanticsLabel('My Note'), findsOneWidget);
    });

    testWidgets('announces shared notes without drawing the sharer', (
      tester,
    ) async {
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

      // Only the title is drawn; the sharer stays available to assistive
      // technologies through the row's semantics label.
      expect(find.text('Shared Note'), findsOneWidget);
      expect(find.text('De: owner@example.com'), findsNothing);
      expect(
        find.bySemanticsLabel(
          'Shared Note. Compartilhada por owner@example.com',
        ),
        findsOneWidget,
      );
    });
  });

  group('NotesListView title-only rows', () {
    testWidgets('does not decorate favorite notes', (tester) async {
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

      expect(find.text('Favorite Note'), findsOneWidget);
      expect(find.byIcon(Icons.star_rate_rounded), findsNothing);
    });

    testWidgets('shows only the title, without excerpt', (
      tester,
    ) async {
      final note = NoteModel(
        id: '4',
        userId: 'user1',
        content: 'Non-favorite Note\nBody text',
        title: 'Non-favorite Note',
        excerpt: 'Body text',
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

      expect(find.text('Non-favorite Note'), findsOneWidget);
      expect(find.text('Body text'), findsNothing);
      final row = tester.getSize(find.byType(NoteTitleRow));
      expect(row.height, greaterThanOrEqualTo(52));
    });

    testWidgets('shows the placeholder for untitled notes', (tester) async {
      final note = NoteModel(
        id: '7',
        userId: 'user1',
        content: '',
        title: '',
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

      expect(find.text(NoteStrings.fallbackTitle), findsOneWidget);
    });

    testWidgets('keeps the first note nearest the bottom', (tester) async {
      NoteModel noteWith(String id) => NoteModel(
        id: id,
        userId: 'user1',
        content: id,
        title: id,
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
              notes: [noteWith('newest'), noteWith('older')],
              onTap: (_) {},
              onDelete: (_) {},
              onToggleFavorite: (_) {},
              onEditIcon: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('newest')).dy,
        greaterThan(tester.getTopLeft(find.text('older')).dy),
      );
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
