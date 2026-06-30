# Node-Tree Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate SupaNotes editor and storage from a monolithic Markdown string to a structured Node Tree, treating tasks as relational entities while preserving Markdown generation on-the-fly for the LLM agent.

**Architecture:** We introduce a `note_nodes` table linked to `notes` and `tasks`. The Go backend handles delta syncs and on-the-fly Markdown rendering for the agent. The Flutter frontend maps `super_editor` nodes directly to Drift rows and uses incremental save.

**Tech Stack:** PostgreSQL, sqlc, Go, Echo, Flutter, Drift, super_editor.

---

### Task 1: Database Schema Migration

**Files:**
- Create: `backend/db/migrations/000024_node_tree_architecture.up.sql`
- Create: `backend/db/migrations/000024_node_tree_architecture.down.sql`

- [ ] **Step 1: Write UP migration**

```sql
CREATE TABLE note_nodes (
    id UUID PRIMARY KEY,
    note_id UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES note_nodes(id) ON DELETE CASCADE,
    position INT NOT NULL,
    type VARCHAR(50) NOT NULL,
    data JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE tasks ADD COLUMN node_id UUID REFERENCES note_nodes(id) ON DELETE CASCADE;
```

- [ ] **Step 2: Write DOWN migration**

```sql
ALTER TABLE tasks DROP COLUMN IF EXISTS node_id;
DROP TABLE IF EXISTS note_nodes;
```

- [ ] **Step 3: Run migration test**

Run: `migrate -path backend/db/migrations -database "postgres://postgres:postgres@localhost:5432/supanotes?sslmode=disable" up`
Expected: Migration successful.

- [ ] **Step 4: Commit**

```bash
git add backend/db/migrations/000024_node_tree_architecture.*
git commit -m "db: add note_nodes table and task relation for node-tree architecture"
```

---

### Task 2: Backend Query Layer

**Files:**
- Create: `backend/db/queries/nodes.sql`
- Modify: `backend/db/queries/tasks.sql`

- [ ] **Step 1: Write node queries**

Create `backend/db/queries/nodes.sql`:
```sql
-- name: InsertNode :one
INSERT INTO note_nodes (id, note_id, parent_id, position, type, data)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING *;

-- name: UpdateNode :one
UPDATE note_nodes
SET position = $2, data = $3, updated_at = NOW()
WHERE id = $1
RETURNING *;

-- name: DeleteNode :exec
DELETE FROM note_nodes WHERE id = $1;

-- name: GetNodesByNoteId :many
SELECT * FROM note_nodes WHERE note_id = $1 ORDER BY position ASC;
```

- [ ] **Step 2: Update tasks queries**

Modify `backend/db/queries/tasks.sql` to include `node_id` in inserts/updates where necessary. Add returning `node_id`.

- [ ] **Step 3: Generate SQLC**

Run: `cd backend && sqlc generate`
Expected: Code generated in `backend/internal/db/sqlcgen/nodes.sql.go`.

- [ ] **Step 4: Commit**

```bash
git add backend/db/queries/nodes.sql backend/db/queries/tasks.sql backend/internal/db/sqlcgen
git commit -m "db: generate sqlc queries for note_nodes"
```

---

### Task 3: Backend Markdown Renderer

**Files:**
- Create: `backend/internal/notes/renderer.go`
- Create: `backend/internal/notes/renderer_test.go`

- [ ] **Step 1: Write failing test**

```go
func TestRenderNoteToMarkdown(t *testing.T) {
	// Mock nodes: a paragraph and a task
	nodes := []sqlcgen.NoteNode{
		{ID: uuid.New(), Type: "paragraph", Data: []byte(`{"text": "Hello world"}`)},
		{ID: uuid.New(), Type: "task", Data: []byte(`{"text": "Buy milk"}`)},
	}
	tasks := map[pgtype.UUID]sqlcgen.Task{
		nodes[1].ID: {Status: "open"},
	}

	markdown := RenderNoteToMarkdown(nodes, tasks)
	expected := "Hello world\n- [ ] Buy milk\n"
	
	if markdown != expected {
		t.Errorf("Expected %q, got %q", expected, markdown)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test -v ./backend/internal/notes/... -run TestRenderNoteToMarkdown`
Expected: Compile error.

- [ ] **Step 3: Write minimal implementation**

```go
package notes

import (
	"encoding/json"
	"strings"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

func RenderNoteToMarkdown(nodes []sqlcgen.NoteNode, tasks map[pgtype.UUID]sqlcgen.Task) string {
	var sb strings.Builder
	for _, n := range nodes {
		var data map[string]interface{}
		json.Unmarshal(n.Data, &data)
		text, _ := data["text"].(string)

		switch n.Type {
		case "paragraph":
			sb.WriteString(text + "\n")
		case "task":
			status := " "
			if t, ok := tasks[n.ID]; ok && t.Status == "done" {
				status = "x"
			}
			sb.WriteString("- [" + status + "] " + text + "\n")
		}
	}
	return sb.String()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test -v ./backend/internal/notes/... -run TestRenderNoteToMarkdown`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/notes/renderer.go backend/internal/notes/renderer_test.go
git commit -m "feat(notes): add backend markdown renderer for node tree"
```

---

### Task 4: Agent Context Refactoring

**Files:**
- Modify: `backend/internal/agent/context.go`

- [ ] **Step 1: Update ContextBuilder**

Modify `ContextBuilder.Build()` to fetch nodes via `GetNodesByNoteId` instead of reading the monolithic `content` field for recent notes. Pass the fetched nodes and associated tasks to `notes.RenderNoteToMarkdown` to generate the text injected into the prompt.

- [ ] **Step 2: Run tests**

Run: `go test -v ./backend/internal/agent/...`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add backend/internal/agent/context.go
git commit -m "feat(agent): update context builder to render markdown from nodes on the fly"
```

---

### Task 5: Frontend Drift Schema

**Files:**
- Create: `lib/core/database/tables/note_nodes.dart`
- Modify: `lib/core/database/tables/tasks.dart`
- Modify: `lib/core/database/database.dart`

- [ ] **Step 1: Create NoteNodes table**

```dart
import 'package:drift/drift.dart';
import 'notes.dart';

class NoteNodes extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text().references(Notes, #id)();
  TextColumn get parentId => text().nullable().references(NoteNodes, #id)();
  IntColumn get position => integer()();
  TextColumn get type => text()();
  TextColumn get data => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 2: Update Tasks table**

Add `nodeId` column to `Tasks` table:
```dart
TextColumn get nodeId => text().nullable().references(NoteNodes, #id)();
```

- [ ] **Step 3: Run build_runner**

Run: `dart run build_runner build -d`
Expected: Drift database generated successfully.

- [ ] **Step 4: Commit**

```bash
git add lib/core/database/
git commit -m "feat(flutter): add note_nodes table and task relation to drift schema"
```

---

### Task 6: Frontend Editor Controller Deltas

**Files:**
- Create: `lib/features/notes/domain/node_sync_manager.dart`
- Modify: `lib/features/notes/presentation/controllers/note_editor_controller.dart`

- [ ] **Step 1: Write NodeSyncManager**

Implement `NodeSyncManager` that listens to `MutableDocument.changes` and translates `DocumentEdit` events (insert, update, delete) into Drift `NoteNodesCompanion` objects, bypassing the old `markdownSerializer`.

- [ ] **Step 2: Update NoteEditorController**

Remove the `SaveThrottle` that serializes the entire markdown. Instantiate `NodeSyncManager` during `init()` and attach it to the document. Update the initial load sequence to query `NoteNodes` from Drift and map them directly to `DocumentNode` instances, assembling the `MutableDocument` without parsing markdown.

- [ ] **Step 3: Run tests**

Run: `flutter test`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/features/notes/
git commit -m "feat(flutter): implement incremental save and load via node tree in super_editor"
```
