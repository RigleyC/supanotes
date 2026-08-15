# Task — iOS task text selection

- [x] Confirm that task text captures the iOS selection long press.
- [x] Move the task action long press to the checkbox target.
- [x] Add regression coverage for task actions and task text selection.
- [x] Validate the focused editor tests and analyzer.
- [x] Run the full suite.
- [x] Review the final diff.
- [x] Commit the completed fix.
- [x] Implement note draft lifecycle: keep empty local drafts out of the
  catalog, focus from draft state, discard untouched aggregates, and mark
  accepted REST/OT drafts as remote.
- [x] Remove the obsolete router focus option and repository cleanup path.
- [x] Validate analyzer, focused tests, and diff checks.
- [x] Correct final-flush ordering so immediate editor close cannot discard a
  just-captured edit.
- [x] Move draft validation and aggregate deletion into one database transaction.
- [x] Remove optional lifecycle dependencies and make note state explicit.
- [x] Add coverage for immediate close and attachment-only drafts.
- [x] Repair the invalid canonical Delta snapshot that blocked Windows debug
  note hydration.
- [x] Harden document-native task occurrences: stable calendar identity,
  anchor-aware monthly recurrence, repeated early completion, overdue reminder
  targeting, and effective-document materialization.
- [x] Add the read-only production migration preflight and retention runbook.
- [x] Run Flutter analyze, the full Flutter suite, and the full Go suite.
- [x] Execute the production backup, export, isolated restore rehearsal,
  preflight, canonical backfill, retention gate, and backend health check with
  operator-owned artifacts. Physical cleanup remains a separate approval.
- [x] Replace the ineffective AppBar gradient with a real content shader mask.
- [x] Calculate the fade from the rendered viewport instead of screen height.
- [x] Apply the shared fade to the notes list and note editor.
- [x] Validate fade geometry and existing editor layout behavior.

## Per-note preference sync (plan 2026-08-14) — Task 2: collapse ownership → preference row

- [x] Failing DAO tests: collapse changes dirty the shared preference row; remote
  data is clean; remote data cannot replace a dirty local row; schema upgrade
  preserves the old local collapse value under its owner.
- [x] Removed `collapseImages` from the Drift `Notes` table; added it to
  `UserNotePreferences`; bumped schema to 30.
- [x] v29→v30 migration backfills owner preference rows from the legacy
  `notes.collapse_images` (dirty, so the preserved value is pushed), materializes
  collapsed notes, then drops the old column. Removed the collapse clause from the
  lifecycle materialization predicate. Migration test simulates the v29→30 delta
  on one open connection using the production `perUserCollapseBackfillSql`
  (Drift cannot reopen a closed `NativeDatabase`).
- [x] Pref DAO gains `setCollapseImages`, whole-row `setPreferences`, guarded
  `applyRemotePreference`, and timestamp-guarded `clearDirtyFlag(userId, noteId,
  pushedUpdatedAt)`.
- [x] `NotesDao` projects `collapse_images` from the preference join;
  `NoteModel.fromQueryResult` maps `qr.collapseImages`.
- [x] Collapse UI mutation now writes the owner's preference row via
  `UserNotePreferencesRepository`; `NotesRepository.updateNote` lost its
  `collapseImages` param; catalog hydration no longer writes the shared column.
- [x] `flutter analyze --no-pub` clean; DAO tests green; `git diff --check` clean.
- [x] Committed `refactor(notes): store collapse images per user`.

**Deferred to Task 3/4 (compile-coupled, per plan):** note_catalog_sync push/apply
wiring (`pushDirtyPreferences`, `applyRemotePreference` in hydration), extending
`RemoteNoteMetadata` to all four flags, controller/sync test fixtures, and final
dead-code audit.
