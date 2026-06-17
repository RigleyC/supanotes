import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_card.dart';
import 'package:supanotes/shared/theme/app_theme.dart';

void main() {
  group('NoteCard dark theme', () {
    testWidgets('uses a visible card surface and menu icon color', (
      tester,
    ) async {
      final note = NoteModel(
        id: 'note-1',
        userId: 'user-1',
        title: 'Dark note',
        excerpt: 'Readable excerpt',
        content: '',
        isInbox: false,
        favorite: false,
        archived: false,
        contextId: null,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: Scaffold(
            body: NoteCard(
              note: note,
              onTap: () {},
              onDelete: () {},
              onToggleFavorite: () {},
            ),
          ),
        ),
      );

      final scheme = AppTheme.darkTheme.colorScheme;
      final cardContainer = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(NoteCard),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = cardContainer.decoration! as BoxDecoration;

      expect(decoration.color, isNot(scheme.surface));

      final menuIcon = tester.widget<Icon>(
        find.byIcon(Icons.more_vert_rounded),
      );
      expect(menuIcon.color, scheme.onSurfaceVariant);
    });
  });
}
