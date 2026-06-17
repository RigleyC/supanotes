# Plan 029: Fix RoutineResponse pgtype leak to client

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat fd87433..HEAD -- backend/internal/routines/handler.go backend/internal/routines/handler_test.go`
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

The `RoutineResponse` struct in the routines handler uses raw `pgtype.UUID` and `pgtype.Timestamptz` fields. When serialized by `encoding/json`, these produce `{"Bytes":[1,2,3,4,...],"Valid":true}` instead of clean string values like `"550e8400-e29b-41d4-a716-446655440000"`. This breaks the client contract — every other endpoint returns pre-formatted strings. The Flutter client's `RoutineModel.fromJson` expects `json['id']` to be a `String`, so it will crash on the current response.

The `ListRoutinesTool`, `SetDailyBriefScheduleTool`, and `SetWeeklyBriefScheduleTool` also marshal raw `sqlcgen.Routine` structs (which have the same pgtype fields), leaking the same format to the LLM agent context.

## Current state

- `backend/internal/routines/handler.go:34-46` — `RoutineResponse` struct uses `pgtype.UUID` and `pgtype.Timestamptz` directly
- `backend/internal/routines/handler.go:253-268` — `routineToResponse()` copies raw pgtype values without conversion
- `backend/internal/routines/handler.go:118` — `Logs` handler returns raw `[]sqlcgen.RoutineLog` (related, covered in plan 032)
- `backend/internal/agent/tools/routines_tools.go:29` — `ListRoutinesTool.Execute` calls `json.Marshal(rs)` on `[]sqlcgen.Routine`
- `backend/internal/agent/tools/routines_tools.go:104,144` — `SetDailyBriefScheduleTool` and `SetWeeklyBriefScheduleTool` marshal updated `sqlcgen.Routine`

The correct pattern exists in `backend/internal/tasks/handler.go:294-306`:
```go
func mapToTaskResponse(t sqlcgen.Task) TaskResponse {
    return TaskResponse{
        ID:         uid.UUIDToString(t.ID),
        NoteID:     uid.UUIDToString(t.NoteID),
        CreatedAt:  t.CreatedAt.Time.Format(time.RFC3339),
        UpdatedAt:  t.UpdatedAt.Time.Format(time.RFC3339),
        // ...all string fields
    }
}
```

And in `backend/internal/auth/handler.go:65-72` — the auth handler defines its own `RoutineResponse` that IS correctly string-based:
```go
type RoutineResponse struct {
    ID        string `json:"id"`
    Type      string `json:"type"`
    CronExpr  string `json:"cron_expr"`
    Enabled   bool   `json:"enabled"`
    CreatedAt string `json:"created_at"`
    UpdatedAt string `json:"updated_at"`
}
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build backend | `cd backend && go build ./...` | exit 0, no errors |
| Vet backend | `cd backend && go vet ./...` | exit 0, no errors |
| Test backend | `cd backend && go test ./internal/routines/... -v` | pass (or skip if no tests exist) |
| Test agent tools | `cd backend && go test ./internal/agent/... -v` | pass |

## Scope

**In scope**:
- `backend/internal/routines/handler.go` — fix `RoutineResponse` struct and `routineToResponse()`
- `backend/internal/agent/tools/routines_tools.go` — fix marshaling of routine data for LLM context

**Out of scope**:
- `backend/internal/routines/service.go` — service layer returns sqlcgen types correctly; mapping happens in handler
- `backend/internal/auth/handler.go` — already correct, no changes needed
- `backend/internal/routines/handler.go:118` (Logs endpoint) — covered separately in plan 032
- Flutter client — no changes needed; it already expects string values

## Git workflow

- Branch: `fix/029-routine-response-pgtype`
- Commit: `fix(routines): convert pgtype fields to strings in RoutineResponse`
- Do NOT push unless instructed.

## Steps

### Step 1: Fix RoutineResponse struct fields

In `backend/internal/routines/handler.go`, change the `RoutineResponse` struct from:

```go
type RoutineResponse struct {
    ID         pgtype.UUID        `json:"id"`
    UserID     pgtype.UUID        `json:"user_id"`
    Type       string             `json:"type"`
    DaysOfWeek string             `json:"days_of_week"`
    TimeOfDay  string             `json:"time_of_day"`
    Enabled    bool               `json:"enabled"`
    CreatedAt  pgtype.Timestamptz `json:"created_at"`
    UpdatedAt  pgtype.Timestamptz `json:"updated_at"`
    Name       string             `json:"name"`
    LastRunAt  pgtype.Timestamptz `json:"last_run_at"`
    BriefType  string             `json:"brief_type"`
}
```

To:

```go
type RoutineResponse struct {
    ID         string  `json:"id"`
    UserID     string  `json:"user_id"`
    Type       string  `json:"type"`
    DaysOfWeek string  `json:"days_of_week"`
    TimeOfDay  string  `json:"time_of_day"`
    Enabled    bool    `json:"enabled"`
    CreatedAt  string  `json:"created_at"`
    UpdatedAt  string  `json:"updated_at"`
    Name       string  `json:"name"`
    LastRunAt  *string `json:"last_run_at"`
    BriefType  string  `json:"brief_type"`
}
```

Note: `LastRunAt` becomes `*string` because `pgtype.Timestamptz` can be invalid (null). Use the `mapper.Time()` helper or inline the conversion.

**Verify**: `cd backend && go build ./...` → exit 0

### Step 2: Fix routineToResponse() to convert pgtype values

In `backend/internal/routines/handler.go`, change `routineToResponse` from:

```go
func routineToResponse(r sqlcgen.Routine) RoutineResponse {
    daysOfWeek, timeOfDay := cronToDaysAndTime(r.CronExpr)
    return RoutineResponse{
        ID:        r.ID,
        UserID:    r.UserID,
        // ...
    }
}
```

To:

```go
func routineToResponse(r sqlcgen.Routine) RoutineResponse {
    daysOfWeek, timeOfDay := cronToDaysAndTime(r.CronExpr)
    return RoutineResponse{
        ID:         uid.UUIDToString(r.ID),
        UserID:     uid.UUIDToString(r.UserID),
        Type:       r.Type,
        DaysOfWeek: daysOfWeek,
        TimeOfDay:  timeOfDay,
        Enabled:    r.Enabled,
        CreatedAt:  r.CreatedAt.Time.Format(time.RFC3339),
        UpdatedAt:  r.UpdatedAt.Time.Format(time.RFC3339),
        Name:       r.Name,
        LastRunAt:  formatTimestamp(r.LastRunAt),
        BriefType:  r.BriefType,
    }
}
```

Add a helper (or reuse `mapper.Time()` if you import the mapper package):

```go
func formatTimestamp(t pgtype.Timestamptz) *string {
    if !t.Valid {
        return nil
    }
    s := t.Time.Format(time.RFC3339)
    return &s
}
```

Also add `"time"` to the imports if not already present, and add `"github.com/RigleyC/supanotes/pkg/uid"` if not already present.

**Verify**: `cd backend && go build ./...` → exit 0

### Step 3: Fix agent tools to marshal DTO instead of sqlcgen

In `backend/internal/agent/tools/routines_tools.go`, the tools currently call `json.Marshal(rs)` where `rs` is `[]sqlcgen.Routine`. Instead, map to a string-friendly struct before marshaling.

Define a local struct at the top of the file (or in a shared location):

```go
type routineDTO struct {
    ID        string `json:"id"`
    Type      string `json:"type"`
    CronExpr  string `json:"cron_expr"`
    Enabled   bool   `json:"enabled"`
    CreatedAt string `json:"created_at"`
    UpdatedAt string `json:"updated_at"`
}
```

In `ListRoutinesTool.Execute` (line 24-35), replace:
```go
rs, err := t.routinesSvc.GetRoutines(ctx, userID)
// ...
b, err := json.Marshal(rs)
```

With:
```go
rs, err := t.routinesSvc.GetRoutines(ctx, userID)
// ...
dtos := make([]routineDTO, len(rs))
for i, r := range rs {
    dtos[i] = routineDTO{
        ID:        uid.UUIDToString(r.ID),
        Type:      r.Type,
        CronExpr:  r.CronExpr,
        Enabled:   r.Enabled,
        CreatedAt: r.CreatedAt.Time.Format(time.RFC3339),
        UpdatedAt: r.UpdatedAt.Time.Format(time.RFC3339),
    }
}
b, err := json.Marshal(dtos)
```

Apply the same pattern to `SetDailyBriefScheduleTool.Execute` (line 100-109) and `SetWeeklyBriefScheduleTool.Execute` (line 140-149) for the `updated` routine.

Add `"time"` and `"github.com/RigleyC/supanotes/pkg/uid"` to the imports.

**Verify**: `cd backend && go build ./...` → exit 0

### Step 4: Remove unused pgtype import if applicable

After the changes, check if `pgtype` is still needed in `routines/handler.go`. The `routineToResponse` function now uses `pgtype.Timestamptz` in its parameter type (via `formatTimestamp`), so the import stays. But verify there are no unused imports.

**Verify**: `cd backend && go vet ./...` → exit 0

## Test plan

- If existing tests exist in `backend/internal/routines/`, run them.
- Write a unit test `routineToResponse_test.go` that creates a `sqlcgen.Routine` with known values and asserts the response has clean string fields:
  - `resp.ID` is a hyphenated UUID string (not `{"Bytes":...}`)
  - `resp.CreatedAt` is an RFC3339 string
  - `resp.LastRunAt` is either a valid RFC3339 string or nil
- Verify the agent tools test (if any) still passes.

## Done criteria

- [ ] `cd backend && go build ./...` exits 0
- [ ] `cd backend && go vet ./...` exits 0
- [ ] `grep -n 'pgtype' backend/internal/routines/handler.go` shows pgtype ONLY in function signatures / imports, NOT in struct fields
- [ ] `grep -n 'pgtype' backend/internal/agent/tools/routines_tools.go` returns no matches (tools should not use pgtype directly)
- [ ] `plans/README.md` status row updated

## STOP conditions

- If `backend/internal/routines/service.go` has changed and `GetRoutines` no longer returns `[]sqlcgen.Routine`.
- If the Flutter client's `RoutineModel.fromJson` has changed to expect a different shape.
- If a step's verification fails twice after a reasonable fix attempt.

## Maintenance notes

- The auth handler already has its own `RoutineResponse` (at `backend/internal/auth/handler.go:65-72`). Consider consolidating into a shared DTO in `dto/` if more endpoints need routine responses. This is deferred — not part of this plan.
- If `LastRunAt` starts being populated by the backend in the future, the `formatTimestamp` helper handles it automatically.
- The agent tools now return clean JSON to the LLM context, which improves tool output readability.
