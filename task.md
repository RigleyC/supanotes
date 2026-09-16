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

## Standalone tasks and Tasks/Notes tabs (2026-09-15) — Task 12 rollout verification

- [x] Run focused Flutter domain, data, application, sync and Tasks DAO tests:
  171 tests passed.
- [x] Run focused router and task presentation tests: 56 tests passed.
- [ ] Pass the full `flutter analyze` gate. Blocked by the unrelated
  `integration_test/full_suite_test.dart:231` reference to the removed
  `loadPendingProjection` method; the command also reports existing
  warnings/infos across the checkout.
- [x] Run `go test ./...`: all backend packages passed.
- [x] Run `go vet ./...`: passed with no findings.
- [x] Run `git diff --check`: passed with no whitespace errors; Git only
  reported normal LF/CRLF conversion warnings for existing dirty files.
- [ ] Exercise PostgreSQL migration, quarantine counts and restore rehearsal
  in an isolated database. Blocked because `make`, Docker and a disposable
  PostgreSQL DSN are unavailable; migration tests were run and skipped
  explicitly for the missing DSNs.
- [x] Record commands, evidence, limitations and rollback procedure in the
  standalone-task walkthrough.

## Editor and sync hardening (2026-09-02)

- [x] Skip hidden completed tasks at visible deletion boundaries while
  preserving canonical hidden nodes.
- [x] Stabilize asynchronous paste destinations and report paste failures.
- [x] Correct multi-heading toolbar state, task callback lifecycle, completion
  recovery, and list-marker text scaling.
- [x] Pin all Super Editor monorepo dependencies to one immutable commit.
- [x] Wake the global outbox when an editor closes and avoid redundant polling.
- [x] Move remote inbox/cursor state into Drift schema v31 with migration tests.
- [x] Run the complete Flutter suite (733 tests passed) and document the Go
  toolchain limitation in `HANDOFF.md`.
- [ ] Run Go verification and commit after thermo-nuclear review on a machine
  with the Go toolchain available.

## Code quality and reliability corrections (2026-09-16)

- [x] Correct backend runtime/configuration/Alexa security contracts.
- [x] Correct attachment upload errors and safe storage lifecycle.
- [x] Harden MCP, sharing intake, destructive confirmation and sensitive logs.
- [x] Simplify backend task/note/auth method and repository boundaries.
- [x] Simplify Flutter auth/session cleanup and token contracts.
- [x] Simplify editor/codec/controller boundaries and attachment upload flow.
- [x] Simplify task metadata, recurrence, preference and sharing controllers.
- [x] Simplify sync/catalog/DAO ownership, atomicity and diagnostics.
- [x] Align documentation and remove confirmed dead code.
- [x] Validate the aggregate diff with Sol low and focused checks.

## Navigation, task creation and auth follow-up (2026-09-16)

- [x] Keep `AdaptiveScaffold` as the host for the adaptive navbar, show the bar
  only on root tab destinations, restore iOS back affordances on
  nested/completed routes, and place FABs above the navigation bar.
- [x] Implement standalone task creation/editing with the shared modal/input,
  existing date/time/reminder options, and cancel/save actions.
- [x] Simplify notes empty state and focus-dismiss control; remove the
  task-to-note navigation trampoline without adding visual-only tests.
- [x] Validate the Dio access-token injection, single-flight refresh, one-time
  request replay, and failed-refresh session cleanup contract.
- [x] Run focused Flutter tests/analyzer, aggregate Go checks, and Sol low
  validation.

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
