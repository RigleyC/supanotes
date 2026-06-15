# Plan 007: Batch sync pull operations

> **Executor instructions**: Follow this plan step by step.
> **Drift check**: `git diff --stat HEAD -- lib/core/sync/sync_service.dart`

## Status
- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: perf

## Why this matters
The local database sync logic uses sequential `await _db.notesDao.upsertFromRemote(...)` loops. This incurs Dart microtask overhead for every item. Drift supports `_db.batch()` which is orders of magnitude faster.

## Scope
**In scope**: `lib/core/sync/sync_service.dart`

## Steps

### Step 1: Wrap pull insertions in _db.batch
Find the `for` loops in `pull()` and replace them with:
```dart
await _db.batch((batch) {
  for (final raw in data['notes']) {
    // Note: daos must expose a method that takes a batch, or use batch.insertAll
  }
});
```

## Done criteria
- [ ] Sequential awaits removed from sync pull.
- [ ] `plans/README.md` updated.
