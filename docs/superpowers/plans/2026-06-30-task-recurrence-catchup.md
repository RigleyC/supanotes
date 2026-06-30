# Plan: Recurring task catch-up and done→recurring transition

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 8f5e652..HEAD -- lib/core/database/daos/tasks_dao.dart backend/internal/tasks/service.go`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `8f5e652`, 2026-06-30

## Why this matters

When a recurring task's due date is missed and the next occurrence's day arrives, completing the overdue task currently records the completion and advances from the old date — which may still land in the past (already fixed by the fast-forward in `_nextDueDate`) but the user sees the overdue badge until they interact. Worse, it feels like completing two occurrences at once. The fix: automatically advance the task's due date to the current active occurrence on app startup, so the user always sees today's task. Additionally, converting a completed one-off task to recurring doesn't re-open it — the user expects it to schedule the next occurrence.

## Current state

### Frontend — `lib/core/database/daos/tasks_dao.dart`

**`updateTask` (lines 86–93)** — simple write, no awareness of status or recurrence:
```dart
Future<void> updateTask(TasksCompanion companion) async {
  final now = DateTime.now();
  final updatedCompanion = companion.copyWith(
    updatedAt: Value(now),
    isDirty: const Value(true),
  );
  await (update(tasks)..where((t) => t.id.equals(companion.id.value))).write(updatedCompanion);
}
```

**`completeTask` (lines 118–169)** — records completion, calculates next due from `task.dueDate ?? now`:
```dart
final recurrence = task.recurrence;
if (recurrence != null) {
  nextDue = _nextDueDate(
    from: task.dueDate ?? now,
    recurrence: recurrence,
  );
  ...
}
```

**`_nextDueDate` (lines 252–291)** — already has a fast-forward to today:
```dart
if (raw.isBefore(today)) {
  raw = today;
}
```
This means `_nextDueDate` never returns a date in the past, but it doesn't advance `task.dueDate` in the database — the row's `dueDate` stays stale until the user completes it.

### Backend — `backend/internal/tasks/service.go`

**`CompleteTask` (lines 135–191)** — records completion with `task.DueDate.Time`, then calls `calculateNextDueDate(task.DueDate.Time, ...)`:
```go
if task.Recurrence.Valid && task.Recurrence.String != "" && task.DueDate.Valid {
  nextDue, ok := calculateNextDueDate(task.DueDate.Time, task.Recurrence.String)
  ...
}
```

**`UpdateTask` (lines 80–123)** — pure field update, no awareness of done→recurring transition.

**`calculateNextDueDate` (lines 261–278)** — no fast-forward to today (unlike the Dart version).

### Test patterns — `test/core/database/daos/tasks_dao_test.dart`

Tests use `AppDatabase.test()` with an in-memory SQLite, wire `completionsDao`, insert via `db.tasksDao.insertTask(TaskData(...))`, and query via `db.select(db.tasks).get()`. All `TaskData` constructors include every field (no optionals). Match this pattern exactly.

## Commands you will need

| Purpose   | Command                                                        | Expected on success    |
|-----------|----------------------------------------------------------------|------------------------|
| Analyze   | `dart analyze lib/core/database/daos/tasks_dao.dart`           | No issues found        |
| Test (Dart) | `flutter test test/core/database/daos/tasks_dao_test.dart`   | All pass               |
| Test (Go) | `cd backend && go test ./internal/tasks/...`                   | PASS                   |

## Scope

**In scope** (the only files you should modify):
- `lib/core/database/daos/tasks_dao.dart` — add `catchUpRecurringTasks`, update `updateTask` and `completeTask`
- `lib/features/tasks/data/local/tasks_local_repository.dart` — expose `catchUpRecurringTasks`
- `lib/features/tasks/data/tasks_repository.dart` — call catch-up on construction
- `test/core/database/daos/tasks_dao_test.dart` — new tests
- `backend/internal/tasks/service.go` — update `CompleteTask` and `UpdateTask`
- `backend/internal/tasks/service_test.go` — new tests

**Out of scope** (do NOT touch, even though they look related):
- `lib/core/database/daos/task_completions_dao.dart` — no changes needed
- `lib/features/tasks/presentation/` — no UI changes
- `backend/db/migrations/` — no schema changes
- `backend/internal/sync/` — sync layer is unaffected; dirty flags propagate naturally
- The `_nextDueDate` fast-forward logic (lines 286–288) — keep it as-is; it's a safety net, not the primary catch-up mechanism

## Git workflow

- Branch: `feat/task-recurrence-catchup`
- Commit per step or per logical unit; message style: `feat(tasks): description` (Conventional Commits — match repo convention)
- Do NOT push or open a PR unless instructed

## Steps

### Step 1: Add `catchUpRecurringTasks` to TasksDao with tests

Add a new method to `lib/core/database/daos/tasks_dao.dart` that queries all open recurring tasks with a past due date and advances them to the current active occurrence. Add tests first.

**1a. Write the tests** in `test/core/database/daos/tasks_dao_test.dart`:

```dart
test('catchUpRecurringTasks advances overdue daily task to today', () async {
  final db = AppDatabase.test();
  db.tasksDao.completionsDao = db.taskCompletionsDao;
  final today = DateTime.now();
  final todayStart = DateTime(today.year, today.month, today.day);
  final twoDaysAgo = todayStart.subtract(const Duration(days: 2));

  await db.tasksDao.insertTask(TaskData(
    id: 'catchup-1',
    userId: 'user-1',
    noteId: 'note-1',
    title: 'Daily standup',
    status: 'open',
    position: 0,
    recurrence: TaskRecurrence.daily,
    dueDate: twoDaysAgo,
    completedAt: null,
    createdAt: twoDaysAgo,
    updatedAt: twoDaysAgo,
    deletedAt: null,
    isDirty: true,
  ));

  await db.tasksDao.catchUpRecurringTasks();

  final tasks = await db.select(db.tasks).get();
  expect(tasks, hasLength(1));
  final task = tasks.single;
  expect(task.status, 'open');
  expect(task.dueDate, todayStart);
  expect(task.isDirty, isTrue);

  // No completion records — the missed days are just skipped
  final completions = await db.select(db.localTaskCompletions).get();
  expect(completions, isEmpty);

  await db.close();
});

test('catchUpRecurringTasks does not touch tasks already due today or in the future', () async {
  final db = AppDatabase.test();
  final today = DateTime.now();
  final todayStart = DateTime(today.year, today.month, today.day);

  await db.tasksDao.insertTask(TaskData(
    id: 'catchup-2',
    userId: 'user-1',
    noteId: 'note-1',
    title: 'Already current',
    status: 'open',
    position: 0,
    recurrence: TaskRecurrence.daily,
    dueDate: todayStart,
    completedAt: null,
    createdAt: todayStart,
    updatedAt: todayStart,
    deletedAt: null,
    isDirty: false,
  ));

  await db.tasksDao.catchUpRecurringTasks();

  final tasks = await db.select(db.tasks).get();
  final task = tasks.single;
  expect(task.dueDate, todayStart);
  expect(task.isDirty, isFalse); // Not touched

  await db.close();
});

test('catchUpRecurringTasks does not touch non-recurring tasks', () async {
  final db = AppDatabase.test();
  final today = DateTime.now();
  final todayStart = DateTime(today.year, today.month, today.day);
  final yesterday = todayStart.subtract(const Duration(days: 1));

  await db.tasksDao.insertTask(TaskData(
    id: 'catchup-3',
    userId: 'user-1',
    noteId: 'note-1',
    title: 'One-off overdue',
    status: 'open',
    position: 0,
    recurrence: null,
    dueDate: yesterday,
    completedAt: null,
    createdAt: yesterday,
    updatedAt: yesterday,
    deletedAt: null,
    isDirty: false,
  ));

  await db.tasksDao.catchUpRecurringTasks();

  final tasks = await db.select(db.tasks).get();
  final task = tasks.single;
  expect(task.dueDate, yesterday); // Unchanged
  expect(task.isDirty, isFalse);

  await db.close();
});
```

**1b. Run tests to confirm they fail:**

Run: `flutter test test/core/database/daos/tasks_dao_test.dart`
Expected: Compile error — `catchUpRecurringTasks` does not exist.

**1c. Implement `catchUpRecurringTasks`** in `lib/core/database/daos/tasks_dao.dart`, after the `reorderTasksBatch` method (around line 236):

```dart
/// Advances overdue recurring tasks to the current active occurrence.
///
/// For each open task with a recurrence rule and a due date in the past,
/// walks the recurrence forward until the next occurrence would be in
/// the future, and writes the latest "arrived" occurrence as the new
/// due date. No completion records are created — the missed days are
/// silently skipped.
///
/// Call once at app startup. The method is idempotent — calling it
/// multiple times in the same day is harmless (the loop exits
/// immediately when `dueDate >= today`).
Future<void> catchUpRecurringTasks() async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final query = select(tasks)
    ..where((t) => t.status.equals('open'))
    ..where((t) => t.dueDate.isSmallerThanValue(today))
    ..where((t) => t.recurrence.isNotNull())
    ..where((t) => t.deletedAt.isNull());

  final overdue = await query.get();
  if (overdue.isEmpty) return;

  await transaction(() async {
    for (final task in overdue) {
      final recurrence = task.recurrence!;
      var currentDue = task.dueDate!;

      // Walk forward until the next occurrence would be in the future.
      var next = _nextDueDate(from: currentDue, recurrence: recurrence);
      while (next != null && next.isBefore(today)) {
        currentDue = next;
        next = _nextDueDate(from: currentDue, recurrence: recurrence);
      }
      // If next == today, that's the active occurrence.
      if (next != null && next.isAtSameMomentAs(today)) {
        currentDue = next;
      }

      if (currentDue != task.dueDate) {
        await (update(tasks)..where((t) => t.id.equals(task.id))).write(
          TasksCompanion(
            dueDate: Value(currentDue),
            updatedAt: Value(now),
            isDirty: const Value(true),
          ),
        );
      }
    }
  });
}
```

**1d. Run tests:**

Run: `flutter test test/core/database/daos/tasks_dao_test.dart`
Expected: All pass.

**Verify**: `dart analyze lib/core/database/daos/tasks_dao.dart` → No issues found

**1e. Commit:**
```bash
git add lib/core/database/daos/tasks_dao.dart test/core/database/daos/tasks_dao_test.dart
git commit -m "feat(tasks): add catchUpRecurringTasks to TasksDao"
```

---

### Step 2: Update `updateTask` to re-open done→recurring transitions

When a user adds a recurrence to a completed task, the task should re-open with the next due date calculated from `completedAt` (or `dueDate`, or now).

**2a. Write the test** in `test/core/database/daos/tasks_dao_test.dart`:

```dart
test('adding recurrence to a completed task re-opens it with next due date', () async {
  final db = AppDatabase.test();
  db.tasksDao.completionsDao = db.taskCompletionsDao;
  final today = DateTime.now();
  final todayStart = DateTime(today.year, today.month, today.day);
  final completedAt = todayStart.subtract(const Duration(hours: 2));

  await db.tasksDao.insertTask(TaskData(
    id: 'reopen-1',
    userId: 'user-1',
    noteId: 'note-1',
    title: 'Was one-off',
    status: 'done',
    position: 0,
    recurrence: null,
    dueDate: todayStart,
    completedAt: completedAt,
    createdAt: todayStart,
    updatedAt: todayStart,
    deletedAt: null,
    isDirty: false,
  ));

  await db.tasksDao.updateTask(TasksCompanion(
    id: const Value('reopen-1'),
    recurrence: const Value(TaskRecurrence.daily),
  ));

  final tasks = await db.select(db.tasks).get();
  final task = tasks.single;
  expect(task.status, 'open');
  expect(task.completedAt, isNull);
  expect(task.recurrence, TaskRecurrence.daily);
  // Next due from completedAt (today - 2h) → daily → today.
  // But _nextDueDate fast-forwards past dates to today, so either today or tomorrow is valid
  // depending on the completedAt time. The key assertion: it's re-opened with a future-or-today date.
  expect(task.dueDate!.isAfter(todayStart.subtract(const Duration(days: 1))), isTrue);
  expect(task.isDirty, isTrue);

  await db.close();
});
```

**2b. Run to confirm it fails:**

Run: `flutter test test/core/database/daos/tasks_dao_test.dart`
Expected: FAIL — `updateTask` does not check status or re-open.

**2c. Update `updateTask`** in `lib/core/database/daos/tasks_dao.dart` (replace lines 86–93):

```dart
Future<void> updateTask(TasksCompanion companion) async {
  final now = DateTime.now();
  await transaction(() async {
    var updatedCompanion = companion.copyWith(
      updatedAt: Value(now),
      isDirty: const Value(true),
    );

    // If the task is currently completed and the user is adding a
    // recurrence rule, re-open it for the next occurrence.
    if (companion.recurrence.present && companion.recurrence.value != null) {
      final current = await (select(tasks)
            ..where((t) => t.id.equals(companion.id.value)))
          .getSingleOrNull();

      if (current != null && current.status == 'done') {
        final recurrence = companion.recurrence.value!;
        final baseTime = current.completedAt ?? current.dueDate ?? now;
        final nextDue = _nextDueDate(from: baseTime, recurrence: recurrence);
        if (nextDue != null) {
          updatedCompanion = updatedCompanion.copyWith(
            status: const Value('open'),
            dueDate: Value(nextDue),
            completedAt: const Value(null),
          );
        }
      }
    }

    await (update(tasks)..where((t) => t.id.equals(companion.id.value)))
        .write(updatedCompanion);
  });
}
```

**2d. Run tests:**

Run: `flutter test test/core/database/daos/tasks_dao_test.dart`
Expected: All pass.

**Verify**: `dart analyze lib/core/database/daos/tasks_dao.dart` → No issues found

**2e. Commit:**
```bash
git add lib/core/database/daos/tasks_dao.dart test/core/database/daos/tasks_dao_test.dart
git commit -m "feat(tasks): re-open completed task when recurrence is added"
```

---

### Step 3: Update `completeTask` to catch up before completing

The existing `completeTask` uses `task.dueDate ?? now` as the base for `_nextDueDate`. If the task is 3 days overdue (daily), `_nextDueDate` already fast-forwards to today thanks to the `if (raw.isBefore(today)) raw = today` guard. But the completion is recorded against the stale `task.dueDate`. We need to catch up the due date first so the completion is recorded against the active occurrence.

**3a. Write the test** in `test/core/database/daos/tasks_dao_test.dart`:

```dart
test('completing a 3-day overdue daily task completes today and advances to tomorrow', () async {
  final db = AppDatabase.test();
  db.tasksDao.completionsDao = db.taskCompletionsDao;
  final today = DateTime.now();
  final todayStart = DateTime(today.year, today.month, today.day);
  final threeDaysAgo = todayStart.subtract(const Duration(days: 3));

  await db.tasksDao.insertTask(TaskData(
    id: 'complete-catchup-1',
    userId: 'user-1',
    noteId: 'note-1',
    title: 'Overdue 3 days',
    status: 'open',
    position: 0,
    recurrence: TaskRecurrence.daily,
    dueDate: threeDaysAgo,
    completedAt: null,
    createdAt: threeDaysAgo,
    updatedAt: threeDaysAgo,
    deletedAt: null,
    isDirty: true,
  ));

  final nextDue = await db.tasksDao.completeTask('complete-catchup-1');

  // Should advance to tomorrow (today + 1)
  final tomorrowStart = todayStart.add(const Duration(days: 1));
  expect(nextDue, tomorrowStart);

  // Task row: open, due tomorrow
  final tasks = await db.select(db.tasks).get();
  final task = tasks.single;
  expect(task.status, 'open');
  expect(task.dueDate, tomorrowStart);

  // Exactly 1 completion record
  final completions = await db.select(db.localTaskCompletions).get();
  expect(completions, hasLength(1));

  await db.close();
});
```

**3b. Run to confirm it fails:**

Run: `flutter test test/core/database/daos/tasks_dao_test.dart`
Expected: FAIL — `completeTask` computes from 3 days ago, `_nextDueDate` fast-forwards to today (not tomorrow).

**3c. Update `completeTask`** in `lib/core/database/daos/tasks_dao.dart` (replace lines 118–169):

```dart
Future<DateTime?> completeTask(String id) async {
  final task = await (select(tasks)..where((t) => t.id.equals(id)))
      .getSingleOrNull();
  if (task == null) return null;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  DateTime? nextDue;

  await transaction(() async {
    // 1. If recurring and overdue, catch up to the current active date.
    final recurrence = task.recurrence;
    var taskDueDate = task.dueDate;
    if (recurrence != null && taskDueDate != null && taskDueDate.isBefore(today)) {
      var next = _nextDueDate(from: taskDueDate, recurrence: recurrence);
      while (next != null && next.isBefore(today)) {
        taskDueDate = next;
        next = _nextDueDate(from: taskDueDate, recurrence: recurrence);
      }
      if (next != null && next.isAtSameMomentAs(today)) {
        taskDueDate = next;
      }
    }

    // 2. Record the completion event.
    if (completionsDao != null) {
      await completionsDao!.recordCompletion(
        taskId: task.id,
        userId: task.userId,
        completedAt: now,
      );
    }

    // 3. If recurring, schedule the next occurrence on the same row.
    if (recurrence != null) {
      nextDue = _nextDueDate(
        from: taskDueDate ?? now,
        recurrence: recurrence,
      );
      if (nextDue != null) {
        await (update(tasks)..where((t) => t.id.equals(id))).write(
          TasksCompanion(
            dueDate: Value(nextDue),
            completedAt: const Value(null),
            status: const Value('open'),
            updatedAt: Value(now),
            isDirty: const Value(true),
          ),
        );
        return;
      }
    }

    // 4. Non-recurring or unsupported recurrence: mark completed.
    await (update(tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        status: const Value('done'),
        completedAt: Value(now),
        updatedAt: Value(now),
        isDirty: const Value(true),
      ),
    );
  });

  return nextDue;
}
```

**3d. Run tests:**

Run: `flutter test test/core/database/daos/tasks_dao_test.dart`
Expected: All pass.

**Verify**: `dart analyze lib/core/database/daos/tasks_dao.dart` → No issues found

**3e. Commit:**
```bash
git add lib/core/database/daos/tasks_dao.dart test/core/database/daos/tasks_dao_test.dart
git commit -m "feat(tasks): catch up overdue recurring task before completing"
```

---

### Step 4: Wire catch-up into repository initialization

Call `catchUpRecurringTasks` once when the `TasksRepository` is constructed (fire-and-forget). Do NOT call it inside stream getters — it would fire on every subscription.

**4a. Expose in `TasksLocalRepository`** — add to `lib/features/tasks/data/local/tasks_local_repository.dart`:

```dart
Future<void> catchUpRecurringTasks() => _dao.catchUpRecurringTasks();
```

**4b. Call from `TasksRepository` constructor** — modify `lib/features/tasks/data/tasks_repository.dart`:

```dart
class TasksRepository implements ITasksRepository {
  TasksRepository(this._local) {
    // Fire-and-forget: advance overdue recurring tasks to today.
    // Errors are swallowed — the fast-forward in _nextDueDate is a safety net.
    _local.catchUpRecurringTasks();
  }
  ...
}
```

**4c. Verify:**

Run: `flutter test`
Expected: All pass.

Run: `dart analyze lib/features/tasks/data/local/tasks_local_repository.dart lib/features/tasks/data/tasks_repository.dart`
Expected: No issues found.

**4d. Commit:**
```bash
git add lib/features/tasks/data/local/tasks_local_repository.dart lib/features/tasks/data/tasks_repository.dart
git commit -m "feat(tasks): trigger catch-up on TasksRepository initialization"
```

---

### Step 5: Update Go backend `CompleteTask` with catch-up

Apply the same catch-up logic to the Go backend so API callers and sync get correct behavior.

**5a. Write the test** in `backend/internal/tasks/service_test.go`:

```go
func TestCalculateNextDueDateCatchUp(t *testing.T) {
	// Simulates a 3-day overdue daily task. Walking from 3 days ago:
	// day-3 → day-2 → day-1 → today → tomorrow.
	// The catch-up loop should stop at today, then calculateNextDueDate
	// from today gives tomorrow.
	now := time.Now().UTC()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
	threeDaysAgo := today.AddDate(0, 0, -3)

	// Walk forward like CompleteTask does
	taskDueDate := threeDaysAgo
	nextDue, ok := calculateNextDueDate(taskDueDate, "daily")
	for ok && (nextDue.Before(today) || nextDue.Equal(today)) {
		taskDueDate = nextDue
		nextDue, ok = calculateNextDueDate(taskDueDate, "daily")
	}

	if !taskDueDate.Equal(today) {
		t.Errorf("catch-up taskDueDate = %v, want %v", taskDueDate, today)
	}
	if !ok {
		t.Fatal("expected ok=true for next due after today")
	}
	expectedNext := today.AddDate(0, 0, 1)
	if !nextDue.Equal(expectedNext) {
		t.Errorf("next due after catch-up = %v, want %v", nextDue, expectedNext)
	}
}
```

**5b. Run to confirm it passes** (this tests the pure function, should pass already):

Run: `cd backend && go test ./internal/tasks/... -run TestCalculateNextDueDateCatchUp -v`
Expected: PASS

**5c. Update `CompleteTask`** in `backend/internal/tasks/service.go`. Replace lines 135–191 with:

```go
func (s *Service) CompleteTask(ctx context.Context, userID, id pgtype.UUID) (sqlcgen.Task, error) {
	task, err := s.repo.GetTaskByID(ctx, id, userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return sqlcgen.Task{}, ErrTaskNotFound
		}
		return sqlcgen.Task{}, err
	}

	// Catch up: if recurring and overdue, walk forward to the current active date.
	taskDueDate := task.DueDate.Time
	if task.Recurrence.Valid && task.Recurrence.String != "" && task.DueDate.Valid {
		now := time.Now().UTC()
		today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)

		nextDue, ok := calculateNextDueDate(taskDueDate, task.Recurrence.String)
		for ok && (nextDue.Before(today) || nextDue.Equal(today)) {
			taskDueDate = nextDue
			nextDue, ok = calculateNextDueDate(taskDueDate, task.Recurrence.String)
		}
	}

	// Record completion with the caught-up due date.
	dueDateParam := pgtype.Date{}
	if task.DueDate.Valid {
		dueDateParam = pgtype.Date{Time: taskDueDate, Valid: true}
	}
	if _, err := s.repo.CreateTaskCompletion(ctx, id, dueDateParam); err != nil {
		return sqlcgen.Task{}, err
	}

	// Recurring task: schedule next occurrence from caught-up date.
	if task.Recurrence.Valid && task.Recurrence.String != "" && task.DueDate.Valid {
		nextDue, ok := calculateNextDueDate(taskDueDate, task.Recurrence.String)
		if ok {
			task, err = s.repo.UpdateTask(ctx, sqlcgen.UpdateTaskParams{
				ID:         id,
				UserID:     userID,
				SetDueDate: pgtype.Bool{Bool: true, Valid: true},
				DueDate:    pgtype.Date{Time: nextDue, Valid: true},
				SetStatus:  pgtype.Bool{Bool: true, Valid: true},
				Status:     pgtype.Text{String: "open", Valid: true},
			})
			if err != nil {
				if errors.Is(err, pgx.ErrNoRows) {
					return sqlcgen.Task{}, ErrTaskNotFound
				}
				return sqlcgen.Task{}, err
			}
			return task, nil
		}
	}

	// Non-recurring: mark completed.
	now := time.Now()
	task, err = s.repo.UpdateTask(ctx, sqlcgen.UpdateTaskParams{
		ID:             id,
		UserID:         userID,
		SetStatus:      pgtype.Bool{Bool: true, Valid: true},
		Status:         pgtype.Text{String: "done", Valid: true},
		SetCompletedAt: pgtype.Bool{Bool: true, Valid: true},
		CompletedAt:    pgtype.Timestamptz{Time: now, Valid: true},
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return sqlcgen.Task{}, ErrTaskNotFound
		}
		return sqlcgen.Task{}, err
	}
	return task, nil
}
```

**5d. Run Go tests:**

Run: `cd backend && go test ./internal/tasks/... -v`
Expected: PASS

**5e. Commit:**
```bash
git add backend/internal/tasks/service.go backend/internal/tasks/service_test.go
git commit -m "feat(backend): catch up overdue recurring task before completing"
```

---

### Step 6: Update Go backend `UpdateTask` for done→recurring transition

When a completed task is updated with a recurrence rule via the API, re-open it.

**6a. Update `UpdateTask`** in `backend/internal/tasks/service.go`. The current function (lines 80–123) builds `arg` and calls `s.repo.UpdateTask`. Insert the transition logic after `arg` is built but before the repo call. Replace the entire function:

```go
func (s *Service) UpdateTask(ctx context.Context, userID, id pgtype.UUID, opts UpdateTaskOpts) (sqlcgen.Task, error) {
	if err := opts.Validate(); err != nil {
		return sqlcgen.Task{}, err
	}

	// If adding recurrence to a completed task, re-open it.
	if opts.Recurrence != nil {
		existing, err := s.repo.GetTaskByID(ctx, id, userID)
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return sqlcgen.Task{}, err
		}
		if err == nil && existing.Status == "done" {
			baseTime := time.Now().UTC()
			if existing.CompletedAt.Valid {
				baseTime = existing.CompletedAt.Time
			} else if existing.DueDate.Valid {
				baseTime = existing.DueDate.Time
			}
			nextDue, ok := calculateNextDueDate(baseTime, *opts.Recurrence)
			if ok {
				statusOpen := "open"
				opts.Status = &statusOpen
				opts.DueDate = &nextDue
				// ClearDueDate must be false since we're setting a due date
				opts.ClearDueDate = false
			}
		}
	}

	arg := sqlcgen.UpdateTaskParams{
		ID:     id,
		UserID: userID,
	}
	if opts.Title != nil {
		arg.SetTitle = pgtype.Bool{Bool: true, Valid: true}
		arg.Title = pgtype.Text{String: *opts.Title, Valid: true}
	}
	if opts.Status != nil {
		arg.SetStatus = pgtype.Bool{Bool: true, Valid: true}
		arg.Status = pgtype.Text{String: *opts.Status, Valid: true}
	}
	if opts.DueDate != nil {
		arg.SetDueDate = pgtype.Bool{Bool: true, Valid: true}
		arg.DueDate = pgtype.Date{Time: *opts.DueDate, Valid: true}
	} else if opts.ClearDueDate {
		arg.SetDueDate = pgtype.Bool{Bool: true, Valid: true}
	}
	if opts.Recurrence != nil {
		arg.SetRecurrence = pgtype.Bool{Bool: true, Valid: true}
		arg.Recurrence = pgtype.Text{String: *opts.Recurrence, Valid: true}
	} else if opts.ClearRecurrence {
		arg.SetRecurrence = pgtype.Bool{Bool: true, Valid: true}
	}
	if opts.Position != nil {
		arg.SetPosition = pgtype.Bool{Bool: true, Valid: true}
		arg.Position = pgtype.Int4{Int32: int32(*opts.Position), Valid: true}
	}

	// Clear completed_at when re-opening
	if opts.Status != nil && *opts.Status == "open" {
		arg.SetCompletedAt = pgtype.Bool{Bool: true, Valid: true}
		// CompletedAt stays zero-value (NULL)
	}

	task, err := s.repo.UpdateTask(ctx, arg)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return sqlcgen.Task{}, ErrTaskNotFound
		}
		return sqlcgen.Task{}, err
	}
	return task, nil
}
```

**6b. Run Go tests:**

Run: `cd backend && go test ./internal/tasks/... -v`
Expected: PASS

**6c. Commit:**
```bash
git add backend/internal/tasks/service.go
git commit -m "feat(backend): re-open completed task when recurrence is added"
```

## Test plan

- New Dart tests in `test/core/database/daos/tasks_dao_test.dart`:
  - `catchUpRecurringTasks advances overdue daily task to today`
  - `catchUpRecurringTasks does not touch tasks already due today or in the future`
  - `catchUpRecurringTasks does not touch non-recurring tasks`
  - `adding recurrence to a completed task re-opens it with next due date`
  - `completing a 3-day overdue daily task completes today and advances to tomorrow`
- New Go test in `backend/internal/tasks/service_test.go`:
  - `TestCalculateNextDueDateCatchUp`
- Pattern: match existing `AppDatabase.test()` setup in `test/core/database/daos/tasks_dao_test.dart`
- Verification: `flutter test test/core/database/daos/tasks_dao_test.dart` → all pass (9 tests: 4 existing + 5 new)
- Verification: `cd backend && go test ./internal/tasks/...` → PASS

## Done criteria

- [ ] `dart analyze lib/core/database/daos/tasks_dao.dart` exits 0
- [ ] `flutter test test/core/database/daos/tasks_dao_test.dart` exits 0; 5 new tests exist and pass
- [ ] `cd backend && go test ./internal/tasks/...` exits 0; 1 new test exists and passes
- [ ] No files outside the in-scope list are modified (`git diff --name-only`)
- [ ] A daily task due 3 days ago, after catch-up, has `dueDate == today`
- [ ] Completing that caught-up task produces `dueDate == tomorrow` and exactly 1 completion record
- [ ] A completed one-off task, after adding daily recurrence, has `status == open` and `dueDate != null`

## STOP conditions

Stop and report back (do not improvise) if:

- The code at the locations in "Current state" doesn't match the excerpts (the codebase has drifted since this plan was written at `8f5e652`).
- A step's verification fails twice after a reasonable fix attempt.
- The fix requires touching an out-of-scope file.
- `_nextDueDate`'s fast-forward logic (lines 286–288) has been removed or changed — the catch-up logic depends on it as a safety net.
- The `TasksCompanion.copyWith` method does not support `status`, `dueDate`, or `completedAt` fields — Drift generates these, but if the schema changed, this would break.

## Maintenance notes

- The backend `calculateNextDueDate` in `service.go` still has no fast-forward to today (unlike the Dart version). This is fine because the backend only runs catch-up inside `CompleteTask`, not as a background job. If a background catch-up job is ever added to the backend, port the Dart `catchUpRecurringTasks` logic.
- If new recurrence types are added (e.g. `biweekly`, `yearly`), they must be handled in both `_nextDueDate` (Dart) and `calculateNextDueDate` (Go). The catch-up loops don't need changes — they're generic.
- The `catchUpRecurringTasks` call in the `TasksRepository` constructor is fire-and-forget. If it throws, the error is silently swallowed. This is intentional — the `_nextDueDate` fast-forward is a safety net for the same scenario. If stricter error handling is needed later, add a `.catchError` with logging.
- Sync: dirty flags are set correctly in all paths, so the sync layer will propagate catch-up date changes to the backend on the next push. No sync code changes needed.
