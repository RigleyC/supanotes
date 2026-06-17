# Plan 033: Add validation to update endpoints

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat fd87433..HEAD -- backend/internal/tasks/handler.go backend/internal/routines/handler.go backend/internal/notes/handler.go backend/internal/sync/handler.go`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `fd87433`, 2026-06-17

## Why this matters

Create endpoints consistently use `web.BindAndValidate()` which calls both `c.Bind()` (JSON decoding) and `c.Validate()` (go-playground/validator). Update endpoints use raw `c.Bind()` without validation, skipping the `validate` tags on request structs. This means malformed or malicious input on update routes is not rejected at the API boundary — it passes through to the service/SQL layer where it may cause unexpected behavior.

Affected endpoints:
- `PATCH /api/v1/tasks/:id` — `UpdateTaskRequest` has no validation enforced
- `PATCH /api/v1/routines/:id` — `UpdateRoutineRequest` has no validation enforced
- `PATCH /api/v1/routines/daily` and `/weekly` — `UpdateRoutineConfigRequest` has no validation enforced
- `PATCH /api/v1/notes/:id` — `UpdateNoteRequest` has no validation enforced
- Sync Pull/Push — `SyncPayload` has no validation (acceptable — sync uses business logic validation)

## Current state

**Pattern with validation** — `backend/internal/tasks/handler.go:66-75` (Create):
```go
var req CreateTaskRequest
if err := web.BindAndValidate(c, &req); err != nil {
    return err
}
```

**Pattern without validation** — `backend/internal/tasks/handler.go:155-158` (Update):
```go
var req UpdateTaskRequest
if err := c.Bind(&req); err != nil {
    return web.JSONError(c, http.StatusBadRequest, "invalid request body")
}
```

The same inconsistency exists in:
- `backend/internal/routines/handler.go:86-89` (Update)
- `backend/internal/routines/handler.go:157-160` (updateByType)
- `backend/internal/notes/handler.go:179-182` (Update — needs verification)

**Helper** — `backend/internal/web/bind.go:7-17`:
```go
func BindAndValidate(c echo.Context, req any) error {
    if err := c.Bind(req); err != nil {
        return JSONError(c, http.StatusBadRequest, "invalid request body")
    }
    if err := c.Validate(req); err != nil {
        return JSONValidationError(c, err)
    }
    return nil
}
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build backend | `cd backend && go build ./...` | exit 0, no errors |
| Vet backend | `cd backend && go vet ./...` | exit 0, no errors |

## Scope

**In scope**:
- `backend/internal/tasks/handler.go` — `Update` handler
- `backend/internal/routines/handler.go` — `Update` and `updateByType` handlers
- `backend/internal/notes/handler.go` — `Update` handler (verify it needs fixing)

**Out of scope**:
- Sync handlers — sync uses business-level validation (empty note check, conflict detection), not struct-level validate tags
- Gateway webhook handler — raw Telegram data, no validate tags needed
- Create endpoints — already correct

## Git workflow

- Branch: `fix/033-add-validation-to-updates`
- Commit: `fix(api): use BindAndValidate on update endpoints for consistent input validation`
- Do NOT push unless instructed.

## Steps

### Step 1: Fix Tasks Update handler

In `backend/internal/tasks/handler.go`, change the `Update` handler (line 155-158) from:

```go
var req UpdateTaskRequest
if err := c.Bind(&req); err != nil {
    return web.JSONError(c, http.StatusBadRequest, "invalid request body")
}
```

To:

```go
var req UpdateTaskRequest
if err := web.BindAndValidate(c, &req); err != nil {
    return err
}
```

**Verify**: `cd backend && go build ./...` → exit 0

### Step 2: Fix Routines Update handler

In `backend/internal/routines/handler.go`, change the `Update` handler (line 86-89) from:

```go
var req UpdateRoutineRequest
if err := c.Bind(&req); err != nil {
    return web.JSONError(c, http.StatusBadRequest, "invalid request body")
}
```

To:

```go
var req UpdateRoutineRequest
if err := web.BindAndValidate(c, &req); err != nil {
    return err
}
```

**Verify**: `cd backend && go build ./...` → exit 0

### Step 3: Fix Routines updateByType handler

In `backend/internal/routines/handler.go`, change the `updateByType` handler (line 157-160) from:

```go
var req UpdateRoutineConfigRequest
if err := c.Bind(&req); err != nil {
    return web.JSONError(c, http.StatusBadRequest, "invalid request body")
}
```

To:

```go
var req UpdateRoutineConfigRequest
if err := web.BindAndValidate(c, &req); err != nil {
    return err
}
```

**Verify**: `cd backend && go build ./...` → exit 0

### Step 4: Fix Notes Update handler

In `backend/internal/notes/handler.go`, find the `Update` handler and change the binding from `c.Bind(&req)` to `web.BindAndValidate(c, &req)`. The pattern is the same as steps 1-3.

Note: Verify the `UpdateNoteRequest` struct has `validate` tags. If it doesn't, this step still changes the binding for consistency, but validation won't do anything until tags are added (that's a separate concern).

**Verify**: `cd backend && go build ./...` → exit 0

### Step 5: Add validate tags to UpdateRoutineRequest (if missing)

Check if `UpdateRoutineRequest` and `UpdateRoutineConfigRequest` have `validate` tags. If they don't, add appropriate tags. For example:

```go
type UpdateRoutineRequest struct {
    DaysOfWeek *string `json:"days_of_week" validate:"omitempty,daysOfWeek"` // if custom validator exists
    TimeOfDay  *string `json:"time_of_day"  validate:"omitempty,timeOfDay"` // if custom validator exists
    Enabled    *bool   `json:"enabled"`
}
```

If no custom validators exist for `daysOfWeek`/`timeOfDay`, just add `validate:"omitempty"` to keep it consistent. The key point is that `BindAndValidate` is called, so any future validate tags will be enforced.

**Verify**: `cd backend && go build ./...` → exit 0

### Step 6: Verify all update endpoints use BindAndValidate

Run:
```bash
grep -n 'c.Bind(&req)' backend/internal/*/handler.go
```

Expected: no matches in tasks, routines, or notes handlers. Sync and gateway handlers may still use raw `c.Bind()` (which is acceptable — see Scope section).

**Verify**: `cd backend && go vet ./...` → exit 0

## Test plan

- No existing validation tests.
- Manual verification: send a PATCH request with invalid JSON body to `/api/v1/tasks/:id` and confirm it returns a 400 error with the standard validation error format.
- Send a valid PATCH request and confirm it still works.

## Done criteria

- [ ] `cd backend && go build ./...` exits 0
- [ ] `cd backend && go vet ./...` exits 0
- [ ] `grep -n 'c.Bind(&req)' backend/internal/tasks/handler.go` returns no matches
- [ ] `grep -n 'c.Bind(&req)' backend/internal/routines/handler.go` returns no matches
- [ ] `grep -n 'BindAndValidate' backend/internal/tasks/handler.go` returns at least 2 matches (Create + Update)
- [ ] `grep -n 'BindAndValidate' backend/internal/routines/handler.go` returns at least 4 matches (Create + Update + updateByType + test)
- [ ] `plans/README.md` status row updated

## STOP conditions

- If any update handler has business logic that depends on skipping validation.
- If the notes handler's `Update` method has a different binding pattern than expected.
- If a step's verification fails twice after a reasonable fix attempt.

## Maintenance notes

- This change is backward-compatible: existing valid requests will continue to work. Only invalid requests that previously passed through will now be rejected.
- The `SyncPayload` struct intentionally does not use `validate` tags because sync validation happens at the business logic level (empty note check, conflict detection, ownership verification). Do not add `BindAndValidate` to sync handlers.
- Future validate tags added to request structs will be automatically enforced because `BindAndValidate` is now consistently used.
