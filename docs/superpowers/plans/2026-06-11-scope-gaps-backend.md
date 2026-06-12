# Scope Gaps — Part 2: Backend Fixes

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all remaining backend gaps discovered in the scope v3 gap analysis that are NOT covered by `back-core.md` or `back-support.md`.

**Architecture:** Each task is isolated and mergeable. No breaking API changes except field rename (`message`→`content`).

**Tech Stack:** Go 1.23, Echo, sqlc, pgx, pgvector, OpenAI.

**Depends on:** `2026-06-11-scope-gaps-db.md` (migration 000011).

---

## File Map

| File | Role | Action |
|------|------|--------|
| `backend/internal/memories/service.go` | Memories service | Fix embedding stub |
| `backend/internal/agent/context.go` | Context builder | Fix Tier 4 source, add routine context |
| `backend/internal/agent/handler.go` | Agent handler | Fix SSE wire format, rename `message`→`content` |
| `backend/internal/gateway/handler.go` | Telegram gateway | Add streaming (placeholder + edit) |
| `backend/internal/tasks/handler.go` | Tasks handler | Make `note_id` optional |
| `backend/internal/tasks/service.go` | Tasks service | Support inbox tasks (no note_id) |
| `backend/internal/agent/tools.go` | Agent tools | Remove `note_id` from add_task required, register inbox organize tools |
| `backend/internal/routines/handler.go` | Routines handler | Add PATCH `/daily` and `/weekly` |
| `backend/cmd/server/main.go` | Server entry | Wire new routes |

---

## Task 1: Fix memories embedding stub

**Why:** `memories/service.go:26-29` hardcodes `0.01` vector. All long-term memory is non-functional.

**Files:**
- Modify: `backend/internal/memories/service.go`
- Test: `backend/internal/memories/service_test.go` (new)

---

- [ ] **Step 1: Inject `EmbeddingClient` into `Service`**

```go
// backend/internal/memories/service.go

type Service struct {
    repo    Repository
    embedCL *llm.EmbeddingClient  // ADD THIS
}

func NewService(repo Repository, embedCL *llm.EmbeddingClient) *Service {
    return &Service{repo: repo, embedCL: embedCL}
}
```

---

- [ ] **Step 2: Replace hardcoded vector with real embedding**

```go
func (s *Service) CreateMemory(ctx context.Context, userID pgtype.UUID, content string) (*sqlcgen.Memory, error) {
    emb, err := s.embedCL.GenerateEmbedding(ctx, content)
    if err != nil {
        return nil, fmt.Errorf("memories: generate embedding: %w", err)
    }
    vec := pgvector.NewVector(emb)
    return s.repo.CreateMemory(ctx, userID, content, vec)
}
```

---

- [ ] **Step 3: Update `cmd/server/main.go` to inject `embedCL`**

In `main.go`, find where `memoriesSvc` is constructed and add the embedding client:

```go
memoriesSvc := memories.NewService(memoriesRepo, embedCL)
```

---

- [ ] **Step 4: Write test**

Create `backend/internal/memories/service_test.go`:

```go
package memories

import (
    "context"
    "testing"

    "github.com/RigleyC/supanotes/internal/db/sqlcgen"
    "github.com/jackc/pgx/v5/pgtype"
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/mock"
)

type mockRepo struct {
    mock.Mock
}

func (m *mockRepo) GetMemories(ctx context.Context, userID pgtype.UUID, limit, offset int32) ([]sqlcgen.Memory, error) {
    args := m.Called(ctx, userID, limit, offset)
    return args.Get(0).([]sqlcgen.Memory), args.Error(1)
}

func (m *mockRepo) CreateMemory(ctx context.Context, userID pgtype.UUID, content string, embedding interface{}) (*sqlcgen.Memory, error) {
    args := m.Called(ctx, userID, content, embedding)
    return args.Get(0).(*sqlcgen.Memory), args.Error(1)
}

func (m *mockRepo) DeleteMemory(ctx context.Context, id, userID pgtype.UUID) error {
    args := m.Called(ctx, id, userID)
    return args.Error(0)
}

type mockEmbedCL struct {
    mock.Mock
}

func (m *mockEmbedCL) GenerateEmbedding(ctx context.Context, text string) ([]float64, error) {
    args := m.Called(ctx, text)
    return args.Get(0).([]float64), args.Error(1)
}

func TestCreateMemory_UsesRealEmbedding(t *testing.T) {
    repo := new(mockRepo)
    embedCL := new(mockEmbedCL)
    svc := NewService(repo, embedCL)

    expectedEmb := make([]float64, 1536)
    expectedEmb[0] = 0.5

    embedCL.On("GenerateEmbedding", mock.Anything, "test memory").Return(expectedEmb, nil)
    repo.On("CreateMemory", mock.Anything, mock.Anything, "test memory", mock.Anything).Return(&sqlcgen.Memory{}, nil)

    _, err := svc.CreateMemory(context.Background(), pgtype.UUID{}, "test memory")
    assert.NoError(t, err)
    embedCL.AssertCalled(t, "GenerateEmbedding", mock.Anything, "test memory")
}
```

Run: `cd backend && go test ./internal/memories/...`

---

- [ ] **Step 5: Commit**

```bash
git add backend/internal/memories/service.go backend/internal/memories/service_test.go backend/cmd/server/main.go
git commit -m "fix(memories): use real embeddings instead of hardcoded 0.01 stub"
```

---

## Task 2: Fix context builder — Tier 4 source + routine context

**Why:** Tier 4 (vault) doesn't filter by `is_vault=true`. `BuildForRoutine` doesn't include RAG notes.

**Files:**
- Modify: `backend/internal/agent/context.go`

---

- [ ] **Step 1: Fix Tier 4 vault filter**

In `context.go`, find the Tier 4 query or service call. The current code queries recent notes without vault filter. Add `is_vault = true`:

```go
// In buildTier4 or wherever vault notes are fetched
// Before: gets all recent notes
// After: filter to vault-only

vaultNotes, err := b.repo.GetRecentNotes(ctx, userID, 10)
// This is wrong — needs vault filter. Add a new query or filter:

// Option A: Add GetVaultNotes to notes repository
// Option B: Filter in code (less efficient but simpler for now)

var vaultNotes []sqlcgen.Note
for _, n := range allRecentNotes {
    if n.IsVault {
        vaultNotes = append(vaultNotes, n)
    }
}
```

Better approach — add SQL query:

```sql
-- In backend/db/queries/notes.sql
-- name: GetVaultNotes :many
SELECT id, title, excerpt, content, updated_at
FROM notes
WHERE user_id = $1 AND is_vault = true AND deleted_at IS NULL
ORDER BY updated_at DESC
LIMIT $2;
```

Then regenerate sqlc and use in context builder:

```go
vaultNotes, err := b.repo.GetVaultNotes(ctx, userID, 10)
```

---

- [ ] **Step 2: Add RAG to `BuildForRoutine`**

In `context.go`, `BuildForRoutine` currently builds context without semantic search. Add RAG:

```go
func (b *ContextBuilder) BuildForRoutine(ctx context.Context, userID pgtype.UUID, routineType string) (string, error) {
    var sb strings.Builder

    // Tier 1: Open tasks
    // ... existing code ...

    // Tier 2: Recent notes (last 48h)
    // ... existing code ...

    // ADD: Tier 3 — Semantic search (RAG) using routine type as query
    query := fmt.Sprintf("routine %s context", routineType)
    ragNotes, err := b.searchNotesByEmbedding(ctx, userID, query, 5)
    if err == nil && len(ragNotes) > 0 {
        sb.WriteString("## Notas Relevantes (via busca semântica)\n\n")
        for _, n := range ragNotes {
            sb.WriteString(fmt.Sprintf("- %s (similaridade: %.0f%%)\n", n.Title, n.Similarity*100))
        }
        sb.WriteString("\n")
    }

    // Tier 4: Vault notes
    // ... existing code ...

    return sb.String(), nil
}
```

---

- [ ] **Step 3: Commit**

```bash
git add backend/internal/agent/context.go backend/db/queries/notes.sql backend/internal/db/sqlcgen/notes.sql.go
git commit -m "fix(context): add vault filter to Tier 4, add RAG to BuildForRoutine"
```

---

## Task 3: Fix SSE wire format + rename `message`→`content`

**Why:** Backend sends `{type, data, delta}` but scope says `{delta}` and `{done: true}`. Frontend expects `content` not `message`.

**Files:**
- Modify: `backend/internal/agent/handler.go`

---

- [ ] **Step 1: Fix SSE frame format in `streamChat`**

In `handler.go`, find the SSE streaming loop. The current format wraps data in `{type, data, delta}`. Change to match scope:

```go
// Current (wrong):
fmt.Fprintf(w, "data: {\"type\":\"chunk\",\"data\":\"%s\",\"delta\":\"%s\"}\n\n", escaped, escaped)

// Scope-correct:
fmt.Fprintf(w, "data: {\"delta\":\"%s\"}\n\n", escaped)
```

And the done frame:

```go
// Current (wrong):
fmt.Fprintf(w, "data: {\"type\":\"done\"}\n\n")

// Scope-correct:
fmt.Fprintf(w, "data: {\"done\":true}\n\n")
```

---

- [ ] **Step 2: Rename `message` to `content` in request body**

In `handler.go`, find where the request body is bound:

```go
// Current:
type ChatRequest struct {
    SessionID string `json:"session_id"`
    Message   string `json:"message"`
}

// Change to:
type ChatRequest struct {
    SessionID string `json:"session_id"`
    Content   string `json:"content"`
}
```

Update all references from `req.Message` to `req.Content` in the handler.

---

- [ ] **Step 3: Also fix `ChatRepository.sendMessage` on Flutter side**

This is a frontend change — add to the frontend plan. But note: the frontend `chat_repository.dart` sends `message` field. It must be updated to `content`.

---

- [ ] **Step 4: Commit**

```bash
git add backend/internal/agent/handler.go
git commit -m "fix(agent): SSE wire format {delta}/{done:true} + rename message→content"
```

---

## Task 4: Make `note_id` optional in task creation

**Why:** Agent creates inbox tasks without a note. Backend requires `note_id` with `validate:"required,uuid"`.

**Files:**
- Modify: `backend/internal/tasks/handler.go`
- Modify: `backend/internal/tasks/service.go`
- Modify: `backend/internal/agent/tools.go`

---

- [ ] **Step 1: Make `note_id` optional in `CreateTaskRequest`**

```go
// backend/internal/tasks/handler.go

type CreateTaskRequest struct {
    NoteID     *string `json:"note_id" validate:"omitempty,uuid"`  // CHANGED: was required
    Title      string  `json:"title" validate:"required"`
    DueDate    *string `json:"due_date"`
    Recurrence *string `json:"recurrence"`
    Position   int     `json:"position"`
}
```

---

- [ ] **Step 2: Update handler to handle nil `note_id`**

```go
func (h *Handler) Create(c echo.Context) error {
    // ... existing code ...

    var noteID *pgtype.UUID
    if req.NoteID != nil {
        n, err := uid.UUIDFromString(*req.NoteID)
        if err != nil {
            return web.JSONError(c, http.StatusBadRequest, "invalid note_id")
        }
        noteID = &n
    }

    task, err := h.svc.CreateTask(c.Request().Context(), userID, noteID, req.Title, dueDate, req.Recurrence, req.Position)
    // ... rest unchanged ...
}
```

---

- [ ] **Step 3: Update `CreateTask` service signature**

```go
// backend/internal/tasks/service.go

func (s *Service) CreateTask(ctx context.Context, userID pgtype.UUID, noteID *pgtype.UUID, title string, dueDate *time.Time, recurrence *string, position int) (*sqlcgen.Task, error) {
    // noteID is now *pgtype.UUID (pointer, nullable)
    // Pass to sqlc query — if nil, the DB column gets NULL
}
```

---

- [ ] **Step 4: Remove `note_id` from `AddTaskTool` required fields**

In `tools.go`, find `AddTaskTool`:

```go
// Current (wrong):
func (t *AddTaskTool) SchemaJSON() string {
    return `{
        "type": "object",
        "properties": {
            "title": {"type": "string"},
            "note_id": {"type": "string"}
        },
        "required": ["title", "note_id"]  // WRONG
    }`
}

// Fix:
func (t *AddTaskTool) SchemaJSON() string {
    return `{
        "type": "object",
        "properties": {
            "title": {"type": "string"},
            "note_id": {"type": "string", "description": "Optional note ID to link the task to"},
            "due_date": {"type": "string", "description": "ISO 8601 date"},
            "recurrence": {"type": "string", "description": "daily, weekdays, weekly, monthly"}
        },
        "required": ["title"]
    }`
}
```

---

- [ ] **Step 5: Commit**

```bash
git add backend/internal/tasks/handler.go backend/internal/tasks/service.go backend/internal/agent/tools.go
git commit -m "fix(tasks): make note_id optional for inbox task creation"
```

---

## Task 5: Register inbox organize tools

**Why:** `OrganizeInboxTool` and `ExtractTasksTool` exist in `tools.go` but are never registered in `NewToolRegistry`.

**Files:**
- Modify: `backend/internal/agent/tools.go`

---

- [ ] **Step 1: Add tools to registry**

In `tools.go`, `NewToolRegistry` (line ~40), add the missing tools:

```go
executors := []ToolExecutor{
    // ... existing tools ...
    &OrganizeInboxTool{notesSvc: notesSvc, tasksSvc: tasksSvc},  // ADD
    &ExtractTasksTool{notesSvc: notesSvc, tasksSvc: tasksSvc},   // ADD
}
```

---

- [ ] **Step 2: Commit**

```bash
git add backend/internal/agent/tools.go
git commit -m "fix(agent): register OrganizeInbox and ExtractTasks tools"
```

---

## Task 6: Add PATCH `/routines/daily` and `/routines/weekly`

**Why:** Scope §6.1.7 requires PATCH endpoints for routine config. Currently only one generic `PATCH /:id` exists.

**Files:**
- Modify: `backend/internal/routines/handler.go`
- Modify: `backend/internal/routines/service.go`
- Modify: `backend/cmd/server/main.go`

---

- [ ] **Step 1: Add `UpdateDaily` and `UpdateWeekly` handlers**

In `routines/handler.go`:

```go
type UpdateRoutineConfigRequest struct {
    TimeOfDay  *string  `json:"time_of_day"`   // "HH:MM"
    DaysOfWeek *[]int   `json:"days_of_week"`   // [0..6]
    Enabled    *bool    `json:"enabled"`
    Timezone   *string  `json:"timezone"`
}

func (h *Handler) UpdateDaily(c echo.Context) error {
    return h.updateByType(c, "daily")
}

func (h *Handler) UpdateWeekly(c echo.Context) error {
    return h.updateByType(c, "weekly")
}

func (h *Handler) updateByType(c echo.Context, routineType string) error {
    userID, err := web.UserID(c)
    if err != nil { return err }

    var req UpdateRoutineConfigRequest
    if err := c.Bind(&req); err != nil {
        return web.JSONError(c, http.StatusBadRequest, "invalid request body")
    }

    routine, err := h.svc.UpdateRoutineByType(c.Request().Context(), userID, routineType, req.TimeOfDay, req.DaysOfWeek, req.Enabled, req.Timezone)
    if err != nil {
        c.Logger().Error(err)
        return web.JSONError(c, http.StatusInternalServerError, "failed to update routine")
    }
    return c.JSON(http.StatusOK, routine)
}
```

---

- [ ] **Step 2: Add `UpdateRoutineByType` to service**

In `routines/service.go`:

```go
func (s *Service) UpdateRoutineByType(ctx context.Context, userID pgtype.UUID, routineType string, timeOfDay *string, daysOfWeek *[]int, enabled *bool, timezone *string) (*sqlcgen.Routine, error) {
    // 1. Find routine by type + user
    routines, err := s.GetRoutines(ctx, userID)
    if err != nil { return nil, err }

    var target *sqlcgen.Routine
    for _, r := range routines {
        if r.Type == routineType {
            target = &r
            break
        }
    }
    if target == nil {
        return nil, ErrRoutineNotFound
    }

    // 2. Update fields
    // ... call UpdateRoutine with the target's ID ...
}
```

---

- [ ] **Step 3: Register routes in `main.go`**

```go
// In main.go, in the routines route registration:
protected.PATCH("/routines/daily", routinesH.UpdateDaily)
protected.PATCH("/routines/weekly", routinesH.UpdateWeekly)
```

---

- [ ] **Step 4: Commit**

```bash
git add backend/internal/routines/handler.go backend/internal/routines/service.go backend/cmd/server/main.go
git commit -m "feat(routines): add PATCH /routines/daily and /routines/weekly"
```

---

## Task 7: Implement Telegram gateway streaming

**Why:** `gateway/handler.go` uses one-shot `SendMessage`. Scope requires placeholder + `editMessageText` for streaming.

**Files:**
- Modify: `backend/internal/gateway/handler.go`

---

- [ ] **Step 1: Add placeholder message + edit pattern**

In `gateway/handler.go`, replace the one-shot `SendMessage` with streaming:

```go
func (h *Handler) handleTelegramMessage(c echo.Context, update TelegramUpdate) error {
    chatID := update.Message.Chat.ID
    text := update.Message.Text
    userID := /* resolve from telegram_links */ 

    // 1. Send placeholder "Pensando..."
    placeholder, err := h.telegram.SendMessage(chatID, "Pensando...")
    if err != nil {
        return err
    }

    // 2. Build context and stream response
    ctx := c.Request().Context()
    response, err := h.buildAgentResponse(ctx, userID, text)
    if err != nil {
        h.telegram.EditMessageText(chatID, placeholder.MessageID, "Erro ao processar mensagem.")
        return err
    }

    // 3. Edit placeholder with final response (chunked if > 4096 chars)
    if len(response) > 4096 {
        // Split into chunks and send as separate messages
        for i := 0; i < len(response); i += 4096 {
            end := i + 4096
            if end > len(response) { end = len(response) }
            if i == 0 {
                h.telegram.EditMessageText(chatID, placeholder.MessageID, response[i:end])
            } else {
                h.telegram.SendMessage(chatID, response[i:end])
            }
        }
    } else {
        h.telegram.EditMessageText(chatID, placeholder.MessageID, response)
    }

    return c.JSON(http.StatusOK, map[string]string{"status": "ok"})
}
```

---

- [ ] **Step 2: Add `EditMessageText` to Telegram client**

In the Telegram client (wherever `SendMessage` is defined):

```go
func (c *Client) EditMessageText(chatID int64, messageID int, text string) error {
    url := fmt.Sprintf("%s/editMessageText", c.baseURL)
    body := map[string]interface{}{
        "chat_id":    chatID,
        "message_id": messageID,
        "text":       text,
    }
    // ... POST to Telegram API ...
}
```

---

- [ ] **Step 3: Commit**

```bash
git add backend/internal/gateway/handler.go
git commit -m "feat(telegram): streaming via placeholder + editMessageText"
```

---

## Self-Review

| Gap | Task | Covered? |
|-----|------|----------|
| Memories embedding stub | Task 1 | ✅ |
| Context Tier 4 vault filter | Task 2 | ✅ |
| Context BuildForRoutine missing RAG | Task 2 | ✅ |
| SSE wire format mismatch | Task 3 | ✅ |
| `message`→`content` rename | Task 3 | ✅ |
| Task handler note_id required | Task 4 | ✅ |
| add_task tool required: ['note_id'] | Task 4 | ✅ |
| Inbox organize tools not registered | Task 5 | ✅ |
| Routines PATCH /daily + /weekly | Task 6 | ✅ |
| Telegram gateway streaming | Task 7 | ✅ |

**Not addressed:** `note_embeddings` ivfflat index is in the DB plan. `SearchNotesByEmbedding` archived filter is in `back-core.md`.

---

## Execution Handoff

Plan complete. Ready to execute via subagent-driven or inline approach.
