# Walkthrough — atomic local note hydration

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

## Progressive content fade

The AppBar background gradient was removed because it painted a background
over the document and did not change document opacity. The notes list and note
editor now use a shared `ProgressiveFade` below their transparent AppBars.
The mask follows `kToolbarHeight` and fades the AppBar's 56-pixel content
region through 20%, 40%, 60%, 80%, and 100% opacity. The top stays partially
visible instead of becoming fully transparent.

Focused verification:

- Progressive fade tests: 2 passed.
- Progressive fade plus editor layout tests: 5 passed.
- Static analysis of the changed Dart files: no issues found.
