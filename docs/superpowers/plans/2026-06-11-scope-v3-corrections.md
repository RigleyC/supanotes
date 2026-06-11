# Scope V3 Corrections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring backend and Flutter implementation back in line with the revised v1 scope in `.docs/notes-agent-scope-v3.md`.

**Architecture:** Fix the database contract first, then regenerate sqlc and repair backend services around the new contract. Frontend work stays separate: Riverpod compliance, sync payload alignment, and offline gating should not be mixed with backend schema changes.

**Tech Stack:** Go + Echo + sqlc + pgx + golang-migrate + PostgreSQL/pgvector; Flutter + Riverpod 3 + Drift + Dio + Go Router + super_editor.

---

## Scope Decisions Already Resolved

- Task status is only `open` or `done`.
- Repeating tasks reuse the same task row, create a `task_completions` row, and advance `due_date`.
- `tasks.completed_at` means most recent completion timestamp.
- Overdue is derived from `due_date`; tasks do not expire automatically.
- `task_completions.due_date` stores the due date of the completed occurrence.
- Telegram identity uses `message.from.id` as `telegram_user_id`; `telegram_chat_id` is only the delivery target.
- Telegram progressive streaming is required in v1.
- Routines use days/time/enabled as the public contract; cron is internal only if needed.
- Sync v1 includes notes, tasks, contexts, tags, note tags, note links, and task completions.
- Sync pagination/cursor is deferred.
- FAB creates a new note in v1.
- Inbox organization stays in v1, but `create_section` is deferred.
- Riverpod codegen is not allowed; feature providers should default to `.autoDispose`; shared async loading/error should use `AsyncValue`.
- Online-only features need a simple offline-disabled state.

---

## File Structure Map

### Backend Schema And sqlc

- Modify: `backend/db/migrations/000007_telegram.up.sql`
- Modify: `backend/db/migrations/000007_telegram.down.sql`
- Modify: `backend/db/migrations/000011_scope_gaps.up.sql`
- Modify: `backend/db/migrations/000011_scope_gaps.down.sql`
- Modify: `backend/db/queries/tasks.sql`
- Modify: `backend/db/queries/sync.sql`
- Generated after sqlc: `backend/internal/db/sqlcgen/*.go`

### Backend Services

- Modify: `backend/internal/tasks/service.go`
- Modify: `backend/internal/tasks/repository.go`
- Modify: `backend/internal/sync/service.go`
- Modify: `backend/internal/sync/repository.go`
- Modify: `backend/internal/gateway/handler.go`
- Modify: `backend/internal/gateway/repository.go`
- Modify: `backend/internal/gateway/telegram_client.go`
- Modify: `backend/internal/agent/loop.go`
- Modify: `backend/internal/agent/handler.go`
- Modify: `backend/internal/routines/service.go`
- Modify: `backend/internal/routines/repository.go`
- Modify: `backend/internal/routines/runner.go`
- Modify: `backend/internal/notes/service.go`
- Modify: `backend/internal/notes/repository.go`
- Modify: `backend/internal/notes/handler.go`
- Modify: `backend/cmd/server/main.go`

### Backend Tests And Config

- Modify/Create: `backend/internal/tasks/service_test.go`
- Create: `backend/internal/gateway/handler_test.go`
- Modify/Create: `backend/internal/sync/service_test.go`
- Modify/Create: `backend/internal/routines/service_test.go`
- Modify/Create: `backend/internal/notes/service_test.go`
- Modify: `backend/Dockerfile`
- Modify/Create: `backend/.env.example`

### Flutter

- Modify: `pubspec.yaml`
- Modify: `pubspec.lock` after `flutter pub get`
- Modify: feature providers under `lib/features/**`
- Modify: `lib/core/sync/sync_mapper.dart`
- Modify: `lib/core/sync/sync_service.dart`
- Modify: `lib/core/sync/sync_repository.dart`
- Modify: `lib/core/sync/connectivity_monitor.dart` only if needed
- Modify/Create: shared offline-disabled widget under `lib/shared/widgets/`
- Modify online screens under `lib/features/agent`, `lib/features/search`, `lib/features/routines`, `lib/features/settings`, `lib/features/telegram`

---

## Task 1: Fix Schema Contract Before Code

**Files:**
- Modify: `backend/db/migrations/000007_telegram.up.sql`
- Modify: `backend/db/migrations/000007_telegram.down.sql`
- Modify: `backend/db/migrations/000011_scope_gaps.up.sql`
- Modify: `backend/db/migrations/000011_scope_gaps.down.sql`
- Modify: `backend/db/queries/tasks.sql`

- [ ] **Step 1: Make Telegram schema match the v1 identity contract**

In `backend/db/migrations/000007_telegram.up.sql`, ensure `telegram_links` has `telegram_user_id` and keeps `telegram_chat_id` for delivery:

```sql
CREATE TABLE telegram_links (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    telegram_user_id  BIGINT NOT NULL,
    telegram_chat_id  BIGINT NOT NULL,
    telegram_username TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id),
    UNIQUE(telegram_user_id)
);
```

In `backend/db/migrations/000007_telegram.down.sql`, drop both Telegram tables:

```sql
DROP TABLE IF EXISTS telegram_link_codes;
DROP TABLE IF EXISTS telegram_links;
```

- [ ] **Step 2: Rewrite the broken Telegram part of `000011_scope_gaps`**

Remove references to `telegram_chats` and `tl.chat_id`. Keep the migration id, but make it idempotent for already-migrated databases:

```sql
ALTER TABLE telegram_links
  ADD COLUMN IF NOT EXISTS telegram_user_id BIGINT;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM telegram_links
    WHERE telegram_user_id IS NULL
  ) THEN
    RAISE NOTICE 'telegram_user_id is NULL for existing rows; relink affected Telegram accounts';
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS telegram_links_telegram_user_id_idx
  ON telegram_links (telegram_user_id)
  WHERE telegram_user_id IS NOT NULL;
```

- [ ] **Step 3: Fix task status and completion schema**

In `backend/db/migrations/000011_scope_gaps.up.sql`, make the task status check exactly `open|done`:

```sql
UPDATE tasks SET status = 'open' WHERE status IN ('pending', 'in_progress');
UPDATE tasks SET status = 'done' WHERE status = 'completed';

ALTER TABLE tasks
  DROP CONSTRAINT IF EXISTS chk_tasks_status;

ALTER TABLE tasks
  ADD CONSTRAINT chk_tasks_status
  CHECK (status IN ('open', 'done'));
```

Ensure `completed_at` is idempotent:

```sql
ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;
```

Ensure `task_completions` has `due_date` and no `status` dependency:

```sql
ALTER TABLE task_completions
  ADD COLUMN IF NOT EXISTS due_date DATE;

ALTER TABLE task_completions
  DROP COLUMN IF EXISTS status;
```

- [ ] **Step 4: Fix task sqlc queries**

In `backend/db/queries/tasks.sql`, replace `CreateTaskCompletion` and completed count:

```sql
-- name: CreateTaskCompletion :one
INSERT INTO task_completions (task_id, completed_at, due_date)
VALUES ($1, NOW(), $2)
RETURNING *;

-- name: CountCompletedTasks :one
SELECT COUNT(*) FROM tasks WHERE user_id = $1 AND deleted_at IS NULL AND status = 'done';
```

- [ ] **Step 5: Run sqlc generation**

Run:

```powershell
cd D:\projects\supanotes\backend
make sqlc
```

Expected: generated files under `backend/internal/db/sqlcgen` update without errors.

- [ ] **Step 6: Run backend tests**

Run:

```powershell
cd D:\projects\supanotes\backend
go test ./...
```

Expected: tests compile. Some service tests may fail until Task 2 is complete; compile errors from generated query signatures must be fixed before moving on.

---

## Task 2: Align Task Completion Service Semantics

**Files:**
- Modify: `backend/internal/tasks/service.go`
- Modify: `backend/internal/tasks/repository.go`
- Modify: `backend/internal/tasks/service_test.go`

- [ ] **Step 1: Add failing tests for non-repeating and repeating completion**

In `backend/internal/tasks/service_test.go`, add tests that assert:

```go
func TestService_CompleteTask_NonRepeatingMarksDone(t *testing.T) {
    // Arrange: open task with nil recurrence and due_date.
    // Act: CompleteTask.
    // Assert: status == "done", completed_at is valid, one completion row is created.
}

func TestService_CompleteTask_RepeatingAdvancesSameTask(t *testing.T) {
    // Arrange: open weekly task due on 2026-06-08.
    // Act: CompleteTask.
    // Assert: same task id, status == "open", due_date == 2026-06-15,
    // completed_at is valid, completion.due_date == 2026-06-08.
}
```

Use the existing test style in `backend/internal/tasks/service_test.go`; do not introduce a new mocking framework.

- [ ] **Step 2: Implement the service behavior**

In `backend/internal/tasks/service.go`, make completion follow this shape:

```go
originalDueDate := task.DueDate
completion, err := s.repo.CreateTaskCompletion(ctx, task.ID, originalDueDate)
if err != nil {
    return sqlcgen.Task{}, err
}

now := time.Now()
if task.Recurrence.Valid {
    nextDueDate := nextRecurrenceDate(originalDueDate, task.Recurrence.String)
    return s.repo.UpdateTask(ctx, userID, task.ID, nil, ptr("open"), &nextDueDate, nil, nil, &now)
}

return s.repo.UpdateTask(ctx, userID, task.ID, nil, ptr("done"), nil, nil, nil, &now)
```

The exact helper names should match the existing service style. Keep recurrence calculation in the task service; do not move it into handlers.

- [ ] **Step 3: Run focused tests**

Run:

```powershell
cd D:\projects\supanotes\backend
go test ./internal/tasks -run CompleteTask -v
```

Expected: new completion tests pass.

- [ ] **Step 4: Commit**

```powershell
git add backend/db/migrations backend/db/queries backend/internal/db/sqlcgen backend/internal/tasks
git commit -m "fix(tasks): align completion contract"
```

---

## Task 3: Complete Sync Contract For Note Tags And Note Links

**Files:**
- Modify: `backend/db/queries/sync.sql`
- Modify: `backend/internal/sync/service.go`
- Modify: `backend/internal/sync/repository.go`
- Modify: `backend/internal/sync/service_test.go`
- Modify: `lib/core/sync/sync_mapper.dart`
- Modify: `lib/core/sync/sync_service.dart`
- Modify: `lib/core/sync/sync_repository.dart`

- [ ] **Step 1: Add backend sync queries**

Add sqlc queries for `note_tags` and `note_links`:

```sql
-- name: GetSyncNoteTags :many
SELECT nt.note_id, nt.tag_id
FROM note_tags nt
JOIN notes n ON n.id = nt.note_id
WHERE n.user_id = $1;

-- name: UpsertNoteTag :exec
INSERT INTO note_tags (note_id, tag_id)
SELECT sqlc.arg('note_id')::uuid, sqlc.arg('tag_id')::uuid
WHERE EXISTS (
  SELECT 1 FROM notes WHERE id = sqlc.arg('note_id')::uuid AND user_id = sqlc.arg('user_id')::uuid
)
ON CONFLICT (note_id, tag_id) DO NOTHING;

-- name: GetSyncNoteLinks :many
SELECT nl.*
FROM note_links nl
JOIN notes n ON n.id = nl.source_id
WHERE n.user_id = $1;
```

For `UpsertNoteLink`, preserve the current note_links schema and ownership checks for both source and target.

- [ ] **Step 2: Extend sync payload**

In `backend/internal/sync/service.go`, extend `SyncPayload`:

```go
type SyncPayload struct {
    Notes           []sqlcgen.Note           `json:"notes"`
    Tasks           []sqlcgen.Task           `json:"tasks"`
    Contexts        []sqlcgen.Context        `json:"contexts"`
    Tags            []sqlcgen.Tag            `json:"tags"`
    NoteTags        []sqlcgen.NoteTag        `json:"note_tags"`
    NoteLinks       []sqlcgen.NoteLink       `json:"note_links"`
    TaskCompletions []sqlcgen.TaskCompletion `json:"task_completions"`
}
```

- [ ] **Step 3: Keep pull non-paginated for v1**

Do not add cursor pagination in this task. Keep `last_synced_at` and `limit` as currently wired. If a hard limit remains, set it high enough to avoid truncation in personal v1 usage.

- [ ] **Step 4: Add frontend/backend shape tests**

Backend test in `backend/internal/sync/service_test.go` should assert that `Pull` includes `note_tags` and `note_links`.

Flutter test in `test/core/sync/sync_service_test.dart` should assert push payload includes:

```dart
expect(payload['note_tags'], isA<List>());
expect(payload['note_links'], isA<List>());
expect(payload['task_completions'], isA<List>());
```

- [ ] **Step 5: Verify**

Run:

```powershell
cd D:\projects\supanotes\backend
make sqlc
go test ./internal/sync ./internal/db/...
cd D:\projects\supanotes
flutter test test/core/sync/sync_service_test.dart
```

Expected: backend sync tests and Flutter sync tests pass.

---

## Task 4: Fix Telegram Link Identity And Progressive Streaming

**Files:**
- Modify: `backend/internal/gateway/handler.go`
- Modify: `backend/internal/gateway/repository.go`
- Modify: `backend/internal/gateway/telegram_client.go`
- Modify: `backend/internal/agent/loop.go`
- Modify: `backend/internal/agent/handler.go`
- Create/Modify: `backend/internal/gateway/handler_test.go`

- [ ] **Step 1: Add Telegram sender to webhook DTO**

In `backend/internal/gateway/handler.go`:

```go
type TgMsg struct {
    MessageID int64   `json:"message_id"`
    Chat      TgChat  `json:"chat"`
    From      *TgUser `json:"from,omitempty"`
    Text      string  `json:"text"`
    Date      int64   `json:"date"`
}

type TgUser struct {
    ID       int64  `json:"id"`
    Username string `json:"username,omitempty"`
}
```

If `From == nil`, ignore the message with `200 OK`.

- [ ] **Step 2: Resolve links by sender id**

Change free-form routing from chat id:

```go
linked, err := h.repo.GetLinkByTelegramUserID(ctx, msg.From.ID)
```

`telegram_chat_id` remains the delivery target and may be updated on each inbound message:

```go
_ = h.repo.UpdateDeliveryChat(ctx, linked, msg.From.ID, msg.Chat.ID, msg.From.Username)
```

- [ ] **Step 3: Store links with sender id on `/start`**

Change `handleStart` to call:

```go
if err := h.repo.CreateLink(ctx, userID, msg.From.ID, msg.Chat.ID, msg.From.Username); err != nil {
    return fmt.Errorf("create link: %w", err)
}
```

- [ ] **Step 4: Add agent streaming bridge**

Introduce a shared stream method on the agent loop:

```go
type StreamEvent struct {
    Delta string
    Done  bool
    Err   error
}

func (l *Loop) ChatStream(ctx context.Context, userID pgtype.UUID, sessionID, userMessage string) (<-chan StreamEvent, error)
```

Then make HTTP SSE and Telegram both use `ChatStream`. Do not duplicate agent loop logic in the gateway.

- [ ] **Step 5: Edit Telegram message progressively**

In `gateway.Handler`, send a placeholder, accumulate deltas, and edit every 600ms:

```go
placeholderID, err := h.bot.SendMessage(msg.Chat.ID, "Pensando...")
if err != nil {
    return c.NoContent(http.StatusOK)
}

ticker := time.NewTicker(600 * time.Millisecond)
defer ticker.Stop()

var accumulated strings.Builder
for {
    select {
    case ev, ok := <-events:
        if !ok || ev.Done {
            h.bot.EditMessageText(msg.Chat.ID, placeholderID, accumulated.String())
            return c.NoContent(http.StatusOK)
        }
        if ev.Err != nil {
            h.bot.EditMessageText(msg.Chat.ID, placeholderID, "Something went wrong. Try again in a moment.")
            return c.NoContent(http.StatusOK)
        }
        accumulated.WriteString(ev.Delta)
    case <-ticker.C:
        if accumulated.Len() > 0 {
            _ = h.bot.EditMessageText(msg.Chat.ID, placeholderID, accumulated.String())
        }
    case <-ctx.Done():
        return c.NoContent(http.StatusOK)
    }
}
```

- [ ] **Step 6: Verify**

Run:

```powershell
cd D:\projects\supanotes\backend
go test ./internal/gateway ./internal/agent
```

Expected: tests cover link by `from.id` and progressive edit calls.

---

## Task 5: Move Routines Public Contract Off cron_expr

**Files:**
- Modify: `backend/db/queries/routines.sql`
- Modify: `backend/internal/routines/service.go`
- Modify: `backend/internal/routines/repository.go`
- Modify: `backend/internal/routines/runner.go`
- Modify: `backend/internal/agent/tools.go`
- Modify: `lib/features/routines/**`

- [ ] **Step 1: Update backend API DTOs**

Daily/weekly update requests should use:

```json
{
  "days_of_week": [1, 2, 3, 4, 5],
  "time_of_day": "08:00",
  "enabled": true
}
```

Weekly must validate exactly one day.

- [ ] **Step 2: Generate cron internally only**

If `robfig/cron` still requires cron expressions, derive them inside runner:

```go
func routineCronExpression(days []int16, timeOfDay time.Time) string {
    minute := timeOfDay.Minute()
    hour := timeOfDay.Hour()
    dayList := joinSmallInts(days)
    return fmt.Sprintf("%d %d * * %s", minute, hour, dayList)
}
```

Do not expose `cron_expr` to Flutter or agent tools.

- [ ] **Step 3: Update agent tools**

Replace `cron_expr` schemas in `set_daily_brief_schedule` and `set_weekly_brief_schedule` with:

```json
{
  "type": "object",
  "properties": {
    "days_of_week": { "type": "array", "items": { "type": "integer" } },
    "time_of_day": { "type": "string", "description": "HH:MM local time" },
    "enabled": { "type": "boolean" }
  }
}
```

- [ ] **Step 4: Verify**

Run:

```powershell
cd D:\projects\supanotes\backend
make sqlc
go test ./internal/routines ./internal/agent
cd D:\projects\supanotes
flutter test test/features/routines
```

Expected: routines are updated by days/time/enabled, and no public DTO requires `cron_expr`.

---

## Task 6: Implement Real Inbox Organization Apply

**Files:**
- Modify: `backend/internal/notes/service.go`
- Modify: `backend/internal/notes/repository.go`
- Modify: `backend/internal/notes/handler.go`
- Modify: `backend/cmd/server/main.go`
- Modify: `lib/features/agent/data/inbox_organize_repository.dart`
- Modify: `lib/features/notes/presentation/widgets/inbox_organize_sheet.dart`

- [ ] **Step 1: Keep v1 actions to three**

Use only:

```json
"append_to_note"
"create_note"
"keep_in_inbox"
```

Do not implement `create_section`.

- [ ] **Step 2: Make apply transactional**

Backend service must run all writes in one transaction:

```go
return s.repo.WithTx(ctx, func(tx Repository) error {
    for _, item := range plan.Items {
        if !item.Accepted || item.Action == "keep_in_inbox" {
            continue
        }
        switch item.Action {
        case "append_to_note":
            if err := tx.AppendContent(ctx, userID, item.TargetNoteID, item.Snippet); err != nil {
                return err
            }
        case "create_note":
            if err := tx.CreateNote(ctx, userID, item.TargetTitle, item.Snippet); err != nil {
                return err
            }
        }
    }
    return tx.RemoveInboxSnippets(ctx, userID, organizedSnippets(plan.Items))
})
```

- [ ] **Step 3: Generate plan through agent/LLM**

Replace deterministic placeholder planning with an agent-backed planning call. The output must be parsed into a strict JSON plan; invalid JSON returns `{ "error": "failed to generate organization plan" }`.

- [ ] **Step 4: Verify rollback**

Add a service test:

```go
func TestApplyOrganization_RollsBackWhenAppendFails(t *testing.T) {
    // Arrange inbox with two snippets, first action create_note, second action append_to_missing_note.
    // Act ApplyOrganization.
    // Assert no new note was committed and inbox content is unchanged.
}
```

Run:

```powershell
cd D:\projects\supanotes\backend
go test ./internal/notes -run Organization -v
```

Expected: plan/apply tests pass.

---

## Task 7: Riverpod Compliance And Offline Gating

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `lib/features/**`
- Modify/Create: `lib/shared/widgets/offline_disabled_view.dart`
- Modify tests under `test/features/**`

- [ ] **Step 1: Remove Riverpod codegen dependencies**

Remove from `pubspec.yaml`:

```yaml
riverpod_annotation: ^4.0.2
riverpod_generator: ^4.0.3
```

Run:

```powershell
cd D:\projects\supanotes
flutter pub get
```

- [ ] **Step 2: Convert feature providers to autoDispose**

Use this pattern:

```dart
final routinesProvider = FutureProvider.autoDispose<List<RoutineModel>>((ref) {
  return ref.watch(routinesRepositoryProvider).listRoutines();
});
```

Do not autoDispose the exceptions listed in `agents.md`: auth controller, router, database, API client, auth storage/repository, sync service/state, connectivity monitor, session cache.

- [ ] **Step 3: Replace duplicated loading/error state**

For shared async controllers, prefer:

```dart
final memoriesControllerProvider =
    NotifierProvider.autoDispose<MemoriesController, AsyncValue<List<MemoryModel>>>(
  MemoriesController.new,
);
```

Controller methods should set:

```dart
state = const AsyncValue.loading();
state = AsyncValue.data(memories);
state = AsyncValue.error(error, stackTrace);
```

- [ ] **Step 4: Add offline disabled view**

Create `lib/shared/widgets/offline_disabled_view.dart`:

```dart
import 'package:flutter/material.dart';

class OfflineDisabledView extends StatelessWidget {
  const OfflineDisabledView({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
```

Use it in chat, search, routines, settings, and Telegram linking when `connectivityMonitorProvider` says offline. Notes/tasks remain usable offline.

- [ ] **Step 5: Verify**

Run:

```powershell
cd D:\projects\supanotes
flutter analyze
flutter test
```

Expected: no Riverpod codegen dependency remains, tests pass, and online-only screens have deterministic offline states.

---

## Task 8: Infrastructure And Final Verification

**Files:**
- Modify: `backend/Dockerfile`
- Modify/Create: `backend/.env.example`
- Modify: `implementation_plan.md` if this becomes the active execution plan

- [ ] **Step 1: Align Docker Go version**

Either lower `go.mod` to a supported version or update Docker builder. Preferred if Go 1.25 is intentional:

```dockerfile
FROM golang:1.25-alpine AS builder
```

- [ ] **Step 2: Complete backend env example**

Ensure `backend/.env.example` includes all config keys read by `backend/pkg/config/config.go`, especially:

```env
ANTHROPIC_API_KEY=
DEEPSEEK_API_KEY=
OPENAI_EMBEDDINGS_API_KEY=
TELEGRAM_BOT_TOKEN=
FCM_CREDENTIALS_FILE=
DATABASE_URL=
JWT_SECRET=
```

- [ ] **Step 3: Full verification**

Run:

```powershell
cd D:\projects\supanotes\backend
go test ./...
cd D:\projects\supanotes
flutter analyze
flutter test
git diff --check
```

Expected:

- Backend tests pass.
- Flutter analyze passes.
- Flutter tests pass.
- No whitespace errors.
- `.docs/notes-agent-scope-v3.md` remains consistent with `.docs/CONTEXT.md`.

---

## Recommended Execution Order

1. Task 1 and Task 2 together: schema + tasks contract.
2. Task 3: sync contract.
3. Task 4: Telegram identity + streaming.
4. Task 5: routines contract.
5. Task 6: inbox organization.
6. Task 7: Flutter Riverpod/offline gating.
7. Task 8: infrastructure and full verification.

Tasks 4, 5, and 7 can run in parallel after Tasks 1-3 if each worker owns its file set and avoids broad formatting.

---

## Self-Review

- Spec coverage: all decisions from the updated scope are represented: tasks, Telegram, routines, sync, inbox organization, Riverpod, offline behavior, and infra.
- Placeholder scan: no task relies on undefined filler instructions. Some examples intentionally describe Arrange/Act/Assert because existing test fixtures must be reused.
- Type consistency: backend payload names match the revised scope: `note_tags`, `note_links`, `task_completions`, `telegram_user_id`, `telegram_chat_id`, `days_of_week`, `time_of_day`.
