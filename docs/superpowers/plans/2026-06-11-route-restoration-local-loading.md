# Route Restoration And Local Loading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the last safe in-app route after app restart and remove unnecessary full-screen loading states when local note data is being read from Drift.

**Architecture:** Persist only safe, authenticated app routes in a small router-owned store backed by `SharedPreferences`, initialized before `runApp` so `GoRouter.initialLocation` can be synchronous. Keep Drift as the source of truth for notes, but change note screens to render stable shells and only show blocking loaders where there is no usable local content yet.

**Tech Stack:** Flutter, Riverpod 3.x manual providers, `go_router`, `shared_preferences`, Drift streams, Flutter widget tests.

---

## File Structure

- Create `lib/core/router/last_route_store.dart`
  - Owns the persisted last route key, validation, read/write/clear methods, and Riverpod provider for router integration.
- Modify `lib/main.dart`
  - Initializes `SharedPreferences` before `runApp`.
  - Overrides `sharedPreferencesProvider` at the root `ProviderScope`.
- Modify `lib/core/router/app_router.dart`
  - Uses the persisted route as `initialLocation`.
  - Listens to route changes and persists safe authenticated routes.
- Modify `lib/core/router/auth_guard.dart`
  - Keeps auth decisions pure and adds helper checks for public/protected routes if needed.
- Modify `lib/features/auth/presentation/controllers/auth_controller.dart`
  - Clears persisted last route on logout/session expiry.
- Modify `lib/features/notes/presentation/notes_list_screen.dart`
  - Replaces the full-screen notes loading spinner with the stable notes shell plus a small loading body state.
- Modify `lib/features/notes/presentation/note_editor_screen.dart`
  - Keeps editor initialization blocking only until the note row is known, but avoids repeated full-screen spinners after controller initialization.
- Create `test/core/router/last_route_store_test.dart`
  - Unit tests route validation and persistence.
- Modify `test/core/router/app_router_test.dart`
  - Widget tests startup with a persisted route.
- Add or modify `test/features/notes/presentation/notes_list_screen_test.dart`
  - Widget test that loading local notes does not replace the whole screen with only a spinner.
- Add or modify `test/features/notes/presentation/note_editor_screen_test.dart`
  - Widget test that initialized editor content remains visible during a subsequent stream refresh/loading transition.

---

### Task 1: Add Last Route Store

**Files:**
- Create: `lib/core/router/last_route_store.dart`
- Test: `test/core/router/last_route_store_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/core/router/last_route_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/core/router/last_route_store.dart';

void main() {
  group('LastRouteStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns /home when there is no persisted route', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = LastRouteStore(prefs);

      expect(store.initialLocation(), AppRoutes.home);
    });

    test('persists and restores a safe note route', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = LastRouteStore(prefs);

      await store.save('/notes/note-1');

      expect(store.initialLocation(), '/notes/note-1');
    });

    test('does not persist public auth routes', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = LastRouteStore(prefs);

      await store.save(AppRoutes.login);
      await store.save(AppRoutes.register);

      expect(store.initialLocation(), AppRoutes.home);
    });

    test('does not persist unsupported routes', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = LastRouteStore(prefs);

      await store.save('/unknown');

      expect(store.initialLocation(), AppRoutes.home);
    });

    test('clear removes the persisted route', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = LastRouteStore(prefs);

      await store.save(AppRoutes.search);
      await store.clear();

      expect(store.initialLocation(), AppRoutes.home);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
rtk flutter test test/core/router/last_route_store_test.dart
```

Expected: FAIL because `last_route_store.dart` does not exist.

- [ ] **Step 3: Implement the route store**

Create `lib/core/router/last_route_store.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:supanotes/core/router/app_routes.dart';

class LastRouteStore {
  const LastRouteStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _key = 'last_route';

  String initialLocation() {
    final route = _prefs.getString(_key);
    if (route == null || !_isPersistable(route)) {
      return AppRoutes.home;
    }
    return route;
  }

  Future<void> save(String location) async {
    if (!_isPersistable(location)) return;
    await _prefs.setString(_key, location);
  }

  Future<void> clear() => _prefs.remove(_key);

  static bool _isPersistable(String location) {
    if (location == AppRoutes.login || location == AppRoutes.register) {
      return false;
    }
    if (location == AppRoutes.home ||
        location == AppRoutes.inbox ||
        location == AppRoutes.settings ||
        location == AppRoutes.soul ||
        location == AppRoutes.contexts ||
        location == AppRoutes.routines ||
        location == AppRoutes.routinesLogs ||
        location == AppRoutes.telegram ||
        location == AppRoutes.chat ||
        location == AppRoutes.search ||
        location == AppRoutes.memories) {
      return true;
    }
    return location.startsWith('/notes/') && location.length > '/notes/'.length;
  }
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final lastRouteStoreProvider = Provider<LastRouteStore>((ref) {
  return LastRouteStore(ref.watch(sharedPreferencesProvider));
});
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```powershell
rtk flutter test test/core/router/last_route_store_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
rtk git add lib/core/router/last_route_store.dart test/core/router/last_route_store_test.dart
rtk git commit -m "feat(router): persist last safe route"
```

---

### Task 2: Initialize SharedPreferences At App Startup

**Files:**
- Modify: `lib/main.dart`
- Test: `test/core/router/app_router_test.dart`

- [ ] **Step 1: Write the failing router startup test**

In `test/core/router/app_router_test.dart`, add imports:

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supanotes/core/router/last_route_store.dart';
```

Update `_makeContainer` so it accepts initial preferences:

```dart
Future<ProviderContainer> _makeContainer(
  AsyncValue<User?> stub, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPreferences = await SharedPreferences.getInstance();
  final storage = _MockAuthLocalStorage();
  final repository = _MockAuthRepository();
  _stubEmptySession(storage);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      authLocalStorageProvider.overrideWithValue(storage),
      authRepositoryProvider.overrideWithValue(repository),
      authControllerProvider.overrideWith(() => _StubAuthController(stub)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}
```

Update existing call sites from:

```dart
final container = _makeContainer(stub);
```

to:

```dart
final container = await _makeContainer(stub);
```

Then add this test:

```dart
testWidgets('authenticated startup opens the persisted note route', (tester) async {
  final stub = AsyncValue<User?>.data(
    const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
  );
  final container = await _makeContainer(
    stub,
    prefs: {'last_route': '/notes/note-1'},
  );

  await tester.pumpWidget(_wrapRouter(container));
  await settleRedirect(tester);

  final router = container.read(goRouterProvider);
  expect(
    router.routerDelegate.currentConfiguration.uri.toString(),
    '/notes/note-1',
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
rtk flutter test test/core/router/app_router_test.dart
```

Expected: FAIL because `goRouterProvider` still hardcodes `AppRoutes.login`.

- [ ] **Step 3: Initialize preferences in `main.dart`**

Modify `lib/main.dart` imports:

```dart
import 'package:shared_preferences/shared_preferences.dart';

import 'package:supanotes/core/router/last_route_store.dart';
```

Modify `main()`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  final sharedPreferences = await SharedPreferences.getInstance();

  timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());
  warnIfAndroidBackendUnreachable();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: const SupaNotesApp(),
    ),
  );
}
```

- [ ] **Step 4: Update router initial location**

Modify `lib/core/router/app_router.dart` imports:

```dart
import 'package:supanotes/core/router/last_route_store.dart';
```

Inside `goRouterProvider`, before `return GoRouter(`:

```dart
final lastRouteStore = ref.watch(lastRouteStoreProvider);
```

Change:

```dart
initialLocation: AppRoutes.login,
```

to:

```dart
initialLocation: lastRouteStore.initialLocation(),
```

- [ ] **Step 5: Run router tests**

Run:

```powershell
rtk flutter test test/core/router/app_router_test.dart test/core/router/last_route_store_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
rtk git add lib/main.dart lib/core/router/app_router.dart test/core/router/app_router_test.dart
rtk git commit -m "feat(router): restore last route on startup"
```

---

### Task 3: Persist Route Changes And Clear On Logout

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/features/auth/presentation/controllers/auth_controller.dart`
- Test: `test/core/router/app_router_test.dart`

- [ ] **Step 1: Write failing persistence tests**

Add to `test/core/router/app_router_test.dart`:

```dart
testWidgets('router persists protected route navigation', (tester) async {
  final stub = AsyncValue<User?>.data(
    const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
  );
  final container = await _makeContainer(stub);

  await tester.pumpWidget(_wrapRouter(container));
  await settleRedirect(tester);

  final router = container.read(goRouterProvider);
  router.go(AppRoutes.search);
  await settleRedirect(tester);

  final store = container.read(lastRouteStoreProvider);
  expect(store.initialLocation(), AppRoutes.search);
});

testWidgets('router does not persist login or register routes', (tester) async {
  final stub = AsyncValue<User?>.data(null);
  final container = await _makeContainer(stub);

  await tester.pumpWidget(_wrapRouter(container));
  await settleRedirect(tester);

  final router = container.read(goRouterProvider);
  router.go(AppRoutes.register);
  await settleRedirect(tester);

  final store = container.read(lastRouteStoreProvider);
  expect(store.initialLocation(), AppRoutes.home);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```powershell
rtk flutter test test/core/router/app_router_test.dart
```

Expected: FAIL because route changes are not persisted.

- [ ] **Step 3: Persist router location changes**

In `lib/core/router/app_router.dart`, replace the direct `return GoRouter(...)` with a local variable and listener:

```dart
final router = GoRouter(
  initialLocation: lastRouteStore.initialLocation(),
  debugLogDiagnostics: false,
  refreshListenable: notifier,
  routes: [
    // keep existing routes unchanged
  ],
  redirect: (context, state) => authGuardRedirect(
    currentLocation: state.matchedLocation,
    authState: notifier.value,
  ),
);

router.routerDelegate.addListener(() {
  final authState = notifier.value;
  if (!authState.hasValue || authState.valueOrNull == null) return;
  final location = router.routerDelegate.currentConfiguration.uri.toString();
  unawaited(lastRouteStore.save(location));
});

return router;
```

Add this import:

```dart
import 'dart:async';
```

- [ ] **Step 4: Clear route on logout and session expiry**

Modify `lib/features/auth/presentation/controllers/auth_controller.dart` import:

```dart
import 'package:supanotes/core/router/last_route_store.dart';
```

In `logout()`, after `_sessionCache.clear();`:

```dart
await ref.read(lastRouteStoreProvider).clear();
```

In `onSessionExpired()`, after `_sessionCache.clear();`:

```dart
await ref.read(lastRouteStoreProvider).clear();
```

- [ ] **Step 5: Run focused tests**

Run:

```powershell
rtk flutter test test/core/router/app_router_test.dart test/core/router/last_route_store_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
rtk git add lib/core/router/app_router.dart lib/features/auth/presentation/controllers/auth_controller.dart test/core/router/app_router_test.dart
rtk git commit -m "feat(router): remember route changes"
```

---

### Task 4: Replace Notes List Full-Screen Loading

**Files:**
- Modify: `lib/features/notes/presentation/notes_list_screen.dart`
- Test: `test/features/notes/presentation/notes_list_screen_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create or update `test/features/notes/presentation/notes_list_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:supanotes/features/notes/presentation/notes_list_screen.dart';

void main() {
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

    expect(find.text('Brain Dump'), findsOneWidget);
    expect(find.text('Notas'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
rtk flutter test test/features/notes/presentation/notes_list_screen_test.dart
```

Expected: FAIL because current loading branch returns only a centered spinner and hides the home shell.

- [ ] **Step 3: Extract a shell body builder**

In `lib/features/notes/presentation/notes_list_screen.dart`, replace `body: notesAsync.when(...)` with:

```dart
body: notesAsync.when(
  loading: () => _NotesLoadingView(headerSlivers: headerSlivers),
  error: (e, _) =>
      AppErrorView(title: _Strings.errorTitle, subtitle: e.toString()),
  data: (notes) {
    return Cue.onChange(
      value: _viewMode,
      motion: .smooth(),
      acts: [.fadeIn()],
      child: _viewMode == _NotesViewMode.grid
          ? NotesGridView(
              key: const ValueKey('grid'),
              notes: notes.toList(),
              headerSlivers: headerSlivers,
              onTap: _openNote,
              onDelete: _deleteNote,
              onToggleFavorite: _toggleFavorite,
            )
          : NotesListView(
              key: const ValueKey('list'),
              notes: notes.toList(),
              headerSlivers: headerSlivers,
              onTap: _openNote,
              onDelete: _deleteNote,
              onToggleFavorite: _toggleFavorite,
            ),
    );
  },
),
```

Add this private widget below `_OfflineStatusBottomSheet`:

```dart
class _NotesLoadingView extends StatelessWidget {
  const _NotesLoadingView({required this.headerSlivers});

  final List<Widget> headerSlivers;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        ...headerSlivers,
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the notes list test**

Run:

```powershell
rtk flutter test test/features/notes/presentation/notes_list_screen_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
rtk git add lib/features/notes/presentation/notes_list_screen.dart test/features/notes/presentation/notes_list_screen_test.dart
rtk git commit -m "fix(notes): keep home shell during local load"
```

---

### Task 5: Keep Editor Stable During Local Refresh

**Files:**
- Modify: `lib/features/notes/presentation/note_editor_screen.dart`
- Test: `test/features/notes/presentation/note_editor_screen_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create or update `test/features/notes/presentation/note_editor_screen_test.dart` with a stream-controller-backed repository override. The exact fake should implement only the members used by `NoteEditorScreen`.

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/note_editor_screen.dart';

class _FakeNotesRepository implements INotesRepository {
  _FakeNotesRepository(this.controller);

  final StreamController<NoteModel?> controller;

  @override
  Stream<NoteModel?> watchNoteById(String id) => controller.stream;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('initialized editor stays visible during stream refresh', (tester) async {
    final streamController = StreamController<NoteModel?>();
    addTearDown(streamController.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesRepositoryProvider.overrideWithValue(
            _FakeNotesRepository(streamController),
          ),
        ],
        child: const MaterialApp(
          home: NoteEditorScreen(noteId: 'note-1'),
        ),
      ),
    );

    streamController.add(
      NoteModel(
        id: 'note-1',
        contextId: null,
        title: 'Persisted note',
        content: '# Persisted note',
        favorite: false,
        archived: false,
        isInbox: false,
        isDirty: false,
        createdAt: DateTime(2026, 6, 11),
        updatedAt: DateTime(2026, 6, 11),
        deletedAt: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Persisted note'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    streamController.add(
      NoteModel(
        id: 'note-1',
        contextId: null,
        title: 'Persisted note',
        content: '# Persisted note',
        favorite: false,
        archived: false,
        isInbox: false,
        isDirty: true,
        createdAt: DateTime(2026, 6, 11),
        updatedAt: DateTime(2026, 6, 11),
        deletedAt: null,
      ),
    );
    await tester.pump();

    expect(find.text('Persisted note'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify current behavior**

Run:

```powershell
rtk flutter test test/features/notes/presentation/note_editor_screen_test.dart
```

Expected: If this already passes, keep the test as regression coverage. If it fails because dependencies such as task streams are missing, add a `tasksByNoteStreamProvider` override returning `Stream.value(const <TaskModel>[])`.

- [ ] **Step 3: Make loading conditional on missing controller state only**

In `lib/features/notes/presentation/note_editor_screen.dart`, keep the existing `if (controller.document == null)` gate, but ensure the loading branch is only reachable before the first local note row arrives:

```dart
if (controller.document == null) {
  if (asyncValue.isLoading && !asyncValue.hasValue) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
  if (asyncValue.hasError) {
    return Scaffold(
      body: Center(child: Text('Error: ${asyncValue.error}')),
    );
  }
  final note = asyncValue.asData?.value;
  if (note == null) {
    return const Scaffold(body: Center(child: Text('Nota nao encontrada')));
  }
  controller.init(content: note.content, title: note.title);
}
```

This is intentionally small: do not rebuild the `SuperEditor` document on every Drift emission, because that can overwrite in-progress editing state.

- [ ] **Step 4: Run focused tests**

Run:

```powershell
rtk flutter test test/features/notes/presentation/note_editor_screen_test.dart test/features/notes/presentation/controllers/note_editor_controller_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
rtk git add lib/features/notes/presentation/note_editor_screen.dart test/features/notes/presentation/note_editor_screen_test.dart
rtk git commit -m "fix(editor): avoid spinner after local note init"
```

---

### Task 6: Full Verification And Documentation

**Files:**
- Modify: `implementation_plan.md`
- Create: `walkthrough.md`

- [ ] **Step 1: Update `implementation_plan.md`**

Create or update `implementation_plan.md` with this summary:

```markdown
# Route Restoration And Local Loading

## Goal

Restore the last safe authenticated route on app startup and reduce visible full-screen loading when local Drift notes are being read.

## Decisions

- Persist only safe authenticated routes.
- Never persist `/login` or `/register`.
- Fall back to `/home` when the persisted route is missing, public, or unsupported.
- Keep Drift streams as the note source of truth.
- Do not rebuild the editor document from every stream emission.

## Verification

- `flutter test test/core/router/last_route_store_test.dart`
- `flutter test test/core/router/app_router_test.dart`
- `flutter test test/features/notes/presentation/notes_list_screen_test.dart`
- `flutter test test/features/notes/presentation/note_editor_screen_test.dart`
- `flutter analyze lib/core/router lib/features/notes/presentation`
```

- [ ] **Step 2: Create `walkthrough.md`**

Create `walkthrough.md`:

```markdown
# Route Restoration And Local Loading Walkthrough

## Manual Check

1. Log in.
2. Open an existing note.
3. Close the app or perform a hot restart.
4. Relaunch.
5. Confirm the app opens the same note route when the user is still authenticated.
6. Log out.
7. Relaunch.
8. Confirm the app starts at login and does not restore the protected note route.

## Loading Check

1. Start on the notes home screen.
2. Hot restart.
3. Confirm the home shell remains visible while local notes load.
4. Open a note.
5. Trigger a hot reload.
6. Confirm initialized editor content remains visible and is not replaced by a full-screen spinner.
```

- [ ] **Step 3: Run all focused verification**

Run:

```powershell
rtk flutter test test/core/router/last_route_store_test.dart test/core/router/app_router_test.dart test/features/notes/presentation/notes_list_screen_test.dart test/features/notes/presentation/note_editor_screen_test.dart test/features/notes/presentation/controllers/note_editor_controller_test.dart
rtk flutter analyze lib/core/router lib/features/notes/presentation lib/features/auth/presentation/controllers/auth_controller.dart lib/main.dart
```

Expected: PASS for tests and no new analyzer errors in touched files.

- [ ] **Step 4: Commit docs**

```powershell
rtk git add implementation_plan.md walkthrough.md
rtk git commit -m "docs: document route restoration walkthrough"
```

---

## Self-Review

**Spec coverage:** The plan covers restoring page state after close/reopen, avoiding persistence of public auth pages, clearing route state on logout/session expiry, and reducing full-screen loading during local note reads.

**Placeholder scan:** No task contains TBD/TODO/fill-later language. The only conditional instruction is in Task 5, where the test may need a task stream override depending on current widget dependencies; the exact override target is specified.

**Type consistency:** `LastRouteStore`, `sharedPreferencesProvider`, and `lastRouteStoreProvider` are introduced before later tasks reference them. Route strings use existing `AppRoutes` constants where available and the existing `/notes/:id` path shape for note routes.

**Known project caveat:** The current worktree has many unrelated dirty files. Before executing this plan, run the focused baseline tests and do not revert unrelated edits.
