# Hermes Patterns Integration — Design Spec

## Overview

Integrate proven patterns from Hermes Agent (NousResearch/hermes-agent) into the SupaNotes agent. Our audit revealed that Hermes' excellence comes from **behavioral prompt engineering and loop intelligence**, not its specific file-based architecture.

This spec adapts the "Hermes Secret Sauce" (Budget Pressure, Tool Pruning, Strict Memory Discipline, Tool Enforcement) to SupaNotes' existing PostgreSQL/pgvector architecture.

## Approach: "Hermes Lite" (Behavioral Focus)

Instead of rewriting our storage layer to use markdown files and SQLite (as originally proposed), we will enhance our existing DB-backed systems with Hermes' rigorous behavioral constraints.

---

## 1. System Prompt Enrichment (The Core Fix)

The system prompt (`backend/internal/agent/system_prompt.md`) will be heavily enriched with Hermes patterns to stop the agent from narrating and force it to act.

### Tool-Use Enforcement
- **Rule:** Don't describe what you would do — call the tool.
- **Rule:** Continue until you have the actual result. Never stop at a stub or plan.
- **Rule:** Batch independent reads (parallel tool calls) in a single turn.

### Memory Discipline
- **Rule:** Save declarative facts, not instructions to yourself.
- **Rule:** Do not save session state, progress logs, or temporary TODOs.
- **Rule:** Check existing memories before saving duplicates.
- **Context boundary:** Wrap memory injection in XML-style tags (`<memory-context>`) to prevent injection and help the model parse sections.

### Per-Tool Rules
Specific guidance injected for:
- `search_notes` vs `get_note`
- `add_task` (only when explicit or cross-referenced)
- `save_memory` (facts only)

---

## 2. The Ralph Loop & Budget Pressure

Currently, the loop hard-stops at 5 iterations. Hermes uses a "Ralph Loop" with Budget Pressure to ensure graceful wrap-ups.

**Changes to `loop.go`:**
1. **Increase limit:** 5 → 15 iterations.
2. **Budget Pressure (Ephemeral Warnings):**
   - At iteration 12, inject a temporary system message into the message list: *"You are approaching the iteration limit. Start producing your final response."*
   - At iteration 14, inject: *"This is your last iteration. Provide your final answer now."*
3. **Graceful Exhaustion:** If it hits iteration 15, make a final tool-less LLM call to summarize progress instead of returning a generic error string.

---

## 3. Context Compression (Cheapest First)

Long sessions exceed context windows. Hermes handles this in two phases:

**Phase 1: Tool Output Pruning (Fast & Cheap)**
- When history > 15 messages, scan for tool-result messages older than the last 8 turns.
- Replace their large JSON/text content with a placeholder: `[Earlier tool output cleared to save context space]`.
- *Why:* Tool outputs consume the most tokens and are rarely needed verbatim after the LLM has already reasoned over them.

**Phase 2: Static History Truncation**
- Keep the system prompt + first 3 messages + last 8 messages.
- Replace the middle with `[Earlier conversation messages were trimmed. Recent context is preserved.]`.
- *(LLM-based summarization of the middle is deferred to a future phase).*

---

## 4. Strict Memory Management

Hermes treats memory as a scarce budget. We will enforce this on our pgvector DB:

1. **Anti-Injection Scanning:**
   - In `memories.Service.CreateMemory()`, scan content for prompt injection patterns (`ignore previous instructions`, `system prompt:`, `forget everything`).
   - Reject malicious content.
2. **Hard Limits & Agent Curation:**
   - Limit memories per user (e.g., max 50 memories).
   - If `save_memory` hits the limit, return an error instructing the agent to use `list_memories` and `delete_memory` to consolidate outdated facts before trying again.
3. **No 'Read' Tool:**
   - Memories are already injected via semantic RAG. The agent should rely on the injected context. `list_memories` is kept ONLY for finding IDs to delete.

---

## 5. Files to Modify

| File | Action | Description |
|------|--------|-------------|
| `backend/internal/agent/system_prompt.md` | Modify | Add tool enforcement, memory rules, parallel calls, XML tags |
| `backend/internal/agent/loop.go` | Modify | 15 iterations, Budget Pressure messages, tool pruning |
| `backend/internal/agent/tools/memories_tools.go` | Modify | Update tool descriptions with discipline rules |
| `backend/internal/memories/service.go` | Modify | Add anti-injection scanning, per-user memory limits |
| `backend/internal/agent/context.go` | Modify | Wrap memories in `<memory-context>`, fix Token vs Bytes naming |

---

## 6. Migration & Rollout

This approach requires **zero breaking changes** to the database schema or file structure.

1. **Phase 1: Prompt & Loop**
   - Update `system_prompt.md`
   - Implement 15 iterations + Budget Pressure
2. **Phase 2: Memory Discipline**
   - Add injection scanning and limits to memory service
   - Update memory tool descriptions
3. **Phase 3: Compression**
   - Implement tool output pruning in the loop

---

## 7. Success Criteria

1. Agent never says "I will check the tasks" without actually calling the tool in the same turn.
2. Agent never stops mid-task due to hitting a silent iteration limit.
3. Memories remain clean (no session state or instructions-to-self).
4. Long conversations remain responsive due to tool output pruning.
