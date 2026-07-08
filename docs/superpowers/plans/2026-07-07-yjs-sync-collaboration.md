# Yjs Synchronization & Collaboration Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current Operational Transformation (OT) delta synchronization mechanism with a Yjs-based synchronization engine utilizing Go's `ygo` and Dart's `yjs_dart` libraries. Includes dynamic election sticky-routing, connection-level permission caching, transactional database projections, client-side Drift YDoc backups, and strict agent mutation pathways.

**Architecture:** The client and server communicate via WebSockets (with REST push/pull fallback). The in-memory YDoc acts as the single source of truth, periodically projecting structural updates into the Postgres `note_nodes` and `tasks` tables.

**Tech Stack:** Go 1.22 (Standard Library, Reearth `ygo`, Gorilla `websocket`), Dart/Flutter (Drift, `yjs_dart`), PostgreSQL.

---

## Task 0: Safety Backup of Production Database

**Files:** None (CLI commands only)

- [ ] **Step 1: Execute pg_dump on Fly.io Database Cluster**
Run:
```bash
fly ssh console -a backend-winter-waterfall-5807-db
```
Inside the container, run:
```bash
pg_dump -U postgres supanotes -F c -b -v -f /tmp/supanotes_prod_backup_pre_yjs.dump
```
Expected output: A compressed database dump is created under `/tmp/`.

- [ ] **Step 2: Download Dump to Local Machine**
Run:
```bash
fly ssh sftp get /tmp/supanotes_prod_backup_pre_yjs.dump ./supanotes_prod_backup_pre_yjs.dump -a backend-winter-waterfall-5807-db
```
Expected output: File `supanotes_prod_backup_pre_yjs.dump` is downloaded locally. Verify size is greater than 0.

---

## Task 1: Go SQL Migrations & Indexes

**Files:**
- Create: `backend/db/migrations/000029_yjs_sync.up.sql`
- Create: `backend/db/migrations/000029_yjs_sync.down.sql`

- [ ] **Step 1: Create the SQL migration files**
Create `backend/db/migrations/000029_yjs_sync.up.sql`:
```sql
CREATE TABLE note_yjs_states (
    note_id UUID PRIMARY KEY REFERENCES notes(id) ON DELETE CASCADE,
    state BYTEA NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE note_yjs_updates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    note_id UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    update_data BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for compaction lookup and room initialization
CREATE INDEX idx_note_yjs_updates_note_created ON note_yjs_updates(note_id, created_at ASC);

CREATE TABLE note_ws_leases (
    note_id UUID PRIMARY KEY REFERENCES notes(id) ON DELETE CASCADE,
    machine_id VARCHAR(100) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL
);
```

Create `backend/db/migrations/000029_yjs_sync.down.sql`:
```sql
DROP TABLE IF EXISTS note_ws_leases;
DROP INDEX IF EXISTS idx_note_yjs_updates_note_created;
DROP TABLE IF EXISTS note_yjs_updates;
DROP TABLE IF EXISTS note_yjs_states;
```

- [ ] **Step 2: Run SQL migration locally**
Run:
```bash
cd backend
migrate -path db/migrations -database "$DATABASE_URL" up
```
Expected output: Migration runs successfully and tables are created.

- [ ] **Step 3: Commit**
```bash
git add backend/db/migrations
git commit -m "feat(db): add Yjs state, updates, and lease tables with index"
```

---

## Task 2: Go Backend Room Leases & Heartbeats

**Files:**
- Create: `backend/internal/sync/lease.go`
- Test: `backend/internal/sync/lease_test.go`

- [ ] **Step 1: Write lease manager interface & implementation**
Create `backend/internal/sync/lease.go` correcting the `GetLeaseMachine` parameter bug and propagating real infrastructure errors:
```go
package sync

import (
	"context"
	"errors"
	"time"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type LeaseManager interface {
	AcquireLease(ctx context.Context, noteID string, machineID string) (bool, error)
	RenewLease(ctx context.Context, noteID string, machineID string) error
	ReleaseLease(ctx context.Context, noteID string, machineID string) error
	GetLeaseMachine(ctx context.Context, noteID string) (string, error)
}

type leaseManager struct {
	pool *pgxpool.Pool
}

func NewLeaseManager(pool *pgxpool.Pool) LeaseManager {
	return &leaseManager{pool: pool}
}

func (m *leaseManager) AcquireLease(ctx context.Context, noteID string, machineID string) (bool, error) {
	query := `
		INSERT INTO note_ws_leases (note_id, machine_id, expires_at)
		VALUES ($1, $2, NOW() + INTERVAL '60 seconds')
		ON CONFLICT (note_id) DO UPDATE
		SET machine_id = EXCLUDED.machine_id, expires_at = NOW() + INTERVAL '60 seconds'
		WHERE note_ws_leases.expires_at < NOW() OR note_ws_leases.machine_id = EXCLUDED.machine_id
		RETURNING true;
	`
	var acquired bool
	err := m.pool.QueryRow(ctx, query, noteID, machineID).Scan(&acquired)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return false, nil // Lease is held by another active machine
		}
		return false, err // Propagate real database errors
	}
	return acquired, nil
}

func (m *leaseManager) RenewLease(ctx context.Context, noteID string, machineID string) error {
	query := `
		UPDATE note_ws_leases
		SET expires_at = NOW() + INTERVAL '60 seconds'
		WHERE note_id = $1 AND machine_id = $2
	`
	_, err := m.pool.Exec(ctx, query, noteID, machineID)
	return err
}

func (m *leaseManager) ReleaseLease(ctx context.Context, noteID string, machineID string) error {
	query := `
		DELETE FROM note_ws_leases
		WHERE note_id = $1 AND machine_id = $2
	`
	_, err := m.pool.Exec(ctx, query, noteID, machineID)
	return err
}

func (m *leaseManager) GetLeaseMachine(ctx context.Context, noteID string) (string, error) {
	query := `
		SELECT machine_id FROM note_ws_leases
		WHERE note_id = $1 AND expires_at > NOW()
	`
	var machineID string
	err := m.pool.QueryRow(ctx, query, noteID).Scan(&machineID)
	return machineID, err
}
```

- [ ] **Step 2: Run lease manager tests**
Create unit tests in `backend/internal/sync/lease_test.go`. Run tests:
```bash
go test -v ./internal/sync/... -run TestLease
```
Expected output: PASS

- [ ] **Step 3: Commit**
```bash
git add backend/internal/sync/lease.go backend/internal/sync/lease_test.go
git commit -m "feat(sync): implement room lease election and renewal with correct query binding"
```

---

## Task 3: Relational Database Projection & Disaster Recovery

**Files:**
- Create: `backend/internal/sync/projection.go`
- Test: `backend/internal/sync/projection_test.go`

- [ ] **Step 1: Write YDoc parser and SQL projector**
Create `backend/internal/sync/projection.go` using `ygo` library to decode `YDoc` state vector/updates and map them back to rows in `note_nodes` and `tasks` in a single transaction.
Include a disaster recovery routine `ReconstructYDocFromNodes` to populate a YDoc from database rows.

- [ ] **Step 2: Write tests for projection**
Verify that changes in YDoc maps map perfectly to inserts, updates, and deletes in the database tables. Run tests:
```bash
go test -v ./internal/sync/... -run TestProjection
```
Expected output: PASS

- [ ] **Step 3: Commit**
```bash
git add backend/internal/sync/projection.go backend/internal/sync/projection_test.go
git commit -m "feat(sync): implement relational DB projection from YDoc to note_nodes and tasks"
```

---

## Task 4: YDoc Durability Service & Merged Write-Buffering

**Files:**
- Create: `backend/internal/sync/ydoc_service.go`
- Test: `backend/internal/sync/ydoc_service_test.go`

- [ ] **Step 1: Write YDoc manager & batching worker**
Create `backend/internal/sync/ydoc_service.go`. The service:
- Accumulates binary updates in a thread-safe room buffer.
- On flushing (every 200-500ms), merges all buffered updates using `ygo` into a single consolidated update blob.
- Opens a transaction, takes a Postgres advisory lock (`pg_advisory_xact_lock(hashtext(noteID), hashtext('nodes'))`), and saves the single consolidated binary update row to `note_yjs_updates`.
```go
package sync

import (
	"context"
	"sync"
	"time"
	"github.com/jackc/pgx/v5/pgxpool"
)

type YDocService struct {
	pool *pgxpool.Pool
	mu   sync.Mutex
	buffers map[string][][]byte
}

func NewYDocService(pool *pgxpool.Pool) *YDocService {
	return &YDocService{
		pool:    pool,
		buffers: make(map[string][][]byte),
	}
}

func (s *YDocService) ApplyNodeMutation(ctx context.Context, noteID string, update []byte) error {
	s.mu.Lock()
	s.buffers[noteID] = append(s.buffers[noteID], update)
	s.mu.Unlock()
	return nil
}

func (s *YDocService) FlushUpdates(ctx context.Context, noteID string) error {
	s.mu.Lock()
	updates := s.buffers[noteID]
	delete(s.buffers, noteID)
	s.mu.Unlock()

	if len(updates) == 0 {
		return nil
	}

	// Use ygo to merge updates into a single byte slice
	mergedUpdate, err := mergeYjsUpdates(updates)
	if err != nil {
		return err
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	// Acquire dual-key Postgres advisory lock (nodes table space)
	_, err = tx.Exec(ctx, "SELECT pg_advisory_xact_lock(hashtext($1), hashtext('nodes'))", noteID)
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx, "INSERT INTO note_yjs_updates (note_id, update_data) VALUES ($1, $2)", noteID, mergedUpdate)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}
```

- [ ] **Step 2: Wire up the Flush Scheduler**
Add a background goroutine loop inside `YDocService` (e.g. `StartFlusher()`) that ticks every 200-500ms, iterates over all non-empty buffers in `s.buffers`, and calls `FlushUpdates(ctx, noteID)`. Wire this up in `main.go`.

- [ ] **Step 3: Run YDoc service unit tests**
Create unit tests in `backend/internal/sync/ydoc_service_test.go`. Run tests:
```bash
go test -v ./internal/sync/... -run TestYDocService
```
Expected output: PASS

- [ ] **Step 4: Commit**
```bash
git add backend/internal/sync/ydoc_service.go backend/internal/sync/ydoc_service_test.go backend/cmd/server/main.go
git commit -m "feat(sync): implement write path merging, advisory locking, and periodic flush scheduler"
```

---

## Task 5: In-Memory Rooms & RoomManager

**Files:**
- Create: `backend/internal/sync/room.go`
- Test: `backend/internal/sync/room_test.go`

- [ ] **Step 1: Write `Room` and `RoomManager` types**
Create `backend/internal/sync/room.go`:
- Houses the active `ygo.Doc` in-memory per active `note_id`.
- Handshakes new client connections: sends Server State Vector (Sync Step 1), receives client updates (Sync Step 2), and answers.
- Lazy Migration: When creating a new Room, if no snapshot exists in `note_yjs_states`, call `ReconstructYDocFromNodes` (from Task 3) to mount the baseline YDoc from Postgres before proceeding.
- Dispatches periodic heartbeats (every 30 seconds) to renew the lease.
- Implements `Room.HandleIncomingUpdate(update []byte, senderConn *websocket.Conn)`: applies the raw update to the in-memory doc, broadcasts the update to all clients excluding `senderConn`, and delegates the raw update to `YDocService.ApplyNodeMutation(noteID, update)` to queue for durable persistence.
- Automatically releases the lease and deletes itself from RoomManager when the count of connected clients drops to 0.
```go
package sync

import (
	"context"
	"sync"
	"time"
	"github.com/gorilla/websocket"
)

type Room struct {
	NoteID    string
	Doc       interface{} // ygo.Doc
	clients   map[*websocket.Conn]bool
	mu        sync.Mutex
	leaseMgr  LeaseManager
	machineID string
	stopHeart chan struct{}
}

type RoomManager struct {
	rooms    map[string]*Room
	mu       sync.Mutex
	leaseMgr LeaseManager
}

func NewRoomManager(leaseMgr LeaseManager) *RoomManager {
	return &RoomManager{
		rooms:    make(map[string]*Room),
		leaseMgr: leaseMgr,
	}
}

// Implement room lookup, creation, client registration, handshake exchange, HandleIncomingUpdate, and teardown
```

- [ ] **Step 2: Write tests for Room and RoomManager**
Create unit tests in `backend/internal/sync/room_test.go` to test isolated handshake and the full integration chain (from receiving an update to invoking `ApplyNodeMutation`). Run tests:
```bash
go test -v ./internal/sync/... -run TestRoom
```
Expected output: PASS

- [ ] **Step 3: Commit**
```bash
git add backend/internal/sync/room.go backend/internal/sync/room_test.go
git commit -m "feat(sync): implement in-memory room manager and handshake protocol"
```

---

## Task 5.5: YDoc Compaction Job

**Files:**
- Create: `backend/internal/sync/compactor.go`
- Test: `backend/internal/sync/compactor_test.go`

- [ ] **Step 1: Write compactor task**
Create `backend/internal/sync/compactor.go` to compact a note's state after 10 minutes of inactivity OR when `note_yjs_updates` holds > 1,000 updates:
- Locks note ID via `pg_advisory_xact_lock(hashtext(noteID), hashtext('nodes'))`.
- Merges updates into snapshot `note_yjs_states`.
- Deletes compacted logs older than 30 days.

- [ ] **Step 2: Wire up Compaction Scheduler in main.go**
Add a background goroutine with `time.Ticker` in `backend/cmd/server/main.go` that runs every 5 minutes to trigger the compactor for all eligible notes.

- [ ] **Step 3: Run tests for Compactor**
Create unit tests verifying compaction. Run:
```bash
go test -v ./internal/sync/... -run TestCompaction
```
Expected: PASS

- [ ] **Step 4: Commit**
```bash
git add backend/internal/sync/compactor.go backend/internal/sync/compactor_test.go backend/cmd/server/main.go
git commit -m "feat(sync): implement YDoc compaction worker with advisory locking, pruning, and periodic scheduler"
```

---

## Task 6: Go WebSocket Handler, Rate Limiting & Permission Revocation

**Files:**
- Create: `backend/internal/sync/ws_handler.go`
- Modify: `backend/cmd/server/main.go`

- [ ] **Step 1: Implement WebSocket handler, rate-limiting, and permission revocation**
Create `backend/internal/sync/ws_handler.go`:
- Obtains or creates the `Room` for the `note_id` using `RoomManager` (from Task 5) immediately upon accepting the connection.
- Caches permissions locally per connection and validates on every message.
- Immediately disconnects users if permission is revoked (receives events via PG Notify `permission_revocation`).
- Filters WebSocket broadcasts to exclude the sender of the mutation (origin check).
- Implements connection-level rate limiting of 50 mutations/second.
- Handles dynamic routing via `fly-replay` headers.

- [ ] **Step 2: Connect WS route in main server**
Modify `backend/cmd/server/main.go` to mount `GET /api/v1/sync/ws/:note_id` WebSocket route.

- [ ] **Step 3: Compile and run check**
Run:
```bash
go build -o /tmp/server ./cmd/server
```
Expected: Compiles cleanly with no errors.

- [ ] **Step 4: Commit**
```bash
git add backend/internal/sync/ws_handler.go backend/cmd/server/main.go
git commit -m "feat(sync): implement WebSocket rooms handler with rate limiting and dynamic election"
```

---

## Task 7: Flutter Yjs Local State Table

**Files:**
- Modify: `lib/core/database/database.dart`
- Modify: `lib/core/database/database.g.dart` (generate)

- [ ] **Step 1: Add `local_yjs_states` table to Drift database schema**
Modify `lib/core/database/database.dart`:
```dart
class LocalYjsStates extends Table {
  TextColumn get noteId => text().references(Notes, #id, onDelete: KeyAction.cascade)();
  BlobColumn get state => blob()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {noteId};
}
```

- [ ] **Step 2: Rebuild database code generation**
Run:
```bash
dart run build_runner build --delete-conflicting-outputs
```
Expected: `database.g.dart` is rebuilt successfully.

- [ ] **Step 3: Commit**
```bash
git add lib/core/database
git commit -m "feat(db): add local_yjs_states table to local database"
```

---

## Task 8: Flutter Yjs Sync Manager

**Files:**
- Create: `lib/core/sync/yjs_sync_manager.dart`
- Test: `test/sync/yjs_sync_manager_test.dart`

- [ ] **Step 1: Write `YjsSyncManager`**
Create `lib/core/sync/yjs_sync_manager.dart` to manage the local `YDoc` instance, serialize it into Drift database on changes, perform structural mapping, and prevent phantom node edits:
- Lazy Migration: Upon opening a note without a local state in `local_yjs_states`, construct the initial `YDoc` locally from the `note_nodes` rows in the Drift DB, and save the binary state to `local_yjs_states` before continuing.
- Phantom node protection:
```dart
// Check if the node ID exists in root nodes YMap before mutating
if (!rootNodesYMap.containsKey(nodeId)) {
  // Discard phantom mutation
  return;
}
```

- [ ] **Step 2: Run client sync unit tests**
Create tests in `test/sync/yjs_sync_manager_test.dart` verifying the mapping logic. Run:
```bash
flutter test test/sync/yjs_sync_manager_test.dart
```
Expected: PASS

- [ ] **Step 3: Commit**
```bash
git add lib/core/sync/yjs_sync_manager.dart test/sync/yjs_sync_manager_test.dart
git commit -m "feat(sync): implement client YjsSyncManager with local state persistence and phantom node defense"
```

---

## Task 9: Flutter WebSocket Client & Handshake

**Files:**
- Create: `lib/core/sync/yjs_websocket_client.dart`
- Modify: `lib/core/sync/sync_service.dart`

- [ ] **Step 1: Implement Flutter WebSocket client**
Create `lib/core/sync/yjs_websocket_client.dart` to connect to `ws://.../ws/:note_id`.
- Performs Yjs sync protocol state vector exchange on connect (sends state vector, applies missing blocks).
- Support idle disconnect: close socket after 5 minutes of no activity.
- Automatic reconnect on next edit event.
- Show "syncing..." indicator in UI state during connection handshakes.

- [ ] **Step 2: Connect WebSocket client to `SyncService`**
Modify `lib/core/sync/sync_service.dart` to trigger Yjs WebSocket sync when notes are active.

- [ ] **Step 3: Commit**
```bash
git add lib/core/sync/yjs_websocket_client.dart lib/core/sync/sync_service.dart
git commit -m "feat(sync): implement WebSocket client with idle timeout and UI sync indicator"
```

---

## Task 10: Multi-User UndoManager Configuration

**Files:**
- Modify: `lib/features/notes/presentation/controllers/note_editor_controller.dart`

- [ ] **Step 1: Add origin filter to client UndoManager**
Modify `lib/features/notes/presentation/controllers/note_editor_controller.dart` (or editor coordinator) where UndoManager is instantiated:
Ensure the `UndoManager` is configured with an origin filter matching only local transactions (e.g., `origin: 'local'`), ensuring peer changes aren't rolled back.

- [ ] **Step 2: Commit**
```bash
git add lib/features/notes/presentation/controllers/note_editor_controller.dart
git commit -m "feat(sync): configure UndoManager to filter out remote transaction origins"
```

---

## Task 11: Refactoring Agent & Recurrence Database Mutations

**Files:**
- Modify: `backend/internal/agent/service.go`
- Modify: `backend/internal/tasks/recurrence.go`

- [ ] **Step 1: Refactor AI Agent write queries to invoke `ApplyNodeMutation`**
Modify the AI agent logic to call `YDocService.ApplyNodeMutation` instead of issuing direct SQL writes (`INSERT/UPDATE`) to `note_nodes`.

- [ ] **Step 2: Refactor Recurrence Engine task generation**
Update `backend/internal/tasks/recurrence.go` to generate UUID tasks deterministically using `sha256(template_id + due_date)` and write updates through the `ApplyNodeMutation` flow.

- [ ] **Step 3: Revoke direct write grants on `note_nodes` table**
Update backend connection setup or migration script to restrict AI Agent database role privileges to `SELECT` only on `note_nodes` to force mutation flow compliance.

- [ ] **Step 4: Commit**
```bash
git add backend/internal/agent/ backend/internal/tasks/
git commit -m "refactor(agent,recurrence): enforce ApplyNodeMutation writes and revoke direct node grants"
```

---

## Task 12: Fuzzer Mitigation Test & Cross-Verification

**Files:**
- Modify: `compatibility_test/dart_runner/bin/fuzzer.dart`
- Modify: `compatibility_test/cases_generator.dart`

- [ ] **Step 1: Add phantom/concurrent delete test case to fuzzer**
Modify `compatibility_test/dart_runner/bin/fuzzer.dart` and `compatibility_test/cases_generator.dart` to execute a test simulating typing into a node while a concurrent delete on the same node is applied from a peer, verifying that no silent errors or memory leaks occur.

- [ ] **Step 2: Run full cross-compatibility validation suite**
Run:
```bash
cd compatibility_test
validate.bat
```
Expected output: All 25 + new cases pass, fuzzer runs 10,000 iterations successfully, and both Go and Dart verify convergence.

- [ ] **Step 3: Commit**
```bash
git add compatibility_test
git commit -m "test(sync): add concurrent delete fuzzer test case and run validation suite"
```
