# Plan 009: Remove core interceptor layering violation

> **Executor instructions**: Follow this plan step by step.
> **Drift check**: `git diff --stat HEAD -- lib/core/api/auth_interceptor.dart`

## Status
- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt

## Why this matters
`core/api/auth_interceptor.dart` imports `features/auth/data/auth_local_storage.dart`. The `core` layer should never depend on the `features` layer.

## Scope
**In scope**: `lib/core/api/auth_interceptor.dart`

## Steps

### Step 1: Inject token provider
Change `AuthInterceptor` to accept a `String? Function() getToken` callback in its constructor instead of importing `AuthLocalStorage` directly.
Update the Riverpod provider that constructs `AuthInterceptor` to pass `ref.read(authLocalStorageProvider).getToken()`.

## Done criteria
- [ ] No imports of `features/` in `core/`.
- [ ] `plans/README.md` updated.
