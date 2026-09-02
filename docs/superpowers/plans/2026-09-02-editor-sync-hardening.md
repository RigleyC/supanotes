# Editor and Sync Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct every confirmed editor and synchronization defect from the audit, then leave the branch with green verification and no actionable thermo-nuclear maintainability findings.

**Architecture:** Keep document mutations inside the existing editor policy/command layer and keep REST/OT state in `NoteOperationsSyncService`. The app-scoped workers own durable outbox/inbox orchestration; the open editor owns only visible-document reconciliation. Replace incidental conditionals with small typed policies and keep database-owned state in Drift migrations.

**Tech Stack:** Flutter/Dart, Super Editor, Riverpod 3, Drift/SQLite, Go, PostgreSQL, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-01-sync-coordinator-outbox-design.md` plus the editor audit recorded in the referenced conversation.

## Global Constraints

- Preserve the canonical REST/OT document snapshot as the source of truth for note content and task metadata.
- Persist local edits before network work; closing an editor must not wait for remote acknowledgement.
- Do not allow hidden completed tasks to mutate or become selection barriers in the visible editor flow.
- Keep network coalescing at 350 ms and local adapter durability at its existing 50 ms boundary.
- Do not introduce `StateNotifier`, Riverpod code generation, or direct relational task writes.
- Every production behavior change gets a regression test that fails before the implementation change.
- Pin Super Editor dependencies to one immutable commit shared by all monorepo packages.

---

### Task 1: Make hidden-node editing policy explicit and complete

**Files:**
- Modify: `lib/features/notes/editor/document/hidden_task_editing_guard.dart`
- Modify: `lib/features/notes/editor/application/note_editor_controller.dart`
- Modify: `lib/features/notes/editor/presentation/widgets/note_editor.dart`
- Test: `test/features/notes/presentation/controllers/note_editor_controller_test.dart`

**Interfaces:**
- Preserve `HiddenTaskEditingGuard.handle(Editor, EditRequest)`.
- Add focused helpers for visible-neighbor selection and selection sanitization rather than adding more request-specific branches.

- [x] Write tests for upstream/downstream deletion, range deletion, selection changes, and insertion around one or more hidden tasks.
- [x] Run the focused controller test and confirm the new tests fail under the current no-op barrier behavior.
- [x] Refactor the guard so hidden nodes are skipped for navigation/deletion boundaries while direct mutation of a hidden node remains rejected.
- [x] Remove the duplicated `hideCompleted` comparison and centralize predicate updates plus selection cleanup.
- [x] Run the focused controller/editor tests and analyzer.

Evidence: controller/editor regression tests pass; range edits and direct hidden-node
mutations remain rejected, while caret deletion at a visible boundary skips hidden
tasks without deleting their canonical blocks.

### Task 2: Stabilize paste destination and errors

**Files:**
- Modify: `lib/features/notes/editor/presentation/widgets/rich_keyboard_actions.dart`
- Modify: `lib/features/notes/editor/presentation/widgets/rich_common_editor_operations.dart`
- Modify: `lib/features/notes/editor/presentation/widgets/clipboard_preprocessor.dart`
- Test: `test/features/notes/presentation/widgets/rich_clipboard_test.dart`

**Interfaces:**
- Preserve public `pasteWithPreprocessing(Editor, {SystemClipboard? testClipboard})`.
- Introduce an immutable destination selection/position passed through the asynchronous clipboard readers.

- [x] Add a regression test that changes the composer selection while clipboard reading is suspended and asserts insertion uses the original destination.
- [x] Run the test and confirm it fails because the current helpers re-read `editor.composer.selection`.
- [x] Thread the captured destination through plain, HTML, Markdown-file, and single-line task insertion paths.
- [x] Handle asynchronous paste errors through the editor's existing error/reporting boundary instead of an unobserved `unawaited` future.
- [x] Run rich clipboard tests and analyzer.

Evidence: rich clipboard tests pass, including delayed clipboard reads, all text
formats, task insertion, and bitmap paste; paste failures are reported through
`FlutterError.reportError`.

### Task 3: Correct toolbar state and task-component lifecycle

**Files:**
- Modify: `lib/features/notes/editor/presentation/widgets/note_toolbar.dart`
- Modify: `lib/features/notes/editor/presentation/widgets/custom_task_component.dart`
- Modify: `lib/features/notes/editor/presentation/widgets/custom_list_item_component.dart`
- Test: `test/features/notes/presentation/widgets/note_toolbar_test.dart`
- Test: `test/features/notes/presentation/widgets/custom_task_component_test.dart`
- Test: `test/features/notes/presentation/widgets/list_marker_alignment_test.dart`

**Interfaces:**
- Preserve existing toolbar commands and `CustomTaskComponentBuilder` public callbacks.
- Add a lifecycle cleanup method invoked when the builder is disposed or the document changes.

- [x] Add a multi-heading selection test and failure-path test for task completion focus/selection restoration.
- [x] Run focused widget tests and confirm the heading-state test fails with the current set-size comparison.
- [x] Compare one normalized block attribution across all selected paragraphs, remove stale task IDs/handlers, and restore the prior composer/focus state when completion fails.
- [x] Remove hard-coded text scalers from list markers and pass the current media/text scaler into width measurement.
- [x] Run focused widget tests and analyzer.

Evidence: toolbar, task-component, and list-marker tests pass. Task callbacks now
live in the view model for the current node instead of builder-lifetime maps/sets.

### Task 4: Pin and verify Super Editor dependencies

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Test/verification: dependency resolution and `flutter analyze`

- [x] Replace every `ref: main` for Super Editor monorepo packages with the immutable resolved commit already used by the lockfile.
- [x] Run dependency generation and verify all four packages resolve to the same commit.
- [x] Run analyzer and the focused editor suite.

Evidence: `super_editor`, `super_editor_clipboard`, `super_keyboard`, and
`super_text_layout` all resolve to `3bb857bc423240b61dc0fb799f3c269e71feb24a`.

### Task 5: Finish sync orchestration without redundant work

**Files:**
- Modify: `lib/features/notes/editor/sync/note_sync_session.dart`
- Modify: `lib/core/di/providers.dart`
- Modify: `lib/main.dart`
- Modify: `lib/core/sync/note_outbox_worker.dart`
- Test: `test/features/notes/editor/sync/note_sync_session_debounce_test.dart`
- Test: `test/core/di/note_outbox_worker_provider_test.dart`
- Test: `test/core/sync/note_outbox_worker_test.dart`

**Interfaces:**
- Preserve `NoteSyncSession.flushNow`, `pollNow`, `NoteOutboxWorker.drain`, and `wake`.
- Add a close/availability wake hook without coupling the worker to editor widgets.

- [x] Add tests for close-triggered worker wake and for avoiding a second poll after a successful pending-operation response.
- [x] Run the focused sync tests and confirm they fail on the current five-minute close latency and POST-then-GET sequence.
- [x] Have the session coordinator signal the app-scoped worker after a successful close; let explicit polling consume the sync response without an immediate redundant GET.
- [x] Keep active notes excluded from the global worker and preserve per-note retry isolation.
- [x] Run focused sync tests and analyzer.

Evidence: coordinator and session tests pass; a successful pending POST is treated
as the poll result, and closing a durable session wakes the global outbox worker.
The app-scoped remote runtime now uses the same bounded retry schedule as the
outbox after transient feed/catalog failures.

### Task 6: Make inbox schema and feed lifecycle production-safe

**Files:**
- Modify: `lib/core/database/database.dart` (`schemaVersion`, `@DriftDatabase`, `_onUpgrade`)
- Create: `lib/core/database/tables/sync_feed_cursors.dart`
- Create: `lib/core/database/tables/sync_inbox.dart`
- Regenerate: `lib/core/database/database.g.dart`
- Modify: `lib/core/sync/sync_inbox_store.dart`
- Modify: `backend/db/migrations/000053_sync_change_feed.up.sql`
- Add/modify: backend sync-feed tests
- Test: `test/core/sync/sync_inbox_store_test.dart`, `test/core/sync/sync_inbox_worker_test.dart`, backend integration tests

- [x] Add a migration/schema test proving inbox/cursor tables survive an app database upgrade and inbox/cursor state remains actor-scoped by user.
- [x] Run the schema-backed store tests and confirm the tables are represented in Drift schema metadata.
- [x] Move inbox/cursor tables into the database schema/migration path; consumed rows retain `applied_at` for crash-safe replay and are actor-scoped by `(user_id, sequence)`.
- [x] Keep the feed watermark transactionally stable and test share, revoke, preference, soft-delete, and repeated-update events.
- [x] Run backend integration/full tests and focused Flutter sync tests.

The server feed intentionally has no guessed time-based deletion policy: deleting
events without a client acknowledgement/watermark protocol could make an offline
client skip changes permanently. Retention/compaction remains a separate protocol
change rather than an unsafe local cleanup.

### Task 7: Documentation, handoff, and full verification

**Files:**
- Modify: `docs/superpowers/plans/2026-09-01-sync-coordinator-outbox.md`
- Modify: `docs/superpowers/specs/2026-09-01-sync-coordinator-outbox-design.md`
- Add: `HANDOFF.md`
- Modify: `task.md`, `walkthrough.md` as needed
- Test/verification: all focused and full commands below

- [x] Reconcile the plan and PR scope with the actual outbox plus inbox implementation.
- [x] Write `HANDOFF.md` with current branch, commits, verification commands, known external limitations, and next actions.
- [ ] Run `flutter analyze --no-fatal-infos`, all Flutter test groups, `go vet ./...`, `go build ./...`, and `go test -count=1 ./...` (Flutter is verified; Go is blocked because the toolchain is absent on this host).
- [x] Run the thermo-nuclear review against the current branch, fix every actionable finding, and repeat until the review is clean.
