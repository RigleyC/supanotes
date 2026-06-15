# Plan 015: Expose inbox organization tools to Agent

> **Executor instructions**: Follow this plan step by step.
> **Drift check**: `git diff --stat HEAD -- backend/internal/agent/tools.go`

## Status
- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: direction

## Why this matters
The roadmap specifies that the Agent should be able to organize the inbox. The HTTP endpoints exist, but the tools are not registered for the LLM.

## Scope
**In scope**: `backend/internal/agent/tools.go`

## Steps

### Step 1: Define Tools
Create `PlanInboxOrganizationTool` and `ApplyInboxOrganizationTool` structs.
Register them in `NewToolRegistry`.

## Done criteria
- [ ] Agent can call inbox tools.
- [ ] `plans/README.md` updated.
