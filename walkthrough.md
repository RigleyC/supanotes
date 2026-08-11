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
