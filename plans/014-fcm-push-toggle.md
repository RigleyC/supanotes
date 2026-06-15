# Plan 014: Wire up FCM Push Notification toggle

> **Executor instructions**: Follow this plan step by step.
> **Drift check**: `git diff --stat HEAD -- lib/features/settings/presentation/settings_screen.dart`

## Status
- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: direction

## Why this matters
The UI toggle for push notifications does not actually call the backend to register or unregister the FCM token, making the feature useless.

## Scope
**In scope**: 
- `lib/features/settings/presentation/settings_screen.dart`
- `lib/core/notifications/push_service.dart` (new)

## Steps

### Step 1: Create PushService
Create a `PushService` that integrates `firebase_messaging`. It should have `enable()` (fetches FCM token and POSTs to `/api/v1/device-tokens`) and `disable()` (DELETEs token).

### Step 2: Wire UI
In `settings_screen.dart`, when the toggle is flipped, call `ref.read(pushServiceProvider.notifier).toggle(newValue)`.

**Verify**: `flutter analyze` passes.

## Done criteria
- [ ] Push toggle connects to backend.
- [ ] `plans/README.md` updated.
