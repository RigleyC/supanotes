# Plan 031: Fix GetByNoteID returning raw sqlcgen.Task

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat fd87433..HEAD -- backend/internal/tasks/handler.go`
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

The `GetByNoteID` handler at `backend/internal/tasks/handler.go:272` returns `[]sqlcgen.Task` directly instead of mapping through `mapToTaskResponse()`. This means the response leaks raw pgtype fields (`pgtype.UUID`, `pgtype.Text`, `pgtype.Date`, `pgtype.Timestamptz`) to the client, producing `{"Bytes":[...],"Valid":true}` JSON shapes instead of clean strings. Every other task endpoint (Create, List, Update, Complete, Reopen, Today) correctly uses `mapToTaskResponse()`.

## Current state

**Broken code** — `backend/internal/tasks/handler.go:258-273`:
```go
func (h *Handler) GetByNoteID(c echo.Context) error {
    // ... (lines 258-271 are fine)
    tasks, err := h.svc.GetTasks(c.Request().Context(), userID, &noteID, nil, nil, nil, 100, 0)
    if err != nil {
        c.Logger().Error(err)
        return web.JSONError(c, http.StatusInternalServerError, "failed to get tasks")
    }
    return c.JSON(http.StatusOK, tasks)  // BUG: returns []sqlcgen.Task directly
}
```

**Correct pattern** — `backend/internal/tasks/handler.go:137-141` (List handler):
```go
res := make([]TaskResponse, 0, len(tasks))
for _, t := range tasks {
    res = append(res, mapToTaskResponse(t))
}
return c.JSON(http.StatusOK, res)
```

The `mapToTaskResponse` function already exists at line 294-306 and correctly converts all pgtype fields to strings.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build backend | `cd backend && go build ./...` | exit 0, no errors |
| Vet backend | `cd backend && go vet ./...` | exit 0, no errors |

## Scope

**In scope**:
- `backend/internal/tasks/handler.go` — fix `GetByNoteID` to map through `mapToTaskResponse`

**Out of scope**:
- `backend/internal/tasks/handler.go` other methods — already correct
- Flutter client — no changes needed
- Other endpoints — not affected

## Git workflow

- Branch: `fix/031-get-by-note-id-raw-response`
- Commit: `fix(tasks): map sqlcgen.Task to TaskResponse in GetByNoteID`
- Do NOT push unless instructed.

## Steps

### Step 1: Fix GetByNoteID to map tasks through mapToTaskResponse

In `backend/internal/tasks/handler.go`, replace lines 267-272:

```go
tasks, err := h.svc.GetTasks(c.Request().Context(), userID, &noteID, nil, nil, nil, 100, 0)
if err != nil {
    c.Logger().Error(err)
    return web.JSONError(c, http.StatusInternalServerError, "failed to get tasks")
}
return c.JSON(http.StatusOK, tasks)
```

With:

```go
tasks, err := h.svc.GetTasks(c.Request().Context(), userID, &noteID, nil, nil, nil, 100, 0)
if err != nil {
    c.Logger().Error(err)
    return web.JSONError(c, http.StatusInternalServerError, "failed to get tasks")
}
res := make([]TaskResponse, 0, len(tasks))
for _, t := range tasks {
    res = append(res, mapToTaskResponse(t))
}
return c.JSON(http.StatusOK, res)
```

**Verify**: `cd backend && go build ./...` → exit 0

## Test plan

- No existing unit tests for this handler method.
- Manual verification: call `GET /api/v1/tasks/note/:id` and confirm the response has clean string `id`, `note_id`, `created_at`, `updated_at` fields (not pgtype shapes).
- Compare response shape against `GET /api/v1/tasks` (List) — they should now be identical.

## Done criteria

- [ ] `cd backend && go build ./...` exits 0
- [ ] `cd backend && go vet ./...` exits 0
- [ ] `grep -n 'return c.JSON(http.StatusOK, tasks)' backend/internal/tasks/handler.go` returns no matches (all list endpoints use mapped response)
- [ ] `plans/README.md` status row updated

## STOP conditions

- If `GetTasks` return type has changed since this plan was written.
- If a step's verification fails twice after a reasonable fix attempt.

## Maintenance notes

- This is a one-line logical fix — the mapping pattern already exists and is used by every other endpoint.
- The Flutter client's `TaskModel.fromData` already expects clean field types, so it should work once the backend response is correct.
