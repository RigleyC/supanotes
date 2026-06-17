# Plan 027: Structure Agent Context Rules

> **Executor instructions**: Follow this plan step by step. Run every verification command before moving on. If a STOP condition occurs, stop and report; do not improvise.
>
> **Drift check (run first)**:
> `git diff --stat fd87433..HEAD -- backend/internal/agent/context.go backend/internal/agent/context_test.go`

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/026-classify-agent-tool-risk-and-confirmation.md`
- **Category**: tech-debt
- **Planned at**: commit `fd87433`, 2026-06-17

## Why this matters

The agent prompt is currently built as one long context string with a final generic tool instruction. As tool risk and confirmation become explicit, the prompt should also separate system rules, tool rules, Soul, date/time, notes, tasks, and memories. This reduces accidental behavior changes and makes prompt tests meaningful.

## Current state

`backend/internal/agent/context.go:129-172` writes:

```go
b.WriteString(truncate(fmt.Sprintf(`SOUL:
%s

CURRENT DATE & TIME:
%s
`, soul.Personality, now), MaxTier0Tokens))
...
b.WriteString("\nYou have access to tools to modify the database. If the user asks you to create a note, use add_note. If the user asks about a specific file/note, search for its ID using search_notes, and then retrieve its full content using get_note.")
```

Existing `backend/internal/agent/context_test.go` verifies the builder returns non-empty context but does not lock section structure.

## Commands you will need

| Purpose | Command | Expected |
|---------|---------|----------|
| Context tests | `go test ./internal/agent -run TestContextBuilder_Build` from `backend/` | pass |
| Agent tests | `go test ./internal/agent/...` from `backend/` | pass |

## Scope

**In scope**:

- `backend/internal/agent/context.go`
- `backend/internal/agent/context_test.go`

**Out of scope**:

- Tool implementations
- Stream event contract
- Flutter UI
- LLM provider/model changes

## Steps

### Step 1: Add context section assertions

In `context_test.go`, add to `TestContextBuilder_Build`:

```go
requiredSections := []string{
	"SYSTEM RULES:",
	"TOOL RULES:",
	"SOUL:",
	"CURRENT DATE & TIME:",
	"TODAY/OVERDUE TASKS:",
	"RECENT NOTES",
	"SEMANTIC SEARCH RESULTS:",
	"RELATED NOTES:",
	"RELEVANT MEMORIES:",
}
for _, section := range requiredSections {
	if !strings.Contains(result, section) {
		t.Fatalf("expected context to contain %q, got:\n%s", section, result)
	}
}
```

Add `strings` import.

**Verify**:

```powershell
go test ./internal/agent -run TestContextBuilder_Build
```

Expected: FAIL because `SYSTEM RULES:` and `TOOL RULES:` are absent.

### Step 2: Add system and tool sections

In `context.go`, before `SOUL:`, write:

```go
b.WriteString(`SYSTEM RULES:
- Answer in the user's language.
- Be concise and explicit about what changed.
- Admit when available context is insufficient.

TOOL RULES:
- Use read tools when the current context is insufficient.
- Do not expose raw tool JSON or internal tool names to the user.
- Summarize successful writes in the final answer.
- Ask for confirmation before sensitive writes.

`)
```

Keep the existing section names for Soul, current date, tasks, recent notes, semantic search, related notes, and memories so existing behavior remains recognizable.

**Verify**:

```powershell
go test ./internal/agent -run TestContextBuilder_Build
```

Expected: PASS.

### Step 3: Replace final generic tool instruction

Replace the final `b.WriteString("\nYou have access...")` with:

```go
b.WriteString("\nUse tools only when they directly help answer or complete the user's request.")
```

**Verify**:

```powershell
go test ./internal/agent -run TestContextBuilder_Build
```

Expected: PASS.

### Step 4: Final backend verification

Run:

```powershell
go test ./internal/agent/...
```

Expected: PASS.

## Done criteria

- [ ] Context output contains `SYSTEM RULES:` and `TOOL RULES:`.
- [ ] Existing data context sections remain present.
- [ ] Generic tool instruction is replaced with concise rule.
- [ ] Context tests and agent tests pass.

## STOP conditions

- Plan 026 has not landed.
- Context test fakes no longer compile.
- This requires changing LLM provider code.
- Prompt changes require editing unrelated routines prompts.

## Maintenance notes

Routine prompts have a separate `BuildForRoutine` path. Do not force this chat prompt structure onto routine briefs without a separate product decision.
