# Sync Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement fractional indexing, single source of truth for YDoc, and robust sync logic for SupaNotes.

**Architecture:** 
1. Fractional index strings for positions in Go and Flutter (using strict lexo-rank compatibility across both languages).
2. `NodeSyncManager` delegates all remote writes to `YjsDocEditorBridge` with a 50ms micro-debounce (to group keystrokes without UI lag).
3. Tasks map is removed; tasks are purely nodes with `completed`, `due_date`, `recurrence` in `data`. They are projected to the relational `tasks` table downstream.
4. Safe merge logic for incoming Yjs blobs in pull, bypassing the `yjs_dart` YText bug (scanning both local and remote nodes).
5. Incremental projection of nodes directly via diffs instead of full rebuilds.

**Tech Stack:** Go (backend, PostgreSQL, SQLC), Flutter (Dart, Drift, Yjs-Dart, SuperEditor)

---

### Task 1: Backend - Fractional Indexing Migration

**Files:**
- Create: `backend/db/migrations/000032_fractional_indexing.up.sql`
- Create: `backend/db/migrations/000032_fractional_indexing.down.sql`
- Modify: `backend/db/queries/notes.sql`
- Modify: `backend/db/queries/tasks.sql`

- [ ] **Step 1: Write Up Migration**
```sql
-- 000032_fractional_indexing.up.sql
ALTER TABLE note_nodes ALTER COLUMN position TYPE VARCHAR(255);
ALTER TABLE tasks ALTER COLUMN position TYPE VARCHAR(255);
```

- [ ] **Step 2: Write Down Migration**
```sql
-- 000032_fractional_indexing.down.sql
-- Down-migration is fundamentally unsafe if lexical string positions (like "a0V") exist.
-- It will crash the cast. This is provided for pre-production rollbacks only.
ALTER TABLE note_nodes ALTER COLUMN position TYPE double precision USING position::double precision;
ALTER TABLE tasks ALTER COLUMN position TYPE double precision USING position::double precision;
```

- [ ] **Step 3: Update SQLC Queries & Generate**
Ensure queries use string type for `position`.
Run: `cd backend && make sqlc`

### Task 2: Backend - Remove Tasks from YMap, Project Correctly, and Implement Fractional Indexing

**Files:**
- Modify: `backend/internal/sync/projection.go`
- Modify: `backend/internal/sync/sync_task.go`
- Modify: `backend/internal/agent/tools/notes_tools.go`
- Modify: `backend/go.mod`

- [ ] **Step 1: Fractional Indexing Go Implementation**
Find or implement a Fractional Indexing (Lexo-rank) library in Go (e.g. `github.com/rocicorp/fracdex` or equivalent) inside `backend/internal/utils/fractional_index.go`. **CRITICAL:** Ensure the base encoding and midpoint logic exactly matches the Dart implementation (e.g., standard Figma-style string fractional indexing) to prevent cross-platform drift.

- [ ] **Step 2: Update Projection and Task fields**
In `projection.go` and `sync_task.go`, remove all reading of `tasksMap`. 
When projecting `note_nodes`, if `meta["type"] == "task"`, extract `completed`, `due_date`, `recurrence` from `data` JSON. Upsert into the relational `tasks` table.

- [ ] **Step 3: Apply Fractional Indexing on Node/Task Creation via WithDoc**
In `notes_tools.go` and `sync_task.go`, when creating a new node or task:
Use the `RoomManager.WithDoc` (or similar active Doc loader) to fetch the note's active YDoc. Read the adjacent nodes from the `nodesMap`, generate the position string via the helper from Step 1, apply the insertion, and let standard sync persist it. Do NOT generate numeric positions.

- [ ] **Step 4: Compile and Test**
Run: `cd backend && go build ./... && go test ./internal/sync`

### Task 3: Frontend - Fractional Indexing DB

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/database/tables/note_nodes.dart`
- Modify: `lib/core/database/tables/tasks.dart`
- Modify: `lib/core/utils/fractional_indexing.dart`

- [ ] **Step 1: Add Dependency**
Add `fractional_indexing_dart: ^0.1.0` (or appropriate version) to `pubspec.yaml`.

- [ ] **Step 2: Update Drift Tables & Generate**
Change `position` columns to `TextColumn`.
Run: `dart run build_runner build -d`

- [ ] **Step 3: Create Fractional Indexing Helper**
Wrap the library to provide `between(String? prev, String? next)` using the package. **CRITICAL:** The algorithm must match the Go implementation from Task 2 exactly.

### Task 4: Frontend - YDoc Single Source of Truth & Timers

**Files:**
- Modify: `lib/features/notes/domain/node_sync_manager.dart`
- Modify: `lib/features/notes/domain/yjs_sync_manager.dart`

- [ ] **Step 1: Remove SQLite writes & Adjust Timers in NodeSyncManager**
Delete all `_db.into(_db.noteNodes).insertOnConflictUpdate(...)` from `_applyOpsTransaction`.
Delete `_calculatePositionForInsert` and `_calculatePositionForMove` since SQLite no longer dictates position.
In `_onDocumentChanged`, change the debounce from 500ms to 50ms (micro-debounce) before calling `onFlush(ops)`. This groups keystrokes without perceptible WS delay.

- [ ] **Step 2: Incremental _projectToNodes in YjsSyncManager**
Instead of `noteNodesFromDoc(doc)` scanning everything, listen to `doc.getMap('nodes').observe((event, tr) { ... })`. Iterate over `event.keys` to find exactly which keys changed (added, updated, deleted). Parse only those nodes and update/delete them in `_db.noteNodes` (and `_db.tasks` if type is task, parsing `due_date`, etc.).

### Task 5: Frontend - Safe Merge Pull & YText Bug Workaround

**Files:**
- Modify: `lib/core/sync/sync_service.dart`

- [ ] **Step 1: Implement Safe Merge with Double Workaround**
```dart
final existing = await (_db.select(_db.localYjsStates)..where((t) => t.noteId.equals(state.noteId))).getSingleOrNull();
if (existing != null) {
  final doc = crdt.Doc();
  // BUG WORKAROUND: Pre-register YText from BOTH existing and incoming blobs
  final tempDoc = crdt.Doc();
  crdt.applyUpdate(tempDoc, existing.stateData);
  crdt.applyUpdate(tempDoc, state.stateData); // Incoming might have new nodes!
  final nodesMap = tempDoc.getMap('nodes');
  if (nodesMap != null) {
    for (final key in nodesMap.keys) doc.getText('content/$key');
  }
  
  crdt.applyUpdate(doc, existing.stateData);
  crdt.applyUpdate(doc, state.stateData);
  state = state.copyWith(stateData: crdt.encodeStateAsUpdate(doc));
}
```

### Task 6: Frontend - Clean YText, Guards, and Proper Positional Logic

**Files:**
- Modify: `lib/features/notes/domain/yjs_doc_editor_bridge.dart`

- [ ] **Step 1: Update Bridge Signatures & Implement Fractional Index Logic**
Change the signature of `_serializeNode` (and `_repositionNode` if applicable) to accept `String? position` instead of `double?`.
Implement a helper `_calculatePosition(int index, YMap nodesMap)` that reads the `nodesMap` (sorted by its existing positions), finds `prev` and `next`, and uses `FractionalIndex.between()` to generate the new string position.

- [ ] **Step 2: Implement Phantom Node Guard, YText Deletion, and position logic for Insert/Move**
```dart
case DeleteOp(:final id):
  nodesMap.delete(id);
  final ytext = _doc.getText('content/$id');
  if (ytext != null) ytext.delete(0, ytext.length); // Clean memory

case UpdateOp(:final id, :final node):
  if (nodesMap.get(id) != null) {
    _serializeNode(node, null, id, nodesMap);
  }

case InsertOp(:final id, :final node, :final index):
  if (nodesMap.get(id) == null) {
     final position = _calculatePosition(index, nodesMap); // Fractional indexing logic
     _serializeNode(node, position, id, nodesMap);
  }

case MoveOp(:final id, :final to):
  if (nodesMap.get(id) != null) {
     final position = _calculatePosition(to, nodesMap);
     _repositionNode(id, position, nodesMap);
  }
```
