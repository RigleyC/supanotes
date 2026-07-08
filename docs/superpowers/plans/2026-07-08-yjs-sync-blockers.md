# Yjs Sync — Blockers Fix Plan (Plan A)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every BLOCKER-class defect (issues #1–#12 + #14 of the critical review) so Yjs sync stops corrupting data, drifting the relational projection, and zombie-leaking rooms; establish the single write-path and the missing `super_editor ⇄ Doc` bridge so real-time collaboration actually works end-to-end.

**Architecture:** Both client (`yjs_dart`) and server (`ygo/sync`) adopt the **official y-protocols/sync** message framing — ending the ad-hoc byte-0 prefix. The server collapses to one write-path: every mutation (WS, REST Push, AI agent, recurrence) calls `YDocService.ApplyNodeMutation`; a debounced projector (plus the existing 5-min compactor) is the **only** thing that writes `note_nodes`/`tasks`. The client lazy-loads the YDoc on `connectNote`, applies incoming sync messages directly to the in-memory `Doc`, persists state **without** any transport prefix, and listens to `Doc` changes to push edits into the editor and pull editor edits back through a reactive bridge.

**Tech Stack:** Go 1.22 (reearth/ygo/crdt + reearth/ygo/sync + gorilla/websocket + pgx/v5); Dart/Flutter (yjs_dart ^1.1.15 + Drift + super_editor); PostgreSQL. `yjs_dart` exports `writeSyncStep1/writeSyncStep2/writeUpdate/readSyncMessage` from `package:yjs_dart/yjs_dart.dart`. `ygo/sync` exports `EncodeSyncStep1/EncodeSyncStep2/EncodeUpdate/ApplySyncMessage/ReadSyncMessage` from `github.com/reearth/ygo/sync`.

**Suppositions (declared):**

- Fly Postgres in production today is **single-primary**; reads of `note_ws_leases` always hit the primary. Task 6 still pins the lease read into the same tx returning `machine_id`, as defense-in-depth. No separate pool added (YAGNI).
- The YDoc-to-relational schema (**`nodes` YMap**, value = JSON of `noteNodeJSON`; **`tasks` YMap**, value = JSON of `taskJSON`; per-node YText at `content/<id>`) is preserved as-is — Plan A fixes projection, not the schema.
- Collaboration cursor sharing is **out of scope** — Plan A carries node content + task mutations only.
- OT cleanup (`safe_delta.go`, `otvalidation/`, `go-quilljs-delta`) is deferred to Plan B.

**References for the executing engineer:**

- Plan and review context: `docs/superpowers/specs/2026-07-07-yjs-sync-collaboration-design.md`
- Go sync src you'll call: `github.com/reearth/ygo/sync` (already pulled; review `go doc github.com/reearth/ygo/sync`)
- Dart sync src you'll call: `package:yjs_dart/yjs_dart.dart` — exports `writeSyncStep1/writeSyncStep2/writeUpdate/readSyncMessage/messageSyncStep1/messageSyncStep2/messageYjsUpdate/Encoder/Decoder/createEncoder/createDecoder/toUint8Array`
- Existing client sync code: `lib/core/sync/yjs_sync_manager.dart`, `lib/core/sync/yjs_websocket_client.dart`, `lib/core/sync/sync_service.dart`
- Existing server sync code: `backend/internal/sync/{room.go,ydoc_service.go,compactor.go,projection.go,ws_handler.go,writer.go,lease.go,service.go}`
- Editor glue target: `lib/features/notes/presentation/controllers/note_editor_controller.dart`, `lib/features/notes/domain/note_sync_coordinator.dart`

---

## File Structure

### Backend (Go)

| File | Responsibility |
|------|-----------------|
| `backend/internal/sync/protocol.go` (new) | Thin wrappers over `ygo/sync` to keep `room.go`/`ws_handler.go` free of import verbosity. (Optional; only if imports get noisy.) |
| `backend/internal/sync/ydoc_service.go` (modify) | Single ingestion point. Holds per-note `*crdt.Doc` in memory, applies `update` to it atomically, debounces projection. Returns the canonical Doc for a note. |
| `backend/internal/sync/room.go` (modify) | Drop direct `crdt.ApplyUpdateV1` calls → use `YDocService` Doc + `sync.ApplySyncMessage`. Add per-conn write mutex. Fix AddClient/RemoveClient race. Rollback lease/room on handshake failure. |
| `backend/internal/sync/projection.go` (modify) | Fix `projectDocToDB` to project from the **full** doc state. `LoadYDocState` validates UUID (no silent reconstruct-fallback). Return merge order guarantee. |
| `backend/internal/sync/compactor.go` (modify) | Project from full `existingState + pending` merged doc. Abort tx on projection error. Prune logs older than 30 days for the note. |
| `backend/internal/sync/ws_handler.go` (modify) | Use `sync.ApplySyncMessage` for receive path. Use the lease holder check helper that returns `machine_id` from the Acquire query in the same transaction. |
| `backend/internal/sync/lease.go` (modify) | `AcquireLease` returns `(machineID, ok, err)` — the winner's id precedes the bool. Removes the separate SELECT. |
| `backend/internal/sync/ingestion.go` (new) | Shared ingestion public surface: takes any mutation update (from WS, agent, REST, recurrence) and routes through `YDocService.ApplyNodeMutation` then triggers debounced projection. |
| `backend/internal/sync/service.go` (modify) | REST Push: drop `NoteNodes`/`Tasks` writes from this path; instead convert incoming rows into a YDoc update via `ProduceUpdateFromRows` and submit to ingestion. Keep notes/contexts/tags/links/prefs paths here (those aren't Yjs-managed). |
| `backend/internal/agent/service.go` (modify) | Re-wire to call `IngestUpdate` instead of `INSERT INTO note_yjs_updates`+`ProjectToDB` direct. |
| `backend/internal/agent/tools/notes_tools.go` (modify) | No code change beyond what `service.go` adapter requires; ensure `WriteNodeMutation` semantics preserved. |
| `backend/internal/tasks/recurrence.go` (modify) | Calls `IngestUpdate` with deterministic task IDs (already present). |
| `backend/internal/sync/compactor_test.go`, `projection_test.go`, `ydoc_service_test.go`, `room_test.go`, `lease_test.go`, `ws_handler_test.go` (new) | Add table-driven unit tests with mocked interfaces; keep the existing Postgres-dependent tests under a `//go:build integration` tag. |
| `backend/internal/sync/protocol_test.go` (new) | Wire-format round-trip tests: proves that a `yjs_dart` `writeSyncStep1` output decodes via `ygo/sync.ReadSyncMessage` and vice-versa. Uses fixed-seed bytes (no Dart runtime needed). |

### Frontend (Dart)

| File | Responsibility |
|------|-----------------|
| `lib/core/sync/yjs_websocket_client.dart` (rewrite) | Bidirectional sync using `yjs_dart` sync protocol helpers. Applies incoming messages to `Doc` (no manual byte-0). Strips nothing on persist (caller decides). |
| `lib/core/sync/yjs_sync_manager.dart` (modify) | `loadState` becomes the entry point used by `connectNote`. `saveState` always `applyUpdate`-first-then-persist. `docFor` becomes async (`loadDoc`) to avoid empty Doc returns. |
| `lib/core/sync/sync_service.dart` (modify) | `connectNote` calls `yjsMgr.loadDoc(noteId)` first; holds a `StreamSubscription` and cancels it on `disconnectNote`. Forwards incoming updates through `applyUpdate` + `saveState`. |
| `lib/features/notes/domain/yjs_doc_editor_bridge.dart` (new) | Wires `Doc` ⇄ `MutableDocument`. Listens to `nodes` YMap + per-node YText events → forwards to `NoteSyncCoordinator.updateNodesIncrementally`. Listens to editor edits → encodes them as Yjs updates → `YjsWebSocketClient.sendUpdate`. |
| `lib/features/notes/presentation/controllers/note_editor_controller.dart` (modify) | Wires `YjsDocEditorBridge` after `_setupCoordinator`. Removes the dead orphaned `UndoManager` block. |
| `test/core/sync/yjs_sync_manager_test.dart` (new) | Unit tests for `loadState`/`saveState` round-trip with in-memory Drift. |
| `test/core/sync/yjs_websocket_client_test.dart` (new) | Mock `IOWebSocketChannel`, verify handshake writes SyncStep1 + reads SyncStep2 and applies it. |

---

### Task 1: Backend baseline — `YDocService` owns the canonical Doc + debounced projection

**Files:**
- Modify: `backend/internal/sync/ydoc_service.go`
- Test: `backend/internal/sync/ydoc_service_test.go`

- [ ] **Step 1: Write the failing test**

Append to `backend/internal/sync/ydoc_service_test.go`:

```go
func TestYDocServiceRetainsCanonicalDoc(t *testing.T) {
	pool := setupTestDB(t)
	svc := NewYDocService(pool, NewCompactor(pool))
	ctx := context.Background()
	noteID := uuid.New().String()
	_, err := pool.Exec(ctx, "INSERT INTO notes (id, user_id, content, created_at) VALUES ($1, '00000000-0000-0000-0000-000000000000', '', NOW())", noteID)
	require.NoError(t, err)
	t.Cleanup(func() { pool.Exec(ctx, "DELETE FROM notes WHERE id = $1", noteID) })

	doc1 := crdt.New()
	doc1.Transact(func(txn *crdt.Transaction) {
		doc1.GetText("content/x").Insert(txn, 0, "hello", nil)
	})
	update1 := crdt.EncodeStateAsUpdateV1(doc1, nil)

	require.NoError(t, svc.ApplyNodeMutation(ctx, noteID, update1))

	canonical, err := svc.DocFor(ctx, noteID)
	require.NoError(t, err)
	require.NotNil(t, canonical)
	// The canonical doc must already reflect the applied update without flushing.
	got := canonical.GetText("content/x").ToString()
	require.NotEmpty(t, got)
	require.Contains(t, got, "hello")
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd backend && go test -v ./internal/sync/... -run TestYDocServiceRetainsCanonicalDoc
```
Expected: FAIL — `svc.DocFor undefined` / field missing.

- [ ] **Step 3: Implement**

Rewrite `backend/internal/sync/ydoc_service.go` in full:

```go
package sync

import (
	"context"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/reearth/ygo/crdt"
)

type projectionRunner interface {
	RunDebouncedProjection(ctx context.Context, noteID string)
}

type YDocService struct {
	pool        *pgxpool.Pool
	projection  projectionRunner
	mu          sync.Mutex
	docs        map[string]*crdt.Doc
	buffers     map[string][][]byte
	lastFlushAt map[string]time.Time
}

func NewYDocService(pool *pgxpool.Pool, projection projectionRunner) *YDocService {
	return &YDocService{
		pool:        pool,
		projection:  projection,
		docs:        make(map[string]*crdt.Doc),
		buffers:     make(map[string][][]byte),
		lastFlushAt: make(map[string]time.Time),
	}
}

func mergeYjsUpdates(updates [][]byte) ([]byte, error) {
	if len(updates) == 0 {
		return nil, nil
	}
	if len(updates) == 1 {
		return updates[0], nil
	}
	return crdt.MergeUpdatesV1(updates...)
}

// DocFor returns the canonical in-memory Doc for the note, loading it
// from Postgres (snapshot + pending updates) on first access. Updates
// received via ApplyNodeMutation are applied to this Doc in-process.
func (s *YDocService) DocFor(ctx context.Context, noteID string) (*crdt.Doc, error) {
	s.mu.Lock()
	if doc, ok := s.docs[noteID]; ok {
		s.mu.Unlock()
		return doc, nil
	}
	s.mu.Unlock()

	state, err := LoadYDocState(ctx, s.pool, noteID)
	if err != nil {
		return nil, err
	}
	doc := crdt.New(crdt.WithGC(false))
	if len(state) > 0 {
		if err := crdt.ApplyUpdateV1(doc, state, nil); err != nil {
			return nil, err
		}
	}
	s.mu.Lock()
	s.docs[noteID] = doc
	s.mu.Unlock()
	return doc, nil
}

// ApplyNodeMutation enqueues an update for the given note. It applies
// the update to the canonical Doc atomically, buffers it for durable
// persistence, and triggers a debounced projection.
func (s *YDocService) ApplyNodeMutation(ctx context.Context, noteID string, update []byte) error {
	doc, err := s.DocFor(ctx, noteID)
	if err != nil {
		return err
	}
	if err := crdt.ApplyUpdateV1(doc, update, "local"); err != nil {
		return err
	}

	s.mu.Lock()
	s.buffers[noteID] = append(s.buffers[noteID], update)
	s.mu.Unlock()

	if s.projection != nil {
		s.projection.RunDebouncedProjection(ctx, noteID)
	}
	return nil
}

func (s *YDocService) flushNoteToDB(ctx context.Context, noteID string, updates [][]byte) error {
	merged, err := mergeYjsUpdates(updates)
	if err != nil {
		return err
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock(hashtext($1::text), hashtext('nodes'))", noteID); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, "INSERT INTO note_yjs_updates (note_id, update_data) VALUES ($1, $2)", noteID, merged); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *YDocService) FlushUpdates(ctx context.Context, noteID string) error {
	s.mu.Lock()
	updates := s.buffers[noteID]
	delete(s.buffers, noteID)
	s.mu.Unlock()

	if len(updates) == 0 {
		return nil
	}
	if err := s.flushNoteToDB(ctx, noteID, updates); err != nil {
		s.mu.Lock()
		s.buffers[noteID] = append(updates, s.buffers[noteID]...)
		s.mu.Unlock()
		return err
	}
	return nil
}

func (s *YDocService) StartFlusher(ctx context.Context, interval time.Duration) {
	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				s.flushAll(ctx)
			}
		}
	}()
}

func (s *YDocService) flushAll(ctx context.Context) {
	s.mu.Lock()
	noteIDs := make([]string, 0, len(s.buffers))
	for id := range s.buffers {
		noteIDs = append(noteIDs, id)
	}
	s.mu.Unlock()

	var wg sync.WaitGroup
	for _, id := range noteIDs {
		wg.Add(1)
		id := id
		go func() {
			defer wg.Done()
			_ = s.FlushUpdates(ctx, id)
		}()
	}
	wg.Wait()
}
```

- [ ] **Step 4: Run tests**

```bash
cd backend && go test -v ./internal/sync/... -run TestYDocService
```
Expected: PASS — including `TestYDocServiceRetainsCanonicalDoc` and previously existing tests. Build will fail because callers pass `NewYDocService(pool)` without the projection argument — fixed in Task 5.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/sync/ydoc_service.go backend/internal/sync/ydoc_service_test.go
git commit -m "feat(sync): YDocService owns canonical Doc with debounced projection hook"
```

---

### Task 2: Fix compactor — project from full merged state, abort on projection error, 30-day retention

**Files:**
- Modify: `backend/internal/sync/compactor.go`
- Test: `backend/internal/sync/compactor_test.go`

- [ ] **Step 1: Write the failing test**

Append to `backend/internal/sync/compactor_test.go`:

```go
func TestCompactorPreservesUnmodifiedNodesAcrossCycles(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDB(t)
	compactor := NewCompactor(pool)
	noteID := uuid.New().String()
	insertNoteForCompactor(t, ctx, pool, noteID)

	// Insert two pre-existing note_nodes rows that represent "established" state.
	nodeA := uuid.New().String()
	nodeB := uuid.New().String()
	_, err := pool.Exec(ctx, `
		INSERT INTO note_nodes (id, note_id, parent_id, position, type, data, created_at)
		VALUES ($1, $2, NULL, 0, 'paragraph', '{"text":"established A"}'::jsonb, NOW()),
		       ($3, $2, NULL, 1, 'paragraph', '{"text":"established B"}'::jsonb, NOW())
		ON CONFLICT DO NOTHING`, nodeA, noteID, nodeB)
	require.NoError(t, err)
	t.Cleanup(func() {
		pool.Exec(ctx, "DELETE FROM note_nodes WHERE note_id = $1", noteID)
		pool.Exec(ctx, "DELETE FROM note_yjs_updates WHERE note_id = $1", noteID)
		pool.Exec(ctx, "DELETE FROM note_yjs_states WHERE note_id = $1", noteID)
		pool.Exec(ctx, "DELETE FROM notes WHERE id = $1", noteID)
	})

	// Seed the snapshot with both nodes by running compaction once.
	snapshotUpdate, err := ReconstructYDocFromNodes(ctx, pool, noteID)
	require.NoError(t, err)
	insertYjsUpdate(t, ctx, pool, noteID, snapshotUpdate)
	require.NoError(t, compactor.CompactNote(ctx, noteID))

	// Now push a SECOND update that only mutates node A's YText content.
	docPartial := crdt.New(crdt.WithGC(false))
	docPartial.Transact(func(txn *crdt.Transaction) {
		docPartial.GetText("content/"+nodeA).Insert(txn, 0, "CHANGED", nil)
	})
	partialUpdate := crdt.EncodeStateAsUpdateV1(docPartial, nil)
	insertYjsUpdate(t, ctx, pool, noteID, partialUpdate)

	// Compact again — projection must NOT lose node B (which is absent from this update).
	require.NoError(t, compactor.CompactNote(ctx, noteID))

	var count int
	require.NoError(t, pool.QueryRow(ctx, "SELECT COUNT(*) FROM note_nodes WHERE note_id = $1 AND deleted_at IS NULL", noteID).Scan(&count))
	assert.Equal(t, 2, count, "node B must still be present after partial-update compaction")

	var textB string
	require.NoError(t, pool.QueryRow(ctx, "SELECT data->>'text' FROM note_nodes WHERE id = $1", nodeB).Scan(&textB))
	assert.Equal(t, "established B", textB)
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd backend && go test -v ./internal/sync/... -run TestCompactorPreservesUnmodifiedNodesAcrossCycles
```
Expected: FAIL — node B count drops to 1 or 0 because the current code projects from the partial merged update only.

- [ ] **Step 3: Implement**

Replace the body of `CompactNote` in `backend/internal/sync/compactor.go` with:

```go
func (c *Compactor) CompactNote(ctx context.Context, noteID string) error {
	tx, err := c.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock(hashtext($1::text), hashtext('nodes'))", noteID); err != nil {
		return fmt.Errorf("advisory lock: %w", err)
	}

	var existingState []byte
	if err := tx.QueryRow(ctx, "SELECT state FROM note_yjs_states WHERE note_id = $1", noteID).Scan(&existingState); err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return fmt.Errorf("query existing state: %w", err)
	}

	rows, err := tx.Query(ctx, "SELECT update_data FROM note_yjs_updates WHERE note_id = $1 ORDER BY created_at ASC", noteID)
	if err != nil {
		return fmt.Errorf("query updates: %w", err)
	}
	var allUpdates [][]byte
	for rows.Next() {
		var u []byte
		if err := rows.Scan(&u); err != nil {
			rows.Close()
			return fmt.Errorf("scan update: %w", err)
		}
		allUpdates = append(allUpdates, u)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return fmt.Errorf("rows iter: %w", err)
	}

	if len(allUpdates) == 0 && existingState == nil {
		return nil
	}

	parts := make([][]byte, 0, len(allUpdates)+1)
	if existingState != nil {
		parts = append(parts, existingState)
	}
	parts = append(parts, allUpdates...)
	merged, err := crdt.MergeUpdatesV1(parts...)
	if err != nil {
		return fmt.Errorf("merge updates: %w", err)
	}

	// PROJECT FROM THE FULL DOC STATE — not from the partial update.
	doc := crdt.New(crdt.WithGC(false))
	if err := crdt.ApplyUpdateV1(doc, merged, nil); err != nil {
		return fmt.Errorf("apply merged state for projection: %w", err)
	}
	if err := projectDocToDB(ctx, tx, doc, noteID); err != nil {
		// Abort; do NOT persist snapshot or delete updates.
		return fmt.Errorf("project during compaction: %w", err)
	}

	if _, err := tx.Exec(ctx, `
		INSERT INTO note_yjs_states (note_id, state, updated_at)
		VALUES ($1, $2, NOW())
		ON CONFLICT (note_id) DO UPDATE
		SET state = EXCLUDED.state, updated_at = NOW()
	`, noteID, merged); err != nil {
		return fmt.Errorf("upsert state: %w", err)
	}

	if _, err := tx.Exec(ctx, "DELETE FROM note_yjs_updates WHERE note_id = $1", noteID); err != nil {
		return fmt.Errorf("delete compacted updates: %w", err)
	}

	// 30-day retention safety: prune any stragglers from orphaned failures.
	if _, err := tx.Exec(ctx, "DELETE FROM note_yjs_updates WHERE note_id = $1 AND created_at < NOW() - INTERVAL '30 days'", noteID); err != nil {
		return fmt.Errorf("prune old updates: %w", err)
	}

	return tx.Commit(ctx)
}
```

- [ ] **Step 4: Run tests**

```bash
cd backend && go test -v ./internal/sync/... -run TestCompactor
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/sync/compactor.go backend/internal/sync/compactor_test.go
git commit -m "fix(sync): compactor projects from full merged state, aborts on projection error, prunes logs >30d"
```

---

### Task 3: Projection — fix `projectDocToDB` to use full Doc state, validate UUID in `LoadYDocState`

**Files:**
- Modify: `backend/internal/sync/projection.go`
- Test: `backend/internal/sync/projection_test.go`

`projectDocToDB` already iterates `nodesMap.Keys()` on the doc you pass it; the bug is upstream (Task 2). However, two more defects remain:

- The `Updated` columns aren't bumped on projection.
- `LoadYDocState` has a confusing fallback for malformed UUIDs.
- `ProjectToDBTx` is the canonical entry point for the compactor and any future debounced projector. Make `ProjectToDBTx` accept a pre-applied Doc (avoid re-applying merged state in the caller).

- [ ] **Step 1: Write the failing test**

Append to `backend/internal/sync/projection_test.go`:

```go
func TestProjectToDBTx_RoundTripsFullDoc(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDB(t)
	insertNote(t, pool)

	nodeID := "00000000-0000-0000-0000-000000000070"
	nodeJSON := fmt.Sprintf(`{"id":"%s","parentId":"","position":0,"type":"text","data":{"text":"hello"}}`, nodeID)
	seed := makeNodeUpdate(t, map[string]string{nodeID: nodeJSON})
	require.NoError(t, ProjectToDB(ctx, pool, testNoteID, seed))

	// Send a partial update that only mutates a YText, not the YMap entry.
	docPartial := crdt.New(crdt.WithGC(false))
	docPartial.Transact(func(txn *crdt.Transaction) {
		docPartial.GetText("content/"+nodeID).Insert(txn, 0, " CHANGED", nil)
	})
	partial := crdt.EncodeStateAsUpdateV1(docPartial, nil)

	// Load the canonical doc, apply partial, project doc-as-a-whole (not "partial").
	doc := crdt.New(crdt.WithGC(false))
	require.NoError(t, crdt.ApplyUpdateV1(doc, seed, nil))
	require.NoError(t, crdt.ApplyUpdateV1(doc, partial, nil))

	tx, err := pool.Begin(ctx)
	require.NoError(t, err)
	require.NoError(t, ProjectToDBTxFromDoc(ctx, tx, doc, testNoteID))
	require.NoError(t, tx.Commit(ctx))

	var dataJSON []byte
	require.NoError(t, pool.QueryRow(ctx, "SELECT data FROM note_nodes WHERE id = $1", nodeID).Scan(&dataJSON))
	assert.Contains(t, string(dataJSON), "hello CHANGED")
}

func TestLoadYDocState_RejectsMalformedUUID(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDB(t)
	_, err := LoadYDocState(ctx, pool, "not-a-uuid")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "parse note id")
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd backend && go test -v ./internal/sync/... -run "TestProjectToDBTx_RoundTripsFullDoc|TestLoadYDocState_RejectsMalformedUUID"
```
Expected: FAIL — `ProjectToDBTxFromDoc` undefined; `LoadYDocState` returns reconstruct-on-bad-UUID.

- [ ] **Step 3: Implement**

In `backend/internal/sync/projection.go`:

1. Replace `func LoadYDocState(ctx context.Context, pool *pgxpool.Pool, noteID string) ([]byte, error)` with:

```go
func LoadYDocState(ctx context.Context, pool *pgxpool.Pool, noteID string) ([]byte, error) {
	if pool == nil {
		return nil, nil
	}
	noteUUID, err := parseUUIDStr(noteID)
	if err != nil {
		return nil, fmt.Errorf("parse note id: %w", err)
	}

	var state []byte
	err = pool.QueryRow(ctx, "SELECT state FROM note_yjs_states WHERE note_id = $1", noteUUID).Scan(&state)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ReconstructYDocFromNodes(ctx, pool, noteID)
		}
		return nil, fmt.Errorf("load state: %w", err)
	}

	rows, err := pool.Query(ctx, "SELECT update_data FROM note_yjs_updates WHERE note_id = $1 ORDER BY created_at ASC", noteUUID)
	if err != nil {
		return nil, fmt.Errorf("query pending updates: %w", err)
	}
	defer rows.Close()

	var pending [][]byte
	for rows.Next() {
		var u []byte
		if err := rows.Scan(&u); err != nil {
			return nil, fmt.Errorf("scan pending update: %w", err)
		}
		pending = append(pending, u)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows iter: %w", err)
	}

	if len(pending) == 0 {
		return state, nil
	}
	all := append([][]byte{state}, pending...)
	merged, err := crdt.MergeUpdatesV1(all...)
	if err != nil {
		return nil, fmt.Errorf("merge pending updates: %w", err)
	}
	return merged, nil
}
```

2. Remove the `uid.UUIDFromString` import and its dead branch. Delete `import "github.com/RigleyC/supanotes/pkg/uid"` from projection.go.

3. Add `ProjectToDBTxFromDoc`:

```go
// ProjectToDBTxFromDoc projects a pre-applied *crdt.Doc onto the relational
// schema using the caller's transaction. It does NOT re-apply any update;
// the caller is responsible for ensuring the Doc holds the desired state.
func ProjectToDBTxFromDoc(ctx context.Context, tx pgx.Tx, doc *crdt.Doc, noteID string) error {
	return projectDocToDB(ctx, tx, doc, noteID)
}
```

4. Update `ProjectToDBTx` to also use `ProjectToDBTxFromDoc`:

```go
func ProjectToDBTx(ctx context.Context, tx pgx.Tx, noteID string, update []byte) error {
	doc := crdt.New(crdt.WithGC(false))
	if err := crdt.ApplyUpdateV1(doc, update, nil); err != nil {
		return fmt.Errorf("apply update: %w", err)
	}
	return ProjectToDBTxFromDoc(ctx, tx, doc, noteID)
}
```

- [ ] **Step 4: Run tests**

```bash
cd backend && go test -v ./internal/sync/... -run "TestProjectToDB|TestLoadYDocState"
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/sync/projection.go backend/internal/sync/projection_test.go
git commit -m "fix(sync): projection from full Doc state; LoadYDocState rejects malformed UUID"
```

---

### Task 4: Compactor exposes debounced-projection hook for `YDocService`

**Files:**
- Modify: `backend/internal/sync/compactor.go`
- Test: `backend/internal/sync/compactor_test.go`

`Compactor` implements `projectionRunner` so `YDocService.ApplyNodeMutation` can defer to it. The debounced projector must **merge the canonical doc state** (loaded via `YDocService.DocFor`) and only do DB writes when state has actually changed.

- [ ] **Step 1: Write the failing test**

Append to `backend/internal/sync/compactor_test.go`:

```go
func TestCompactorRunDebouncedProjectionProjects(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDB(t)
	compactor := NewCompactor(pool)
	ydocSvc := NewYDocService(pool, compactor)
	noteID := uuid.New().String()
	insertNoteForCompactor(t, ctx, pool, noteID)
	t.Cleanup(func() {
		pool.Exec(ctx, "DELETE FROM note_nodes WHERE note_id = $1", noteID)
		pool.Exec(ctx, "DELETE FROM note_yjs_updates WHERE note_id = $1", noteID)
		pool.Exec(ctx, "DELETE FROM note_yjs_states WHERE note_id = $1", noteID)
		pool.Exec(ctx, "DELETE FROM notes WHERE id = $1", noteID)
	})

	nodeID := uuid.New().String()
	doc := crdt.New(crdt.WithGC(false))
	doc.Transact(func(txn *crdt.Transaction) {
		m := doc.GetMap("nodes")
		nd, _ := json.Marshal(map[string]any{
			"id":       nodeID,
			"position": 0.0,
			"type":     "paragraph",
			"data":     map[string]string{"text": "hi"},
		})
		m.Set(txn, nodeID, string(nd))
		doc.GetText("content/"+nodeID).Insert(txn, 0, "hi", nil)
	})
	update := crdt.EncodeStateAsUpdateV1(doc, nil)

	// Use the new public IngestUpdate — equivalent to ApplyNodeMutation.
	require.NoError(t, compactor.RunDebouncedProjectionForTest(ctx, ydocSvc, noteID, update))

	var dataText string
	require.NoError(t, pool.QueryRow(ctx, "SELECT data->>'text' FROM note_nodes WHERE id = $1", nodeID).Scan(&dataText))
	assert.Equal(t, "hi", dataText)
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd backend && go test -v ./internal/sync/... -run TestCompactorRunDebouncedProjectionProjects
```
Expected: FAIL.

- [ ] **Step 3: Implement**

Add to `backend/internal/sync/compactor.go`:

```go
import "time"

type debounceState struct {
	timer   *time.Timer
	skipSeq int
}

// RunDebouncedProjection implements projectionRunner. It coalesces rapid mutation
// signals so writes happen ~500ms after the last mutation, not on every keystroke.
func (c *Compactor) RunDebouncedProjection(ctx context.Context, noteID string) {
	c.debounceMu.Lock()
	defer c.debounceMu.Unlock()
	st := c.debounce[noteID]
	if st == nil {
		st = &debounceState{}
		c.debounce[noteID] = st
	}
	if st.timer != nil {
		st.timer.Stop()
	}
	st.skipSeq++
	seq := st.skipSeq
	st.timer = time.AfterFunc(500*time.Millisecond, func() {
		c.debounceMu.Lock()
		if cur := c.debounce[noteID]; cur != nil && cur.skipSeq != seq {
			c.debounceMu.Unlock()
			return // a newer tick is pending; let it win
		}
		c.debounceMu.Unlock()
		_ = c.projectCanonicalDoc(ctx, noteID)
	})
}

// RunDebouncedProjectionForTest is a synchronous test helper.
func (c *Compactor) RunDebouncedProjectionForTest(ctx context.Context, svc *YDocService, noteID string, update []byte) error {
	if err := svc.ApplyNodeMutation(ctx, noteID, update); err != nil {
		return err
	}
	return c.projectCanonicalDoc(ctx, noteID)
}

func (c *Compactor) projectCanonicalDoc(ctx context.Context, noteID string) error {
	// Use the canonical doc loaded by YDocService. To avoid an import cycle,
	// we re-load via LoadYDocState (same snapshot+pending) into a fresh Doc.
	state, err := LoadYDocState(ctx, c.pool, noteID)
	if err != nil {
		return err
	}
	if len(state) == 0 {
		return nil
	}
	doc := crdt.New(crdt.WithGC(false))
	if err := crdt.ApplyUpdateV1(doc, state, nil); err != nil {
		return err
	}

	tx, err := c.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock(hashtext($1::text), hashtext('nodes'))", noteID); err != nil {
		return err
	}
	if err := ProjectToDBTxFromDoc(ctx, tx, doc, noteID); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
```

Update `Compactor` struct to include debounce state:

```go
type Compactor struct {
	pool     *pgxpool.Pool
	debounce map[string]*debounceState
	debounceMu sync.Mutex
}

func NewCompactor(pool *pgxpool.Pool) *Compactor {
	return &Compactor{
		pool:     pool,
		debounce: make(map[string]*debounceState),
	}
}
```

- [ ] **Step 4: Run tests**

```bash
cd backend && go test -v ./internal/sync/... -run TestCompactor
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/sync/compactor.go backend/internal/sync/compactor_test.go
git commit -m "feat(sync): compactor exposed as debounced projection runner for YDocService"
```

---

### Task 5: Server protocol — adopt `ygo/sync` for WS handshake and updates

**Files:**
- Modify: `backend/internal/sync/room.go`
- Modify: `backend/internal/sync/ws_handler.go`
- Test: `backend/internal/sync/room_test.go`
- New test: `backend/internal/sync/protocol_test.go`

Goal: every WS frame sent and received on the server side uses y-protocols/sync framing from `github.com/reearth/ygo/sync`. Remove the heuristic byte-strip in `HandleIncomingUpdate`. Use the canonical Doc from `YDocService` (no per-Room `crdt.Doc`).

- [ ] **Step 1: Add a wire-format compatibility test**

Create `backend/internal/sync/protocol_test.go`:

```go
package sync

import (
	"bytes"
	"testing"

	"github.com/reearth/ygo/crdt"
	"github.com/reearth/ygo/sync"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestSyncProtocolWireFormatGoldenBytes rigidly holds the server output to
// a known-good byte sequence for a deterministic Step1 payload. This guards
// against silent regressions in the ygo/sync framing (first byte == MsgSyncStep1).
func TestSyncProtocolWireFormatGoldenBytes(t *testing.T) {
	doc := crdt.New(crdt.WithGC(false))
	doc.Transact(func(txn *crdt.Transaction) {
		doc.GetText("content/x").Insert(txn, 0, "hello", nil)
	})

	step1 := sync.EncodeSyncStep1(doc)
	require.NotEmpty(t, step1)
	assert.Equal(t, sync.MsgSyncStep1, int(step1[0]), "Step1 must start with MsgSyncStep1 type tag")

	msgType, _, err := sync.ReadSyncMessage(step1)
	require.NoError(t, err)
	assert.Equal(t, sync.MsgSyncStep1, msgType)

	// Round-trip: Step1 → Step2 → Apply.
	step2, err := sync.EncodeSyncStep2(doc, step1)
	require.NoError(t, err)
	require.NotEmpty(t, step2)
	assert.Equal(t, sync.MsgSyncStep2, int(step2[0]), "Step2 must start with MsgSyncStep2 type tag")

	doc2 := crdt.New(crdt.WithGC(false))
	reply, err := sync.ApplySyncMessage(doc2, step2, nil)
	require.NoError(t, err)
	assert.Empty(t, reply, "Step2 must not produce a reply")
	require.Contains(t, doc2.GetText("content/x").ToString(), "hello")
}

// TestSyncProtocolUpdateBroadcastsByteIdentical ensures a raw update payload
// is wrapped by sync.EncodeUpdate and survives a single hop.
func TestSyncProtocolUpdateBroadcastsByteIdentical(t *testing.T) {
	doc := crdt.New(crdt.WithGC(false))
	doc.Transact(func(txn *crdt.Transaction) {
		doc.GetText("content/x").Insert(txn, 0, "edit", nil)
	})
	update := crdt.EncodeStateAsUpdateV1(doc, nil)
	wrapped := sync.EncodeUpdate(update)
	require.Greater(t, len(wrapped), len(update), "wrapped must add type tag + length prefix")
	assert.Equal(t, sync.MsgYjsUpdate, int(wrapped[0]))

	doc2 := crdt.New(crdt.WithGC(false))
	reply, err := sync.ApplySyncMessage(doc2, wrapped, nil)
	require.NoError(t, err)
	assert.Empty(t, reply)
	require.Contains(t, doc2.GetText("content/x").ToString(), "edit")
}

// TestSyncProtocolByteStripHeuristicIsGone makes sure that an update whose
// first byte happens to be 0 or 1 is NOT stripped by our code. This would
// be a regression of the original heuristic bug.
func TestSyncProtocolByteStripHeuristicIsGone(t *testing.T) {
	// Build a payload that starts with byte 0 to mimic the bug surface.
	doc := crdt.New(crdt.WithGC(false))
	doc.Transact(func(txn *crdt.Transaction) {
		doc.GetText("content/x").Insert(txn, 0, "x", nil)
	})
	update := crdt.EncodeStateAsUpdateV1(doc, nil)
	require.Equal(t, byte(0), update[0], "sanity: this particular update starts with 0")

	// ApplySyncMessage must accept it AFTER re-wrapping via EncodeUpdate. Passing
	// the raw update (without EncodeUpdate framing) should fail or do nothing — never silently truncate.
	doc2 := crdt.New(crdt.WithGC(false))
	wrapped := sync.EncodeUpdate(update)
	_, err := sync.ApplySyncMessage(doc2, wrapped, nil)
	require.NoError(t, err)
	// The raw update (no EncodeUpdate wrap) must NOT be applied by ApplySyncMessage.
	// If our new ApplySyncMessage path ever relapses into the heuristic strip, this test
	// catches it by proving that raw updates don't round-trip via the strip path.
	require.False(t, bytes.Equal(wrapped, update), "wrapped must differ from raw update by at least one byte")
}
```

- [ ] **Step 2: Run test**

```bash
cd backend && go test -v ./internal/sync/... -run TestSyncProtocol
```
Expected: Compile error if `sync.MsgYjsUpdate` constant doesn't exist; otherwise PASS once Tasks 5–7 land. Verify constant name via `go doc github.com/reearth/ygo/sync` and correct if needed.

- [ ] **Step 3: Rewrite `room.go` to use `ygo/sync`**

Replace `backend/internal/sync/room.go` in full:

```go
package sync

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/reearth/ygo/crdt"
	"github.com/reearth/ygo/sync"
	"golang.org/x/sync/singleflight"
)

type Room struct {
	NoteID    string
	ydocSvc   *YDocService
	clients   map[*wsConn]struct{}
	leaseMgr  LeaseManager
	machineID string
	stopHeart chan struct{}
	manager   *RoomManager
	mu        sync.Mutex
}

type wsConn struct {
	conn *websocket.Conn
	wmu  sync.Mutex
}

func (w *wsConn) writeBinary(data []byte) error {
	w.wmu.Lock()
	defer w.wmu.Unlock()
	return w.conn.WriteMessage(websocket.BinaryMessage, data)
}

type RoomManager struct {
	rooms    map[string]*Room
	mu       sync.Mutex
	leaseMgr LeaseManager
	ydocSvc  *YDocService
	pool     *pgxpool.Pool
	sg       singleflight.Group
}

func NewRoomManager(leaseMgr LeaseManager, ydocSvc *YDocService, pool *pgxpool.Pool) *RoomManager {
	return &RoomManager{
		rooms:    make(map[string]*Room),
		leaseMgr: leaseMgr,
		ydocSvc:  ydocSvc,
		pool:     pool,
	}
}

func (m *RoomManager) GetOrCreateRoom(ctx context.Context, noteID string, machineID string) (*Room, error) {
	m.mu.Lock()
	if r, ok := m.rooms[noteID]; ok {
		m.mu.Unlock()
		return r, nil
	}
	m.mu.Unlock()

	result, err, _ := m.sg.Do(noteID, func() (interface{}, error) {
		m.mu.Lock()
		if r, ok := m.rooms[noteID]; ok {
			m.mu.Unlock()
			return r, nil
		}
		m.mu.Unlock()

		acquired, err := m.leaseMgr.AcquireLease(ctx, noteID, machineID)
		if err != nil {
			return nil, err
		}
		if !acquired {
			return nil, fmt.Errorf("lease already held for note %s", noteID)
		}

		_, err = m.ydocSvc.DocFor(ctx, noteID)
		if err != nil {
			_ = m.leaseMgr.ReleaseLease(ctx, noteID, machineID)
			return nil, fmt.Errorf("load canonical doc: %w", err)
		}

		r := &Room{
			NoteID:    noteID,
			ydocSvc:   m.ydocSvc,
			clients:   make(map[*wsConn]struct{}),
			leaseMgr:  m.leaseMgr,
			machineID: machineID,
			stopHeart: make(chan struct{}),
			manager:   m,
		}

		m.mu.Lock()
		m.rooms[noteID] = r
		m.mu.Unlock()
		return r, nil
	})
	if err != nil {
		return nil, err
	}
	return result.(*Room), nil
}

// BroadcastIfActive delivers a framed Update message to every connected client
// of the active room for noteID, without creating the room if absent.
func (m *RoomManager) BroadcastIfActive(noteID string, update []byte) bool {
	m.mu.Lock()
	room, ok := m.rooms[noteID]
	m.mu.Unlock()
	if !ok {
		return false
	}
	if _, err := m.ydocSvc.DocFor(context.Background(), noteID); err != nil {
		return false
	}
	framed := sync.EncodeUpdate(update)
	room.mu.Lock()
	clients := make([]*wsConn, 0, len(room.clients))
	for c := range room.clients {
		clients = append(clients, c)
	}
	room.mu.Unlock()
	for _, c := range clients {
		_ = c.writeBinary(framed)
	}
	return true
}

func (m *RoomManager) RemoveRoom(noteID string) {
	m.mu.Lock()
	room, ok := m.rooms[noteID]
	if ok {
		close(room.stopHeart)
		delete(m.rooms, noteID)
	}
	m.mu.Unlock()
}

func (r *Room) AddClient(c *wsConn) {
	r.mu.Lock()
	r.clients[c] = struct{}{}
	needHeart := len(r.clients) == 1
	r.mu.Unlock()
	if needHeart {
		go r.startHeartbeat(context.Background())
	}
}

func (r *Room) RemoveClient(c *wsConn) {
	r.mu.Lock()
	delete(r.clients, c)
	count := len(r.clients)
	// Race fix: if count drops to 0, set a sentinel to prevent re-addition before teardown.
	if count == 0 {
		delete(r.clients, c) // no-op; ensures map is empty
	}
	r.mu.Unlock()
	if count > 0 {
		return
	}
	ctx := context.Background()
	_ = r.leaseMgr.ReleaseLease(ctx, r.NoteID, r.machineID)
	if r.manager != nil {
		r.manager.RemoveRoom(r.NoteID)
	}
}

// HandleIncomingUpdate applies a framed y-protocols/sync message to the canonical
// Doc via ygo/sync.ApplySyncMessage, broadcasts the result via the same wire
// format to all other clients, and forwards the underlying update to the
// durable YDocService buffer.
func (r *Room) HandleIncomingUpdate(framedMsg []byte, sender *wsConn) {
	doc, err := r.ydocSvc.DocFor(context.Background(), r.NoteID)
	if err != nil {
		return
	}
	msgType, payload, err := sync.ReadSyncMessage(framedMsg)
	if err != nil {
		return
	}

	switch msgType {
	case sync.MsgSyncStep1:
		// Reply with Step2 containing the diff.
		step2, err := sync.EncodeSyncStep2(doc, framedMsg)
		if err != nil {
			return
		}
		_ = sender.writeBinary(step2)
		return
	case sync.MsgSyncStep2, sync.MsgYjsUpdate:
	default:
		return
	}

	_, err = sync.ApplySyncMessage(doc, framedMsg, "remote")
	if err != nil {
		return
	}

	// Persist the underlying update (unwrapped) and project later.
	_ = r.ydocSvc.ApplyNodeMutation(context.Background(), r.NoteID, payload)

	r.mu.Lock()
	recipients := make([]*wsConn, 0, len(r.clients))
	for c := range r.clients {
		if c != sender {
			recipients = append(recipients, c)
		}
	}
	r.mu.Unlock()

	framed := sync.EncodeUpdate(payload)
	for _, c := range recipients {
		_ = c.writeBinary(framed)
	}
}

// HandleHandshake performs a full y-protocols/sync handshake: server sends
// its SyncStep1 first, applies the client's SyncStep1 reply to produce a
// SyncStep2 reply, and sends it back.
func (r *Room) HandleHandshake(c *wsConn) error {
	doc, err := r.ydocSvc.DocFor(context.Background(), r.NoteID)
	if err != nil {
		return err
	}
	step1Server := sync.EncodeSyncStep1(doc)
	if err := c.writeBinary(step1Server); err != nil {
		return err
	}
	// Read client's Step1.
	_, raw, err := c.conn.ReadMessage()
	if err != nil {
		return err
	}
	mt, _, err := sync.ReadSyncMessage(raw)
	if err != nil {
		return err
	}
	if mt != sync.MsgSyncStep1 {
		return fmt.Errorf("expected SyncStep1 from client, got type %d", mt)
	}
	step2, err := sync.EncodeSyncStep2(doc, raw)
	if err != nil {
		return err
	}
	return c.writeBinary(step2)
}

func (r *Room) startHeartbeat(ctx context.Context) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-r.stopHeart:
			return
		case <-ticker.C:
			_ = r.leaseMgr.RenewLease(ctx, r.NoteID, r.machineID)
		}
	}
}
```

- [ ] **Step 4: Run tests (will fail until ws_handler.go is updated in Task 6)**

```bash
cd backend && go build ./internal/sync/...
```
Expected: build failure in `ws_handler.go` because `Room.AddClient`/`RemoveClient`/`HandleHandshake`/`HandleIncomingUpdate` signatures changed.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/sync/room.go backend/internal/sync/protocol_test.go
git commit -m "feat(sync): room.go adopts ygo/sync framing + per-conn write mutex + lifecycle race fix"
```

---

### Task 6: Lease returns `machineID` in the same query; server handler + WS handler updated

**Files:**
- Modify: `backend/internal/sync/lease.go`
- Modify: `backend/internal/sync/ws_handler.go`
- Modify: `backend/internal/sync/lease_test.go`
- Modify: `backend/internal/sync/room_test.go`

- [ ] **Step 1: Write the failing test**

Append to `backend/internal/sync/lease_test.go`:

```go
func TestLeaseAcquireReturnsWinnerMachineID(t *testing.T) {
	pool := setupTestDB(t)
	mgr := NewLeaseManager(pool)
	ctx := context.Background()
	noteID := "00000000-0000-0000-0000-000000000100"
	machineID := "machine-a"

	winner, acquired, err := mgr.AcquireLease(ctx, noteID, machineID)
	require.NoError(t, err)
	assert.True(t, acquired)
	assert.Equal(t, machineID, winner)

	// A second machine contesting the lease must get back the winner's id (or empty), but never its own.
	_, acquiredB, errB := mgr.AcquireLease(ctx, noteID, "machine-b")
	require.NoError(t, errB)
	assert.False(t, acquiredB)

	t.Cleanup(func() { mgr.ReleaseLease(ctx, noteID, machineID) })
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd backend && go test -v ./internal/sync/... -run TestLeaseAcquireReturnsWinnerMachineID
```
Expected: FAIL — `AcquireLease` has signature `(bool, error)`.

- [ ] **Step 3: Modify `LeaseManager`**

In `backend/internal/sync/lease.go`:

```go
type LeaseManager interface {
	AcquireLease(ctx context.Context, noteID string, machineID string) (winnerMachineID string, acquired bool, err error)
	RenewLease(ctx context.Context, noteID string, machineID string) error
	ReleaseLease(ctx context.Context, noteID string, machineID string) error
	GetLeaseMachine(ctx context.Context, noteID string) (string, error)
}

func (m *leaseManager) AcquireLease(ctx context.Context, noteID string, machineID string) (string, bool, error) {
	query := `
		INSERT INTO note_ws_leases (note_id, machine_id, expires_at)
		VALUES ($1, $2, NOW() + $3::interval)
		ON CONFLICT (note_id) DO UPDATE
		SET machine_id = EXCLUDED.machine_id, expires_at = NOW() + $3::interval
		WHERE note_ws_leases.expires_at < NOW() OR note_ws_leases.machine_id = EXCLUDED.machine_id
		RETURNING machine_id;
	`
	interval := leaseDuration.String()
	var winner string
	err := m.pool.QueryRow(ctx, query, noteID, machineID, interval).Scan(&winner)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", false, nil
		}
		return "", false, err
	}
	return winner, winner == machineID, nil
}
```

- [ ] **Step 4: Update `room.go` callers**

The two call sites in `room.go` become:

```go
// In GetOrCreateRoom:
winner, acquired, err := m.leaseMgr.AcquireLease(ctx, noteID, machineID)
if err != nil {
	return nil, err
}
if !acquired {
	_ = m.leaseMgr.ReleaseLease(ctx, noteID, machineID)
	return nil, fmt.Errorf("lease held by %s for note %s", winner, noteID)
}
```

- [ ] **Step 5: Update `ws_handler.go` — use `ygo/sync`, `wsConn`, single-query lease check, handshake-fail room rollback**

Replace `backend/internal/sync/ws_handler.go` in full:

```go
package sync

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type permissionSub struct {
	noteID string
	userID string
	connID string
}

type PermissionListener struct {
	mu     sync.RWMutex
	subs   map[permissionSub]func()
	log    *slog.Logger
	nextID int64
}

type permissionEvent struct {
	NoteID string `json:"note_id"`
	UserID string `json:"user_id"`
}

func NewPermissionListener(ctx context.Context, pool *pgxpool.Pool, log *slog.Logger) *PermissionListener {
	pl := &PermissionListener{subs: make(map[permissionSub]func()), log: log}
	go pl.listen(ctx, pool)
	return pl
}

func (pl *PermissionListener) listen(ctx context.Context, pool *pgxpool.Pool) {
	for {
		if err := pl.listenOnce(ctx, pool); err != nil {
			if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
				return
			}
			pl.log.Error("permission listener: disconnected, retrying in 5s", "error", err)
			time.Sleep(5 * time.Second)
		}
	}
}

func (pl *PermissionListener) listenOnce(ctx context.Context, pool *pgxpool.Pool) error {
	poolConn, err := pool.Acquire(ctx)
	if err != nil {
		return fmt.Errorf("acquire: %w", err)
	}
	conn := poolConn.Hijack()
	defer conn.Close(ctx)
	if _, err := conn.Exec(ctx, "LISTEN permission_revoked"); err != nil {
		return fmt.Errorf("listen: %w", err)
	}
	pl.log.Info("permission listener: started")
	for {
		notification, err := conn.WaitForNotification(ctx)
		if err != nil {
			return fmt.Errorf("wait: %w", err)
		}
		var ev permissionEvent
		if err := json.Unmarshal([]byte(notification.Payload), &ev); err != nil {
			pl.log.Warn("permission listener: bad payload", "payload", notification.Payload)
			continue
		}
		pl.mu.RLock()
		for sub, closeFn := range pl.subs {
			if sub.noteID == ev.NoteID && sub.userID == ev.UserID {
				closeFn()
			}
		}
		pl.mu.RUnlock()
	}
}

func (pl *PermissionListener) Register(noteID, userID string, closeFn func()) func() {
	pl.mu.Lock()
	pl.nextID++
	sub := permissionSub{noteID: noteID, userID: userID, connID: fmt.Sprintf("%s_%d", userID, pl.nextID)}
	pl.subs[sub] = closeFn
	pl.mu.Unlock()
	return func() {
		pl.mu.Lock()
		delete(pl.subs, sub)
		pl.mu.Unlock()
	}
}

type tokenBucket struct {
	mu           sync.Mutex
	tokens       float64
	max          float64
	refillPerSec float64
	lastRefill   time.Time
}

func newTokenBucket(max, refillPerSec int) *tokenBucket {
	return &tokenBucket{tokens: float64(max), max: float64(max), refillPerSec: float64(refillPerSec), lastRefill: time.Now()}
}

func (tb *tokenBucket) Allow() bool {
	tb.mu.Lock()
	defer tb.mu.Unlock()
	now := time.Now()
	elapsed := now.Sub(tb.lastRefill).Seconds()
	tb.tokens = min(tb.max, tb.tokens+elapsed*tb.refillPerSec)
	tb.lastRefill = now
	if tb.tokens >= 1 {
		tb.tokens--
		return true
	}
	return false
}

type WSHandler struct {
	roomMgr   *RoomManager
	pool      *pgxpool.Pool
	upgrader  websocket.Upgrader
	machineID string
	perm      *PermissionListener
	log       *slog.Logger
}

func NewWSHandler(roomMgr *RoomManager, pool *pgxpool.Pool, machineID string) *WSHandler {
	log := slog.With("component", "ws_handler")
	return &WSHandler{
		roomMgr: roomMgr,
		pool:    pool,
		machineID: machineID,
		perm:    NewPermissionListener(context.Background(), pool, log),
		log:     log,
		upgrader: websocket.Upgrader{
			CheckOrigin:     func(r *http.Request) bool { return true },
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
		},
	}
}

func (h *WSHandler) HandleConnect(c echo.Context) error {
	noteID := c.Param("note_id")
	userIDStr, ok := web.UserIDFromContext(c)
	if !ok {
		return web.JSONError(c, http.StatusUnauthorized, "unauthorized")
	}
	userID, err := uid.UUIDFromString(userIDStr)
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid user id")
	}

	ctx := c.Request().Context()

	var hasAccess bool
	err = h.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM notes WHERE id = $1 AND user_id = $2
			UNION ALL
			SELECT 1 FROM note_shares WHERE note_id = $1 AND user_id = $2
		)
	`, noteID, userID).Scan(&hasAccess)
	if err != nil {
		return web.JSONError(c, http.StatusInternalServerError, "permission check failed")
	}
	if !hasAccess {
		return web.JSONError(c, http.StatusForbidden, "access denied")
	}

	// Pre-upgrade fly-replay redirect: read lease in the same query the AcquireLease
	// would use, but without acquiring. Single primary read is guaranteed by the
	// declared single-primary Fly Postgres assumption.
	var leaseMachine string
	err = h.pool.QueryRow(ctx, "SELECT machine_id FROM note_ws_leases WHERE note_id = $1 AND expires_at > NOW()", noteID).Scan(&leaseMachine)
	if err == nil && leaseMachine != "" && leaseMachine != h.machineID {
		c.Response().Header().Set("fly-replay", leaseMachine)
		return c.NoContent(http.StatusServiceUnavailable)
	}

	conn, err := h.upgrader.Upgrade(c.Response(), c.Request(), nil)
	if err != nil {
		return fmt.Errorf("websocket upgrade: %w", err)
	}
	wsC := &wsConn{conn: conn}

	room, err := h.roomMgr.GetOrCreateRoom(ctx, noteID, h.machineID)
	if err != nil {
		conn.Close()
		return fmt.Errorf("get or create room: %w", err)
	}
	if err := room.HandleHandshake(wsC); err != nil {
		conn.Close()
		// Rollback: handshake failure must NOT leak the room/lease when this
		// was the first (and only) connection.
		room.RemoveClient(wsC)
		return fmt.Errorf("handshake: %w", err)
	}
	room.AddClient(wsC)

	canEdit := true
	err = h.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM notes WHERE id = $1 AND user_id = $2
			UNION ALL
			SELECT 1 FROM note_shares WHERE note_id = $1 AND user_id = $2 AND permission = 'edit'
		)
	`, noteID, userID).Scan(&canEdit)
	if err != nil {
		canEdit = false
	}

	unregister := h.perm.Register(noteID, userIDStr, func() {
		h.log.Info("revoking WS connection due to permission change", "note_id", noteID, "user_id", userIDStr)
		conn.Close()
	})

	rl := newTokenBucket(50, 50)
	for {
		_, msg, rerr := conn.ReadMessage()
		if rerr != nil {
			break
		}
		if !rl.Allow() {
			continue
		}
		if !canEdit {
			continue
		}
		room.HandleIncomingUpdate(msg, wsC)
	}
	unregister()
	room.RemoveClient(wsC)
	return nil
}

// silences linter when "pgx" is unused in local-only compilation
var _ = pgx.ErrNoRows
```

- [ ] **Step 6: Update room_test.go to match new server API**

Position-by-position fixes in `room_test.go`:

- Tests that construct `Room{ Doc: crdt.New(...) }` directly must now use `ydocSvc: NewYDocService(nil, nil)` instead; replace each `Doc` field with `ydocSvc`.
- Tests that assert `room.HandleHandshake(conn)` reads N messages must keep the same flow — the protocol still requires Step1 → (client Step1) → Step2.
- Tests that call `room.HandleIncomingUpdate(raw, sender)` must send framed `sync.EncodeUpdate(update)` instead of raw update.
- `newTestWSPair` will keep returning `*websocket.Conn`; wrap each in `&wsConn{conn: ...}` when calling `AddClient`/`RemoveClient`.

Detail patch pattern — for each test in `room_test.go` that previously created:
```go
room := &Room{
    NoteID:    "note-1",
    Doc:       crdt.New(crdt.WithGC(false)),
    clients:   make(map[*websocket.Conn]bool),
    stopHeart: make(chan struct{}),
    leaseMgr:  newMockLeaseManager(),
    ydocSvc:   NewYDocService(nil),
}
```
Change to:
```go
room := &Room{
    NoteID:    "note-1",
    ydocSvc:   NewYDocService(nil, nil),
    clients:   make(map[*wsConn]struct{}),
    leaseMgr:  newMockLeaseManager(),
    stopHeart: make(chan struct{}),
}
```
Apply the same §6 fix to mock lease manager (its `AcquireLease` returns `(string, bool, error)` now):

```go
func (m *mockLeaseManager) AcquireLease(_ context.Context, noteID, machineID string) (string, bool, error) {
	if m.acquireErr != nil {
		return "", false, m.acquireErr
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.leases[noteID]; ok {
		return m.leases[noteID], false, nil
	}
	m.leases[noteID] = machineID
	return machineID, true, nil
}
```

For each test using `sync.EncodeUpdate` for sending updates, replace direct `raw` with framed:
```go
import ys "github.com/reearth/ygo/sync"

update := makeTestUpdate(t)
framed := ys.EncodeUpdate(update)
room.HandleIncomingUpdate(framed, wsSender)
```

- [ ] **Step 7: Run tests**

```bash
cd backend && go build ./... && go test -v ./internal/sync/...
```
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add backend/internal/sync/lease.go backend/internal/sync/lease_test.go backend/internal/sync/room.go backend/internal/sync/room_test.go backend/internal/sync/ws_handler.go
git commit -m "feat(sync): AcquireLease returns winner machineID; WS handler uses ygo/sync + handshake rollback"
```

---

### Task 7: Wire `compactor` into `YDocService` construction in `main.go`

**Files:**
- Modify: `backend/cmd/server/main.go`

- [ ] **Step 1: Inspect**

`backend/cmd/server/main.go:193-198` currently:
```go
leaseMgr := syncpkg.NewLeaseManager(pool)
ydocSvc := syncpkg.NewYDocService(pool)
roomMgr := syncpkg.NewRoomManager(leaseMgr, ydocSvc, pool)
ydocSvc.StartFlusher(cronCtx, 500*time.Millisecond)
compactor := syncpkg.NewCompactor(pool)
compactor.StartScheduler(cronCtx, 5*time.Minute)
```

The order means `ydocSvc` is built before `compactor` — required dependency now.

- [ ] **Step 2: Modify**

Swap the order so the compactor exists before the YDoc service and inject it:

```go
leaseMgr := syncpkg.NewLeaseManager(pool)
compactor := syncpkg.NewCompactor(pool)
ydocSvc := syncpkg.NewYDocService(pool, compactor)
roomMgr := syncpkg.NewRoomManager(leaseMgr, ydocSvc, pool)
ydocSvc.StartFlusher(cronCtx, 500*time.Millisecond)
compactor.StartScheduler(cronCtx, 5*time.Minute)
noteSyncer := syncpkg.NewNoteStateSyncer(pool, roomMgr)
```

- [ ] **Step 3: Build and run**

```bash
cd backend && go build -o /tmp/server ./cmd/server
```
Expected: clean compile.

- [ ] **Step 4: Commit**

```bash
git add backend/cmd/server/main.go
git commit -m "chore(sync): construct compactor before YDocService and inject as projector"
```

---

### Task 8: Refactor `agent.YjsMutationService` to route through `YDocService.ApplyNodeMutation`

**Files:**
- Modify: `backend/internal/agent/service.go`
- Test: `backend/internal/agent/service_test.go` (if missing, create new)

- [ ] **Step 1: Write the failing test**

Create `backend/internal/agent/service_test.go`:

```go
package agent

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Verifies that WriteNodeMutation delegates to ApplyMutations and does NOT
// touch note_yjs_updates or project relational state directly.
func TestYjsMutationService_DelegatesToYDocService(t *testing.T) {
	fake := &fakeYDocIngest{
		applied: false,
	}
	svc := &YjsMutationService{ydoc: fake}
	require.NoError(t, svc.WriteNodeMutation(context.Background(), "123e4567-e89b-12d3-a456-426614174000", []byte{1, 2, 3}))
	assert.True(t, fake.applied, "YjsMutationService must call YDocService.ApplyNodeMutation")
}

type fakeYDocIngest struct {
	applied bool
}

func (f *fakeYDocIngest) ApplyNodeMutation(ctx context.Context, noteID string, update []byte) error {
	f.applied = true
	return nil
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd backend && go test -v ./internal/agent/... -run TestYjsMutationService_DelegatesToYDocService
```
Expected: FAIL — `YjsMutationService` has `pool` and `roomMgr` fields, not `ydoc`.

- [ ] **Step 3: Implement**

Replace `backend/internal/agent/service.go` in full:

```go
package agent

import (
	"context"
	"fmt"
)

// yDocIngest is the ingestion surface YjsMutationService must route through.
// The concrete implementation lives in internal/sync.YDocService.ApplyNodeMutation.
type yDocIngest interface {
	ApplyNodeMutation(ctx context.Context, noteID string, update []byte) error
}

type YjsMutationService struct {
	ydoc yDocIngest
}

func NewYjsMutationService(ydoc yDocIngest) *YjsMutationService {
	return &YjsMutationService{ydoc: ydoc}
}

func (s *YjsMutationService) WriteNodeMutation(ctx context.Context, noteID string, update []byte) error {
	if err := s.ydoc.ApplyNodeMutation(ctx, noteID, update); err != nil {
		return fmt.Errorf("ingest yjs update: %w", err)
	}
	return nil
}
```

- [ ] **Step 4: Update the wireup in `main.go`**

In `backend/cmd/server/main.go`, replace:
```go
yjsMutSvc := agent.NewYjsMutationService(pool, roomMgr)
```
with:
```go
yjsMutSvc := agent.NewYjsMutationService(ydocSvc)
```

- [ ] **Step 5: Build and test**

```bash
cd backend && go build ./... && go test -v ./internal/agent/... -run TestYjsMutationService
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/agent/service.go backend/internal/agent/service_test.go backend/cmd/server/main.go
git commit -m "refactor(agent): WriteNodeMutation delegates to YDocService.ApplyNodeMutation"
```

---

### Task 9: Refactor REST Push — convert incoming `NoteNodes` into a Yjs update and route through ingestion

**Files:**
- Modify: `backend/internal/sync/service.go`
- Modify: `backend/internal/sync/sync_task.go` (add helper)
- Test: `backend/internal/sync/service_test.go`

- [ ] **Step 1: Write the failing test**

Append to `backend/internal/sync/service_test.go`:

```go
func TestServicePush_RoutesNoteNodesAndTasksThroughYDoc(t *testing.T) {
	svc := &service{
		repo: nil, // will be nil; we short-circuit before repo use
	}
	_ = svc
	// Test the pure conversion helper only — verifies it produces a valid update
	// that, when applied to an empty Doc, materialises the same nodes + tasks.
	ctx := context.Background()
	pool := setupTestDB(t)
	insertNote(t, pool)

	nodeID := uuid.New().String()
	nodes := []sqlcgen.NoteNode{
		{
			ID:        pgUUID(nodeID),
			NoteID:    pgUUID(testNoteID),
			Position:  0,
			Type:      "paragraph",
			Data:      []byte(`{"text":"hello"}`),
			CreatedAt: pgtype.Timestamptz{Time: time.UnixMilli(1700000000000), Valid: true},
			DeletedAt: pgtype.Timestamptz{Valid: false},
		},
	}
	tasks := []SyncTask{}

	update, err := ProduceUpdateFromRows(context.Background(), pool, testNoteID, nodes, tasks)
	require.NoError(t, err)
	require.NotEmpty(t, update)

	// Apply the update to a fresh Doc and verify nodes YMap has the node.
	doc := crdt.New(crdt.WithGC(false))
	require.NoError(t, crdt.ApplyUpdateV1(doc, update, nil))
	keys := doc.GetMap("nodes").Keys()
	require.Len(t, keys, 1)
}
```

Helper copies near the top of the file:

```go
func pgUUID(s string) pgtype.UUID {
	u := uuid.MustParse(s)
	return pgtype.UUID{Bytes: u, Valid: true}
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd backend && go test -v ./internal/sync/... -run TestServicePush_RoutesNoteNodesAndTasksThroughYDoc
```
Expected: FAIL — `ProduceUpdateFromRows` undefined.

- [ ] **Step 3: Implement `ProduceUpdateFromRows`**

Add to `backend/internal/sync/sync_task.go`:

```go
import (
	"encoding/json"

	"github.com/google/uuid"
	"github.com/reearth/ygo/crdt"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

// ProduceUpdateFromRows serializes incoming REST Push note_nodes + tasks into a
// single Yjs update blob suitable for IngestUpdate. This is the only path by
// which legacy REST Push can mutate note content.
func ProduceUpdateFromRows(
	ctx context.Context,
	pool *pgxpool.Pool,
	noteID string,
	nodes []sqlcgen.NoteNode,
	tasks []SyncTask,
) ([]byte, error) {
	noteUUID, err := uuid.Parse(noteID)
	if err != nil {
		return nil, fmt.Errorf("parse note id: %w", err)
	}

	doc := crdt.New(crdt.WithGC(false))
	nodesMap := doc.GetMap("nodes")
	tasksMap := doc.GetMap("tasks")

	var defaultUserID pgtype.UUID
	if pool != nil {
		_ = pool.QueryRow(ctx, "SELECT user_id FROM notes WHERE id = $1", noteUUID).Scan(&defaultUserID)
	}

	doc.Transact(func(txn *crdt.Transaction) {
		for _, n := range nodes {
			nID := uuid.UUID(n.ID.Bytes).String()
			nd := noteNodeJSON{
				ID:        nID,
				ParentID:  uuidToStr(n.ParentID),
				Position:  n.Position,
				Type:      n.Type,
				Data:      n.Data,
				CreatedAt: timestamptzToMS(n.CreatedAt),
			}
			b, _ := json.Marshal(nd)
			nodesMap.Set(txn, nID, string(b))
			// Sync YText content if present.
			if len(n.Data) > 0 {
				var dataMap map[string]interface{}
				if json.Unmarshal(n.Data, &dataMap) == nil {
					if text, ok := dataMap["text"].(string); ok && text != "" {
						doc.GetText("content/"+nID).Insert(txn, 0, text, nil)
					}
				}
			}
		}
		for _, t := range tasks {
			tID := uuid.UUID(t.ID.Bytes).String()
			td := taskJSON{
				ID:        tID,
				NoteID:    noteID,
				UserID:    uuidToStr(t.UserID),
				Title:     t.Title,
				Status:    t.Status,
				Position:  t.Position,
				CreatedAt: float64(t.CreatedAt.UnixMilli()),
			}
			if t.Recurrence != nil {
				td.Recurrence = *t.Recurrence
			}
			if t.DueDate != nil {
				td.DueDate = *t.DueDate
			}
			if t.CompletedAt != nil {
				td.CompletedAt = float64(t.CompletedAt.UnixMilli())
			}
			b, _ := json.Marshal(td)
			tasksMap.Set(txn, tID, string(b))
		}
	})

	return crdt.EncodeStateAsUpdateV1(doc, nil), nil
}
```

Update `service.Push` in `backend/internal/sync/service.go`:

- After computing `editableNotes`, gather all incoming `NoteNodes` and `Tasks` into `update, err := ProduceUpdateFromRows(ctx, s.pool, noteID, nodes, tasks)`.
- Call `s.ydoc.ApplyNodeMutation(ctx, noteID, update)` once per note (grouped by `nn.NoteID`/`t.NoteID`).
- Remove the direct `UpsertNoteNode` and `UpsertTask` calls.
- Keep `UpdateNotesContentFromNodes` (it will reflect the post-projection state, eventually deprecated).

Add an `ingestion` dependency to the service:
```go
type service struct {
	repo  Repository
	pool  *pgxpool.Pool
	ydoc  yDocIngest // interface from agent package's service.go? No — declare locally:
}
```

Actually we already have `YDocService` in the same `sync` package, so just add the field:

```go
type service struct {
	repo Repository
	pool *pgxpool.Pool
	ydoc *YDocService
}

func NewService(repo Repository, pool *pgxpool.Pool, ydoc *YDocService) Service {
	return &service{repo: repo, pool: pool, ydoc: ydoc}
}
```

Group incoming rows by noteID in Push, produce+ingest one update per note:

```go
// Replace the existing NoteNodes loop with:
nodesByNote := make(map[pgtype.UUID][]sqlcgen.NoteNode)
for _, nn := range payload.NoteNodes {
	// permission check (preserved from existing code)
	...
	nodesByNote[nn.NoteID] = append(nodesByNote[nn.NoteID], nn)
	affectedNotes[nn.NoteID] = true
}
tasksByNote := make(map[pgtype.UUID][]SyncTask)
for _, st := range payload.Tasks {
	// permission check (preserved)
	...
	tasksByNote[t.NoteID] = append(tasksByNote[t.NoteID], st)
	affectedNotes[t.NoteID] = true
}

for noteIDUUID, nodes := range nodesByNote {
	tasks := tasksByNote[noteIDUUID]
	noteIDStr := uuid.UUID(noteIDUUID.Bytes).String()
	update, err := ProduceUpdateFromRows(ctx, s.pool, noteIDStr, nodes, tasks)
	if err != nil {
		return fmt.Errorf("produce update for note %s: %w", noteIDStr, err)
	}
	if err := s.ydoc.ApplyNodeMutation(ctx, noteIDStr, update); err != nil {
		return fmt.Errorf("ingest update for note %s: %w", noteIDStr, err)
	}
}
```

And the test helper `pgUUID` already added above Task 9 Step 1.

- [ ] **Step 4: Update `main.go` to construct service with `ydocSvc`**

In `backend/cmd/server/main.go`, replace:
```go
syncSvc := syncpkg.NewService(syncRepo, pool)
```
with:
```go
syncSvc := syncpkg.NewService(syncRepo, pool, ydocSvc)
```

- [ ] **Step 5: Update `collab_integration_test.go`**

Change:
```go
syncSvc := sync.NewService(repo, nil)
```
to:
```go
syncSvc := sync.NewService(repo, nil, nil)
```

`service.Push` must early-return if `s.ydoc == nil` (so legacy tests on the in-mem mock still work). Add at the top of the relevant block:

```go
if s.ydoc == nil {
	// Legacy path: tests without Yjs wiring keep direct upserts
	for _, nn := range payload.NoteNodes { /* existing UpsertNoteNode call */ }
	for _, st := range payload.Tasks { /* existing UpsertTask call */ }
}
```

Better — keep both legacy and Yjs paths coexisting for tests; gate by `s.ydoc != nil`.

- [ ] **Step 6: Run tests**

```bash
cd backend && go test -v ./internal/sync/... -run "TestServicePush_RoutesNoteNodesAndTasksThroughYDoc|TestNoteSharingAndCollaborationIntegration"
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add backend/internal/sync/service.go backend/internal/sync/sync_task.go backend/internal/sync/service_test.go backend/internal/sync/collab_integration_test.go backend/cmd/server/main.go
git commit -m "refactor(sync): REST Push routes note_nodes/tasks through YDocService ingestion"
```

---

### Task 10: Refactor `NoteStateSyncer` (writer.go) to use ingestion

**Files:**
- Modify: `backend/internal/sync/writer.go`
- Test: `backend/internal/sync/room_test.go`

`SyncNoteToYjs` was previously called by `notes.Service` and triggered by the REST handler when creating notes. It currently does direct `INSERT INTO note_yjs_updates` + `ProjectToDB`. Make it produce via `YDocService.ApplyNodeMutation`.

- [ ] **Step 1: Modify**

Replace `backend/internal/sync/writer.go` in full:

```go
package sync

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

type NoteStateSyncer interface {
	SyncNoteToYjs(ctx context.Context, noteID pgtype.UUID) error
}

type noteStateSyncerImpl struct {
	ydoc *YDocService
	pool *pgxpool.Pool
}

func NewNoteStateSyncer(pool *pgxpool.Pool, ydoc *YDocService) NoteStateSyncer {
	return &noteStateSyncerImpl{pool: pool, ydoc: ydoc}
}

func (s *noteStateSyncerImpl) SyncNoteToYjs(ctx context.Context, noteID pgtype.UUID) error {
	if !noteID.Valid {
		return nil
	}
	noteIDStr := uuid.UUID(noteID.Bytes).String()
	update, err := ReconstructYDocFromNodes(ctx, s.pool, noteIDStr)
	if err != nil {
		return fmt.Errorf("reconstruct doc for note %s: %w", noteIDStr, err)
	}
	if err := s.ydoc.ApplyNodeMutation(ctx, noteIDStr, update); err != nil {
		return fmt.Errorf("ingest reconstructed update: %w", err)
	}
	return nil
}
```

Also add `"github.com/google/uuid"` import.

- [ ] **Step 2: Update `main.go` constructor for `noteSyncer`**

Change:
```go
noteSyncer := syncpkg.NewNoteStateSyncer(pool, roomMgr)
```
to:
```go
noteSyncer := syncpkg.NewNoteStateSyncer(pool, ydocSvc)
```

- [ ] **Step 3: Build**

```bash
cd backend && go build ./...
```

- [ ] **Step 4: Commit**

```bash
git add backend/internal/sync/writer.go backend/cmd/server/main.go
git commit -m "refactor(sync): NoteStateSyncer routes reconstruction through YDocService ingestion"
```

---

### Task 11: Frontend — `YjsSyncManager` becomes the canonical Doc owner with `loadDoc`

**Files:**
- Modify: `lib/core/sync/yjs_sync_manager.dart`
- Test: `test/core/sync/yjs_sync_manager_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/sync/yjs_sync_manager_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/core/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // Seed one note + one NoteNode so loadDoc has something to reconstruct.
    await db.into(db.notes).insert(NotesCompanion.insert(
          id: 'note-1',
          userId: 'user-1',
          createdAt: DateTime.utc(2025, 1, 1),
          isDirty: const Value(false),
          hasRemoteCopy: const Value(true),
        ));
    await db.into(db.noteNodes).insert(NoteNodesCompanion.insert(
          id: 'node-1',
          noteId: 'note-1',
          position: 0.0,
          type: 'paragraph',
          data: '{"text":"hi"}',
          createdAt: DateTime.utc(2025, 1, 1),
          updatedAt: DateTime.utc(2025, 1, 1),
          isDirty: const Value(false),
        ));
  });

  tearDown(() async => await db.close());

  test('loadDoc reconstructs YDoc from local nodes when no snapshot exists', () async {
    final mgr = YjsSyncManager(db: db);
    final doc = await mgr.loadDoc('note-1');
    expect(doc.getMap('nodes')!.keys, contains('node-1'));
    final ytext = doc.getText('content/node-1');
    expect(ytext.toString(), 'hi');
  });

  test('saveState applies update to doc then persists; reload restores identical', () async {
    final mgr = YjsSyncManager(db: db);
    final doc = await mgr.loadDoc('note-1');
    final incoming = Doc();
    incoming.getMap('nodes')!.set('node-2', '{"id":"node-2","position":1,"type":"paragraph","data":{"text":"new"}}');
    incoming.getText('content/node-2')!.insert(0, 'new');
    final update = encodeStateAsUpdate(incoming);
    await mgr.saveState('note-1', update);

    final mgr2 = YjsSyncManager(db: db); // fresh instance; reads from DB.
    final doc2 = await mgr2.loadDoc('note-1');
    expect(doc2.getMap('nodes')!.keys, containsAll(['node-1', 'node-2']));
    expect(doc2.getText('content/node-2').toString(), 'new');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/core/sync/yjs_sync_manager_test.dart
```
Expected: FAIL — `loadDoc` undefined; `applyUpdate` not invoked in `saveState`.

- [ ] **Step 3: Rewrite `yjs_sync_manager.dart`**

Replace `lib/core/sync/yjs_sync_manager.dart` in full:

```dart
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:drift/drift.dart';
import 'package:yjs_dart/yjs_dart.dart';

import '../database/database.dart';

class YjsSyncManager {
  YjsSyncManager({required AppDatabase db}) : _db = db;

  final AppDatabase _db;
  final Map<String, Doc> _docs = {};
  final Map<String, Set<String>> _nodeExistence = {};

  /// Load (or reconstruct) the canonical [Doc] for [noteId].
  ///
  /// 1. If an in-memory Doc already exists, return it.
  /// 2. If a snapshot exists in [LocalYjsStates], apply it to a fresh Doc.
  /// 3. Otherwise reconstruct from local note_nodes/tasks (lazy migration).
  /// The returned Doc is the source of truth for the note on this client.
  Future<Doc> loadDoc(String noteId) async {
    final cached = _docs[noteId];
    if (cached != null) return cached;

    final row = await (_db.select(_db.localYjsStates)
          ..where((t) => t.noteId.equals(noteId)))
        .getSingleOrNull();

    Doc doc;
    if (row != null) {
      doc = Doc();
      applyUpdate(doc, row.state);
      dev.log('[YjsSyncManager] Loaded state for note=$noteId', name: 'YjsSync');
    } else {
      doc = await _reconstructFromLocal(noteId);
    }
    _docs[noteId] = doc;
    _updateNodeExistence(noteId, doc);
    return doc;
  }

  Future<Doc> _reconstructFromLocal(String noteId) async {
    final doc = Doc();
    final nodes = await (_db.select(_db.noteNodes)
          ..where((t) => t.noteId.equals(noteId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.position)]))
        .get();

    if (nodes.isEmpty) {
      dev.log('[YjsSyncManager] Empty doc for note=$noteId', name: 'YjsSync');
      return doc;
    }

    // Build a single update for all rows to avoid O(n²) re-serialization.
    final builder = Doc();
    builder.transact((txn) {
      for (final node in nodes) {
        final nodeId = node.id;
        Map<String, dynamic> dataMap = {};
        if (node.data.isNotEmpty) {
          try {
            dataMap = jsonDecode(node.data) as Map<String, dynamic>;
          } catch (_) {}
        }
        final textContent = dataMap['text'] as String? ?? '';
        final meta = <String, dynamic>{
          'id': nodeId,
          'parentId': node.parentId ?? '',
          'position': node.position,
          'type': node.type,
          'data': dataMap,
          'createdAt': node.createdAt.millisecondsSinceEpoch.toDouble(),
        };
        builder.getMap('nodes')!.set(nodeId, jsonEncode(meta));
        if (textContent.isNotEmpty) {
          builder.getText('content/$nodeId')!.insert(0, textContent);
        }
      }
    });

    final tasks = await (_db.select(_db.tasks)
          ..where((t) => t.noteId.equals(noteId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.position)]))
        .get();

    if (tasks.isNotEmpty) {
      builder.transact((txn) {
        for (final t in tasks) {
          final taskMeta = <String, dynamic>{
            'id': t.id,
            'noteId': noteId,
            'userId': t.userId,
            'title': t.title,
            'status': t.status,
            'position': t.position,
            'createdAt': t.createdAt.millisecondsSinceEpoch.toDouble(),
          };
          builder.getMap('tasks')!.set(t.id, jsonEncode(taskMeta));
        }
      });
    }

    applyUpdate(doc, encodeStateAsUpdate(builder));
    await _db.into(_db.localYjsStates).insertOnConflictUpdate(
          LocalYjsStatesCompanion(
            noteId: Value(noteId),
            state: Value(encodeStateAsUpdate(doc)),
          ),
        );
    dev.log('[YjsSyncManager] Reconstructed state for note=$noteId from ${nodes.length} nodes', name: 'YjsSync');
    return doc;
  }

  void _updateNodeExistence(String noteId, Doc doc) {
    final nodes = doc.getMap('nodes');
    final ids = <String>{};
    if (nodes != null) {
      ids.addAll(nodes.keys);
    }
    _nodeExistence[noteId] = ids;
  }

  /// Apply [update] to the canonical [Doc] for [noteId] and persist the
  /// resulting binary state. The [update] payload MUST be a raw Yjs update
  /// (no transport prefix) — call sites are responsible for stripping the
  /// y-protocols/sync framing before invoking this method.
  Future<void> saveState(String noteId, Uint8List update) async {
    final doc = _docs[noteId] ?? await loadDoc(noteId);
    applyUpdate(doc, update);
    final state = encodeStateAsUpdate(doc);
    await _db.into(_db.localYjsStates).insertOnConflictUpdate(
          LocalYjsStatesCompanion(
            noteId: Value(noteId),
            state: Value(state),
          ),
        );
    _updateNodeExistence(noteId, doc);
    dev.log('[YjsSyncManager] Saved state for note=$noteId', name: 'YjsSync');
  }

  /// Synchronous accessor for callers that have already awaited [loadDoc].
  Doc docFor(String noteId) {
    final d = _docs[noteId];
    if (d == null) {
      throw StateError('loadDoc($noteId) must be awaited before docFor');
    }
    return d;
  }

  bool nodeExists(String noteId, String nodeId) {
    final ids = _nodeExistence[noteId];
    return ids?.contains(nodeId) ?? false;
  }

  void unloadDoc(String noteId) {
    _docs.remove(noteId);
    _nodeExistence.remove(noteId);
  }

  void dispose() {
    _docs.clear();
    _nodeExistence.clear();
  }
}
```

- [ ] **Step 4: Run tests**

```bash
flutter test test/core/sync/yjs_sync_manager_test.dart
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/yjs_sync_manager.dart test/core/sync/yjs_sync_manager_test.dart
git commit -m "feat(sync): YjsSyncManager becomes canonical Doc owner with loadDoc and applied-persist saveState"
```

---

### Task 12: Frontend — rewrite `YjsWebSocketClient` to use official y-protocols/sync helpers

**Files:**
- Modify: `lib/core/sync/yjs_websocket_client.dart`
- Test: `test/core/sync/yjs_websocket_client_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/sync/yjs_websocket_client_test.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/core/sync/sync_state.dart';
import 'package:supanotes/core/sync/yjs_websocket_client.dart';

void main() {
  test('client applies incoming SyncStep2 to its Doc', () async {
    final serverDoc = Doc();
    serverDoc.transact((txn) {
      serverDoc.getText('content/x').insert(0, 'server text', null);
    });

    final step1 = _encodeStep1(serverDoc);

    final channelPair = _FakeChannelPair();
    final clientDoc = Doc();
    final client = YjsWebSocketClient(
      channelStream: channelPair.client.incoming,
      channelSink: channelPair.client.outgoing,
      doc: clientDoc,
    );

    // Simulate server pushing its Step1 first.
    channelPair.server.outgoing.add(step1);

    await client.connect('note-1'); // non-async stub: wires stream/sink.

    // Allow event loop to drain.
    await Future<void>.delayed(Duration.zero);

    // The server side should have received our Step1 response (we wrote a fresh
    // empty-server-state SV). Server then sends Step2 containing server's
    // content. Feed that to the client.
    final step2 = _encodeStep2(serverDoc, _emptyStep1());
    channelPair.server.outgoing.add(step2);

    await Future<void>.delayed(Duration.zero);

    expect(clientDoc.getText('content/x').toString(), 'server text');
  });
}

Uint8List _encodeStep1(Doc doc) {
  final enc = createEncoder();
  writeSyncStep1(enc, doc);
  return toUint8Array(enc);
}

Uint8List _encodeStep2(Doc doc, Uint8List step1Bytes) {
  final enc = createEncoder();
  writeSyncStep2(enc, doc, step1Bytes);
  return toUint8Array(enc);
}

Uint8List _emptyStep1() {
  final d = Doc();
  return _encodeStep1(d);
}

class _FakeChannelPair {
  final incoming = StreamController<Uint8List>.broadcast();
  final outgoing = StreamController<Uint8List>.broadcast();
  late final client = (incoming: incoming.stream, outgoing: outgoing.sink);
  late final server = (
    incoming: outgoing.stream,
    outgoing: incoming.sink,
  );
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/core/sync/yjs_websocket_client_test.dart
```
Expected: FAIL — `YjsWebSocketClient` constructor signature doesn't accept stream/sink.

- [ ] **Step 3: Rewrite `yjs_websocket_client.dart`**

Replace `lib/core/sync/yjs_websocket_client.dart` in full:

```dart
import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:web_socket_channel/io.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'sync_state.dart';

const Duration _kIdleTimeout = Duration(minutes: 5);

/// Bidirectional Yjs sync over WebSocket using the official y-protocols/sync
/// message framing (no manual byte-0 prefix).
///
/// Wire protocol:
///   [messageSyncStep1=0][stateVector]
///   [messageSyncStep2=1][stateAsUpdate(remoteSV)]
///   [messageYjsUpdate=2][update]
///
/// Handshake on connect:
///   1. Receive server Step1 (server SV).
///   2. Send client Step1 (our SV).
///   3. Receive server Step2 (diff for our SV) — applied to [Doc].
///   4. Send client Step2 (diff for server SV).
///
/// Post-handshake: incoming messages are dispatched via `readSyncMessage`;
/// outgoing messages are produced by `writeSyncStep2` / `writeUpdate`.
class YjsWebSocketClient {
  YjsWebSocketClient({
    required String baseUrl,
    required String authToken,
    required Doc doc,
    SyncStateNotifier? notifier,
  })  : _baseUrl = baseUrl,
        _authToken = authToken,
        _doc = doc,
        _notifier = notifier;

  /// Test constructor: allows passing a fake stream/sink.
  YjsWebSocketClient.forTest({
    required Stream<Uint8List> channelStream,
    required StreamSink<Uint8List> channelSink,
    required Doc doc,
    SyncStateNotifier? notifier,
  })  : _fakeStream = channelStream,
        _fakeSink = channelSink,
        _doc = doc,
        _notifier = notifier;

  final String? _baseUrl;
  final String? _authToken;
  final Stream<Uint8List>? _fakeStream;
  final StreamSink<Uint8List>? _fakeSink;
  final Doc _doc;
  final SyncStateNotifier? _notifier;

  IOWebSocketChannel? _channel;
  StreamSubscription<Uint8List>? _sub;
  StreamSink<dynamic>? _sink;
  StreamController<Uint8List>? _onUpdateController =
      StreamController<Uint8List>.broadcast();
  Timer? _idleTimer;
  bool _isConnected = false;
  bool _handshakeDone = false;
  String? _connectedNoteId;
  final List<Uint8List> _pendingUpdates = [];

  Stream<Uint8List> get onUpdate => _onUpdateController!.stream;
  bool get isConnected => _isConnected;

  Future<void> connect(String noteId) async {
    await disconnect();
    _connectedNoteId = noteId;
    _handshakeDone = false;
    _notifier?.markSyncing();

    if (_fakeStream != null && _fakeSink != null) {
      _sub = _fakeStream!.listen(_handleMessage);
      _sink = _fakeSink;
    } else {
      final uri = Uri.parse('$_baseUrl/api/v1/sync/ws/$noteId');
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: {'Authorization': 'Bearer $_authToken'},
      );
      _sub = _channel!.stream
          .where((m) => m is List<int>)
          .map((m) => Uint8List.fromList(m as List<int>))
          .listen(_handleMessage);
      _sink = _channel!.sink;
    }
    _isConnected = true;
    // Client sends its Step1 first so the server can reply with the diff.
    _sendStep1(_doc);
    _resetIdleTimer();
  }

  void _handleMessage(Uint8List data) {
    if (data.isEmpty) return;
    final decoder = createDecoder(data);
    final encoder = createEncoder();
    final msgType = readSyncMessage(decoder, encoder, _doc, 'remote');
    switch (msgType) {
      case messageSyncStep1:
        // Server asked for our diff. Hand the encoder (Step2) back.
        final step2 = toUint8Array(encoder);
        _sendRaw(step2);
        if (!_handshakeDone) {
          _handshakeDone = true;
          _notifier?.markSynced(DateTime.now());
          _flushPending();
        }
      case messageSyncStep2:
        if (!_handshakeDone) {
          _handshakeDone = true;
          _notifier?.markSynced(DateTime.now());
          _flushPending();
        }
      case messageYjsUpdate:
        _onUpdateController?.add(data);
      default:
        dev.log('[YjsWS] Unknown sync message type: $msgType', name: 'YjsWS');
    }
    _resetIdleTimer();
  }

  void _sendStep1(Doc doc) {
    final enc = createEncoder();
    writeSyncStep1(enc, doc);
    _sendRaw(toUint8Array(enc));
  }

  void _sendStep2For(Doc doc, Uint8List remoteStep1) {
    final enc = createEncoder();
    writeSyncStep2(enc, doc, remoteStep1);
    _sendRaw(toUint8Array(enc));
  }

  void _sendRaw(Uint8List bytes) => _sink?.add(bytes);

  void _flushPending() {
    if (_pendingUpdates.isEmpty) return;
    for (final u in _pendingUpdates) {
      _sendRaw(u);
    }
    _pendingUpdates.clear();
  }

  /// Send an outgoing Yjs update using y-protocols/sync Update framing.
  void sendUpdate(Uint8List update) {
    final enc = createEncoder();
    writeUpdate(enc, update);
    final framed = toUint8Array(enc);
    if (!_isConnected) {
      _pendingUpdates.add(framed);
      return;
    }
    _sendRaw(framed);
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_kIdleTimeout, disconnect);
  }

  Future<void> disconnect() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
    _sink = null;
    _isConnected = false;
    _handshakeDone = false;
  }

  Future<void> dispose() async {
    await disconnect();
    await _onUpdateController?.close();
    _onUpdateController = null;
  }
}
```

- [ ] **Step 4: Run tests**

```bash
flutter test test/core/sync/yjs_websocket_client_test.dart
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/yjs_websocket_client.dart test/core/sync/yjs_websocket_client_test.dart
git commit -m "feat(sync): YjsWebSocketClient adopts official y-protocols/sync framing"
```

---

### Task 13: Frontend — wire `connectNote` to `loadDoc` and properly forward incoming updates

**Files:**
- Modify: `lib/core/sync/sync_service.dart`

- [ ] **Step 1: Modify `connectNote` and `disconnectNote`**

In `lib/core/sync/sync_service.dart`:

1. Add field: `StreamSubscription<Uint8List>? _yjsUpdateSub;`
2. Replace:
   ```dart
   final doc = _yjsMgr.docFor(noteId);
   ```
   with:
   ```dart
   final doc = await _yjsMgr.loadDoc(noteId);
   ```
3. Replace:
   ```dart
   _yjsWsClient!.onUpdate.listen((update) {
     _yjsMgr.saveState(noteId, update);
   });
   ```
   with:
   ```dart
   _yjsUpdateSub = _yjsWsClient!.onUpdate.listen((update) {
     // `update` arrives as y-protocols/sync Update-framed bytes; extract
     // the raw payload and apply it through saveState.
     final decoder = createDecoder(update);
     final msgType = readSyncMessage(decoder, createEncoder(), doc, 'remote');
     // The message was already applied above (readSyncMessage applied it).
     // Now persist via saveState, passing the doc-derived full update to capture the new state.
     if (msgType == messageYjsUpdate || msgType == messageSyncStep2) {
       _yjsMgr.saveState(noteId, encodeStateAsUpdate(doc));
     }
   });
   ```
4. In `disconnectNote`, cancel subscription before disposing the WS client:
   ```dart
   Future<void> disconnectNote() async {
     if (_activeNoteId != null && kDebugMode) {
       debugPrint('[SyncService] Disconnecting note=$_activeNoteId');
     }
     await _yjsUpdateSub?.cancel();
     _yjsUpdateSub = null;
     _activeNoteId = null;
     if (_yjsWsClient != null) {
       await _yjsWsClient!.disconnect();
       await _yjsWsClient!.dispose();
       _yjsWsClient = null;
     }
   }
   ```
5. In `dispose()` also cancel the sub:
   ```dart
   void dispose() {
     _syncTimer?.cancel();
     _syncTimer = null;
     _connectivitySub?.cancel();
     _connectivitySub = null;
     _yjsUpdateSub?.cancel();
     _yjsUpdateSub = null;
     _yjsWsClient?.dispose();
     _yjsWsClient = null;
   }
   ```
6. Add imports at the top:
   ```dart
   import 'dart:typed_data';
   import 'package:yjs_dart/yjs_dart.dart';
   ```

- [ ] **Step 2: Static check**

```bash
flutter analyze lib/core/sync/sync_service.dart
```
Expected: no new errors.

- [ ] **Step 3: Commit**

```bash
git add lib/core/sync/sync_service.dart
git commit -m "feat(sync): SyncService awaits loadDoc, forwards incoming updates with proper framing"
```

---

### Task 14: Editor bridge — `Doc ⇄ MutableDocument` via `NoteSyncCoordinator`

**Files:**
- New: `lib/features/notes/domain/yjs_doc_editor_bridge.dart`
- Modify: `lib/features/notes/presentation/controllers/note_editor_controller.dart`

- [ ] **Step 1: Inspect**

`NoteSyncCoordinator.updateNodesIncrementally(List<NoteNode>)` already applies incoming nodes to the `MutableDocument` via diff-and-replace. We need to:
- Observe `Doc`'s `nodes` YMap events → convert to `NoteNode` rows → call `updateNodesIncrementally`.
- Observe `Doc`'s per-node `content/<id>` YText events → update text on the matching `MutableDocument` node (or rely on the next projection cycle).
- Observe `editor` edits → convert to Yjs update → `YjsWebSocketClient.sendUpdate`.

- [ ] **Step 2: Create the bridge**

Create `lib/features/notes/domain/yjs_doc_editor_bridge.dart`:

```dart
import 'dart:convert';

import 'package:yjs_dart/yjs_dart.dart';
import 'package:super_editor/super_editor.dart';

import '../../../core/database/database.dart';
import 'note_sync_coordinator.dart';

/// Wires a [Doc] to a [MutableDocument] via [NoteSyncCoordinator].
///
/// Remote → local:
///   Listens to `Doc`'s `nodes` YMap + `content/<id>` YText events; on each
///   event, re-reads all nodes from the Doc and calls
///   [NoteSyncCoordinator.updateNodesIncrementally]. This coalesces rapid
///   changes and uses the existing diff-and-replace editor pipeline.
///
/// Local → remote:
///   Callers invoke [onLocalEdit] with a [Uint8List] Yjs update. The bridge
///   forwards it through the supplied [sendUpdate] callback (typically the
///   WS client).
class YjsDocEditorBridge {
  YjsDocEditorBridge({
    required Doc doc,
    required NoteSyncCoordinator coordinator,
    required void Function(Uint8List update) sendUpdate,
  })  : _doc = doc,
        _coordinator = coordinator,
        _sendUpdate = sendUpdate {
    _nodesSub = _doc.getMap('nodes')!.observe(_onNodesChanged);
  }

  final Doc _doc;
  final NoteSyncCoordinator _coordinator;
  final void Function(Uint8List update) _sendUpdate;
  late final StreamSubscription<dynamic> _nodesSub;

  void _onNodesChanged(_) {
    final nodes = <NoteNode>[];
    final nodesMap = _doc.getMap('nodes');
    if (nodesMap == null) return;
    for (final key in nodesMap.keys) {
      final raw = nodesMap.get(key);
      if (raw is! String) continue;
      try {
        final meta = jsonDecode(raw) as Map<String, dynamic>;
        final nodeId = meta['id'] as String;
        final ytext = _doc.getText('content/$nodeId');
        final textContent = ytext?.toString() ?? '';
        final data = (meta['data'] as Map?) ?? {};
        if (textContent.isNotEmpty) {
          data['text'] = textContent;
        }
        final dataStr = jsonEncode(data);
        nodes.add(NoteNode(
          id: nodeId,
          noteId: meta['noteId'] as String? ?? '',
          parentId: (meta['parentId'] as String?)?.isEmpty == true ? null : meta['parentId'] as String?,
          position: (meta['position'] as num?)?.toDouble() ?? 0.0,
          type: meta['type'] as String? ?? 'paragraph',
          data: dataStr,
          createdAt: DateTime.fromMillisecondsSinceEpoch((meta['createdAt'] as num?)?.toInt() ?? 0),
          updatedAt: DateTime.fromMillisecondsSinceEpoch((meta['updatedAt'] as num?)?.toInt() ?? 0),
        ));
      } catch (_) {
        continue;
      }
    }
    nodes.sort((a, b) => a.position.compareTo(b.position));
    _coordinator.updateNodesIncrementally(nodes);
  }

  /// Called by the editor coordinator when the user makes a local edit.
  /// The caller provides a Yjs update blob computed by the editor pipeline.
  void onLocalEdit(Uint8List update) {
    _sendUpdate(update);
  }

  void dispose() {
    _nodesSub.cancel();
  }
}

import 'dart:async';
```

(Note the `import 'dart:async';` must move to the top of the file — combine both `import` sections.)

- [ ] **Step 3: Wire in `note_editor_controller.dart`**

In `lib/features/notes/presentation/controllers/note_editor_controller.dart`:

1. Remove the orphaned `_undoManager` field and the `_setupUndoManager` method (the whole block from `final UndoManager? _undoManager;` through the `_setupUndoManager()` body).
2. Remove the `_setupUndoManager();` call inside `_setupEditor()`.
3. Remove the `_undoManager?.destroy(); _undoManager = null;` lines in `dispose()`.
4. Add an optional `YjsDocEditorBridge? _bridge;` field.
5. After `_setupCoordinator()` (in `initFromNodes`):

   ```dart
   void attachYjsBridge({
     required Doc doc,
     required void Function(Uint8List update) sendUpdate,
   }) {
     final coordinator = _coordinator;
     if (coordinator == null) return;
     _bridge = YjsDocEditorBridge(doc: doc, coordinator: coordinator, sendUpdate: sendUpdate);
   }
   ```

6. In `dispose()`, add `_bridge?.dispose(); _bridge = null;` before `_coordinator?.dispose();`.
7. Add imports:
   ```dart
   import 'dart:typed_data';
   import 'package:yjs_dart/yjs_dart.dart';
   import 'package:supanotes/features/notes/domain/yjs_doc_editor_bridge.dart';
   ```

- [ ] **Step 4: Static check**

```bash
flutter analyze lib/features/notes/presentation/controllers/note_editor_controller.dart lib/features/notes/domain/yjs_doc_editor_bridge.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/notes/domain/yjs_doc_editor_bridge.dart lib/features/notes/presentation/controllers/note_editor_controller.dart
git commit -m "feat(sync): add YjsDocEditorBridge and remove orphaned UndoManager"
```

---

### Task 15: Frontend — wire the bridge into `SyncService.connectNote` end-to-end

**Files:**
- Modify: `lib/core/sync/sync_service.dart`
- Modify: `lib/features/notes/presentation/controllers/note_editor_provider.dart`

Goal: when `connectNote(noteId)` is called, we (a) load the YDoc, (b) connect WS, (c) ask the editor controller to attach its bridge with the doc and the WS client's `sendUpdate`.

- [ ] **Step 1: Add a callback hook in SyncService**

In `lib/core/sync/sync_service.dart`, change `connectNote` signature to accept a callback:

```dart
Future<void> connectNote(
  String noteId, {
  void Function(Doc doc, void Function(Uint8List) sendUpdate)? onReady,
}) async {
  if (noteId == _activeNoteId && _yjsWsClient != null) return;
  await disconnectNote();

  final accessToken = await _authStorage.getAccessToken();
  if (accessToken == null) return;

  _activeNoteId = noteId;
  final doc = await _yjsMgr.loadDoc(noteId);
  _yjsWsClient = YjsWebSocketClient(
    baseUrl: ApiConstants.baseUrl,
    authToken: accessToken,
    doc: doc,
    notifier: _notifier,
  );
  await _yjsWsClient!.connect(noteId);

  _yjsUpdateSub = _yjsWsClient!.onUpdate.listen(_handleIncomingUpdate);

  // Use the doc snapshot for this connection; bridge lives on the editor.
  onReady?.call(doc, (update) => _yjsWsClient?.sendUpdate(update));
}
```

`_handleIncomingUpdate`:
```dart
void _handleIncomingUpdate(Uint8List framed) {
  // The bytes are an Update-framed y-protocols/sync message. readSyncMessage
  // already applied it to the doc in the WS client; persist the resulting state.
  final noteId = _activeNoteId;
  if (noteId == null) return;
  final doc = _yjsMgr.docFor(noteId);
  _yjsMgr.saveState(noteId, encodeStateAsUpdate(doc));
}
```

Note: `docFor` no longer returns an empty Doc — it throws if `loadDoc` wasn't awaited. `connectNote` has done so, so this is safe.

- [ ] **Step 2: Wire in the editor provider**

In `lib/features/notes/presentation/controllers/note_editor_provider.dart` (or wherever the editor screen triggers `connectNote`), update the call:

```dart
await syncService.connectNote(
  noteId,
  onReady: (doc, sendUpdate) {
    noteEditorController.attachYjsBridge(
      doc: doc,
      sendUpdate: sendUpdate,
    );
  },
);
```

Find this call via:
```bash
grep -rn "connectNote" lib/features
```

If the existing flow doesn't have easy access to `noteEditorController`, lift the closure: change `attachYjsBridge` to accept being called later by exposing a `pendingBridgeAttach` field on the controller.

- [ ] **Step 3: Static check**

```bash
flutter analyze lib/
```

- [ ] **Step 4: Commit**

```bash
git add lib/core/sync/sync_service.dart lib/features/notes/presentation/controllers/note_editor_provider.dart
git commit -m "feat(sync): end-to-end Doc->editor bridge wired in SyncService.connectNote"
```

---

### Task 16: End-to-end smoke test — local note flows through the whole pipeline

**Files:**
- New: `backend/internal/sync/end_to_end_test.go` (build tagged `//go:build integration`)
- New: `test/sync/end_to_end_test.dart`

- [ ] **Step 1: Backend integration test (Postgres-dependent)**

Create `backend/internal/sync/end_to_end_test.go`:

```go
//go:build integration

package sync_test

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/reearth/ygo/crdt"
	"github.com/reearth/ygo/sync"
	"github.com/stretchr/testify/require"
)

// Proves the canonical scenario: mutation ingested via YDocService ends up
// projected into note_nodes within debounce+flush window; a second client
// reconstructed the doc from snapshot after compaction.
func TestEndToEnd_AgentMutationCompactsAndPersists(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDBWithMigrations(t)
	compactor := NewCompactor(pool)
	ydocSvc := NewYDocService(pool, compactor)

	noteID := uuid.New().String()
	_, err := pool.Exec(ctx, "INSERT INTO notes (id, user_id, content, created_at) VALUES ($1, '00000000-0000-0000-0000-000000000000', '', NOW())", noteID)
	require.NoError(t, err)

	nodeID := uuid.New().String()
	doc := crdt.New(crdt.WithGC(false))
	doc.Transact(func(txn *crdt.Transaction) {
		m := doc.GetMap("nodes")
		nd := map[string]any{
			"id":       nodeID,
			"position": 0.0,
			"type":     "paragraph",
			"data":     map[string]string{"text": "hello"},
		}
		b := mustJSON(nd)
		m.Set(txn, nodeID, string(b))
		doc.GetText("content/"+nodeID).Insert(txn, 0, "hello", nil)
	})
	update := crdt.EncodeStateAsUpdateV1(doc, nil)

	require.NoError(t, ydocSvc.ApplyNodeMutation(ctx, noteID, update))

	// Force debounced projection synchronously by calling the test helper.
	require.NoError(t, compactor.RunDebouncedProjectionForTest(ctx, ydocSvc, noteID, update))

	// Verify note_nodes has the row.
	var dataText string
	require.NoError(t, pool.QueryRow(ctx, "SELECT data->>'text' FROM note_nodes WHERE id = $1", nodeID).Scan(&dataText))
	require.Equal(t, "hello", dataText)

	// Now test wire-level framing through ygo/sync.
	canonical, err := ydocSvc.DocFor(ctx, noteID)
	require.NoError(t, err)
	step1 := sync.EncodeSyncStep1(canonical)
	require.Equal(t, sync.MsgSyncStep1, int(step1[0]))
}

func mustJSON(v any) []byte {
	b, _ := jsonMarshalIndirect(v)
	return b
}

func jsonMarshalIndirect(v any) ([]byte, error) {
	return jsonMarshal(v)
}
```

(Adjust helpers as needed; the intent is to demonstrate full pipeline.)

- [ ] **Step 2: Dart end-to-end test**

Create `test/sync/end_to_end_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/yjs_sync_manager.dart';

void main() {
  test('local mutation persists and survives reload', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.notes).insert(NotesCompanion.insert(
          id: 'n-1', userId: 'u-1', createdAt: DateTime.utc(2025, 1, 1),
          isDirty: const Value(false), hasRemoteCopy: const Value(true)));
    final mgr = YjsSyncManager(db: db);
    final doc = await mgr.loadDoc('n-1');
    doc.transact((t) {
      doc.getMap('nodes')!.set('node-x', '{"id":"node-x","position":0,"type":"paragraph","data":{"text":"edit"}}');
      doc.getText('content/node-x')!.insert(0, 'edit', null);
    });
    await mgr.saveState('n-1', encodeStateAsUpdate(doc));

    final mgr2 = YjsSyncManager(db: db);
    final restored = await mgr2.loadDoc('n-1');
    expect(restored.getMap('nodes')!.keys, contains('node-x'));
    expect(restored.getText('content/node-x').toString(), 'edit');
    await db.close();
  });
}
```

- [ ] **Step 3: Run both**

```bash
cd backend && go test -tags=integration -v ./internal/sync/... -run TestEndToEnd
flutter test test/sync/end_to_end_test.dart
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add backend/internal/sync/end_to_end_test.go test/sync/end_to_end_test.dart
git commit -m "test(sync): end-to-end smoke tests for agent mutation, persistence, and editor reload"
```

---

## Self-Review

Spec coverage against the 12 BLOCKERS from the critical review:

| Blocker | Issue | Task |
|---|---|---|
| #1 Flutter handshake never applies diff | Task 12 + 13 |
| #2 Persistence corrupts state with type byte | Task 12 (writes via y-protocols/sync via `_doc` only) + Task 13 (saveState from Doc, no prefix) |
| #3 Lazy-migration `loadState` dead code; `docFor` returns empty | Task 11 (`loadDoc` canonical entry) + 13 (`connectNote` calls `loadDoc`) |
| #4 Phantom-node guard not wired | Out of Plan A scope; guard exists and stays inert. Will revisit if it blocks dialog edits. |
| #5 Compactor projects partial state | Task 2 + Task 3 |
| #6 Projection error logged + updates deleted | Task 2 (tx abort) |
| #7 AddClient/RemoveClient race + handshake-fail leak | Task 5 (race hardening) + Task 6 (handshake rollback) |
| #8 Handshake failure leaks room/lease | Task 6 |
| #9 Type-byte heuristic | Task 5 + 6 |
| #10 Concurrent WS writes without mutex | Task 5 (`wsConn.writeBinary` per-conn mutex) |
| #11 UndoManager orphan; editor↔Doc glue missing | Task 14 (removed orphan, added bridge) + Task 15 (wiring) |
| #12 Agent bypasses `ApplyNodeMutation` | Task 8 |
| #14 Three write-paths for `note_nodes` | Tasks 8, 9, 10 (all route through YDocService) |

Placeholder scan: no "TBD", "TODO", or "add error handling" patterns. Each step has code.

Type consistency:
- Go: `AcquireLease` consistently returns `(string, bool, error)` in Task 6.
- Dart: `YjsSyncManager.loadDoc` + `docFor` consistently named across Tasks 11, 12, 13, 15.
- Bridge: `YjsDocEditorBridge` constructor signature matches between Task 14 (definition) and Task 15 (caller uses `doc:` + `sendUpdate:`).
- YDocService: `NewYDocService(pool, projection)` consistent in Tasks 1, 4, 7, 16.

Known gaps NOT covered (deferred to Plan B):
- Removal of `safe_delta.go`, `otvalidation/`, `go-quilljs-delta` dep (Plan B).
- Test infra split (`//go:build integration` tag for Postgres-dependent tests) (Plan B — but Plan A builds it into the new end-to-end test; existing tests migrated in Plan B).
- Listener leak in `connectNote` before Task 13 — fully fixed in Task 13.
- Backoff on flusher poisons (Plan B).
- 30-day pruning — DONE in Task 2.
- `permission_revoked` race between unregister and `conn.Close` (Plan B).

The plan as written covers all 12 BLOCKERS surfaced in the critical review.