# Plan 032: Fix routine logs returning raw sqlcgen.RoutineLog

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat fd87433..HEAD -- backend/internal/routines/handler.go`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `fd87433`, 2026-06-17

## Why this matters

The `Logs` handler at `backend/internal/routines/handler.go:118` returns `[]sqlcgen.RoutineLog` directly. This leaks raw pgtype fields (`pgtype.UUID` for `ID` and `RoutineID`, `pgtype.Timestamptz` for `CreatedAt`) to the client. The Flutter client's `RoutineLogModel.fromJson` expects clean string values for `id`, `routine_id`, and `created_at`.

## Current state

**Broken code** — `backend/internal/routines/handler.go:106-119`:
```go
func (h *Handler) Logs(c echo.Context) error {
    userID, err := web.UserID(c)
    if err != nil {
        return err
    }

    // Use limit/offset in real app
    logs, err := h.svc.GetRoutineLogs(c.Request().Context(), userID, 50, 0)
    if err != nil {
        c.Logger().Error(err)
        return web.JSONError(c, http.StatusInternalServerError, "failed to get logs")
    }
    return c.JSON(http.StatusOK, logs)  // BUG: returns []sqlcgen.RoutineLog directly
}
```

**Flutter client** — `lib/features/routines/domain/routine_log_model.dart:43-52`:
```dart
factory RoutineLogModel.fromJson(Map<String, dynamic> json) {
    return RoutineLogModel(
      id: (json['id'] ?? '') as String,
      routineId: (json['routine_id'] ?? '') as String,
      status: (json['status'] ?? '') as String,
      content: (json['content'] ?? '') as String,
      errorMsg: json['error_msg'] as String?,
      createdAt: _parseTimestamp(json['created_at']),
    );
  }
```

Expects `id` and `routine_id` as strings, `created_at` as a parseable timestamp string.

**Convention reference** — `backend/internal/tasks/handler.go:294-306` (mapToTaskResponse pattern):
```go
func mapToTaskResponse(t sqlcgen.Task) TaskResponse {
    return TaskResponse{
        ID:         uid.UUIDToString(t.ID),
        NoteID:     uid.UUIDToString(t.NoteID),
        CreatedAt:  t.CreatedAt.Time.Format(time.RFC3339),
        UpdatedAt:  t.UpdatedAt.Time.Format(time.RFC3339),
        // ...
    }
}
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build backend | `cd backend && go build ./...` | exit 0, no errors |
| Vet backend | `cd backend && go vet ./...` | exit 0, no errors |

## Scope

**In scope**:
- `backend/internal/routines/handler.go` — add `RoutineLogResponse` struct, mapping function, and fix `Logs` handler

**Out of scope**:
- `backend/internal/routines/service.go` — service returns sqlcgen types correctly
- Flutter client — already correct
- Other routine endpoints — not affected

## Git workflow

- Branch: `fix/032-routine-logs-raw-response`
- Commit: `fix(routines): map sqlcgen.RoutineLog to RoutineLogResponse in Logs endpoint`
- Do NOT push unless instructed.

## Steps

### Step 1: Add RoutineLogResponse struct

In `backend/internal/routines/handler.go`, add a new response struct after the existing `RoutineResponse` struct (around line 46):

```go
type RoutineLogResponse struct {
    ID        string  `json:"id"`
    RoutineID string  `json:"routine_id"`
    Status    string  `json:"status"`
    Content   string  `json:"content"`
    ErrorMsg  *string `json:"error_msg"`
    CreatedAt string  `json:"created_at"`
}
```

**Verify**: `cd backend && go build ./...` → exit 0

### Step 2: Add mapping function

In `backend/internal/routines/handler.go`, add a mapping function:

```go
func routineLogToResponse(l sqlcgen.RoutineLog) RoutineLogResponse {
    return RoutineLogResponse{
        ID:        uid.UUIDToString(l.ID),
        RoutineID: uid.UUIDToString(l.RoutineID),
        Status:    l.Status,
        Content:   l.Content,
        ErrorMsg:  errorPtr(l.ErrorMsg),
        CreatedAt: l.CreatedAt.Time.Format(time.RFC3339),
    }
}
```

Add a helper to handle nullable pgtype.Text:

```go
func errorPtr(t pgtype.Text) *string {
    if !t.Valid {
        return nil
    }
    return &t.String
}
```

Add `"time"` and `"github.com/RigleyC/supanotes/pkg/uid"` to the imports if not already present.

**Verify**: `cd backend && go build ./...` → exit 0

### Step 3: Fix Logs handler to use mapping

In `backend/internal/routines/handler.go`, change the `Logs` handler from:

```go
return c.JSON(http.StatusOK, logs)
```

To:

```go
resp := make([]RoutineLogResponse, len(logs))
for i, l := range logs {
    resp[i] = routineLogToResponse(l)
}
return c.JSON(http.StatusOK, resp)
```

**Verify**: `cd backend && go build ./...` → exit 0

### Step 4: Verify no unused imports

Check that all imports are used. The `pgtype` import is needed for `errorPtr`'s parameter type.

**Verify**: `cd backend && go vet ./...` → exit 0

## Test plan

- No existing unit tests for this handler.
- Manual verification: call `GET /api/v1/routines/logs` and confirm the response has clean string `id`, `routine_id`, and `created_at` fields.
- The `created_at` field should be an RFC3339 string, not a pgtype object.

## Done criteria

- [ ] `cd backend && go build ./...` exits 0
- [ ] `cd backend && go vet ./...` exits 0
- [ ] `grep -n 'return c.JSON(http.StatusOK, logs)' backend/internal/routines/handler.go` returns no matches
- [ ] `grep -n 'RoutineLogResponse' backend/internal/routines/handler.go` returns matches (struct defined and used)
- [ ] `plans/README.md` status row updated

## STOP conditions

- If `GetRoutineLogs` return type has changed since this plan was written.
- If `sqlcgen.RoutineLog` fields have changed (e.g., `CreatedAt` is no longer `pgtype.Timestamptz`).
- If a step's verification fails twice after a reasonable fix attempt.

## Maintenance notes

- This follows the exact same pattern as `mapToTaskResponse` — convert pgtype fields to strings.
- The `ErrorMsg` field uses `pgtype.Text` which has `.Valid` and `.String` — the helper mirrors the pattern used elsewhere.
- If routine logs gain additional fields in the future, add them to both the response struct and the mapping function.
