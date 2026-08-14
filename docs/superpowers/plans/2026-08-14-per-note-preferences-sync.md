# Per-Note Preference Synchronization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement task-by-task.

**Goal:** Synchronize favorite, archived, hide-completed, and image-collapse settings for one user across devices, including offline writes.

**Architecture:** `user_note_preferences` owns all four values. Its local Drift row is a durable outbox (`is_dirty`); `NoteCatalogSync` pushes it before pulling the catalog. Preferences stay outside REST/OT and the canonical document. `collapse_images` is removed from shared `notes` metadata.

**Tech Stack:** Flutter, Riverpod, Drift, Dio, Go, Echo, PostgreSQL, sqlc.

## Global Constraints

- A preference is keyed by `(user_id, note_id)` and read-only shared users may change only their own row.
- Keep `is_dirty`: it prevents offline changes from being lost.
- Remove, rather than support, every shared `collapse_images` path.
- Keep unrelated worktree changes untouched and run commands through `rtk`.

---

### Task 1: Backend preference API and schema

**Files:**
- Create: `backend/db/migrations/000051_per_user_collapse_images.up.sql`, `backend/db/migrations/000051_per_user_collapse_images.down.sql`
- Modify: `backend/db/queries/notes.sql`, `backend/internal/notes/{repository,service,handler}.go`, `backend/cmd/server/main.go`
- Regenerate: `backend/internal/db/sqlcgen/*.go`
- Test: `backend/internal/notes/{handler,service}_test.go`

- [ ] Add failing handler/service tests: owner and shared read-only user can PATCH all four fields; inaccessible user is rejected; response returns all fields; note update is not invoked.
- [ ] Run `rtk go test ./internal/notes -run 'Preference|Preferences' -count=1` and confirm failure.
- [ ] In migration 51 add `user_note_preferences.collapse_images`, copy `notes.collapse_images` into the owner's row using an upsert, then drop `notes.collapse_images`; reverse these steps in down migration.
- [ ] In `notes.sql`, remove `collapse_images` from Create/Update note queries and all note selects; select all four flags from the caller's preference row in list/get; add one authorized complete-row `UpsertUserNotePreference` query with server `updated_at = NOW()`.
- [ ] Add `PATCH /notes/:id/preferences`, request/response DTOs, repository/service plumbing, and the same owner-or-share access predicate as catalog reads. The authenticated identity is the only user ID accepted.
- [ ] Run `rtk sqlc generate`; update every repository mock; run `rtk go test ./internal/notes -count=1`.
- [ ] Commit: `feat(notes): add per-user preference endpoint`.

### Task 2: Move Drift collapse ownership to the preference row

**Files:**
- Modify: `lib/core/database/{database.dart,tables/notes.dart,tables/user_note_preferences.dart,daos/notes_dao.dart,daos/user_note_preferences_dao.dart}`
- Regenerate: `lib/core/database/database.g.dart`, `lib/core/database/daos/user_note_preferences_dao.g.dart`
- Test: `test/core/database/daos/{notes_dao_test.dart,user_note_preferences_dao_test.dart}`

- [ ] Write failing tests: collapse changes make the preference row dirty; remote data is clean; remote data cannot replace a dirty local row; schema upgrade preserves the old local collapse value under its owner's preference.
- [ ] Run the focused DAO tests and confirm the missing preference field/API failure.
- [ ] Remove `collapseImages` from `Notes`; add it to `UserNotePreferences`; bump Drift schema version; migrate old local note values into owner preference rows before dropping the old SQLite column.
- [ ] Add complete-row local mutation, guarded remote apply, dirty-row query, and `clearDirtyFlag(userId, noteId, pushedUpdatedAt)`. The timestamp guard must retain an edit made while a request was in flight.
- [ ] Project `collapse_images` from the preference join in `NotesDao`; remove it from `NoteData`, `NotesCompanion`, lifecycle metadata checks, and `NoteModel.fromQueryResult` note-field mapping.
- [ ] Run `rtk dart run build_runner build --delete-conflicting-outputs`, then focused DAO tests. Commit: `refactor(notes): store collapse images per user`.

### Task 3: Wire the offline outbox and catalog pull

**Files:**
- Modify: `lib/features/notes/editor/sync/note_sync_client.dart`, `lib/features/notes/catalog/{model/remote_note_metadata.dart,data/note_catalog_sync.dart,data/notes_repository.dart}`, `lib/features/notes/preferences/{data/user_note_preferences_repository.dart,application/note_preferences_mutation_controller.dart}`
- Test: `test/features/notes/catalog/data/{note_catalog_sync_test.dart,note_catalog_sync_provider_test.dart}`, `test/features/notes/data/notes_repository_test.dart`, `test/features/notes/presentation/controllers/note_preferences_mutation_controller_test.dart`, `test/features/notes/sharing/share_link_access_resolver_test.dart`

- [ ] Add failing tests: dirty row sends all four fields and clears only matching timestamp; failed request stays dirty; a clean second device applies remote values; remote data cannot overwrite dirty data; preference changes do not alter document revision/content/note timestamp.
- [ ] Run focused catalog-sync tests and confirm failure.
- [ ] Add typed `updatePreferences(noteId, preference)` to `NoteSyncClient` using the new PATCH route.
- [ ] Extend `RemoteNoteMetadata` with all four flags and remove its shared collapse field. Update all share-link fixtures and metadata constructors.
- [ ] Add `pushDirtyPreferences` to `NoteCatalogSync`, running each row via its keyed note queue. Execute it after deleted notes and before `pullRemoteNotes`. Apply catalog preferences through the guarded DAO both when hydrating and when a note is active.
- [ ] Make favorite, archived, hide-completed, and collapse-image UI mutations write the same local preference row. Remove `NotesRepository.updateNote(... collapseImages:)` and the controller's shared-note collapse mutation.
- [ ] Run all named focused Flutter tests. Commit: `feat(sync): synchronize per-note preferences offline`.

### Task 4: Remove dead shared-collapse code and validate presentation

**Files:**
- Modify: `lib/features/notes/editor/presentation/{note_editor_screen.dart,widgets/note_editor.dart}` and remaining image/creation call sites
- Modify: `docs/architecture/notes-file-reference.md`, `implementation_plan.md`, `task.md`, `walkthrough.md`
- Test: `test/features/notes/presentation/{note_editor_screen_test.dart,note_creation_navigation_test.dart}` and every fixture found by the audit

- [ ] Write a widget test showing two models of the same note can render opposite image-collapse settings because the setting is now user-owned.
- [ ] Run the focused widget tests and confirm failure.
- [ ] Remove `collapse_images` from note create/update DTOs, `NotesCompanion` writes, `NoteCatalogSync` note companions, note API request payloads, and all obsolete test helpers. Keep `NoteEditor` rendering input, sourced only from `NoteModel` preference projection.
- [ ] Audit with:

  ```text
  rtk rg -n "collapseImages|collapse_images" lib backend test
  rtk rg -n "getDirtyPreferences|clearDirtyFlag|setCollapseImages" lib backend test
  rtk rg -n "UpdateNoteRequest|CreateNoteRequest|RemoteNoteMetadata" lib backend test
  ```

  Delete every stale shared-note path and fixture. Valid remaining hits are only the preference implementation, JSON API, migrations, and tests. `isDirty`, dirty lookup, and timestamp-guarded clearing remain because they are live offline behavior.
- [ ] Update living docs and `task.md`; append exact validation results to `walkthrough.md`.
- [ ] Run `rtk go test ./...`, `rtk flutter analyze --no-pub`, `rtk flutter test`, and `rtk git diff --check`. If SQLite DLL is locked, close the desktop app and rerun; do not replace Flutter widget tests with `dart test`.
- [ ] Commit: `docs(notes): document preference synchronization`.

## Self-Review

Tasks 1-4 cover backend authorization and migration, local migration, offline delivery/retry, remote application, UI ownership, complete dead-code removal, and tests. The plan has no compatibility layer or second sync mechanism.
