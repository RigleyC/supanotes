# Route Persistence & Stable Loading Shells

## What was done

### Route Restoration
- **`LastRouteStore`** (`lib/core/router/last_route_store.dart`): persists the last safe route to `SharedPreferences` and restores it as `GoRouter.initialLocation`. Validates that only non-auth, known routes are saved.
- **`lastRouteStoreProvider`**: Riverpod `Provider<LastRouteStore>` wrapping `sharedPreferencesProvider`.
- **`main.dart`**: initializes `SharedPreferences` before `runApp()`, overrides `sharedPreferencesProvider` in `ProviderScope`.
- **Auth guards**: `authGuardRedirect` loading branch now redirects to `/login` instead of returning `null` when not on an auth page.
- **Auth controller**: calls `lastRouteStoreProvider.clear()` on both `logout()` and `onSessionExpired()`.
- **Router listener**: added `routerDelegate.addListener` in `goRouterProvider` to persist route changes.

### Stable Loading Shells
- **`notes_list_screen.dart`**: extracted `_NotesLoadingView` — a `CustomScrollView` with header slivers + centered spinner, replacing the full-screen spinner during loading.
- **Editor**: the existing `controller.document == null` guard already ensures the editor is only built once; subsequent stream emissions keep the document intact.

## Test files

| Test | Coverage | Status |
|------|----------|--------|
| `test/core/router/last_route_store_test.dart` | 5 tests: init, save, auth-route filter, unknown-route filter, clear | ✅ |
| `test/core/router/app_router_test.dart` | 11 tests: initial location reset, persistence over restarts, route change listener, auth/register filter | ✅ |
| `test/core/router/auth_guard_test.dart` | 9 tests (updated loading branch expectation) | ✅ |
| `test/features/notes/presentation/notes_list_screen_test.dart` | 2 tests: FAB chat + loading shell visible | ✅ |
| `test/features/notes/presentation/note_editor_screen_test.dart` | 1 test: editor stays stable during stream refresh | ✅ |

## Key decisions
- No `valueOrNull` — Riverpod 3.x doesn't expose it; use `is AsyncData` pattern.
- Router listener guard: `authState is! AsyncData<User?>` because `valueOrNull` is not available.
- `LastRouteStore` is validated (only `/home`, `/inbox`, `/settings`, `/soul`, `/contexts`, `/routines`, `/routinesLogs`, `/telegram`, `/chat`, `/search`, `/memories`, `/notes/*`).
- Public auth routes (`/login`, `/register`) are never persisted.
- `_NotesLoadingView` keeps the full sliver header (Brain Dump, view mode toggle, SectionTitle) visible during loading.
- Editor init is guarded by `controller.document == null`; subsequent note stream values don't re-init the document.
