# Agent V2 Thermonuclear Refactoring Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clean up structural code-quality regressions introduced in the Agent V2 rewrite, specifically dismantling the `executeLoop` god-function, fixing leaky UI label abstractions, removing magic string context compression, and stabilizing the exhaustion fallback.

**Architecture:** We will introduce a lightweight `BudgetManager` to handle iteration state, move UI labels and compression summaries into the `ToolRegistry` boundary where they belong, and break down `executeLoop` into functional phases. 

**Tech Stack:** Go (Backend)

---

### Task 1: Tool Registry Abstraction Fixes

**Files:**
- Modify: `backend/internal/agent/tools.go`
- Modify: `backend/internal/agent/tools/notes_tools.go` (and other tool files if they exist)
- Modify: `backend/internal/agent/loop.go`

- [ ] **Step 1: Write the abstraction changes**

Add `Label()` and `Summary(rawOutput string)` methods to the `Tool` interface. 
Update all tools to implement these. For example, `GetNoteTool` returns `"Lendo notas"` for `Label()` and `"[Retrieved note contents successfully]"` for `Summary()`.

- [ ] **Step 2: Remove leaky label methods**

Delete `labelForTool` function in `loop.go`. In `executeLoop`, replace `labelForTool(tc.Name)` with `l.tools.Get(tc.Name).Label()`.

- [ ] **Step 3: Remove magic compression logic**

In `loop.go`, rewrite `summarizeToolOutput` to query the Tool Registry for the summary rather than using `strings.Contains`.

- [ ] **Step 4: Run tests**

Run: `go test -v ./backend/internal/agent/...`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/agent/
git commit -m "refactor(agent): move UI labels and compression summaries to Tool interface"
```

---

### Task 2: Intent-based UI Labels

**Files:**
- Modify: `backend/internal/agent/loop.go`

- [ ] **Step 1: Remove regex label**

Delete `initialLabelForPrompt` in `loop.go`.

- [ ] **Step 2: Add Intent-based label mapping**

Add a function `labelForIntent(intent Intent) string` that switches on the actual Intent enum:
- `IntentTaskManagement` -> "Consultando sua agenda..."
- `IntentSearchKnowledge` -> "Analisando suas notas..."
- `IntentBrainstorming` -> "Pensando..."
- default -> "Pensando..."

Update `prepareTurn` to use `labelForIntent(turn.intent)` for the `MessageStarted` event payload.

- [ ] **Step 3: Run tests**

Run: `go test -v ./backend/internal/agent/...`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add backend/internal/agent/loop.go
git commit -m "refactor(agent): use intent classifier for initial UI loading labels"
```

---

### Task 3: Execution State and Budget Manager

**Files:**
- Create: `backend/internal/agent/budget.go`
- Modify: `backend/internal/agent/loop.go`

- [ ] **Step 1: Create BudgetManager**

Create `budget.go` with a `BudgetManager` struct that tracks `currentIteration` and `maxIterations`.
Add `NeedsWarning() bool` (returns true if at iteration 12) and `NeedsFinalWarning() bool` (returns true if at iteration 14).
Add `GetSystemPromptWarning() string` that returns the exact strings currently hardcoded in the loop.

- [ ] **Step 2: Replace hardcoded conditionals**

In `executeLoop`, instantiate `budget := NewBudgetManager(15)` and use it to check for system instructions, entirely removing the `if i == 12` and `if i == 14` magic numbers from the core loop orchestration.

- [ ] **Step 3: Run tests**

Run: `go test -v ./backend/internal/agent/...`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add backend/internal/agent/
git commit -m "refactor(agent): extract iteration budget pressure logic into BudgetManager"
```

---

### Task 4: God-Function Decomposition

**Files:**
- Modify: `backend/internal/agent/loop.go`

- [ ] **Step 1: Extract `processToolCalls`**

Extract the tool execution block (the entire `for _, tc := range res.ToolCalls` block) into a separate private method:
`func (l *Loop) processToolCalls(ctx context.Context, turn *agentTurn, toolCalls []llm.ToolCall) ([]string, error)`

- [ ] **Step 2: Extract `executeSingleIteration`**

Extract the body of the `for` loop in `executeLoop` into `func (l *Loop) executeSingleIteration(ctx context.Context, turn *agentTurn, budget *BudgetManager) (bool, error)`. It returns `bool` (done) and handles the LLM call, fallback, and invokes `processToolCalls`.

- [ ] **Step 3: Clean `executeLoop`**

`executeLoop` now becomes a clean 15-line function that sets up the loop, advances the budget, calls `executeSingleIteration`, and breaks when done.

- [ ] **Step 4: Run tests**

Run: `go test -v ./backend/internal/agent/...`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/agent/loop.go
git commit -m "refactor(agent): decompose executeLoop god-function into focused phases"
```

---

### Task 5: Exhaustion Fallback Simplification

**Files:**
- Modify: `backend/internal/agent/loop.go`

- [ ] **Step 1: Remove LLM exhaustion call**

In `finalizeResponse`, find the `if turn.completionReason == "exhausted"` block. Delete the code that constructs a new LLM request and calls `client.Complete()`.

- [ ] **Step 2: Use deterministic fallback**

Replace it with a fast, static assignment: 
`turn.finalContent = "Desculpe, esgotei o limite de ações permitidas sem conseguir formatar a resposta. Todas as consultas foram feitas, mas a tarefa era longa demais. Por favor, tente quebrar o pedido em partes menores."`

- [ ] **Step 3: Run tests**

Run: `go test -v ./backend/internal/agent/...`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add backend/internal/agent/loop.go
git commit -m "refactor(agent): use deterministic static string for exhaustion fallback"
```
