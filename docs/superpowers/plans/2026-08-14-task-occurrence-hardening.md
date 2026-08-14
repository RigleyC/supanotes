# Task Occurrence and Document-Native Migration Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Complete the document-native task migration contract for recurring dates, repeated early completions, overdue reminders, and timezone-stable occurrence identity without restoring a relational task model.

**Architecture:** The note document remains canonical. `TaskOccurrencePolicy` is the only domain resolver; the editor records `scheduledAt -> completedAt`, the badges resolve the visible occurrence, and the notification reader resolves a separate future reminder target when the visible occurrence is overdue. Schedule identity uses calendar wall-clock components, while completion moments remain UTC instants.

**Tech Stack:** Flutter/Dart, Super Editor `TaskNode`, REST/OT document operations, local effective-document snapshots, Flutter local notifications, Go note-operation contract, PostgreSQL read-only migration preflight.

## Global Constraints

- Do not reintroduce `TaskModel`, `TaskData`, task providers, relational task writes, or a global task table.
- `notes.document` and REST/OT operations remain the source of truth.
- `dueDate` remains the recurrence anchor; completing a recurrence never moves the anchor.
- A recurring completion is `completions[scheduledAtKey] = completedAtUtc`.
- Multiple consecutive early completions are valid.
- An overdue occurrence remains visible until the next occurrence starts; notifications may target the next future occurrence.
- Monthly recurrence keeps the anchor day and clamps only the month that lacks that day.
- Schedule keys contain no timezone offset; completion values contain UTC timestamps.
- Do not delete production or local legacy data in application code. Physical cleanup remains a separately approved operation after backup, export, reconciliation, and retention.

---

### Task 1: Make occurrence identity and anchored date arithmetic deterministic

**Files:**
- Create: `lib/features/tasks/domain/task_schedule_identity.dart`
- Modify: `lib/core/utils/recurrence.dart`
- Modify: `lib/features/tasks/domain/task_occurrence.dart`
- Test: `test/core/utils/recurrence_test.dart`
- Test: `test/features/tasks/domain/task_occurrence_test.dart`
- Test: `test/features/tasks/domain/task_completion_command_test.dart`
- Create: `test/features/tasks/domain/task_schedule_identity_test.dart`

**Interfaces:**
- `String scheduledAtKey(DateTime value, {required bool hasTime})` returns a zero-offset calendar key using the value's wall-clock components; all-day keys contain midnight only.
- `DateTime canonicalScheduledAt(DateTime value, {required bool hasTime})` returns a local canonical value for identity comparisons.
- `bool sameScheduledAt(DateTime left, DateTime right, {required bool hasTime})` compares calendar identity, not UTC instants.
- `nextDueDate` accepts an optional `anchorDay` and uses it for monthly recurrence.
- `TaskOccurrencePolicy.resolveNotificationOccurrence` returns the visible occurrence unless it is overdue and recurring, in which case it returns the first future, uncompleted occurrence.

- [x] **Step 1: Write schedule-identity tests**

  Cover all-day `00:00` versus `03:00Z` on the same date, timed wall-clock equality across UTC/local representations, different all-day dates, and canonical serialization without an offset.

- [x] **Step 2: Write the month-end and completion tests**

  Cover January 31 → February 28 → March 31, early weekly completion, two consecutive early completions, same-day completion, late completion, and an overdue occurrence that remains active until the next scheduled date starts.

- [x] **Step 3: Implement the identity helper**

  Build keys from `year`, `month`, `day`, and, when `hasTime` is true, `hour`, `minute`, `second`, and microseconds. Do not call `toUtc()` for the scheduled key. Keep `completedAt` outside this helper.

- [x] **Step 4: Implement anchor-aware monthly arithmetic**

  Add `anchorDay` to `nextDueDate`. Pass the original anchor day from `TaskOccurrencePolicy`, `advanceRecurringDueDate`, and occurrence enumeration. Preserve the existing generic behavior when no anchor day is supplied.

- [x] **Step 5: Make policy matching and comparisons use the contract**

  Match completion keys with `sameScheduledAt`, compare timed schedule values as local wall-clock values, and compare all-day values by calendar date. Use the original anchor day for every next occurrence.

- [x] **Step 6: Implement notification-target resolution**

  Keep `resolveCurrent` unchanged for editor and badge semantics. Add a separate resolver that walks forward from an overdue recurring occurrence and skips any already completed future keys before returning the first future occurrence.

- [x] **Step 7: Run the focused domain tests**

  Run:

  ```text
  flutter test test/core/utils/recurrence_test.dart test/features/tasks/domain/task_schedule_identity_test.dart test/features/tasks/domain/task_occurrence_test.dart test/features/tasks/domain/task_completion_command_test.dart --reporter compact
  ```

  Expected result: zero failures and explicit coverage of the three monthly dates and repeated early completion.

### Task 2: Persist and render the canonical occurrence identity

**Files:**
- Modify: `lib/features/notes/editor/application/note_editor_controller.dart`
- Modify: `lib/features/tasks/presentation/controllers/task_metadata_draft.dart`
- Modify: `lib/features/tasks/presentation/widgets/task_metadata_badges.dart`
- Modify: `lib/features/notes/editor/presentation/widgets/custom_task_component.dart`
- Modify: `lib/features/tasks/domain/task_notification_entry.dart`
- Test: `test/features/notes/presentation/controllers/note_editor_controller_test.dart`
- Test: `test/features/notes/presentation/widgets/custom_task_component_test.dart`
- Test: `test/features/tasks/presentation/widgets/task_metadata_badges_test.dart`

**Interfaces:**
- Editor completion writes `scheduledAtKey(result.scheduledAt, hasTime: snapshot.hasTime)` and `result.completedAt.toUtc().toIso8601String()`.
- Reopen removes every serialized key with the same schedule identity, including a key normalized from an older UTC representation.
- `TaskMetadataDraft` remains an interface model, not a persisted task model; its completion map is read-only display context and is never edited by the sheet.

- [x] **Step 1: Add editor regression tests**

  Assert the anchor remains unchanged, the completion key is stable without an offset, the completed value is UTC, two early completions create two schedule keys, and reopen removes only the requested occurrence.

- [x] **Step 2: Normalize completion maps at document boundaries**

  Parse completion maps into canonical scheduled keys before passing them to the resolver. When writing or reopening, remove equivalent keys before inserting or deleting the canonical key.

- [x] **Step 3: Normalize schedule-anchor writes**

  Serialize `dueDate` with the same wall-clock contract. Compute schedule changes by calendar identity plus `hasTime`, so changing only representation does not incorrectly clear history.

- [x] **Step 4: Preserve completion history through the custom view model**

  Keep `TaskMetadataDraft` in the custom view model copy path and pass its completions to `TaskMetadataBadges`. The sheet state must continue to contain only editable fields.

- [x] **Step 5: Use schedule identity in notification-entry equality**

  Compare `TaskNotificationEntry.dueDate` with `sameScheduledAt` and hash it with `scheduledAtKey` so equivalent wall-clock representations do not cause a platform reschedule.

- [x] **Step 6: Run the focused editor and widget tests**

  Run the controller, custom-task, and metadata-badge test files with the compact reporter. Record the exact result before moving to notification work.

### Task 3: Make reminders follow the next future occurrence after an overdue one

**Files:**
- Modify: `lib/features/tasks/domain/note_task_reader.dart`
- Modify: `lib/features/tasks/domain/task_notification_scheduler.dart` only if the extracted identity or time helper requires it
- Test: `test/features/tasks/domain/note_task_reader_test.dart`
- Test: `test/features/tasks/domain/task_notification_entry_test.dart`
- Create: `test/features/tasks/domain/task_notification_time_test.dart` if notification-time logic is extracted

**Interfaces:**
- `NoteTaskReader` uses the effective local document and `TaskOccurrencePolicy.resolveNotificationOccurrence`.
- The reader still excludes completed non-recurring tasks and keeps the current visible occurrence out of the scheduler contract.
- A stale overdue recurring task emits the next future occurrence as `TaskNotificationEntry.dueDate`; the editor and badges continue to resolve the overdue occurrence.

- [x] **Step 1: Add reader tests with a fixed clock**

  Cover a future task, an overdue recurring task whose next reminder is future, a completed early occurrence, two completed early occurrences, no reminder, and a non-recurring completed task.

- [x] **Step 2: Implement the reader boundary**

  Parse `hasTime` before completions, use canonical completion identity, resolve the notification target, and keep the existing document-only source.

- [x] **Step 3: Add notification-entry equality coverage**

  Assert equivalent UTC/local wall-clock schedule representations compare equal and different calendar dates compare unequal.

- [x] **Step 4: Restore the pure notification-time test seam**

  If the scheduler's private calculation cannot be covered without a provider and platform plugin, extract only the pure `computeTaskNotificationTime` function. Keep platform scheduling, cache, cancellation, and the 30-item limit in the scheduler.

- [x] **Step 5: Run the notification tests**

  Run the reader, entry, and notification-time tests. Confirm that an overdue task is not scheduled at its stale reminder time and that its next future reminder is eligible.

### Task 4: Close the migration and data-safety documentation

**Files:**
- Modify: `docs/superpowers/specs/2026-08-12-task-document-native-design.md`
- Modify: `docs/adr/0009-recurring-task-occurrence-policy.md`
- Modify: `backend/db/operations/task_document_migration_preflight.sql`
- Modify: `backend/internal/noteoperations/validator.go`
- Create: `docs/operations/task-document-migration-runbook.md`
- Modify: `plans/005-task-document-native-migration.md`
- Modify: `implementation_plan.md`
- Test: `backend/internal/noteoperations/document_contract_test.go`
- Test: `backend/internal/noteoperations/operation_contract_validation_test.go`

**Interfaces:**
- Documentation records that repeated early completion is allowed, the anchor day is preserved, scheduled keys are wall-clock identities, and notification target resolution is separate from visible occurrence resolution.
- The preflight remains read-only and reports invalid aliases, missing blocks, orphan rows, conflicting schedule identities, and non-canonical completion keys.
- The runbook defines backup, export, restore rehearsal, read-only comparison, conflict stop conditions, controlled observation, retention, and only then physical cleanup approval.

- [x] **Step 1: Update the approved contract**

  Add the final examples for 12 → 10, 19 → 10, and the month-end sequence. Clarify that `completedAt` stores the real completion instant while `scheduledAt` stores calendar identity.

- [x] **Step 2: Extend the read-only preflight**

  Add result sections for canonical metadata keys, malformed completion maps, duplicate schedule identities after normalization, and rows that cannot be mapped deterministically. Do not add `UPDATE`, `DELETE`, `DROP`, or automatic reconciliation.

- [x] **Step 3: Write the cutover runbook**

  Define exact commands for `pg_dump`, task/completion export including soft-deleted rows, read-only SQL execution, restore verification, artifact retention, rollback by restoring the previous application version, and the approval required before dropping legacy tables or routes.

- [x] **Step 4: Align the migration plan checkboxes**

  Mark the production backup, export, restore rehearsal, preflight, backfill,
  and deployment gates complete because their artifacts and production results
  now exist. Keep physical cleanup explicitly pending because it requires a
  separate approval after retention.

- [x] **Step 5: Self-review the documents**

  Search for unresolved markers, stale `TaskModel` runtime claims, and contradictions between the spec, ADR, implementation plan, and runbook. Fix all findings before validation.

### Task 5: Execute verification and report the real cutover state

**Files:**
- Modify: `implementation_plan.md` with command output references and gate status
- Modify: `walkthrough.md` with the delivered behavior and remaining operational gate, if any

- [x] **Step 1: Run formatting and static checks**

  Run `dart format` on changed Dart files, `flutter analyze` on the changed packages, `go test ./...` in `backend`, and `git diff --check`.

- [x] **Step 2: Run the focused and complete suites**

  Run the focused task/editor tests first, then the complete Flutter test suite and complete Go suite with adequate timeouts. Report focused, full, and environmental results separately.

- [x] **Step 3: Review the final diff**

  Confirm no unrelated user edits are staged or overwritten, no relational task model returns to the editor/scheduler, no runtime fallback aliases were added, and all new behavior is covered by the plan.

- [x] **Step 4: Update the plan from evidence**

  Mark a gate complete only when its command, artifact, or production result is present. If production credentials or a restore environment are unavailable, state that as the remaining external gate instead of claiming a complete migration.

- [x] **Step 5: Complete the goal only after all required gates are evidenced**

  Code, documentation, local verification, production data safety, canonical
  backfill, deployment, and health evidence are complete. Physical removal of
  legacy tables remains outside this plan and requires a new approval.
