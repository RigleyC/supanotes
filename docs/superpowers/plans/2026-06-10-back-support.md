# Back-Support — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix routines (TZ-aware cron, `.md` prompts, per-routine lock), tags (DELETE + note_tags endpoints), note_links (relation column + reverse index), and migration gaps (CHECK constraint, trigger bind).

**Architecture:** Incremental fixes: migrations → sqlcgen → service → handler → route. Each task is isolated and mergeable.

**Tech Stack:** Go 1.23, Echo, sqlc, pgx, PostgreSQL.

---

## File Map

| File | Role | Action |
|------|------|--------|
| `backend/internal/routines/runner.go` | Routine executor | Fix TZ evaluation, add `sync.Map` lock |
| `backend/internal/routines/prompt.go` | Prompt builder | Replace with `//go:embed` |
| `backend/internal/routines/briefs/daily.md` | Daily brief spec | Create |
| `backend/internal/routines/briefs/weekly.md` | Weekly brief spec | Create |
| `backend/internal/tags/handler.go` | Tag HTTP handlers | Add `Delete` |
| `backend/internal/tags/service.go` | Tag service | Add `Delete` method |
| `backend/internal/notes/handler.go` | Notes HTTP handlers | Add tag attach/detach endpoints |
| `backend/internal/notes/service.go` | Notes service | Add tag attach/detach methods |
| `backend/cmd/server/main.go` | Server entry | Wire new routes |
| `backend/db/migrations/000010_note_links_fix.up.sql` | Migration | New migration |
| `backend/db/migrations/000010_note_links_fix.down.sql` | Migration | Down migration |
| `backend/internal/db/sqlcgen/` | Generated code | Regenerate |

---

## Task 1: Add DB migration for schema gaps

**Why:** Missing CHECK constraint, orphan trigger function, missing `relation` column and reverse index on `note_links`.

**Files:**
- Create: `backend/db/migrations/000010_note_links_fix.up.sql`
- Create: `backend/db/migrations/000010_note_links_fix.down.sql`

---

- [ ] **Step 1: Create up migration**

`backend/db/migrations/000010_note_links_fix.up.sql`:

```sql
-- Fix notes_excerpt_update: bind trigger + fix regex to match spec
DROP TRIGGER IF EXISTS trg_generate_note_excerpt ON notes;
DROP FUNCTION IF EXISTS generate_note_excerpt;
CREATE OR REPLACE FUNCTION notes_excerpt_update() RETURNS trigger AS $$
BEGIN
  NEW.excerpt := substring(
    regexp_replace(NEW.content, '[#*_>`\[\]]+', '', 'g')
    FROM 1 FOR 200
  );
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_notes_excerpt_update
BEFORE INSERT OR UPDATE OF content ON notes
FOR EACH ROW EXECUTE FUNCTION notes_excerpt_update();

-- Add CHECK constraint: inbox cannot be archived
ALTER TABLE notes ADD CONSTRAINT chk_inbox_not_archived CHECK (is_inbox = false OR archived = false);

-- Add relation column to note_links
ALTER TABLE note_links ADD COLUMN relation TEXT NOT NULL DEFAULT 'related'
  CHECK (relation IN ('related', 'part_of', 'references'));

-- Add reverse index for bidirectional lookups
CREATE INDEX idx_note_links_target ON note_links (target_id);
```

---

- [ ] **Step 2: Create down migration**

`backend/db/migrations/000010_note_links_fix.down.sql`:

```sql
DROP INDEX IF EXISTS idx_note_links_target;
ALTER TABLE note_links DROP COLUMN IF EXISTS relation;
ALTER TABLE notes DROP CONSTRAINT IF EXISTS chk_inbox_not_archived;
DROP TRIGGER IF EXISTS trg_notes_excerpt_update ON notes;
```

---

- [ ] **Step 3: Commit**

```bash
git add backend/db/migrations/000010_note_links_fix.up.sql backend/db/migrations/000010_note_links_fix.down.sql
git commit -m "feat(db): add relation/reverse index to note_links, fix excerpt trigger, add inbox CHECK"
```

---

## Task 2: Fix routine runner — TZ-aware cron + per-routine lock

**Why:** `robfig/cron` runs in server TZ. The spec requires user TZ. Global `chan sem{}` allows overlaps.

**Files:**
- Modify: `backend/internal/routines/runner.go`
- Modify: `backend/internal/routines/repository.go` (if needed)

---

- [ ] **Step 1: Replace global `sem` with `sync.Map` per routine**

```go
type Runner struct {
    repo           Repository
    agentCtxBldr   ContextBuilder
    llmFactory     llm.Factory
    notifier       Notifier
    telegram       TelegramNotifier
    cronJob        *cron.Cron
    maintenanceJob *cron.Cron
    running        sync.Map  // map[string]chan struct{} — routine_id -> semaphore
    reloadTicker   *time.Ticker
    stopReload     chan struct{}
}
```

In `runRoutine`, use `sync.Map`:

```go
func (r *Runner) runRoutine(rt sqlcgen.GetEnabledRoutinesRow) {
    id := uid.UUIDToString(rt.ID)
    // Acquire per-routine lock (buffer 1 = serial execution)
    sem := make(chan struct{}, 1)
    actual, loaded := r.running.LoadOrStore(id, sem)
    if loaded {
        sem = actual.(chan struct{})
    }
    select {
    case sem <- struct{}{}:
        defer func() { <-sem }()
    default:
        log.Warn().Str("routine_id", id).Msg("routine already running, skipping")
        return
    }
    // ... rest of runRoutine
}
```

---

- [ ] **Step 2: Make cron TZ-aware**

Replace `reload()` to schedule each routine's cron expression with TZ offset prepended, or calculate `nextRun` in user TZ and use `time.Timer`.

Simplest approach: prepend `CRON_TZ=<timezone>` to the cron expression:

```go
expr := fmt.Sprintf("CRON_TZ=%s %s", routine.Timezone, routine.CronExpr)
```

This is supported by `robfig/cron` (v3 spec). Since the `CronExpr` stored is like `"0 8 * * 1-5"`, the full expression becomes `"CRON_TZ=America/Sao_Paulo 0 8 * * 1-5"`, which `robfig/cron` evaluates in that TZ.

---

- [ ] **Step 3: Commit**

```bash
git add backend/internal/routines/runner.go
git commit -m "fix(routines): per-routine sync.Map lock and CRON_TZ support"
```

---

## Task 3: Load brief prompts from embedded `.md` files

**Why:** Spec requires dedicated `.md` files for easy editing.

**Files:**
- Create: `backend/internal/routines/briefs/daily.md`
- Create: `backend/internal/routines/briefs/weekly.md`
- Modify: `backend/internal/routines/prompt.go`

---

- [ ] **Step 1: Create `daily.md`**

`backend/internal/routines/briefs/daily.md`:

```markdown
Você é o Agente do SupaNotes rodando uma rotina automática.

## Brief Diário
Gere um Brief Diário para o usuário cobrindo:
- Tarefas atrasadas (overdue)
- Tarefas de hoje
- Notas recentes relevantes (últimas 48h)
- Lembretes de contextos ativos

Seja curto e acionável. Use português brasileiro.
```

---

- [ ] **Step 2: Create `weekly.md`**

`backend/internal/routines/briefs/weekly.md`:

```markdown
Você é o Agente do SupaNotes rodando uma rotina automática.

## Brief Semanal
Gere um Brief Semanal para o usuário destacando:
- Principais realizações da semana
- Tarefas pendentes que precisam de atenção
- Focos para os próximos dias
- Notas criadas na semana

Seja conciso e motivacional. Use português brasileiro.
```

---

- [ ] **Step 3: Replace `prompt.go` with embedded file loading**

```go
package routines

import (
    _ "embed"
    "fmt"
)

//go:embed briefs/daily.md
var dailyBriefMD string

//go:embed briefs/weekly.md
var weeklyBriefMD string

func buildBriefPrompt(routineType string, ragContext string) string {
    var prompt string
    switch routineType {
    case "daily":
        prompt = dailyBriefMD
    case "weekly":
        prompt = weeklyBriefMD
    default:
        prompt = "Você é o Agente do SupaNotes."
    }
    return fmt.Sprintf("%s\n\nContexto Atual:\n%s", prompt, ragContext)
}
```

---

- [ ] **Step 4: Commit**

```bash
git add backend/internal/routines/briefs/daily.md backend/internal/routines/briefs/weekly.md backend/internal/routines/prompt.go
git commit -m "feat(routines): load brief prompts from embedded .md files"
```

---

## Task 4: Add `DELETE /tags/:id` + note_tags endpoints

**Why:** Tags can be created but never deleted or attached to notes.

**Files:**
- Modify: `backend/internal/tags/handler.go`
- Modify: `backend/internal/tags/service.go`
- Modify: `backend/internal/notes/handler.go` (add tag attach/detach)
- Modify: `backend/internal/notes/service.go` (add tag attach/detach)
- Modify: `backend/cmd/server/main.go`

---

- [ ] **Step 1: Add `Delete` to tags handler + service**

In `backend/internal/tags/service.go`:

```go
func (s *Service) Delete(ctx context.Context, id, userID pgtype.UUID) error {
    // Verify ownership via GetTagsForUser or inline query
    return s.q.DeleteTag(ctx, sqlcgen.DeleteTagParams{ID: id, UserID: userID})
}
```

In `backend/internal/tags/handler.go`:

```go
func (h *Handler) Delete(c echo.Context) error {
    userID, err := web.UserID(c)
    if err != nil { return err }
    id, err := uid.UUIDFromString(c.Param("id"))
    if err != nil { return web.JSONError(c, http.StatusBadRequest, "invalid tag id") }
    if err := h.svc.Delete(c.Request().Context(), id, userID); err != nil {
        return web.JSONError(c, http.StatusInternalServerError, "failed to delete tag")
    }
    return c.NoContent(http.StatusNoContent)
}
```

---

- [ ] **Step 2: Add `DeleteTag` to `backend/db/queries/notes.sql`**

```sql
-- name: DeleteTag :exec
DELETE FROM tags
WHERE id = $1 AND user_id = $2;
```

Regenerate sqlc.

---

- [ ] **Step 3: Add tag attach/detach to notes service + handler**

In `backend/internal/notes/service.go`:

```go
func (s *Service) AddTagToNote(ctx context.Context, noteID, tagID, userID pgtype.UUID) error {
    _, err := s.GetNoteByID(ctx, noteID, userID)
    if err != nil { return err }
    return s.repo.AddTagToNote(ctx, sqlcgen.AddTagToNoteParams{NoteID: noteID, TagID: tagID})
}

func (s *Service) RemoveTagFromNote(ctx context.Context, noteID, tagID, userID pgtype.UUID) error {
    _, err := s.GetNoteByID(ctx, noteID, userID)
    if err != nil { return err }
    return s.repo.RemoveTagFromNote(ctx, sqlcgen.RemoveTagFromNoteParams{NoteID: noteID, TagID: tagID})
}
```

Add handlers and routes:

```go
// In main.go
protected.POST("/notes/:id/tags", notesH.AddTag)
protected.DELETE("/notes/:id/tags/:tagId", notesH.RemoveTag)
```

---

- [ ] **Step 4: Wire tag route in `main.go`**

```go
protected.GET("/tags", tagsH.List)
protected.POST("/tags", tagsH.Create)
protected.DELETE("/tags/:id", tagsH.Delete)
```

---

- [ ] **Step 5: Write tests and commit**

```go
func TestTagsService_Delete(t *testing.T) {
    q := new(mockQuerier)
    svc := tags.NewService(q)
    q.On("DeleteTag", mock.Anything, mock.Anything).Return(nil)
    err := svc.Delete(context.Background(), pgtype.UUID{}, pgtype.UUID{})
    assert.NoError(t, err)
}
```

```bash
git add backend/db/queries/notes.sql backend/internal/db/sqlcgen/notes.sql.go backend/internal/tags/handler.go backend/internal/tags/service.go backend/internal/notes/handler.go backend/internal/notes/service.go backend/cmd/server/main.go
git commit -m "feat(tags): add DELETE /tags/:id and note_tags attach/detach endpoints"
```

---

## Task 5: Remove old `GenerateNoteExcerpt` function from sqlc (cleanup)

**Why:** Redundant after migration 000010.

**Files:**
- Check: `backend/db/queries/notes.sql` — no action needed since it's a plpgsql function, not a query

---

- [ ] **Step 1: Verify migration runs cleanly**

Run: `cd backend && go run ./cmd/server/...`

Expected: Server starts without migration errors.

---

- [ ] **Step 2: Commit**

```bash
git commit -m "chore: cleanup redundant excerpt function"
```

---

## Self-Review

**Spec coverage:**

| Gap | Task | Covered? |
|-----|------|----------|
| TZ-aware cron | Task 2 | ✅ |
| Per-routine lock | Task 2 | ✅ |
| `.md` prompt files | Task 3 | ✅ |
| `DELETE /tags/:id` | Task 4 | ✅ |
| `note_tags` endpoints | Task 4 | ✅ |
| `note_links.relation` column + CHECK | Task 1 | ✅ |
| `note_links` reverse index | Task 1 | ✅ |
| CHECK `inbox=false OR archived=false` | Task 1 | ✅ |
| `notes_excerpt_update` trigger bind + fix regex | Task 1 | ✅ |

**Gap not addressed:** `notes.Repository` still doesn't expose `GetRecent`/`GetLinked`/`GetVaultStats`. Those are accessed directly via `sqlcgen.Querier` in the agent context builder. If service-layer wrappers are needed, add as a separate task.

---

## Execution Handoff

Plan complete. Ready to execute via subagent-driven or inline approach.
