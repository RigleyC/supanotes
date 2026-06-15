# Plan 004: Add sync re-entrancy lock

> **Executor instructions**: Follow this plan step by step.
> **Drift check**: `git diff --stat HEAD -- lib/core/sync/sync_service.dart`

## Status
- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug

## Why this matters
`SyncService` has periodic timers and network event listeners that can trigger `sync()`. It lacks a lock, meaning multiple sync operations can run concurrently, causing duplicate network requests and potential data races.

## Current state
`lib/core/sync/sync_service.dart:99`

## Scope
**In scope**: `lib/core/sync/sync_service.dart`

## Steps

### Step 1: Add a boolean lock
Add `bool _isSyncing = false;` to `SyncService`.

### Step 2: Guard `sync()`
At the start of `sync()`:
```dart
if (_isSyncing) return;
_isSyncing = true;
try {
  ...
} finally {
  _isSyncing = false;
}
```

**Verify**: `flutter analyze` passes.

## Done criteria
- [ ] `sync()` cannot overlap.
- [ ] `plans/README.md` updated.
