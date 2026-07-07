import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_list_row.dart';

void main() {
  group('NoteListRow share indicator', () {
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
        contextId: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        sharedByEmail: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteListRow(
              note: note,
              onTap: () {},
              onDelete: () {},
              onToggleFavorite: () {},
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
        contextId: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        sharedByEmail: 'owner@example.com',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteListRow(
              note: note,
              onTap: () {},
              onDelete: () {},
              onToggleFavorite: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      expect(find.text('De: owner@example.com'), findsOneWidget);
    });
  });

  group('NoteListRow favorite icon', () {
    testWidgets('shows favorite icon when favorited', (tester) async {
      final note = NoteModel(
        id: '3',
        userId: 'user1',
        content: 'Favorite Note',
        title: 'Favorite Note',
        
        favorite: true,
        archived: false,
        contextId: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        sharedByEmail: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteListRow(
              note: note,
              onTap: () {},
              onDelete: () {},
              onToggleFavorite: () {},
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
        contextId: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        sharedByEmail: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteListRow(
              note: note,
              onTap: () {},
              onDelete: () {},
              onToggleFavorite: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star_rate_rounded), findsNothing);
    });
  });
}
