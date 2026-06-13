# Plan 003: Fixing Auth Test Providers

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat ff944a4..HEAD -- lib/features/auth/data/auth_local_storage.dart lib/core/di/providers.dart lib/features/auth/data/session_cache.dart test/features/auth/domain/auth_state_test.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `ff944a4`, 2026-06-13

## Why this matters

The class `SessionCacheNotifier` reads from a local, private `_authLocalStorageProvider` to access the device local storage. This local provider is not configurable or overridable by unit tests, which means that test overrides on `authLocalStorageProvider` do not apply. This causes a real secure storage client to spin up during tests and throw `Binding has not yet been initialized` errors, breaking 23+ unit tests in `auth_state_test.dart` and `app_router_test.dart`.

## Current state

- `lib/features/auth/data/auth_local_storage.dart` — class defining secure token storage operations
- `lib/core/di/providers.dart` — DI registry exposing public `authLocalStorageProvider`
- `lib/features/auth/data/session_cache.dart` — implements in-memory cache for session data

Excerpts:
In `lib/features/auth/data/session_cache.dart` line 16:
```dart
final _authLocalStorageProvider = Provider<AuthLocalStorage>((ref) {
  return AuthLocalStorage();
});
```

In `lib/core/di/providers.dart` line 27:
```dart
final authLocalStorageProvider = Provider<AuthLocalStorage>((ref) {
  return AuthLocalStorage();
});
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Analyze | `flutter analyze` | exit 0, no issues   |
| Tests   | `flutter test test/features/auth/domain/auth_state_test.dart` | all pass |
| Tests   | `flutter test test/core/router/app_router_test.dart` | all pass |

## Scope

**In scope**:
- `lib/features/auth/data/auth_local_storage.dart`
- `lib/core/di/providers.dart`
- `lib/features/auth/data/session_cache.dart`
- `test/features/auth/domain/auth_state_test.dart`

**Out of scope**:
- Modifications to `FlutterSecureStorage` configurations
- Changes to routing configuration

## Git workflow

- Branch: `chore/fix-auth-test-providers`
- Commit format: `chore(auth): restructure authLocalStorageProvider to fix unit tests`

## Steps

### Step 1: Declare provider in auth_local_storage.dart
Move the declaration of `authLocalStorageProvider` from `lib/core/di/providers.dart` to the end of `lib/features/auth/data/auth_local_storage.dart`.
At the end of `lib/features/auth/data/auth_local_storage.dart`, add:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authLocalStorageProvider = Provider<AuthLocalStorage>((ref) {
  return AuthLocalStorage();
});
```

**Verify**: `flutter analyze` runs successfully (though there might be duplicate definition errors temporarily).

### Step 2: Update core/di/providers.dart
Remove the duplicate `authLocalStorageProvider` definition from `lib/core/di/providers.dart` and export/import it from `auth_local_storage.dart` instead.
In `lib/core/di/providers.dart`:
```diff
-final authLocalStorageProvider = Provider<AuthLocalStorage>((ref) {
-  return AuthLocalStorage();
-});
```
(Make sure `package:supanotes/features/auth/data/auth_local_storage.dart` is imported).

**Verify**: `flutter analyze` runs.

### Step 3: Update session_cache.dart
In `lib/features/auth/data/session_cache.dart`, remove the private `_authLocalStorageProvider` and read the shared `authLocalStorageProvider` instead.
```diff
-final _authLocalStorageProvider = Provider<AuthLocalStorage>((ref) {
-  return AuthLocalStorage();
-});
```
And update `build()` method to read `authLocalStorageProvider`:
```diff
   @override
   SessionCache build() {
-    _storage = ref.read(_authLocalStorageProvider);
+    _storage = ref.read(authLocalStorageProvider);
     return const SessionCache();
   }
```

**Verify**: `flutter analyze` runs.

### Step 4: Ensure test bindings are initialized in auth_state_test.dart
In `test/features/auth/domain/auth_state_test.dart`, call `TestWidgetsFlutterBinding.ensureInitialized();` at the beginning of `main()`.
```diff
 void main() {
+  TestWidgetsFlutterBinding.ensureInitialized();
   group('AuthController.build', () {
```

**Verify**: Run `flutter test test/features/auth/domain/auth_state_test.dart` and `flutter test test/core/router/app_router_test.dart`. All tests must pass successfully.

## Test plan

- Run `flutter test test/features/auth/domain/auth_state_test.dart`. All 9 tests in `auth_state_test.dart` must pass successfully.
- Run `flutter test test/core/router/app_router_test.dart`. All tests in `app_router_test.dart` must pass successfully.

## Done criteria

- [ ] All tests in `test/features/auth/domain/auth_state_test.dart` pass
- [ ] All tests in `test/core/router/app_router_test.dart` pass
- [ ] `flutter analyze` returns no warnings/errors on modified files

## STOP conditions

- If `flutter test` throws errors unrelated to the platform channel bindings.
