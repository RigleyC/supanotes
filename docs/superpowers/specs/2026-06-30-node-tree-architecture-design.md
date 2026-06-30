# Spec: Hybrid Node-Tree Task Architecture

## Goal
Migrate the SupaNotes note editor and storage model from a monolithic Markdown string to a structured Node Tree, specifically treating tasks as first-class relational entities, while preserving Markdown generation on-the-fly for the LLM agent. This eliminates fragile regex/HTML-comment parsing, drastically reduces network/database sync payloads (incremental save), and gives the agent typed tools for modifying tasks.

## 1. Data Model (PostgreSQL)

```sql
CREATE TABLE note_nodes (
    id UUID PRIMARY KEY,
    note_id UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES note_nodes(id) ON DELETE CASCADE,
    position INT NOT NULL,
    type VARCHAR(50) NOT NULL, -- 'paragraph', 'heading', 'task', 'divider', 'attachment'
    data JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Existing tasks table is modified/linked to nodes
ALTER TABLE tasks 
    ADD COLUMN node_id UUID REFERENCES note_nodes(id) ON DELETE CASCADE;
```

## 2. Frontend (Flutter / super_editor)

### 2.1 Node Representation
- Remove `markdownSerializer` and HTML comments hack (`<!-- task:UUID -->`) from the critical save path.
- Map `DocumentNode` instances (e.g. `ParagraphNode`, `TaskNode`, `HorizontalRuleNode`) directly to `NodeRow` objects in Drift.
- `TaskNode` in memory pairs with a `TaskModel` that corresponds directly to the `tasks` table.

### 2.2 Incremental Save
- Instead of serializing the whole document on every keystroke, the `NoteEditorController` will listen to `Document` changes and emit delta updates: `insertNode`, `updateNode`, `deleteNode`.
- The `NotesRepository` and Drift DAOs will execute these deltas against the local `note_nodes` table.

### 2.3 Loading (TTI Improvement)
- Fetch nodes ordered by `position`.
- Convert `NodeRow` list directly into a `MutableDocument`. This eliminates markdown parsing on note open.

## 3. Backend (Go)

### 3.1 Context Builder (Agent Read Path)
- The agent loop requires Markdown.
- Add `RenderNoteToMarkdown(note_id)` function in the backend.
- It queries `note_nodes` ordered by position, joins with `tasks` and `attachments` where applicable, and concatenates them into clean Markdown.
- Example task render: `- [ ] Buy milk 📅2026-06-30 🔁weekly`
- This ensures the agent (via `ContextBuilder` or `get_note` tool) receives pure text, consuming zero extra tokens.

### 3.2 Agent Tools (Agent Write Path)
- Agent no longer uses string manipulation to edit tasks.
- Introduce typed tools:
  - `create_task(note_id, text, due_date, recurrence, after_node_id)`
  - `update_task(task_id, ...)`
- These tools update the structured rows, completely eliminating the risk of the agent breaking markdown formatting.

### 3.3 RAG & Embeddings
- Chunk boundaries are updated to respect the Node Tree.
- Instead of arbitrary 500-char text chunks, chunks are generated semantically (e.g., a Heading node + its child paragraphs).

## 4. Migration Strategy
This is a major architectural shift.
- **Phase 1:** Schema creation and Go backend API updates (Read/Write delta endpoints).
- **Phase 2:** Update `ContextBuilder` to render Markdown from nodes on-the-fly.
- **Phase 3:** Flutter Migration (replace markdown serializer with node synchronizer).
- **Phase 4:** Data Migration script (parse existing `content` in `notes` into `note_nodes` and link to `tasks`).
