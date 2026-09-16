# Auth and Editor Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simplify the authenticated session and editor composition without touching the in-progress standalone task implementation.

**Architecture:** Keep the REST/OT editor and backend token rotation boundaries intact, but make the client session lifecycle explicit. The token manager owns the persisted credential pair, the repository owns authentication persistence, the controller owns session identity, and a separate action state reports login/register/logout progress. The editor screen will retain components with real behavior and collapse widgets that only forward values.

**Tech Stack:** Flutter, Dart 3.10, Riverpod 3.x manual providers, Dio, FlutterSecureStorage, SuperEditor, Flutter tests, Mocktail.

**Spec:** Approved architecture review in the conversation on 2026-09-15.

## Global Constraints

- Do not modify any file under `lib/features/tasks/`, task DAOs, or the standalone-task plan; those files contain an implementation in progress on `main`.
- Preserve all pre-existing tracked and untracked changes in the shared checkout.
- Do not add visual-behavior tests or run visual test suites as validation.
- Keep REST/OT document operations and task-block canonical snapshot rules unchanged.
- Use manual Riverpod providers; do not add code generation or `StateNotifier`.
- Do not commit while the shared `main` checkout contains unrelated work.

### Task 1: Make authentication ownership explicit

**Files:**
- Modify: `lib/features/auth/data/auth_repository.dart`
- Modify: `lib/features/auth/presentation/controllers/auth_controller.dart`
- Modify: `lib/core/di/providers.dart`
- Modify: `lib/features/auth/data/auth_local_storage.dart`
- Modify: `lib/features/auth/data/session_cache.dart`
- Modify: `lib/features/auth/presentation/login_screen.dart`
- Modify: `lib/features/auth/presentation/register_screen.dart`
- Test: `test/features/auth/data/auth_repository_test.dart`
- Test: `test/features/auth/domain/auth_state_test.dart`
- Test: `test/features/auth/presentation/login_screen_test.dart`
- Test: `test/features/auth/presentation/register_screen_test.dart`

**Interfaces:**
- `AuthRepository` becomes the concrete provider contract; `IAuthRepository` is removed because there is one implementation and all test doubles already target `AuthRepository`.
- `AuthRepository` requires `AuthTokenManager` and exposes only login, register, and logout.
- `authActionProvider` exposes `AsyncValue<void>` for authentication action progress while `authControllerProvider` remains the session identity state.

- [x] **Step 1: Remove unused repository surface and duplicate persistence.** Delete `IAuthRepository`, `isAuthenticated`, `registerDeviceToken`, the optional token-manager fallback, platform-only imports, and repository calls to `saveSessionData`. Extract shared login/register response handling into `_authenticate(path, data)`.
- [x] **Step 2: Add the separate authentication action state.** Keep login/register/logout session transitions in `AuthController`, but run the operation through `AuthActionController` so a failed login does not replace an existing valid session with `AsyncError`.
- [x] **Step 3: Remove redundant session-cache accessors and reverse documentation imports.** Delete `SessionCache.isEmpty` and `SessionCache.toJson`; rewrite doc comments in storage/cache so data-layer files do not import the controller.
- [x] **Step 4: Make login and register buttons derive loading through `AsyncValue.when`.** Do not use `.isLoading` in the screens.
- [x] **Step 5: Update only auth tests affected by the contract change.** Preserve behavioral coverage and add assertions for action-state errors and session-state stability.
- [x] **Step 6: Run the focused auth tests.** Run `flutter test --no-pub --concurrency=1 test/core/auth/auth_token_manager_test.dart test/core/api/auth_interceptor_test.dart test/features/auth/data/auth_repository_test.dart test/features/auth/domain/auth_state_test.dart`.

### Task 2: Make the credential pair consistent and startup-safe

**Files:**
- Modify: `lib/features/auth/data/auth_local_storage.dart`
- Modify: `lib/core/auth/auth_token_manager.dart`
- Modify: `lib/features/auth/presentation/controllers/auth_controller.dart`
- Test: `test/core/auth/auth_token_manager_test.dart`
- Test: `test/features/auth/domain/auth_state_test.dart`

**Interfaces:**
- `AuthLocalStorage.saveTokens` writes one JSON credential record and keeps legacy-key reads only as a migration fallback.
- `AuthTokenManager` caches both access and refresh tokens after installation or first read, and exposes `hasCompleteSession()` for bootstrap validation.

- [x] **Step 1: Add a single secure-storage record for new token pairs.** Write the pair as one JSON value, delete legacy keys after a successful write, and keep reads of the old keys for existing installations.
- [x] **Step 2: Cache the refresh token alongside the access token.** Update install, refresh, clear, and load paths so logout and refresh use the same in-memory pair ordering.
- [x] **Step 3: Validate both credentials during controller bootstrap.** Clear partial sessions and cached user data; accept a session only when both tokens are non-empty and a cached user exists.
- [x] **Step 4: Add non-visual tests for partial pairs, refresh-token caching, and legacy fallback.**
- [x] **Step 5: Run the focused auth tests again.**

### Task 3: Prevent redundant refresh rotations and stale replay failures

**Files:**
- Modify: `lib/core/api/auth_interceptor.dart`
- Modify: `lib/core/api/api_client.dart`
- Modify: `test/helpers/auth_interceptor_test_helper.dart`
- Test: `test/core/api/auth_interceptor_test.dart`

**Interfaces:**
- `AuthInterceptor` receives one no-argument `SessionRefreshHandler`; the API client composes the HTTP refresh request with the token manager callback.
- A 401 request is replayed with the current access token when it differs from the token used by the failed request; only then is a refresh attempted.

- [x] **Step 1: Remove the interceptor’s nested refresh pass-through and `_doRefresh`.** Keep HTTP refresh construction in `ApiClient` and session persistence in `AuthTokenManager`.
- [x] **Step 2: Capture the failed bearer token and compare it with the current token before refreshing.** Reuse a token already installed by another request.
- [x] **Step 3: Factor one replay helper so refreshed-token and already-refreshed paths share header/retry handling.**
- [x] **Step 4: Add a test where a late 401 arrives after another request installed a new token.** Assert that the refresh callback runs zero additional times and the request is replayed.
- [x] **Step 5: Run the focused interceptor tests.**

### Task 4: Collapse editor pass-through widgets

**Files:**
- Modify: `lib/features/notes/editor/presentation/note_editor_screen.dart`
- Modify: `lib/features/notes/editor/application/note_editor_controller.dart`
- Modify: `lib/features/notes/editor/application/note_editor_provider.dart`
- Modify: `lib/features/notes/editor/sync/note_sync_client.dart`
- Modify: `lib/features/notes/editor/sync/note_sync_session.dart`
- Modify: `lib/core/sync/note_operations_sync_service.dart`

**Interfaces:**
- `_NoteEditorAppBar`, `_NoteEditorWithSession`, and `_NoteEditorTaskDelegate` remain because they own visual behavior, provider access, or callbacks.
- `_NoteEditorBody`, `_NoteEditorDocument`, and `_NoteEditorSessionContent` are replaced by one screen-level content method or one single content component.

- [x] **Step 1: Replace the body wrapper chain with one composition boundary.** Preserve the current `AsyncValue.when` loading, error, not-found, and session-success behavior.
- [x] **Step 2: Keep task metadata callbacks and session ownership unchanged.** Do not alter task-domain files or editor operation capture. Remove only dead editor/sync forwarding (`userId`, `fetchDocument`, `storeDocument`, and the unused outbox-count wrapper).
- [x] **Step 3: Run the focused non-visual editor/domain tests and `dart format` on the edited file.**

### Task 5: Final safety verification

**Files:**
- Inspect only: all files changed by Tasks 1–4

- [x] **Step 1: Run `git diff --check`.**
- [x] **Step 2: Run focused auth and editor tests only; do not run visual behavior tests.**
- [x] **Step 3: Run `git status --short --untracked-files=all` and confirm task paths are outside this change.**
- [x] **Step 4: Report exact files changed, tests run, and any analyzer limitations.**
