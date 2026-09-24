# Walkthrough — atomic local note hydration

## Tasks home list and footer

The Tasks home screen now renders open tasks only. Completed occurrences stay
available through the existing history route, opened by a fixed “Concluídas”
button in the screen footer. The add action sits beside it; bottom padding keeps
both controls clear of the app navigation and device safe area.

The empty state remains visible when the open-task list is empty. The history
route and task completion behavior are unchanged.

Verification: `dart format` passed and targeted `flutter analyze` reported no
errors or warnings (two existing documentation infos). `git diff --check`
passed. No device preview was available in this pass.

Ticket 01 is complete.

Remote hydration now computes the content, excerpt, and task projection first, then saves the canonical document, catalog row, content projection, and task projection in one Drift transaction. A failure rolls back the complete aggregate, so an offline restart cannot see an orphan document or an empty catalog note.

Verification:

- Focused Flutter tests: passed.
- Flutter analyze on changed files: passed.
- Full Flutter test suite: 554 passed, 1 skipped.
- `git diff --check`: passed.

## Thermonuclear review corrections

The final editor flush now updates the canonical local projection before the
session becomes disposed. Draft cleanup runs through a required lifecycle
store, and the database rechecks remote state, projected text, tasks, and
attachments in the same transaction that removes the aggregate.

Catalog queries use the same untouched-draft conditions and keep attachment
notes visible. `NoteModel.hasRemoteCopy` is explicit, while editor autofocus is
named as a UI decision instead of being used as the lifecycle policy.

Verification:

- Flutter analyze: no issues found.
- Lifecycle and sync tests: 32 passed.
- `git diff --check`: passed.

Review fixes complete:

- Remote hydration now uses a version-checked compare-and-set update. Local edits, deleted rows, or notes opened during the request are not overwritten.
- The catalog builds one typed companion and the DAO owns the remote metadata update.
- Pure document projection is separated from database persistence.
- Coverage now opens the real editor session from the persisted local document.
- The editor now opens from the local snapshot before task projection or network
  work completes. The app-scoped catalog sync hydrates all remote pages in the
  background.
- The legacy Material calendar icons were restored, task checkbox alignment was
  adjusted, and Joi indigo is now the accent color with softer semantic green
  and red colors.
- The final Flutter suite passed with 554 tests and 1 skipped test. The Windows
  integration suite passed with 4 tests, and the backend suite passed with 254
  tests in 25 packages.

## Document-native task occurrence hardening

The task flow now keeps the note document as the only source of truth. The
editor records `scheduledAt -> completedAt`, where `scheduledAt` is a calendar
wall-clock identity and `completedAt` is UTC. The recurrence anchor does not
move after completion, monthly series preserve the original anchor day, and
consecutive early completions are allowed.

The visible editor occurrence remains overdue until the next occurrence starts.
The notification reader uses a separate future target so an overdue reminder
is never scheduled in the past. The effective local document includes pending
operations, so offline task metadata is available to the scheduler.

Verification for this change:

- Focused task, editor, notification, sync, and contract tests: passed.
- Full Flutter suite: 680 passed.
- Flutter analyze: no issues found.
- Full Go suite: 347 passed in 26 packages.
- `git diff --check`: passed.

Production cutover is complete for release `task-document-native-2026-08-14`.
The protected artifacts contain a valid custom-format backup, full legacy table
exports, isolated restore results, read-only preflight and metadata inventory,
the per-value backfill audit, and SHA-256 hashes. Production ended with 190
task blocks, 53 completion entries, zero legacy metadata aliases, and zero
relational task rows. The strict backend was deployed and
`GET /api/v1/health` returned HTTP 200. Historical OT payloads retain their old
wire values by design; they are immutable rebase records, not canonical task
state. No table cleanup is performed by application code.

## Editor empty viewport focus

Tapping the blank editor area below visible text now places the caret at the
end of the last visible text block and opens the software keyboard. If trailing
hidden tasks leave no visible text block, the editor inserts and selects an
empty paragraph through the canonical editor request pipeline.

The fix uses Super Editor's `ContentTapDelegate`, editor requests, focus node,
and software keyboard controller. It does not add an outer gesture detector.
Both mutating tap delegates are disabled in read-only mode.

Verification:

- Editor, link, task component, and toolbar test suites: passed.
- Flutter analyze: passed with no issues.
- Full Flutter test suite: 608 passed, 1 skipped.
- Standards and specification reviews: no remaining findings.

## iOS task text selection

Task text no longer captures the long-press gesture that the iOS editor uses
to begin and extend a text selection. Long press on the task checkbox still
opens task metadata, and secondary click on task text still opens metadata on
desktop. Regression coverage drags the selection across task blocks at the
viewport edge, confirms that the editor auto-scrolls, and confirms that the
selection remains expanded.

Verification:

- Custom task component tests: 16 passed.
- Note editor screen tests: 23 passed, 1 skipped.
- Flutter analyze: no issues found.
- Full Flutter suite: 620 passed, 1 skipped.
- Existing Drift and Google Fonts warnings remained non-failing.

## Note draft lifecycle and initial focus

Creating a note still allocates its stable ID before navigation. The ID is
needed by the local editor session and the REST/OT pending-operation queue. The
new row is local-only and empty, so catalog queries hide it until content is
projected.

The editor now derives initial focus from that local draft state. The router
only navigates to `/notes/:id`; it no longer transports a transient focus flag.
If the user leaves without meaningful content, the editor removes the complete
local aggregate. Once a canonical operation is accepted by REST/OT, the local
row is marked as having a remote copy and follows the normal note lifecycle.

Verification:

- Flutter analyze: no issues found.
- Focused Flutter suite: 69 passed, 1 skipped.
- `git diff --check`: passed.

## Remove desktop version features

Desktop-only features were removed from the Flutter app: split-view shell
(`AdaptiveNotesShell` + `ShellRoute`), sidebar and drag handle, desktop editor
chrome/viewport/stylesheet, selection formatting popover, native context menus
(`super_context_menu`), markdown task shortcuts, and the slash command menu.
The router, shared screens, and `note_editor.dart` are now mobile-only; the
Windows platform folder and window bootstrap stay so the app remains buildable.

Removed deps: `super_context_menu` and the direct `follow_the_leader` entry
(still resolved transitively via `super_editor`). Removed 8 desktop test files
and stripped desktop/slash cases from shared tests. Historical specs
(`docs/superpowers/specs/`, `plans/003-*.md`, `.scratch/`) were kept.

Verification:

- Flutter analyze: no issues found.
- Full Flutter test suite: 630 passed, 1 skipped (1 unrelated failure in the
  other agent's draft-lifecycle test).
- `git diff --check`: passed.

## Windows debug launch: canonical Delta snapshot

The Windows debug launch failed during note hydration because the REST/OT
backend persisted a text mutation Delta as part of the document snapshot.
The editor correctly rejected the `delete` operation because snapshots contain
text inserts only.

The backend now keeps mutation operations out of canonical snapshots. Local
hydration repairs the malformed cached snapshot at the projection boundary,
while transport decoding remains strict. This lets the existing local note
open without weakening the shared REST/OT contract.

Verification:

- Backend suite: 337 tests passed in 27 packages.
- `go vet ./...`: passed.
- Flutter suite: 651 tests passed, 1 skipped.
- Flutter analyze: no issues found.
- Windows debug build: passed.
- Controlled `flutter run -d windows --debug`: reached VM service attachment
  with no `FormatException` or note-session startup error.

## Editor and sync hardening (2026-09-02)

The editor now skips hidden completed tasks when deleting across visible block
boundaries, sanitizes selections when a selected task becomes hidden, captures
paste destinations before asynchronous clipboard reads, and reports paste
errors. Multi-heading toolbar state, task callback lifetime/failure recovery,
and text-scaled list markers were corrected. Super Editor packages are pinned
to one immutable commit.

Remote synchronization now has a durable Drift-managed inbox and feed cursor
(schema v31), a tested v30 migration, watermark bootstrap, and a close-session
wake into the global outbox. Polling consumes useful POST responses instead of
issuing an immediate redundant GET. The temporary branch-specific verification
workflow was removed.

Verification: `flutter test --no-pub` passed 733 tests and `git diff --check`
passed. Analyzer output remains limited to the repository's existing
warnings/infos. Go verification is pending because the Go toolchain is not
installed on the current Windows host; see `HANDOFF.md`.

## Code quality, auth and task-flow corrections (2026-09-16)

The delegated review and implementation pass corrected the reported feature
flows while preserving the repository's existing local changes and task
ownership invariant. The adaptive shell remains an `AdaptiveScaffold`, as
required by `AdaptiveBottomNavigationBar`, but the bar is shown only on the
Tasks and Notes roots. Note details, completed tasks and the task editor use
their own back/navigation affordances; the completed iOS route has an explicit
back button.

Standalone task creation and editing now use the shared global sheet titled
`Criar/Editar nota`, with the shared input, existing metadata options, and
Cancelar/Salvar actions. Note task navigation opens the note route directly.
The notes empty state no longer owns an unnecessary scroll view, completed
tasks stay above the navigation bar, and focus dismissal uses the shared icon
button component.

Auth transport now attaches the access token through Dio, serializes refreshes,
stores the access/refresh pair together, retries the original request once,
and avoids refresh loops on auth routes or non-401 errors. Session cleanup is
centralized after an unrecoverable refresh failure.

MCP confirmations use a fenced execution lease. Internal destructive mutations
persist the mutation result in the same transaction; attachment deletion
commits metadata with a retryable storage outbox; document and independent
task mutations retain stable `operation_id` idempotency. A regression test
covers an effect applied before lease expiry followed by a retry.

Verification for this pass:

- `go test ./...`: passed.
- `go vet ./...`: passed.
- Focused Flutter/auth/task/notes/editor/router/widget battery: 297 tests
  passed.
- `flutter analyze --no-pub --no-fatal-infos lib`: exit 0, no errors or
  warnings; remaining diagnostics are repository infos only.
- `git diff --check`: passed; Git reported only normal LF/CRLF conversion
  warnings.
- Sol low final review: approved with no concrete P0/P1/P2 findings.

No real iOS device/simulator or opt-in PostgreSQL integration database was
available in this environment, so those runtime checks remain pending.

## Task occurrence completion and archived history (2026-09-23)

- Recurring occurrence resolution retains the latest started occurrence as
  completed until its successor starts. Timed tasks use their scheduled time;
  all-day tasks use their local calendar date.
- The Tasks screen separates open tasks from the current completed occurrence
  and reopens through the owning independent-task or note-document controller.
  Completion history remains a separate route.
- Note task components keep the check after animation and schedule a local
  refresh at the next occurrence boundary. Hiding follows the note preference.
- Schedule edits move active conclusions into `completionHistory`, preserving
  the old schedule identity, `hasTime`, and completion instant. Independent
  tasks store it in Drift/Postgres; note tasks store it in document metadata.
  A nullable `scheduledAt` represents tasks completed before they had a date.
- Database migrations initialize the archive as empty and do not infer history
  already erased by previous schedule edits.
- Blocked outbox operations no longer participate in task rebase.
- The note-document service rejects metadata changes that erase archived
  completions. Schedule edits must archive active completions and clear the
  active state atomically. The Flutter operation builder now sends this as one
  `set_block_metadata` operation; the server also checks removals earlier in
  the same sync transaction from older clients.

Release compatibility: the backend accepts the older client's one-off
completion operation that removes `dueDate`. An older client changing a
schedule with active completions receives a sync error rather than losing
history. The updated client sends the archive atomically. Android CI generates
artifacts but does not publish an app update; the user will generate APK/IPA
after the staged backend release.

Verification: focused task/editor Flutter tests passed (76 tests). The full Flutter suite completed with 866 passes and one unrelated failure, reproduced in isolation: `test/shared/widgets/confirm_dialog_test.dart`, “showConfirmDialog emits a control tap for Cancelar e Confirmar” expects one haptic but receives two. Task/editor expectations were updated to the approved occurrence behavior without adding tests. Targeted Flutter analysis completed with infos only; Go `go test ./...` passed (462 tests/29 packages), `go build ./...` and `git diff --check` passed. Reminder delivery and note rollover were not device-tested; the note component schedules a local refresh at the next occurrence boundary so hide-completed does not depend on a document event.

## Timed recurring occurrences open at local midnight (2026-09-23)

Timed recurring tasks now use the occurrence scheduled for the current local
calendar date from midnight onward. It remains pending before its scheduled
time, becomes overdue after that time if still open, and can be completed early
against today's schedule key. The prior day's completion no longer makes
today's later-timed occurrence appear checked. At the next scheduled date's
midnight, the following occurrence becomes current.

This uses the shared domain resolver, so it applies to tasks inside notes and
independent tasks in the Tasks tab. Note-editor refresh now considers both the
local midnight date boundary and the scheduled wall-clock boundary. Reminder
calculation remains time-based and separate. The backend already accepts the
canonical scheduled key for early completion, so it needed no change. No
production task data was modified.

Verification: Dart formatting, targeted Flutter analysis, Android debug APK
build, and `git diff --check` passed. Analysis reported existing `info`
diagnostics only. The debug build emitted existing Gradle/AGP/Kotlin deprecation
and Java source/target warnings. Tests were not run because project
`AGENTS.md` prohibits unit tests. Device behavior and the iOS build were not
verified here.

## Task list swipe deletion and recurring metadata date (2026-09-23)

The global Tasks list now supports end-to-start swipe deletion with a
confirmation. Standalone tasks use the task repository; note-owned tasks use
the note editor's canonical document operation and are flushed through the
note session. If the note task is the document's only block, it becomes an
empty paragraph so the note remains editable.

The task metadata editor now shows the persisted schedule anchor for recurring
tasks. The global list remains responsible for showing the current occurrence,
so a past recurrence anchor is no longer presented as the current overdue
occurrence inside the editor.

Verification: targeted Flutter analysis reported infos only, the Android debug
APK build passed, and `git diff --check` passed. No unit tests were run per the
repository instructions. The swipe interaction has not been exercised on a
physical device.

## Note recurring task badge shows the anchor after completion (2026-09-24)

The note editor previously passed the recurring series anchor to the task date
badge. The badge suppresses its own occurrence calculation for completed
tasks, so a series anchored on the 21st kept showing the 21st after today's
occurrence was completed. The editor now passes the resolved current occurrence
separately; recurrence metadata and completion identity continue to use the
original anchor and today's scheduled occurrence respectively.

Verification: targeted Flutter analysis reported existing infos only, the
Android debug APK build passed, and `git diff --check` passed. Unit tests were
not run per repository instructions; device behavior remains unverified.
