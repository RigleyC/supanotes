# Implementation plan — local-first note persistence

Status: complete for ticket 01.

Review-fix pass: complete.

Scope: ticket 01, atomic local persistence during remote note hydration.

- [x] Confirm the current write order and data-loss failure mode.
- [x] Expose a pure document projection result.
- [x] Persist document, catalog row, content projection, and task projection atomically.
- [x] Update catalog hydration to use the aggregate transaction.
- [x] Add first-hydration and rollback tests.
- [x] Run focused tests, full suite, code review, and commit the ticket.

Review fixes:

- [x] Reject stale or missing local rows before publishing remote hydration.
- [x] Remove the insert/update mode flag and centralize metadata updates in the DAO.
- [x] Separate pure document projection from database persistence.
- [x] Test the real editor session opening from local storage.
- [x] Run the final full suite, review, and commit the fixes.

## Editor text and task completion snack

Status: complete.

- [x] Use white text for the editor document styles.
- [x] Keep only the completion title and undo action in the task snack.
- [x] Add focused coverage for hiding the next-occurrence message.
- [x] Run focused tests and analyzer; the full suite timed out in the environment.

## Task metadata sheet bottom spacing

Status: complete.

- [x] Identify the duplicated bottom spacing in the modal content.
- [x] Reduce the explicit bottom gap while preserving safe-area spacing.
- [x] Run the focused task metadata sheet test and analyzer.

## Editor empty viewport focus

Status: complete.

- [x] Reproduce taps below the document but above the mobile toolbar.
- [x] Add regression coverage for caret placement, focus, keyboard reopening,
  and a document with only hidden tasks.
- [x] Handle trailing hidden tasks through the Super Editor content-tap
  delegate API.
- [x] Run focused tests, analyzer, full suite, and two-axis code review.

## iOS task text selection

Status: complete.

- [x] Reproduce the long-press conflict between task actions and iOS text selection.
- [x] Restrict task action long press to the checkbox.
- [x] Preserve secondary-click task actions on desktop.
- [x] Add iOS selection regression coverage across task blocks.
- [x] Run focused tests, analyzer, full suite, code review, and commit.
