import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/presentation/notes_list_screen.dart';
import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/settings/presentation/controllers/preferences_controller.dart';

class _RecordingNotesRepository implements INotesRepository {
  String? createdNoteId;

  @override
  Future<NoteModel> createLocalNote({required String id}) async {
    createdNoteId = id;
    final now = DateTime(2026, 7, 31);
    return NoteModel(
      id: id,
      userId: 'test-user',
      title: '',
      favorite: false,
      archived: false,
      createdAt: now,
      updatedAt: now,
      hasRemoteCopy: false,
    );
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GoRouter _routerFor(Widget screen) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      ShellRoute(
        builder: (_, _, child) => child,
        routes: [
          GoRoute(path: AppRoutes.home, builder: (_, _) => screen),
          GoRoute(
            path: AppRoutes.note(':id'),
            builder: (_, state) => Text(state.uri.toString()),
          ),
        ],
      ),
    ],
  );
}

Widget _app({
  required GoRouter router,
  required _RecordingNotesRepository repository,
}) {
  final overrides = [
    notesRepositoryProvider.overrideWithValue(repository),
    activeNotesProvider.overrideWith((ref) => Stream.value(const [])),
    isGridViewProvider.overrideWithValue(false),
  ];

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('mobile new-note action creates an id and navigates', (
    tester,
  ) async {
    final repository = _RecordingNotesRepository();
    final router = _routerFor(const NotesListScreen());

    await tester.pumpWidget(_app(router: router, repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(repository.createdNoteId, isNotNull);
    expect(find.text('/notes/${repository.createdNoteId}'), findsOneWidget);
  });
}
