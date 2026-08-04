# Spec: Task Recurrence Catch-Up and Transition Logic

## Goal
Improve the user experience and data correctness when completing and editing recurring tasks. Specifically:
1. **Prevent Double Completions (Catch-Up)**: When a recurring task's due date is missed (in the past) and reaches or passes the day of the next occurrence, the missed occurrence is skipped (marked as not completed/missed without logging a completion), and the task automatically catches up to the current active occurrence (either today or the latest overdue occurrence).
2. **Transition from Regular to Recurring Task**: When a completed regular task is edited to add a recurrence rule, it automatically re-opens for the next recurring occurrence based on the task's completion date (or original due date).

## Proposed Changes

### Frontend (Flutter / Drift)

#### [MODIFY] [recurrence.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/core/utils/recurrence.dart)
1. Add one pure function that returns the latest occurrence that has started.
2. Skip missed occurrences instead of creating an overdue backlog.

#### [MODIFY] [note_document_projector.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/domain/note_document_projector.dart)
3. Derive the current due date for open recurring tasks before writing the local
   task projection.

#### [MODIFY] [task_completion_command.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/domain/task_completion_command.dart)
4. Calculate the active occurrence before completing a recurring task.
   Record the completion for that occurrence and calculate the next date from
   it.

#### [MODIFY] [task_model.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/domain/task_model.dart)
5. Apply the same derivation to rows read from the local projection. The DAO
   does not write time-based catch-up data directly.

6. Update `completeTask(String id)`:
   * Calculate the caught-up active occurrence date first if the task is recurring.
   * Record the completion event for that active date.
   * Calculate the next occurrence starting from the active date.
4. Update `updateTask(TasksCompanion companion)`:
   * If the task's current status is `done` and the update adds a recurrence rule, calculate the next due date starting from `completedAt` (or `dueDate` / `now`), clear `completedAt`, set `status` to `open`, and update `dueDate`.

---

### Backend (Go)

#### [MODIFY] [service.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/tasks/service.go)
1. Update `CompleteTask(ctx, userID, id)`:
   * Calculate the caught-up active occurrence date if the task is recurring and next occurrence has arrived (i.e. `nextDue <= today`).
   * Record the completion event for the caught-up due date in `task_completions`.
   * Update the task's due date to the next occurrence starting from the caught-up date.
2. Update `UpdateTask(ctx, userID, id, opts)`:
   * If the task's current status is `done` and `opts.Recurrence` is added:
     * Fetch the task.
     * Calculate the next due date based on the task's completion date or due date.
     * Re-open the task by setting `opts.Status` to `"open"`, `opts.DueDate` to `nextDue`, and clearing `completed_at`.

---

## Verification Plan

### Automated Tests
- Run the recurrence, projection, occurrence, controller, and badge tests.
- Run `go test ./internal/tasks/...` when backend task behavior changes.

### Manual Verification
1. **Automatic Catch-Up**: Set a daily task due yesterday (e.g. June 29). Open the app today (June 30). Verify that the local projection shows today (June 30) without the red "Atrasada" badge, and no completion history was added for yesterday.
2. **Click Catch-Up**: Set a daily task due yesterday. Complete it. Verify it completes for today and advances to tomorrow (July 1), logging exactly 1 completion.
3. **Task Conversion**: Create a one-off task. Complete it. Edit it to add a daily recurrence. Verify that the task is re-opened, its due date is set to tomorrow, and the completion history still shows the completed one-off task.
