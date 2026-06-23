# Codebase Audit Fixes (Backend) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve critical bugs, memory/goroutine leaks, and database schema issues found during the codebase audit in the Go backend.

**Architecture:** 
- A new database migration will fix missing columns (`deleted_at`), missing unique constraints (`note_links`), and drop redundant indexes.
- The SSE Chat stream will be updated to respect the request context, avoiding indefinitely blocked goroutines when clients disconnect.
- The Search service will short-circuit on empty FTS queries to avoid SQL syntax errors.

**Tech Stack:** Go, PostgreSQL, sqlc.

---

### Task 1: Database Schema Fixes (Migrations)

**Files:**
- Create: `backend/db/migrations/000022_audit_fixes.up.sql`
- Create: `backend/db/migrations/000022_audit_fixes.down.sql`

- [ ] **Step 1: Write the up migration**

Create `backend/db/migrations/000022_audit_fixes.up.sql`:
```sql
-- Fix contexts missing deleted_at for HardDeleteExpiredContexts
ALTER TABLE contexts ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Fix note_links missing unique constraint, which implicitly creates an index
ALTER TABLE note_links ADD CONSTRAINT note_links_source_id_target_id_key UNIQUE (source_id, target_id);

-- Drop redundant indexes
DROP INDEX IF EXISTS notes_active_idx;
DROP INDEX IF EXISTS tasks_user_due_idx;
```

- [ ] **Step 2: Write the down migration**

Create `backend/db/migrations/000022_audit_fixes.down.sql`:
```sql
ALTER TABLE contexts DROP COLUMN IF EXISTS deleted_at;

ALTER TABLE note_links DROP CONSTRAINT IF EXISTS note_links_source_id_target_id_key;

CREATE INDEX IF NOT EXISTS notes_active_idx ON notes (user_id, updated_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS tasks_user_due_idx ON tasks (user_id, due_date) WHERE status = 'open' AND deleted_at IS NULL AND due_date IS NOT NULL;
```

- [ ] **Step 3: Run migrations**

Run: `cd backend && make migrate-up`
Expected: Migration applies successfully.

- [ ] **Step 4: Regenerate sqlc code**

Run: `cd backend && make sqlc`
Expected: Code regenerates without errors. (Note: Since we added a column, some `sqlcgen` files might be updated).

- [ ] **Step 5: Commit**

```bash
git add backend/db/migrations/000022_audit_fixes.* backend/internal/db/sqlcgen/
git commit -m "fix(db): add missing deleted_at to contexts, fix note_links unique constraint, drop redundant indexes"
```

---

### Task 2: Fix Goroutine Leaks in SSE Chat Stream

**Files:**
- Modify: `backend/internal/agent/loop.go`
- Modify: `backend/internal/agent/handler.go`

- [ ] **Step 1: Update sendStreamEvent and sendEvent signatures to accept context**

Modify `backend/internal/agent/loop.go`. Update `sendEvent` and `sendStreamEvent`:
```go
func sendEvent(ctx context.Context, events chan<- SSEEvent, typ, data string) {
	if events != nil {
		select {
		case events <- SSEEvent{Type: typ, Data: data}:
		case <-ctx.Done():
		}
	}
}

func sendStreamEvent(ctx context.Context, events chan<- SSEEvent, event StreamEvent) {
	if events == nil {
		return
	}
	payload, err := json.Marshal(event)
	if err != nil {
		slog.Error("marshal stream event", "error", err)
		return
	}
	select {
	case events <- SSEEvent{Type: string(event.Type), Data: string(payload)}:
	case <-ctx.Done():
	}
}
```

- [ ] **Step 2: Update all callers of sendStreamEvent in loop.go**

In `backend/internal/agent/loop.go`, update every call to `sendStreamEvent` to pass `ctx` as the first argument. Search for `sendStreamEvent(events, ` and replace with `sendStreamEvent(ctx, events, `.

- [ ] **Step 3: Update ChatStream and callers in handler.go**

In `backend/internal/agent/handler.go` around line 107, update the error handling in `ChatSSE` to use the request context:
```go
		if err := h.loop.ChatStream(c.Request().Context(), userID, req.SessionID, req.Content, events); err != nil {
			slog.Error("agent chat stream failed", "session_id", req.SessionID, "error", err)
			writer := NewStreamEventWriter(req.SessionID, "")
			sendStreamEvent(c.Request().Context(), events, writer.Event(EventError, ErrorPayload{Message: err.Error()}))
		}
```

- [ ] **Step 4: Verify Compilation**

Run: `cd backend && go build ./...`
Expected: Build succeeds with no errors.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/agent/
git commit -m "fix(agent): pass context to SSE events to prevent goroutine leak on disconnect"
```

---

### Task 3: Prevent Empty Query Search Crash

**Files:**
- Modify: `backend/internal/search/service.go`

- [ ] **Step 1: Add empty query check in Search method**

Modify `backend/internal/search/service.go`. Update the `Search` method around line 47:
```go
	ftsQuery := toPrefixTsQuery(query)
	if ftsQuery == "" {
		return []SearchResult{}, nil
	}

	rows, err := s.q.SearchNotesHybrid(ctx, sqlcgen.SearchNotesHybridParams{
```

- [ ] **Step 2: Verify logic using tests**

Run: `cd backend && go test ./internal/search/...`
Expected: Tests pass.

- [ ] **Step 3: Commit**

```bash
git add backend/internal/search/service.go
git commit -m "fix(search): return empty results for queries with only special characters"
```

---

### Task 4: Prevent Information Leak on HTTP 500

**Files:**
- Modify: `backend/internal/web/response.go` (or wherever `JSONError` is defined)

- [ ] **Step 1: Locate and refactor JSONError to sanitize 500 errors**

We want to centralize the sanitization of internal server errors. Find where `web.JSONError` or the generic error mapping is done.
Use `grep -r "func JSONError" backend/` to locate the file, and modify it:

```go
// Replace err.Error() with a generic string if status >= 500.
func JSONError(c echo.Context, status int, msg string) error {
    if status >= 500 {
        slog.Error("internal server error", "details", msg)
        msg = "Internal server error"
    }
    return c.JSON(status, map[string]string{"error": msg})
}
```

- [ ] **Step 2: Compile and test**

Run: `cd backend && go build ./...`
Expected: Build passes.

- [ ] **Step 3: Commit**

```bash
git add backend/internal/
git commit -m "fix(security): sanitize internal server errors in HTTP responses"
```
