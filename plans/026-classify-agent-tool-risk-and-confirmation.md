# Plan 026: Classify Agent Tool Risk And Confirmation

> **Executor instructions**: Follow this plan step by step. Run every verification command before moving on. If a STOP condition occurs, stop and report; do not improvise.
>
> **Drift check (run first)**:
> `git diff --stat fd87433..HEAD -- backend/internal/agent/tools/registry.go backend/internal/agent/loop.go backend/internal/agent/events.go backend/internal/agent/tools`

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: `plans/023-normalize-agent-chat-stream-contract.md`
- **Category**: security
- **Planned at**: commit `fd87433`, 2026-06-17

## Why this matters

The agent has tools that read data and tools that mutate notes, tasks, memories, routines, and Soul. Treating them all the same erodes trust: sensitive writes can happen without a clear preview or confirmation path. This plan adds explicit risk metadata and a confirmation-required event for sensitive tools. It should be implemented before allowing richer autonomous actions in the chat UI.

## Current state

- `backend/internal/agent/tools/registry.go` registers all tools in one map and exposes only `GetTools()` and `Execute(...)`.
- `backend/internal/agent/loop.go` executes any model-requested tool immediately.
- Existing tools include low-risk reads like `SearchNotesTool`, writes like `AddNoteTool`, and sensitive writes like `UpdateSoulTool`, `DeleteMemoryTool`, and `ApplyInboxOrganizationTool`.

## Commands you will need

| Purpose | Command | Expected |
|---------|---------|----------|
| Tool tests | `go test ./internal/agent/tools/...` from `backend/` | pass |
| Agent tests | `go test ./internal/agent/...` from `backend/` | pass |

## Scope

**In scope**:

- `backend/internal/agent/tools/registry.go`
- `backend/internal/agent/tools/registry_test.go` (create)
- `backend/internal/agent/events.go`
- `backend/internal/agent/loop.go`
- `backend/internal/agent/loop_test.go` if needed

**Out of scope**:

- Flutter confirmation UI
- Prompt/context rewriting
- Changing tool implementations
- Deleting tools

## Steps

### Step 1: Add risk metadata tests

Create `backend/internal/agent/tools/registry_test.go`:

```go
package tools

import "testing"

func TestToolRegistryRiskDefaults(t *testing.T) {
	registry := &ToolRegistry{tools: map[string]ToolExecutor{}}

	cases := map[string]ToolRisk{
		"search_notes":             ToolRiskRead,
		"get_note":                 ToolRiskRead,
		"add_note":                 ToolRiskLowWrite,
		"append_to_inbox":          ToolRiskLowWrite,
		"update_note":              ToolRiskSensitiveWrite,
		"delete_memory":            ToolRiskSensitiveWrite,
		"update_soul":              ToolRiskSensitiveWrite,
		"apply_inbox_organization": ToolRiskSensitiveWrite,
	}

	for name, want := range cases {
		if got := registry.Risk(name); got != want {
			t.Fatalf("%s risk: want %s, got %s", name, want, got)
		}
	}
}
```

**Verify**:

```powershell
go test ./internal/agent/tools -run TestToolRegistryRiskDefaults
```

Expected: FAIL because `ToolRisk` and `Risk` do not exist.

### Step 2: Add risk enum and label lookup

In `registry.go`, add:

```go
type ToolRisk string

const (
	ToolRiskRead           ToolRisk = "read"
	ToolRiskLowWrite       ToolRisk = "low_write"
	ToolRiskSensitiveWrite ToolRisk = "sensitive_write"
)
```

Add:

```go
func (tr *ToolRegistry) Risk(toolName string) ToolRisk {
	switch toolName {
	case "search_notes", "get_note", "get_notes", "get_open_tasks", "get_today_tasks", "list_memories", "get_soul", "list_routines", "get_vault_context":
		return ToolRiskRead
	case "add_note", "add_task", "save_memory", "append_to_inbox":
		return ToolRiskLowWrite
	case "update_note", "append_to_note", "delete_memory", "update_soul", "apply_inbox_organization", "set_daily_brief_schedule", "set_weekly_brief_schedule", "update_task", "complete_task":
		return ToolRiskSensitiveWrite
	default:
		return ToolRiskSensitiveWrite
	}
}
```

Also move any local tool label helper from Plan 023 into:

```go
func (tr *ToolRegistry) Label(toolName string) string { ... }
```

**Verify**:

```powershell
go test ./internal/agent/tools -run TestToolRegistryRiskDefaults
```

Expected: PASS.

### Step 3: Add confirmation event contract

In `backend/internal/agent/events.go`, add:

```go
EventConfirmationRequired EventType = "confirmation_required"
```

Add payload:

```go
type ConfirmationRequiredPayload struct {
	ToolName string `json:"tool_name"`
	Label    string `json:"label"`
	ArgsJSON string `json:"args_json"`
}
```

**Verify**:

```powershell
go test ./internal/agent/...
```

Expected: pass.

### Step 4: Gate sensitive writes in loop

In `loop.go`, before executing a tool:

```go
if l.tools.Risk(tc.Name) == tools.ToolRiskSensitiveWrite {
	sendStreamEvent(events, writer.Event(
		EventConfirmationRequired,
		ConfirmationRequiredPayload{
			ToolName: tc.Name,
			Label:    l.tools.Label(tc.Name),
			ArgsJSON: tc.ArgsJSON,
		},
	))
	finalContent = "Preciso da sua confirmação antes de aplicar essa alteração."
	sendStreamEvent(events, writer.Event(
		EventMessageFinished,
		MessageFinishedPayload{Content: finalContent},
	))
	return finalContent, nil
}
```

If importing the `tools` package into `agent` causes an import cycle, move `ToolRisk` type alias or constants to the `agent` package boundary. Do not collapse packages to work around it.

**Verify**:

```powershell
go test ./internal/agent/...
```

Expected: pass.

### Step 5: Add loop test for sensitive tool gating

Add a test proving that a fake sensitive tool request emits `confirmation_required` and does not call `Execute`.

**Verify**:

```powershell
go test ./internal/agent -run Confirmation
```

Expected: pass.

### Step 6: Final verification

Run:

```powershell
go test ./internal/agent/... ./internal/agent/tools/...
```

Expected: pass.

## Done criteria

- [ ] Every tool has deterministic risk classification.
- [ ] Unknown tools default to sensitive write.
- [ ] Sensitive writes emit `confirmation_required` and do not execute.
- [ ] Existing read and low-risk write behavior remains unchanged.
- [ ] Backend tests pass.

## STOP conditions

- Plan 023 has not landed.
- Risk gating requires a new database table.
- Import cycles appear and cannot be resolved without moving broad packages.
- Tests need real LLM/tool services.

## Maintenance notes

This plan creates backend enforcement but not the full confirmation UX. A follow-up UI plan should render `confirmation_required` with preview/apply controls.
