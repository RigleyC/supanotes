# Spec: Task Recurrence Catch-Up and Transition Logic

## Goal
Improve the user experience and data correctness when completing and editing recurring tasks. Specifically:
1. **Prevent Double Completions (Catch-Up)**: When a recurring task's due date is missed (in the past) and reaches or passes the day of the next occurrence, the missed occurrence is skipped (marked as not completed/missed without logging a completion), and the task automatically catches up to the current active occurrence (either today or the latest overdue occurrence).
2. **Transition from Regular to Recurring Task**: When a completed regular task is edited to add a recurrence rule, it automatically re-opens for the next recurring occurrence based on the task's completion date (or original due date).

## Proposed Changes

### Frontend (Flutter / Drift)

#### [MODIFY] [tasks_dao.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/core/database/daos/tasks_dao.dart)
1. Add `catchUpRecurringTasks()` method to query all open recurring tasks and advance their due dates if they are in the past and their next occurrence has arrived (i.e. `nextDue <= today`).
2. Run `catchUpRecurringTasks()` asynchronously:
   * When initializing the repository/database.
   * Inside `watchOpenTasks` and `watchTodayTasks` to ensure reactive UI catches up automatically.
3. Update `completeTask(String id)`:
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
- Run `flutter test test/core/database/daos/tasks_dao_test.dart` to verify local recurrence calculations.
- Run `go test ./internal/tasks/...` to verify backend recurrence calculations and database updates.

### Manual Verification
1. **Automatic Catch-Up**: Set a daily task due yesterday (e.g. June 29). Open the app today (June 30). Verify that the task's due date automatically changes to today (June 30) without showing the red "Atrasada" badge, and no completion history was added for yesterday.
2. **Click Catch-Up**: Set a daily task due yesterday. Complete it. Verify it completes for today and advances to tomorrow (July 1), logging exactly 1 completion.
3. **Task Conversion**: Create a one-off task. Complete it. Edit it to add a daily recurrence. Verify that the task is re-opened, its due date is set to tomorrow, and the completion history still shows the completed one-off task.
