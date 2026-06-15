# Plan 011: Decentralize agent tools god object

> **Executor instructions**: Follow this plan step by step.
> **Drift check**: `git diff --stat HEAD -- backend/internal/agent/tools.go`

## Status
- **Priority**: P3
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt

## Why this matters
`tools.go` is over 800 lines long and contains all LLM tool definitions, causing massive merge conflicts.

## Scope
**In scope**: `backend/internal/agent/tools.go`, `backend/internal/agent/tools/*.go`

## Steps

### Step 1: Create tools package/directory
Move each logical group of tools (e.g. `notes_tools.go`, `tasks_tools.go`) into their own files.

## Done criteria
- [ ] `tools.go` only acts as a registry.
- [ ] `plans/README.md` updated.
