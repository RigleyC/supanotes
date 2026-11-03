import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/router/app_router.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/presentation/notes_list_screen.dart';
import 'package:supanotes/features/settings/presentation/controllers/preferences_controller.dart';
import 'package:supanotes/shared/widgets/app_navigation_shell.dart';

class _RecordingNotesRepository implements INotesRepository {
  String? createdNoteId;

  @override
  Future<NoteModel> createLocalNote({required String id}) async {
    createdNoteId = id;
    final now = DateTime(2026, 7, 31);
    return NoteModel(
      id: id,
      userId: 'test-user',
      content: '',
      title: '',
      favorite: false,
      archived: false,
      createdAt: now,
      updatedAt: now,
      hasRemoteCopy: false,
      isEmptyDraft: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GoRouter _routerFor(Widget screen) {
  return GoRouter(
    initialLocation: AppRoutes.notes,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) => AppNavigationShell(
          navigationShell: navigationShell,
          destinations: [appNavigationDestinations.last],
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: AppRoutes.notes, builder: (_, _) => screen),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.note(':id'),
        builder: (_, state) => Text(state.uri.toString()),
      ),
      GoRoute(
        path: AppRoutes.completedTasks,
        builder: (_, _) => const Text('completed-tasks'),
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
  testWidgets('shell new-note action creates an id and navigates', (
    tester,
  ) async {
    final repository = _RecordingNotesRepository();
    final router = _routerFor(const NotesListScreen());

    await tester.pumpWidget(_app(router: router, repository: repository));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('app-navigation-primary-action')),
    );
    await tester.pumpAndSettle();

    expect(repository.createdNoteId, isNotNull);
    expect(find.text('/notes/${repository.createdNoteId}'), findsOneWidget);
  });

  testWidgets('empty notes do not expose the completed action', (
    tester,
  ) async {
    final repository = _RecordingNotesRepository();
    final router = _routerFor(const NotesListScreen());

    await tester.pumpWidget(_app(router: router, repository: repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('notes-empty-state')), findsOneWidget);
    expect(find.text('Nenhuma nota ainda'), findsOneWidget);
    expect(find.byKey(const ValueKey('completed-notes-entry')), findsNothing);
  });
}
