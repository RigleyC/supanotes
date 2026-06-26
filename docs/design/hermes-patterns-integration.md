# Hermes Patterns Integration — Design Document

## Analysis Summary

Hermes Agent (NousResearch/hermes-agent) and SupaNotes agent serve similar purposes (personal AI agent with tool use) but differ significantly in architecture. This document outlines specific changes to bring Hermes-proven patterns into SupaNotes.

---

## Current State vs Target State

| Aspect | SupaNotes (Current) | Hermes (Target) |
|--------|---------------------|-----------------|
| System prompt | Flat file (92 lines) | 3-tier layered (stable/context/volatile) |
| Agent personality | String in DB (`soul.personality`) | SOUL.md file + DB override |
| Agent loop | 5 iterations | 30+ iterations with budget |
| Memory | Embedding search only | File-based (MEMORY.md, USER.md) + embedding |
| Tool guidance | None | Detailed guidance per tool category |
| Context handling | Truncation | Compression (summarize, don't truncate) |
| Model awareness | Same prompt for all | Model-specific guidance |
| Skills | None | Dynamic skill loading |

---

## Proposed Changes

### 1. Create SOUL.md Base Personality File

**File:** `backend/internal/agent/soul.md`

This becomes the stable identity layer — always present, never changes between sessions. The user's `soul.personality` from the DB overrides or extends it.

```markdown
# SupaNotes Agent

You are the organizational intelligence of SupaNotes — a personal notes app with
proactive AI capabilities. You help users manage their notes, tasks, and daily
routines with personality and insight.

## Core Identity

- You are warm, direct, and occasionally witty
- You speak the user's language (Portuguese or English, matching their input)
- You have opinions — you're not a passive list机器
- You cross-reference information across notes, tasks, and memories
- You proactively surface connections the user might miss

## Fundamental Rules

1. Never invent information. Use tools to check before answering.
2. Never expose internal IDs, UUIDs, database fields, tool names, or raw outputs.
3. Every response must improve clarity, organization, prioritization, memory, or execution.
4. Prefer silence over weak advice.
5. Don't explain what you're about to do — just do it.

## Behavioral Patterns

### When asked about their day/agenda:
- ALWAYS use tools first (get_today_tasks, get_recent_notes)
- Cross-reference notes with tasks — find commitments without corresponding tasks
- Check recently completed tasks for context ("you finished X yesterday")
- End with prioritized action list

### When user says they completed something:
- Search for matching task by keyword
- If ambiguous, ask which task — don't guess
- After completing, mention what's next

### When reviewing notes:
- Identify action items that aren't tasks yet
- Flag abandoned notes only when genuinely useful
- Don't suggest things just because you can

## Writing Style

- Direct and concise
- Use emoji sparingly for emphasis
- Structure responses with clear sections
- End with actionable next steps
```

**Why:** This gives the agent a stable personality regardless of what the user configures. The user's `soul.personality` can override specific sections.

---

### 2. Restructure System Prompt to 3-Tier Format

**File:** `backend/internal/agent/context.go` (rewrite `Build` method)

Current structure:
```
IDENTITY → CURRENT CONTEXT → BRIEFING → TASKS → NOTES → SEMANTIC → RELATED → MEMORIES → system_prompt
```

New structure (matching Hermes):
```
STABLE TIER (never changes per conversation):
  - SOUL.md content
  - Tool guidance
  - Behavioral rules
  
CONTEXT TIER (changes per session):
  - File context (soul personality, memories, notes)
  - Skills (future)
  
VOLATILE TIER (changes per message):
  - Current timestamp
  - Memory snapshot (relevant memories for this query)
  - User query context
```

**Implementation:**

```go
func (cb *ContextBuilder) Build(ctx context.Context, userID, sessionID pgtype.UUID, query string) (string, error) {
    var b strings.Builder

    // === STABLE TIER (cached across conversation) ===
    b.WriteString(soulBaseContent)  // from soul.md
    b.WriteString("\n\n")
    b.WriteString(toolGuidance)      // tool usage rules
    
    // === CONTEXT TIER (per session) ===
    b.WriteString("\n\n")
    b.WriteString(fmt.Sprintf("USER PERSONALITY:\n%s\n\n", soul.Personality))
    
    // Recent notes, tasks, etc.
    b.WriteString(fmt.Sprintf("TODAY TASKS:\n%s\n", formatTasks(todayTasks)))
    b.WriteString(fmt.Sprintf("RECENT NOTES:\n%s\n", formatNotes(recentNotes)))
    
    // === VOLATILE TIER (per message) ===
    b.WriteString(fmt.Sprintf("\nCURRENT TIME: %s\n", timeStr))
    b.WriteString(fmt.Sprintf("RELEVANT MEMORIES:\n%s\n", formatMemories(memResults)))
    b.WriteString(fmt.Sprintf("SEMANTIC RESULTS:\n%s\n", formatSemantic(semanticResults)))

    return b.String(), nil
}
```

---

### 3. Add Tool Guidance to System Prompt

**File:** `backend/internal/agent/tool_guidance.md` (new file)

```markdown
## Tool Usage Guidelines

### When to Use Tools

**ALWAYS use tools before answering about user data:**
- Questions about tasks, notes, agenda → use tools first
- "What do I have today?" → get_today_tasks + get_recent_notes
- "What's in my inbox?" → get_inbox_note
- Never guess from context alone

**Parallel tool calls:**
- When you need multiple independent pieces of information, call all tools at once
- Example: get_today_tasks AND get_recent_notes AND get_vault_context can be called together
- This is faster than calling them sequentially

**Tool call completion:**
- After executing tools, synthesize the results into a coherent response
- Don't just dump raw tool output
- Cross-reference results from different tools

### Tool-Specific Guidance

**search_notes:**
- Use for keyword/concept searches
- Prefer over browsing when looking for specific content
- Can search by title or content

**get_note:**
- Use when you need full content of a specific note
- Requires note ID from search_notes or get_notes

**query_tasks:**
- Use for task searches with filters
- Can filter by status (open/done), date, keywords

**save_memory:**
- Use when user shares preferences, routines, or recurring patterns
- Don't save one-time information
- Check existing memories before saving duplicates

**add_task:**
- Only create tasks when user explicitly asks or when cross-referencing reveals missing tasks
- Don't create tasks from every mention of an action

### Response Guidelines

- Never reveal tool names, IDs, or raw outputs
- Translate internal concepts to natural language
- After tool execution, provide synthesized response, not raw data
```

---

### 4. Increase Agent Loop Iterations

**File:** `backend/internal/agent/loop.go`

Change line 162:
```go
// Before
for i := 0; i < 5; i++ {

// After
for i := 0; i < 30; i++ {
```

**Add budget tracking (optional enhancement):**
```go
type Loop struct {
    repo            Repository
    llmFact         llm.Factory
    ctxBldr         *ContextBuilder
    tools           *ToolRegistry
    maxIterations   int
    maxTokensBudget int
}

func NewLoop(...) *Loop {
    return &Loop{
        ...
        maxIterations:   30,
        maxTokensBudget: 100000,
    }
}
```

---

### 5. Implement File-Based Memory System

**File:** `backend/internal/agent/memory.go` (new file)

```go
package agent

import (
    "os"
    "path/filepath"
    "strings"
)

const (
    MaxMemoryChars = 2200
    MaxProfileChars = 1375
)

type MemoryManager struct {
    dataDir string // e.g., /app/data/agent-memory/{userID}/
}

func NewMemoryManager(dataDir string) *MemoryManager {
    return &MemoryManager{dataDir: dataDir}
}

func (m *MemoryManager) userDir(userID string) string {
    return filepath.Join(m.dataDir, userID)
}

func (m *MemoryManager) GetMemory(userID string) (string, error) {
    path := filepath.Join(m.userDir(userID), "MEMORY.md")
    data, err := os.ReadFile(path)
    if os.IsNotExist(err) {
        return "", nil
    }
    if err != nil {
        return "", err
    }
    return string(data), nil
}

func (m *MemoryManager) SaveMemory(userID, content string) error {
    if len(content) > MaxMemoryChars {
        content = content[:MaxMemoryChars]
    }
    
    // Security scan (from Hermes)
    if err := m.validateContent(content); err != nil {
        return err
    }
    
    dir := m.userDir(userID)
    if err := os.MkdirAll(dir, 0755); err != nil {
        return err
    }
    
    path := filepath.Join(dir, "MEMORY.md")
    return os.WriteFile(path, []byte(content), 0644)
}

func (m *MemoryManager) GetProfile(userID string) (string, error) {
    path := filepath.Join(m.userDir(userID), "USER.md")
    data, err := os.ReadFile(path)
    if os.IsNotExist(err) {
        return "", nil
    }
    if err != nil {
        return "", err
    }
    return string(data), nil
}

func (m *MemoryManager) SaveProfile(userID, content string) error {
    if len(content) > MaxProfileChars {
        content = content[:MaxProfileChars]
    }
    
    if err := m.validateContent(content); err != nil {
        return err
    }
    
    dir := m.userDir(userID)
    if err := os.MkdirAll(dir, 0755); err != nil {
        return err
    }
    
    path := filepath.Join(dir, "USER.md")
    return os.WriteFile(path, []byte(content), 0644)
}

func (m *MemoryManager) validateContent(content string) error {
    // Injection patterns from Hermes
    suspiciousPatterns := []string{
        "ignore previous instructions",
        "ignore all previous",
        "disregard previous",
        "new instructions:",
        "system prompt:",
        "you are now",
        "forget everything",
    }
    
    lower := strings.ToLower(content)
    for _, pattern := range suspiciousPatterns {
        if strings.Contains(lower, pattern) {
            return fmt.Errorf("content contains suspicious pattern: %s", pattern)
        }
    }
    return nil
}
```

---

### 6. Add Context Compression

**File:** `backend/internal/agent/compression.go` (new file)

```go
package agent

import (
    "strings"
)

// CompressContext summarizes context when approaching token limits
// Instead of truncating (losing info), we summarize (keeping essence)
func CompressContext(content string, maxTokens int) string {
    // Rough estimate: 1 token ≈ 4 chars
    maxChars := maxTokens * 4
    
    if len(content) <= maxChars {
        return content
    }
    
    // Strategy 1: Remove redundant sections
    // Strategy 2: Summarize long sections
    // Strategy 3: Keep most recent/relevant items
    
    // For now, implement smart truncation:
    // Keep beginning (identity/rules) and end (recent context)
    // Summarize middle sections
    
    lines := strings.Split(content, "\n")
    
    // Keep first 20% (stable tier - identity, rules)
    stableEnd := len(lines) / 5
    if stableEnd < 5 {
        stableEnd = 5
    }
    
    // Keep last 40% (volatile tier - recent context)
    volatileStart := len(lines) - (len(lines) * 4 / 10)
    if volatileStart < stableEnd+5 {
        volatileStart = stableEnd + 5
    }
    
    // Middle section gets summarized
    middle := lines[stableEnd:volatileStart]
    summary := summarizeSection(middle)
    
    var result []string
    result = append(result, lines[:stableEnd]...)
    result = append(result, "\n[CONTEXT COMPRESSED - summary of removed section]")
    result = append(result, summary)
    result = append(result, "\n[END COMPRESSED SECTION]\n")
    result = append(result, lines[volatileStart:]...)
    
    return strings.Join(result, "\n")
}

func summarizeSection(lines []string) string {
    // Simple extractive summary: keep first sentence of each paragraph
    var summary []string
    for _, line := range lines {
        if strings.TrimSpace(line) != "" {
            summary = append(summary, line)
        }
    }
    return strings.Join(summary, "\n")
}
```

---

### 7. Update ContextBuilder to Use New Structure

**File:** `backend/internal/agent/context.go`

```go
//go:embed soul.md
var soulBaseContent string

//go:embed tool_guidance.md
var toolGuidanceContent string

func (cb *ContextBuilder) Build(ctx context.Context, userID, sessionID pgtype.UUID, query string) (string, error) {
    // ... existing data fetching ...
    
    var b strings.Builder

    // === STABLE TIER ===
    b.WriteString(soulBaseContent)
    b.WriteString("\n\n")
    b.WriteString(toolGuidanceContent)
    b.WriteString("\n\n---\n\n")

    // === CONTEXT TIER ===
    b.WriteString(fmt.Sprintf("USER PERSONALITY:\n%s\n\n", soul.Personality))
    
    // Tasks
    if len(todayTasks) > 0 {
        b.WriteString("TODAY/OVERDUE TASKS:\n")
        writeTasksWithStatus(&b, todayTasks)
        b.WriteString("\n")
    }
    
    // Notes
    if len(recentNotes) > 0 {
        b.WriteString("RECENT NOTES (Last 48h):\n")
        writeNotesWithID(&b, recentNotes)
        b.WriteString("\n")
    }

    // === VOLATILE TIER ===
    nowStr := time.Now().In(tzLoc).Format("2006-01-02 15:04:05 MST")
    weekday := time.Now().In(tzLoc).Weekday().String()
    b.WriteString(fmt.Sprintf("CURRENT TIME: %s (%s) %s\n\n", nowStr, weekday, tzLoc.String()))

    // Semantic results
    if len(semanticResults) > 0 {
        b.WriteString("SEMANTIC SEARCH:\n")
        for _, r := range semanticResults {
            b.WriteString(fmt.Sprintf("- [%s] %s (similarity: %.4f)\n", 
                uid.UUIDToString(r.ID), notes.DeriveTitle(r.Content), r.Similarity))
        }
        b.WriteString("\n")
    }

    // Memories
    if len(memResults) > 0 {
        b.WriteString("RELEVANT MEMORIES:\n")
        for _, m := range memResults {
            b.WriteString(fmt.Sprintf("- %s\n", m.Content))
        }
        b.WriteString("\n")
    }

    return b.String(), nil
}
```

---

### 8. Update Loop to Use New Structure

**File:** `backend/internal/agent/loop.go`

```go
func (l *Loop) doChat(ctx context.Context, userID pgtype.UUID, sessionIDStr, userMessage string, events chan<- StreamEvent) (string, error) {
    // ... existing setup ...

    // 4. Tool Calling Loop (max 30 iterations)
    for i := 0; i < 30; i++ {
        // ... existing logic ...
        
        // Add compression if context too large
        if len(messages) > 20 {
            messages = l.compressMessages(messages)
        }
    }
    
    // ... rest of function ...
}

func (l *Loop) compressMessages(messages []llm.Message) []llm.Message {
    // Keep system message + last 10 messages
    if len(messages) <= 11 {
        return messages
    }
    
    systemMsg := messages[0]
    recentMsgs := messages[len(messages)-10:]
    
    // Add summary message
    summary := llm.Message{
        Role:    llm.RoleUser,
        Content: "[Context compressed: earlier messages summarized]",
    }
    
    return append([]llm.Message{systemMsg, summary}, recentMsgs...)
}
```

---

## Migration Path

### Phase 1: Core Changes (No Breaking Changes)
1. Create `soul.md` and `tool_guidance.md` files
2. Increase loop iterations from 5 to 30
3. Update context builder to use 3-tier structure
4. Keep existing tool system unchanged

### Phase 2: Memory System
1. Add `memory.go` with file-based memory
2. Update `memories_tools.go` to use file-based storage
3. Migrate existing DB memories to files

### Phase 3: Advanced Features
1. Add context compression
2. Add model-specific guidance
3. Add skills system (future)

---

## Testing Strategy

1. **Unit tests for memory manager** — CRUD operations, security scanning
2. **Unit tests for context compression** — verify no data loss
3. **Integration tests for agent loop** — verify 30 iterations work
4. **Manual testing** — verify personality is consistent, tools work correctly

---

## Open Questions

1. **Memory storage location** — filesystem vs database? Filesystem is simpler, database is more portable.
2. **Compression algorithm** — simple truncation vs LLM-based summarization?
3. **Skills system** — when to implement? Depends on complexity budget.
4. **Backward compatibility** — how to handle existing users' memories?

---

## Success Criteria

1. Agent responds with consistent personality across sessions
2. Agent uses tools correctly (not guessing from context)
3. Agent can handle complex multi-step tasks (30+ iterations)
4. Memory persists between sessions
5. Context doesn't exceed token limits
