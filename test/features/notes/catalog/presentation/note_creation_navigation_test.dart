import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/application/desktop_layout_preferences.dart';
import 'package:supanotes/features/notes/catalog/presentation/adaptive_notes_shell.dart';
import 'package:supanotes/features/notes/catalog/presentation/notes_list_screen.dart';
import 'package:supanotes/features/notes/catalog/presentation/widgets/resize_drag_handle.dart';
import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/notes/editor/application/note_editor_open_options.dart';
import 'package:supanotes/features/settings/presentation/controllers/preferences_controller.dart';
import 'package:supanotes/shared/theme/desktop_layout_tokens.dart';

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
            builder: (_, state) {
              final openOptions = state.extra;
              final requestsInitialFocus =
                  openOptions is NoteEditorOpenOptions &&
                  openOptions.requestInitialFocus;
              return Text('${state.uri}:$requestsInitialFocus');
            },
          ),
        ],
      ),
    ],
  );
}

Widget _app({
  required GoRouter router,
  required _RecordingNotesRepository repository,
  SharedPreferences? preferences,
}) {
  final overrides = [
    notesRepositoryProvider.overrideWithValue(repository),
    activeNotesProvider.overrideWith((ref) => Stream.value(const [])),
    isGridViewProvider.overrideWithValue(false),
  ];
  if (preferences != null) {
    overrides.add(sharedPreferencesProvider.overrideWithValue(preferences));
  }

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('mobile new-note action requests initial editor focus', (
    tester,
  ) async {
    final repository = _RecordingNotesRepository();
    final router = _routerFor(const NotesListScreen());

    await tester.pumpWidget(_app(router: router, repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(repository.createdNoteId, isNotNull);
    expect(
      find.text('/notes/${repository.createdNoteId}:true'),
      findsOneWidget,
    );
  });

  testWidgets('desktop sidebar new-note action requests initial editor focus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = _RecordingNotesRepository();
    final router = _routerFor(
      const AdaptiveNotesShell(child: SizedBox.shrink()),
    );

    await tester.pumpWidget(
      _app(router: router, repository: repository, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Nova nota'));
    await tester.pumpAndSettle();

    expect(repository.createdNoteId, isNotNull);
    expect(
      find.text('/notes/${repository.createdNoteId}:true'),
      findsOneWidget,
    );
  });

  testWidgets('desktop shell restores and persists a safe sidebar width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      desktopSidebarWidthPreferenceKey: 380.0,
    });
    final preferences = await SharedPreferences.getInstance();
    final repository = _RecordingNotesRepository();
    final router = _routerFor(
      const AdaptiveNotesShell(child: SizedBox.shrink()),
    );

    await tester.pumpWidget(
      _app(router: router, repository: repository, preferences: preferences),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-content-surface')),
      findsOneWidget,
    );

    final sidebar = find.byKey(const ValueKey('desktop-sidebar-container'));
    expect(tester.getSize(sidebar).width, 380);

    await tester.drag(find.byType(ResizeDragHandle), const Offset(100, 0));
    await tester.pumpAndSettle();

    expect(tester.getSize(sidebar).width, 420);
    expect(preferences.getDouble(desktopSidebarWidthPreferenceKey), 420);

    final restoredRouter = _routerFor(
      const AdaptiveNotesShell(child: SizedBox.shrink()),
    );
    await tester.pumpWidget(
      _app(
        router: restoredRouter,
        repository: repository,
        preferences: preferences,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(sidebar).width, 420);
  });

  testWidgets('desktop shell switches composition at the layout breakpoint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(899, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = _RecordingNotesRepository();
    final router = _routerFor(
      const AdaptiveNotesShell(child: SizedBox.shrink()),
    );

    await tester.pumpWidget(
      _app(router: router, repository: repository, preferences: preferences),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-sidebar-container')),
      findsNothing,
    );

    tester.view.physicalSize = const Size(900, 800);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-sidebar-container')),
      findsOneWidget,
    );
  });

  testWidgets('desktop shell collapses and restores the sidebar rail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = _RecordingNotesRepository();
    final router = _routerFor(
      const AdaptiveNotesShell(child: SizedBox.shrink()),
    );

    await tester.pumpWidget(
      _app(router: router, repository: repository, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Recolher sidebar'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('desktop-sidebar-rail')), findsOneWidget);
    expect(find.byType(ResizeDragHandle), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('desktop-sidebar-container')))
          .width,
      DesktopLayoutTokens.sidebarCollapsedWidth,
    );
    expect(preferences.getBool(desktopSidebarCollapsedPreferenceKey), isTrue);

    await tester.tap(find.byTooltip('Expandir sidebar'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('expanded-sidebar-surface')),
      findsOneWidget,
    );
    expect(find.byType(ResizeDragHandle), findsOneWidget);
    expect(preferences.getBool(desktopSidebarCollapsedPreferenceKey), isFalse);
  });

  testWidgets('desktop shell keeps the content surface open at wide width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = _RecordingNotesRepository();
    final router = _routerFor(
      const AdaptiveNotesShell(child: SizedBox.shrink()),
    );

    await tester.pumpWidget(
      _app(router: router, repository: repository, preferences: preferences),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(find.byKey(const ValueKey('desktop-content-surface')))
          .width,
      1440 -
          DesktopLayoutTokens.sidebarInitialWidth -
          DesktopLayoutTokens.resizeHitWidth,
    );
  });
}
