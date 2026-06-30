import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/domain/note_with_tasks.dart';
import 'package:supanotes/features/notes/domain/task_entry.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:supanotes/features/notes/presentation/notes_list_screen.dart';
import 'package:supanotes/features/search/domain/search_result_model.dart';
import 'package:supanotes/features/search/presentation/controllers/search_controller.dart';
import 'package:supanotes/shared/theme/app_theme.dart';

class _FakeNotesRepository implements INotesRepository {
  final List<NoteModel> createdNotes = [];

  @override
  Stream<List<NoteModel>> watchNotes({
    String? contextId,
    bool favoritesOnly = false,
  }) {
    return Stream<List<NoteModel>>.value(const []);
  }

  @override
  Stream<NoteModel?> watchInbox() => Stream<NoteModel?>.value(null);

  @override
  Stream<NoteModel?> watchNoteById(String id) => Stream<NoteModel?>.value(null);

  @override
  Future<NoteModel?> getNoteById(String id) async => null;

  @override
  Future<NoteModel> upsertNote({
    required String id,
    String content = '',
    String? contextId,
  }) async {
    final note = _note(id: id, content: content);
    createdNotes.add(note);
    return note;
  }

  @override
  Future<void> updateNote(
    String id, {
    String? content,
    bool? favorite,
    bool? archived,
    bool? hideCompleted,
    bool? collapseImages,
    String? contextId,
  }) async {}

  @override
  Future<void> saveNoteSnapshot({
    required String id,
    required String content,
    required List<TaskEntry> tasks,
  }) async {
    await updateNote(id, content: content);
  }

  @override
  Future<void> toggleFavorite(String id) async {}

  @override
  Future<void> softDelete(String id) async {}

  @override
  Future<NoteModel> ensureInbox() async => _note(id: 'inbox', isInbox: true);

  @override
  Future<void> appendToInbox(String text) async {}

  @override
  Future<void> syncTasksFromDocument(
    String noteId,
    List<TaskEntry> tasks,
  ) async {}

  @override
  Future<NoteModel> createLocalNote({required String id}) async {
    final note = _note(id: id);
    createdNotes.add(note);
    return note;
  }

  @override
  Future<void> deleteIfEmptyOrTombstone(String id) async {}

  @override
  Future<void> markHasRemoteCopy(String id) async {}

  @override
  Stream<NoteWithTasks> watchNoteWithTasks(String noteId) =>
      Stream.value(const NoteWithTasks(note: null, tasks: []));

  NoteModel _note({
    required String id,
    String content = '',
    bool isInbox = false,
  }) {
    final now = DateTime.utc(2026, 6, 12);
    return NoteModel(
      id: id,
      userId: 'user-1',
      content: content,
      isInbox: isInbox,
      favorite: false,
      archived: false,
      contextId: null,
      createdAt: now,
      updatedAt: now,
    );
  }
}

void main() {
  testWidgets('assistant FAB opens chat from notes home', (tester) async {
    final notesRepository = _FakeNotesRepository();
    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (_, _) => const NotesListScreen(),
        ),
        GoRoute(
          path: AppRoutes.chat,
          builder: (_, _) => const Scaffold(body: Text('Assistant chat')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [notesRepositoryProvider.overrideWithValue(notesRepository)],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Conversar com o assistente'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-chat-fab')));
    await tester.pumpAndSettle();

    expect(find.text('Assistant chat'), findsOneWidget);
  });

  testWidgets('loading notes keeps the home shell visible', (tester) async {
    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (_, _) => const NotesListScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeNotesProvider.overrideWith((ref) => const Stream<List<NoteModel>>.empty()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    expect(find.text('Brain Dump'), findsOneWidget);
    expect(find.text('NOTAS'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('search action opens inline search field on notes home', (tester) async {
    final notesRepository = _FakeNotesRepository();
    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (_, _) => const NotesListScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [notesRepositoryProvider.overrideWithValue(notesRepository)],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Buscar notas'));
    await tester.pump();

    expect(find.byKey(const ValueKey('notes-inline-search-field')), findsOneWidget);
    expect(find.byTooltip('Fechar busca'), findsOneWidget);
  });

  testWidgets('inline search renders hybrid backend results', (tester) async {
    final notesRepository = _FakeNotesRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesRepositoryProvider.overrideWithValue(notesRepository),
          searchResultsProvider.overrideWith((ref, query) async {
            expect(query, 'comida');
            return const [
              SearchResultModel(
                id: 'note-shopping',
                title: 'Lista de compras',
                excerpt: 'Comprar arroz, feijao e legumes',
                score: 0.91,
              ),
            ];
          }),
        ],
        child: MaterialApp(
          home: const NotesListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Buscar notas'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'comida');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Lista de compras'), findsOneWidget);
  });
}
