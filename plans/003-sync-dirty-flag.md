# Plan 003: Prevent sync dirty flag data loss

> **Executor instructions**: Follow this plan step by step.
> **Drift check**: `git diff --stat HEAD -- lib/core/sync/sync_service.dart`

## Status
- **Priority**: P1
- **Effort**: M
- **Risk**: HIGH
- **Depends on**: none
- **Category**: bug

## Why this matters
The SyncService pushes dirty records and then unconditionally clears their `isDirty` flag. If the user edits a note *while* the HTTP request is in-flight, the new edit will have its dirty flag cleared and will never be synced to the backend.

## Current state
`lib/core/sync/sync_service.dart:158`
```dart
      for (final n in notes) {
        await _db.notesDao.markHasRemoteCopy(n.id);
        await _db.notesDao.clearDirtyFlag(n.id);
      }
```

## Scope
**In scope**: `lib/core/sync/sync_service.dart`, `lib/core/database/daos/*`

## Steps

### Step 1: Update DAO clearDirtyFlag to check updatedAt
Instead of clearing unconditionally, the DAO must accept the `updatedAt` of the record that was pushed, and only clear the flag if the current local `updatedAt` matches.

Modify `notesDao.clearDirtyFlag(String id, DateTime pushedUpdatedAt)` to execute:
`UPDATE local_notes SET is_dirty = 0 WHERE id = ? AND updated_at = ?`

### Step 2: Apply to all DAOs
Apply this `pushedUpdatedAt` logic to tasks, contexts, tags, completions, and links DAOs.

### Step 3: Update SyncService
In `sync_service.dart:158`, pass `n.updatedAt` to `clearDirtyFlag`.

**Verify**: `flutter analyze` passes.

## Done criteria
- [ ] DAOs verify `updatedAt` before clearing `isDirty`.
- [ ] `plans/README.md` updated.
