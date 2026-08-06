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
                  onToggleCollapsed: () {},
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

    expect(find.text('SupaNotes'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Todas'), findsNothing);
    expect(find.text('Favoritas'), findsNothing);
    expect(find.text('Projeto desktop'), findsOneWidget);
    expect(find.text('Coluna centralizada'), findsNothing);
    expect(find.byTooltip('Coluna centralizada'), findsNothing);
    expect(find.byTooltip('Recolher sidebar'), findsOneWidget);
    expect(find.byTooltip('Nova nota'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('desktop-sidebar-note-list-gap')))
          .height,
      8,
    );
    expect(find.text('Configurações'), findsOneWidget);
    expect(find.text('user@example.com'), findsOneWidget);
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
    expect(
      tester.getSize(find.byKey(const ValueKey('note-a'))).height,
      DesktopLayoutTokens.sidebarRowHeight,
    );
    expect(find.byIcon(Icons.star_rate_rounded), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('note-a'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('note-b'))).dy),
    );
    expect(
      tester
          .getCenter(find.byKey(const ValueKey('desktop-sidebar-collapse')))
          .dx,
      lessThan(
        tester
            .getCenter(find.byKey(const ValueKey('desktop-sidebar-new-note')))
            .dx,
      ),
    );
  });

  testWidgets('search reduces the visible notes without a favorite filter', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Compras');
    await tester.pump();
    expect(find.byKey(const ValueKey('note-b')), findsOneWidget);
    expect(find.text('Projeto desktop'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.text('Projeto desktop'), findsOneWidget);
    expect(find.text('Compras'), findsOneWidget);
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
