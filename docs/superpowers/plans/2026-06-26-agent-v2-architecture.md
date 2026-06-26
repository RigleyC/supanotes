# SupaNotes Agent v2 — Architecture Evolution Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the SupaNotes ReAct agent from a monolithic loop into an organizational intelligence pipeline of specialized components (Intent Classifier, Planner, Smart Context Builder, Working Memory, Memory Manager, Response Builder).

**Architecture:** We decouple reasoning from orchestration. We run an Intent Classifier to select the retrieval policy. We run a Planner to produce an execution roadmap. We fetch only the necessary context data. We maintain a database-backed session-scoped working memory. We actively curate memory persistence (duplicate check, merge/replace, injection check). We apply budget pressure in the agent loop. We format the final result using a Response Builder. We stream progress milestones to the UI timeline via SSE.

**Tech Stack:** Go (REST API, SSE), PostgreSQL (pgvector for memories, uuid), sqlc, DeepSeek/GPT (via pkg/llm).

---

### Task 1: Intent Classification (Phase 1)

**Files:**
- Create: `backend/internal/agent/intent.go`
- Create: `backend/internal/agent/intent_test.go`
- Modify: `backend/internal/agent/loop.go`

- [ ] **Step 1: Write the failing test**
Create `backend/internal/agent/intent_test.go`:
```go
package agent

import (
	"context"
	"testing"

	"github.com/RigleyC/supanotes/pkg/llm"
)

type stubLLMClient struct {
	content string
}

func (s *stubLLMClient) Complete(ctx context.Context, req llm.Request) (*llm.Response, error) {
	return &llm.Response{Content: s.content}, nil
}
func (s *stubLLMClient) CompleteStream(ctx context.Context, req llm.Request, onToken func(string) error) (*llm.Response, error) {
	return &llm.Response{Content: s.content}, nil
}

func TestIntentClassifier(t *testing.T) {
	stub := &stubLLMClient{content: "DailySummary"}
	classifier := NewIntentClassifier(stub)
	intent, err := classifier.Classify(context.Background(), "o que eu tenho pra hoje?")
	if err != nil {
		t.Fatalf("Classify failed: %v", err)
	}
	if intent != IntentDailySummary {
		t.Errorf("expected DailySummary, got %v", intent)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**
Run: `go test -v ./backend/internal/agent/... -run TestIntentClassifier`
Expected: Compile failure (types and functions not defined).

- [ ] **Step 3: Implement IntentClassifier**
Create `backend/internal/agent/intent.go`:
```go
package agent

import (
	"context"
	"strings"

	"github.com/RigleyC/supanotes/pkg/llm"
)

type Intent string

const (
	IntentDailySummary     Intent = "DailySummary"
	IntentSearchKnowledge  Intent = "SearchKnowledge"
	IntentProjectPlanning  Intent = "ProjectPlanning"
	IntentTaskManagement   Intent = "TaskManagement"
	IntentMemoryQuestion   Intent = "MemoryQuestion"
	IntentOrganization     Intent = "Organization"
	IntentBrainstorming    Intent = "Brainstorming"
	IntentGeneralChat      Intent = "GeneralChat"
)

type IntentClassifier struct {
	client llm.Client
}

func NewIntentClassifier(client llm.Client) *IntentClassifier {
	return &IntentClassifier{client: client}
}

func (ic *IntentClassifier) Classify(ctx context.Context, message string) (Intent, error) {
	req := llm.Request{
		System: `Você é um Classificador de Intenção especializado. Analise a mensagem do usuário e responda APENAS com um dos seguintes nomes de intenção, sem explicações, pontuação ou formatação adicional:
- DailySummary: Perguntas sobre o dia, agenda, o que fazer hoje, tarefas vencidas ou resumo diário.
- SearchKnowledge: Buscas semânticas sobre anotações, notas antigas ou informações gerais.
- ProjectPlanning: Planejamento de projetos, notas vinculadas, metas e tarefas de projeto.
- TaskManagement: Criação, atualização ou conclusão de tarefas.
- MemoryQuestion: Perguntas sobre fatos que o agente deveria se lembrar/memorizar.
- Organization: Organização de notas, inbox, arquivar ou limpar notas.
- Brainstorming: Sessões criativas, ideias, pensamentos.
- GeneralChat: Conversa fiada, saudoções ou mensagens gerais.`,
		Messages: []llm.Message{
			{Role: llm.RoleUser, Content: message},
		},
		MaxTokens:   50,
		Temperature: 0.0,
	}
	res, err := ic.client.Complete(ctx, req)
	if err != nil {
		return IntentGeneralChat, err
	}
	cleanIntent := Intent(strings.TrimSpace(res.Content))
	switch cleanIntent {
	case IntentDailySummary, IntentSearchKnowledge, IntentProjectPlanning, IntentTaskManagement, IntentMemoryQuestion, IntentOrganization, IntentBrainstorming, IntentGeneralChat:
		return cleanIntent, nil
	default:
		return IntentGeneralChat, nil
	}
}
```

- [ ] **Step 4: Run test to verify it passes**
Run: `go test -v ./backend/internal/agent/... -run TestIntentClassifier`
Expected: PASS

- [ ] **Step 5: Commit**
Run:
```bash
git add backend/internal/agent/intent.go backend/internal/agent/intent_test.go
git commit -m "feat(agent): add Intent Classifier component"
```

---

### Task 2: Smart Context Builder (Phase 3)

**Files:**
- Modify: `backend/internal/agent/context.go`
- Modify: `backend/internal/agent/context_test.go`

- [ ] **Step 1: Write failing test in `backend/internal/agent/context_test.go`**
Add a test `TestContextBuilderSmartPolicies` verifying that:
1. For `IntentGeneralChat`, neither task fetching nor semantic search queries are run (only user soul/profile is fetched).
2. For `IntentDailySummary`, task queries are executed but note embedding search is skipped.

- [ ] **Step 2: Run test to verify it fails**
Run: `go test -v ./backend/internal/agent/... -run TestContextBuilderSmartPolicies`
Expected: FAIL (because Smart Policies are not implemented).

- [ ] **Step 3: Modify `ContextBuilder` in `context.go`**
Refactor the `Build` method to accept `Intent` and use a conditional retrieval policy:
```go
func (cb *ContextBuilder) Build(ctx context.Context, userID, sessionID pgtype.UUID, query string, intent Intent) (string, error) {
	// Setup local vars.
	// Depending on Intent, configure what is fetched:
	// - DailySummary: fetch soul, userSettings, todayTasks, completedTasks, memories (no notes semantic search, no linked notes)
	// - SearchKnowledge: fetch soul, recentNotes, memories, semantic search
	// - ProjectPlanning: fetch soul, semantic search, linked notes, tasks
	// - TaskManagement: fetch soul, todayTasks, completedTasks
	// - MemoryQuestion: fetch soul, memories, recentNotes
	// - Organization: fetch soul, recentNotes
	// - Brainstorming: fetch soul, semantic search, recentNotes, memories
	// - GeneralChat: fetch soul only
}
```

- [ ] **Step 4: Run test to verify it passes**
Run: `go test -v ./backend/internal/agent/... -run TestContextBuilderSmartPolicies`
Expected: PASS

- [ ] **Step 5: Commit**
Run:
```bash
git add backend/internal/agent/context.go backend/internal/agent/context_test.go
git commit -m "feat(agent): implement smart context builder with demand-driven retrieval policies"
```

---

### Task 3: Planner (Phase 2)

**Files:**
- Create: `backend/internal/agent/planner.go`
- Create: `backend/internal/agent/planner_test.go`
- Modify: `backend/internal/agent/loop.go`

- [ ] **Step 1: Write failing test in `backend/internal/agent/planner_test.go`**
Create a test `TestPlannerGeneratePlan` verifying:
- The planner returns a structured execution plan (e.g. JSON with list of tool steps) when given a goal like "Organizar meu inbox".

- [ ] **Step 2: Run test to verify it fails**
Run: `go test -v ./backend/internal/agent/... -run TestPlannerGeneratePlan`
Expected: Compile error.

- [ ] **Step 3: Implement `planner.go`**
```go
package agent

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/RigleyC/supanotes/pkg/llm"
)

type PlanStep struct {
	ToolName    string `json:"tool_name"`
	Description string `json:"description"`
}

type ExecutionPlan struct {
	Steps []PlanStep `json:"steps"`
}

type Planner struct {
	client llm.Client
}

func NewPlanner(client llm.Client) *Planner {
	return &Planner{client: client}
}

func (p *Planner) GeneratePlan(ctx context.Context, query string, intent Intent, contextBrief string) (*ExecutionPlan, error) {
	systemPrompt := `Você é um Planejador de Agente de IA. Analise a requisição do usuário, a intenção detectada e o contexto atual, e elabore um plano de execução linear composto por ferramentas específicas a executar de forma silenciosa para resolver o objetivo.
Responda APENAS com um objeto JSON válido no formato abaixo, sem tags Markdown:
{
  "steps": [
    { "tool_name": "nome_da_ferramenta", "description": "descrição da ação neste passo" }
  ]
}`
	req := llm.Request{
		System: systemPrompt,
		Messages: []llm.Message{
			{Role: llm.RoleUser, Content: fmt.Sprintf("Query: %s\nIntent: %s\nContext:\n%s", query, intent, contextBrief)},
		},
		MaxTokens:   1000,
		Temperature: 0.0,
	}
	res, err := p.client.Complete(ctx, req)
	if err != nil {
		return nil, err
	}
	var plan ExecutionPlan
	if err := json.Unmarshal([]byte(res.Content), &plan); err != nil {
		return nil, fmt.Errorf("planner: unmarshal json: %w", err)
	}
	return &plan, nil
}
```

- [ ] **Step 4: Run test to verify it passes**
Run: `go test -v ./backend/internal/agent/... -run TestPlannerGeneratePlan`
Expected: PASS

- [ ] **Step 5: Commit**
Run:
```bash
git add backend/internal/agent/planner.go backend/internal/agent/planner_test.go
git commit -m "feat(agent): implement Planner to generate structured tool execution plans"
```

---

### Task 4: Working Memory DB Schema (Phase 4)

**Files:**
- Create: `backend/db/migrations/000023_agent_v2_evolution.up.sql`
- Create: `backend/db/migrations/000023_agent_v2_evolution.down.sql`
- Modify: `backend/db/queries/agent.sql`

- [ ] **Step 1: Create Migration Up/Down Files**
Create `backend/db/migrations/000023_agent_v2_evolution.up.sql`:
```sql
CREATE TABLE IF NOT EXISTS agent_working_memory (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_id UUID NOT NULL,
    key VARCHAR(255) NOT NULL,
    value TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, session_id, key)
);
```

Create `backend/db/migrations/000023_agent_v2_evolution.down.sql`:
```sql
DROP TABLE IF EXISTS agent_working_memory;
```

- [ ] **Step 2: Add queries to `agent.sql`**
Add the following queries to `backend/db/queries/agent.sql`:
```sql
-- name: GetWorkingMemoryValue :one
SELECT value FROM agent_working_memory
WHERE user_id = $1 AND session_id = $2 AND key = $3;

-- name: SetWorkingMemoryValue :one
INSERT INTO agent_working_memory (user_id, session_id, key, value)
VALUES ($1, $2, $3, $4)
ON CONFLICT (user_id, session_id, key) DO UPDATE SET 
    value = EXCLUDED.value,
    updated_at = NOW()
RETURNING *;

-- name: DeleteWorkingMemoryForSession :exec
DELETE FROM agent_working_memory
WHERE user_id = $1 AND session_id = $2;

-- name: GetWorkingMemoryForSession :many
SELECT key, value FROM agent_working_memory
WHERE user_id = $1 AND session_id = $2;
```

- [ ] **Step 3: Run SQLC generator**
Run: `cd backend; sqlc generate`
Expected: Code generated successfully in `backend/internal/db/sqlcgen`.

- [ ] **Step 4: Commit**
Run:
```bash
git add backend/db/migrations/000023_agent_v2_evolution.up.sql backend/db/migrations/000023_agent_v2_evolution.down.sql backend/db/queries/agent.sql
git commit -m "db: add agent_working_memory table schema and sqlc queries"
```

---

### Task 5: Working Memory Integration & Tools (Phase 4)

**Files:**
- Create: `backend/internal/agent/working_memory.go`
- Create: `backend/internal/agent/tools/working_memory_tools.go`
- Modify: `backend/internal/agent/tools/registry.go`
- Modify: `backend/internal/agent/loop.go`

- [ ] **Step 1: Write failing test in `backend/internal/agent/working_memory_test.go`**
Create tests for the working memory service:
- Verify that keys can be written, updated, read, and deleted.

- [ ] **Step 2: Run test to verify it fails**
Run: `go test -v ./backend/internal/agent/... -run TestWorkingMemory`
Expected: Compile failure.

- [ ] **Step 3: Implement `working_memory.go`**
Create `backend/internal/agent/working_memory.go`:
```go
package agent

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type WorkingMemoryService struct {
	q sqlcgen.Querier
}

func NewWorkingMemoryService(q sqlcgen.Querier) *WorkingMemoryService {
	return &WorkingMemoryService{q: q}
}

func (s *WorkingMemoryService) Set(ctx context.Context, userID, sessionID pgtype.UUID, key, value string) error {
	_, err := s.q.SetWorkingMemoryValue(ctx, sqlcgen.SetWorkingMemoryValueParams{
		UserID:    userID,
		SessionID: sessionID,
		Key:       key,
		Value:     value,
	})
	return err
}

func (s *WorkingMemoryService) Get(ctx context.Context, userID, sessionID pgtype.UUID, key string) (string, error) {
	return s.q.GetWorkingMemoryValue(ctx, sqlcgen.GetWorkingMemoryValueParams{
		UserID:    userID,
		SessionID: sessionID,
		Key:       key,
	})
}

func (s *WorkingMemoryService) GetAll(ctx context.Context, userID, sessionID pgtype.UUID) (map[string]string, error) {
	rows, err := s.q.GetWorkingMemoryForSession(ctx, sqlcgen.GetWorkingMemoryForSessionParams{
		UserID:    userID,
		SessionID: sessionID,
	})
	if err != nil {
		return nil, err
	}
	res := make(map[string]string)
	for _, r := range rows {
		res[r.Key] = r.Value
	}
	return res, nil
}

func (s *WorkingMemoryService) Clear(ctx context.Context, userID, sessionID pgtype.UUID) error {
	return s.q.DeleteWorkingMemoryForSession(ctx, sqlcgen.DeleteWorkingMemoryForSessionParams{
		UserID:    userID,
		SessionID: sessionID,
	})
}
```

- [ ] **Step 4: Implement working memory tools**
Create `backend/internal/agent/tools/working_memory_tools.go` defining:
- `GetWorkingMemoryTool`
- `SetWorkingMemoryTool`
Register these tools in `registry.go` and inject their execution code.

- [ ] **Step 5: Inject active working memory into Loop context**
Modify `loop.go` to load working memory at the start of `doChat` and append it to the system context in `<working-memory>` tags.
Ensure `DeleteSessionMessages` also clears `agent_working_memory`.

- [ ] **Step 6: Run tests to verify they pass**
Run: `go test -v ./backend/internal/agent/...`
Expected: PASS

- [ ] **Step 7: Commit**
Run:
```bash
git add backend/internal/agent/working_memory.go backend/internal/agent/tools/working_memory_tools.go backend/internal/agent/tools/registry.go
git commit -m "feat(agent): expose working session memory to the agent loop via tools"
```

---

### Task 6: Active Memory Manager (Phase 5)

**Files:**
- Modify: `backend/internal/memories/service.go`
- Modify: `backend/internal/memories/repository.go`
- Modify: `backend/db/queries/ai.sql`

- [ ] **Step 1: Add update/deduplication queries to `ai.sql`**
Modify `backend/db/queries/ai.sql`:
```sql
-- name: UpdateMemory :one
UPDATE memories
SET content = $2, embedding = $3, updated_at = NOW()
WHERE id = $1 AND user_id = $2
RETURNING *;
```
Run `sqlc generate`.

- [ ] **Step 2: Implement prompt-injection scanner and limit verification in `memories/service.go`**
Add checks:
```go
func validateContent(content string) error {
	lowered := strings.ToLower(content)
	if strings.Contains(lowered, "ignore previous instructions") || strings.Contains(lowered, "system prompt:") {
		return fmt.Errorf("invalid memory content (prompt injection detected)")
	}
	return nil
}
```
In `CreateMemory`, fetch the count of memories first. If count >= 100, reject saving.

- [ ] **Step 3: Implement duplicate/merge flow via LLM**
In `CreateMemory`, query semantic memories. If similarity >= 0.85, send the candidate memory + matched memory to LLM completion to decide whether to MERGE, REPLACE, or REJECT.
If merge, call `UpdateMemory`. If replace, update. If reject, do nothing.

- [ ] **Step 4: Run memories tests**
Run: `go test -v ./backend/internal/memories/...`
Expected: PASS

- [ ] **Step 5: Commit**
Run:
```bash
git add backend/internal/memories/ backend/db/queries/ai.sql
git commit -m "feat(memories): implement active curation, deduplication, and limits in memory manager"
```

---

### Task 7: User Profile (Phase 6)

**Files:**
- Modify: `backend/db/migrations/000023_agent_v2_evolution.up.sql`
- Modify: `backend/db/queries/ai.sql`
- Modify: `backend/internal/agent/context.go`
- Create: `backend/internal/agent/tools/user_profile_tools.go`

- [ ] **Step 1: Add profile column migration**
Add to `000023_agent_v2_evolution.up.sql`:
```sql
ALTER TABLE souls ADD COLUMN profile JSONB NOT NULL DEFAULT '{}'::jsonb;
```

- [ ] **Step 2: Update database queries in `ai.sql`**
Add:
```sql
-- name: UpdateSoulProfile :one
UPDATE souls
SET profile = $2, updated_at = NOW()
WHERE user_id = $1
RETURNING *;
```
Run `sqlc generate`.

- [ ] **Step 3: Expose `update_user_profile` tool**
Create `backend/internal/agent/tools/user_profile_tools.go` to save stable preferences as JSON.
Inject/format user profile JSON as natural language inside the stable context tier in `context.go`.

- [ ] **Step 4: Verify prompt compilation**
Run: `go test -v ./backend/internal/agent/...`
Expected: PASS

- [ ] **Step 5: Commit**
Run:
```bash
git add backend/internal/agent/tools/user_profile_tools.go
git commit -m "feat(agent): separate user profile stable preferences and load them into context"
```

---

### Task 8: Agent Loop: Iterations & Budget Pressure (Phase 7, 8, 9)

**Files:**
- Modify: `backend/internal/agent/loop.go`
- Modify: `backend/internal/agent/system_prompt.md`

- [ ] **Step 1: Increase iterations to 15**
In `loop.go`, change:
```diff
-for i := 0; i < 5; i++ {
+for i := 0; i < 15; i++ {
```

- [ ] **Step 2: Inject Budget Pressure messages**
In `loop.go`:
```go
if i == 12 {
	messages = append(messages, llm.Message{Role: llm.RoleSystem, Content: "SYSTEM INSTRUCTION: You are approaching the iteration limit. Start preparing the final response."})
}
if i == 14 {
	messages = append(messages, llm.Message{Role: llm.RoleSystem, Content: "SYSTEM INSTRUCTION: Final iteration. Finish the task and response now."})
}
```

- [ ] **Step 3: Context Compression**
Implement compression in `loop.go` to summarize older tool results (compress array when `len(messages) > 15`).

- [ ] **Step 4: Verify loop tests**
Run: `go test -v ./backend/internal/agent/... -run TestLoop`
Expected: PASS

- [ ] **Step 5: Commit**
Run:
```bash
git add backend/internal/agent/loop.go backend/internal/agent/system_prompt.md
git commit -m "feat(agent): upgrade agent loop iterations, budget pressure and context compression"
```

---

### Task 9: Observability, Response Builder, and Timeline (Phase 10, 11, 12)

**Files:**
- Create: `backend/internal/agent/trace.go`
- Create: `backend/internal/agent/response_builder.go`
- Modify: `backend/internal/agent/loop.go`
- Modify: `backend/internal/agent/events.go`

- [ ] **Step 1: Implement ResponseBuilder and Observability Trace**
Create `backend/internal/agent/response_builder.go` to format outputs (Portuguese structured presentation).
Create `backend/internal/agent/trace.go` to log execution metadata.

- [ ] **Step 2: Emit Timeline SSE Milestones**
Add `EventTimelineMilestone` event to `events.go`.
Modify `loop.go` to push timeline updates when running classifier, planner, context builder, and response builder.

- [ ] **Step 3: Run comprehensive agent tests**
Run: `go test -v ./backend/internal/agent/...`
Expected: PASS

- [ ] **Step 4: Commit**
Run:
```bash
git add backend/internal/agent/trace.go backend/internal/agent/response_builder.go
git commit -m "feat(agent): add observability tracing, response builder, and UI execution timeline events"
```

---

## Verification Plan

### Automated Tests
- Run `go test -v ./backend/internal/agent/...` to verify the entire pipeline (Intent Classifier, Planner, Smart Context Builder, Working Memory, loop iterations, and SSE events).
- Run `go test -v ./backend/internal/memories/...` to verify memory manager curation, injection checks, and capacity limits.

### Manual Verification
- Start a Chat stream. Verify that `type: timeline_milestone` events are streamed first (e.g. `🧠 Understanding request`).
- Save a duplicate memory. Verify that the memory manager detects it and triggers a merge/overwrite or reject instead of producing duplicate rows in the `memories` table.
- Ask a general chat question. Confirm that the context size sent to the LLM is minimal since the Smart Context Builder filters out semantic notes and task loads for the general chat intent.
