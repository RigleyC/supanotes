import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/auth/presentation/controllers/auth_controller.dart';
import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/notes_sidebar.dart';
import 'package:supanotes/shared/theme/desktop_layout_tokens.dart';

class _StubAuthController extends AuthController {
  @override
  Future<User?> build() async =>
      const User(id: 'user-1', email: 'user@example.com', name: 'User');
}

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

  Widget app({String? selectedNoteId, TextScaler? textScaler}) {
    return ProviderScope(
      overrides: [
        activeNotesProvider.overrideWith((ref) => Stream.value(notes)),
        authControllerProvider.overrideWith(_StubAuthController.new),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: textScaler ?? TextScaler.noScaling),
              child: SizedBox(
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
    expect(find.text('user@example.com'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('desktop-sidebar-filter-all')))
          .height,
      44,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('desktop-sidebar-filter-favorites')),
          )
          .height,
      44,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('desktop-sidebar-settings-action')),
          )
          .height,
      greaterThanOrEqualTo(44),
    );
    expect(find.byKey(const ValueKey('note-a')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('note-a'))),
      tester.getSize(find.byKey(const ValueKey('note-b'))),
    );
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

  testWidgets('note rows expand when desktop text is scaled up', (
    tester,
  ) async {
    await tester.pumpWidget(app(textScaler: TextScaler.linear(2)));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('note-a'))).height,
      greaterThan(DesktopLayoutTokens.sidebarRowHeight),
    );
  });
}
