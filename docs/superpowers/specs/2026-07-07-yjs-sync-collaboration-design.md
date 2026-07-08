# Design Spec: Yjs Synchronization & Collaboration Engine

**Date**: 2026-07-07  
**Status**: Approved (Refined with Production Operations & Rollback Policies)

---

## 1. Goal & Context

SupaNotes currently uses a REST-based Operational Transformation (OT) delta sync for synchronizing editor note nodes. To support real-time collaborative editing, offline-first reliability, and clean convergence across clients, we are transitioning the synchronization and collaboration engine to **Yjs** using the Go `ygo` (`github.com/reearth/ygo/crdt`) library on the backend and the Dart `yjs_dart` library on the Flutter frontend.

To guarantee safety, before any migration or database schema modification is deployed to production, we will perform a **full database backup** of the current Fly.io PostgreSQL database.

---

## 2. Step 0: Safety Backup of Fly.io Database

To prevent any potential data loss or corruption during the deployment of the new Yjs sync engine, we will perform a physical/logical backup of the production database running on Fly.io before applying any migrations.

### Backup Steps:
1. Connect to the database cluster machine:
   ```bash
   fly ssh console -a backend-winter-waterfall-5807-db
   ```
2. Inside the database machine, dump the database to a temporary file:
   ```bash
   pg_dump -U postgres supanotes -F c -b -v -f /tmp/supanotes_prod_backup_pre_yjs.dump
   ```
3. Exit the console and download the backup dump to the local machine:
   ```bash
   fly ssh sftp get /tmp/supanotes_prod_backup_pre_yjs.dump ./supanotes_prod_backup_pre_yjs.dump -a backend-winter-waterfall-5807-db
   ```
4. Verify the file size and verify that the backup exists locally before executing any migrations.

---

## 3. Data Schema & Yjs Mapping

### Yjs Shared Types Structure
Instead of a `YArray`, we will use a **`YMap` of `YMap`s** as the root container, keyed by the unique node ID (UUID). This acts as an order-independent "bag" of nodes and naturally resolves lazy migration race conditions by utilizing Yjs's key-level Last-Write-Wins (LWW) resolution.

- **Top-Level Shared Type**: A `YMap` named `nodes`.
- **Key**: `id` (String - UUID)
- **Value**: A `YMap` representing a single document block/node:
  - `id` (String - UUID)
  - `type` (String, e.g. `"paragraph"`, `"header"`, `"task"`, `"list_item"`, `"divider"`, `"image"`)
  - `parent_id` (String - UUID or null)
  - `data` (YMap containing node properties):
    - `text`: `YText` (for paragraphs, headers, list items, and tasks). This enables character-level collaborative merging.
    - `position`: String (fractional index position value generated via `fractional_indexing_dart`).
    - Other metadata properties (e.g. `level` for headers, `completed` for tasks, `url` for images) are stored as primitive keys inside the `data` `YMap`.

### Database Mapping & Ordering Rules
- **Ordering**: The rendering order of nodes is determined by the `position` string (fractional index).
- **Tie-breaker**: In the rare event of identical positions, nodes are ordered deterministically by comparing their string `id`s.
- **Single Source of Truth**: The `YDoc` is the **single source of truth**. The `note_nodes` and `tasks` tables in PostgreSQL/SQLite are derivable projections (materialized views) that can be fully reconstructed from the YDoc binary state at any time.

### Mitigation: Phantom Node Edits
When a node is deleted from the root `YMap`, any nested `YText` types inside it become unintegrated. If a peer makes edits to a node's text concurrently while another peer deletes the node, these edits are lost silently, and the text object leaks.
- **Mitigation Rule**: In the client-side `YjsSyncManager` and the server-side `ApplyNodeMutation`, before applying any mutation (e.g., text insert/delete) to a node, we **MUST** verify that the node still exists in the root `YMap` (`nodes.has(nodeId)`). If it does not exist, the mutation is discarded.
- **Fuzzer Integration**: A dedicated case ("edit text while another peer concurrently deletes the parent node") will be added to the compatibility fuzzer suite.

---

## 4. Frontend Architecture (Flutter)

The Flutter application will combine Drift (SQLite) local persistence with `yjs_dart` and WebSockets for real-time sync.

### Key Components
1. **`YjsSyncManager`**: Manages the local `YDoc` instance, binds listeners to it, and applies/intercepts incoming and outgoing changes.
2. **`WebSocketSyncClient`**: Manages a persistent WebSocket connection to the backend. To conserve server resources, the client closes the connection after a period of inactivity (idle) and automatically reconnects on the next local edit.
   - **UI Indicator**: During the reconnect-and-handshake sequence, the UI will display a distinct "syncing..." status indicator to ensure the user is aware of the temporary offline window.
3. **Local YDoc Client Persistence**:
   - To eliminate the 200-500ms data-loss window (e.g., if the server crashes right after sending a broadcast and the client's app is simultaneously killed by the OS), the client **MUST** persist the binary representation of the `YDoc` locally in a dedicated Drift table (e.g., `local_yjs_states`).
   - Every local mutation applied to the `YDoc` is written immediately to this local SQLite table, providing local durability before the server confirms the update.
4. **Multi-User Undo/Redo**:
   - The Flutter `UndoManager` must be configured with an **origin filter** to only capture and undo local transactions. This ensures that undo/redo operations never revert edits made by other collaborators.
5. **Reactive SQLite Projection**: When a remote update is applied to `YDoc`:
   - It computes the changes and writes them back to SQLite's `note_nodes` table.
   - The reactive database streams in `NoteSyncCoordinator` automatically trigger the editor's diff-and-replace mechanism to show changes to the user without interrupting typing focus.

---

## 5. Backend Architecture (Go)

The Go backend handles real-time WS rooms, applies incremental Yjs updates via `ygo`, persists YDocs, and projects YDocs back into the PostgreSQL database.

### Database Updates
We will introduce two tables to manage the YDoc states:
1. `note_yjs_states`: Holds the latest compressed YDoc snapshot (1 row per note).
   ```sql
   CREATE TABLE note_yjs_states (
       note_id UUID PRIMARY KEY REFERENCES notes(id) ON DELETE CASCADE,
       state BYTEA NOT NULL,
       updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
   );
   ```
2. `note_yjs_updates`: An append-only log of binary updates with timestamps, retained for a safety window (e.g. 30-60 days).
   ```sql
   CREATE TABLE note_yjs_updates (
       id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
       note_id UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
       update_data BYTEA NOT NULL,
       created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
   );
   ```

### Server Flow & Scaling
1. **Sticky Routing via Dynamic Election with Heartbeats (Fly.io)**:
   - Since there are 2 production instances running on Fly.io, we will implement **dynamic election**.
   - The first WebSocket connection for a note registers the active server host serving the note in a PostgreSQL database table (acting as a lease with a TTL, e.g., 60 seconds).
   - The active server machine serving the note sends a **periodic heartbeat** (e.g., every 30 seconds) to renew the lease in Postgres.
   - If the active server crashes, heartbeats stop, and the lease naturally expires after 60 seconds, allowing the next connection to route through `fly-replay` to trigger a new election on the other machine.
2. **Permission Checking per Mutation**:
   - Instead of waiting for the 5-minute periodic poll, the server caches the user's permission level in memory per WebSocket connection.
   - Every incoming mutation checks this connection cache (O(1) lookups).
   - Cache entries are invalidated immediately when a user permission change event is broadcast (via Postgres `LISTEN/NOTIFY` or an internal event bus).
3. **Write Path Decoupling**:
   - All database updates to a note's nodes (including AI Agent modifications and automatic recurrence jobs) **must** go through a unified Go function: `service.ApplyNodeMutation(noteID, mutation)`.
   - **Real-Time Path (In-Memory)**:
     1. The server applies the mutation to the active in-memory YDoc room instantly.
     2. The server broadcasts the binary update **immediately** to all other connected WebSocket clients in the room (zero lag).
     3. **Broadcast Filtering**: The broadcast **MUST** exclude the connection that originated the mutation (identified via Yjs transaction origin), preventing redundant echo roundtrips to the sender.
   - **Durability Path (Deferred Batching)**:
     1. The server buffers incoming binary updates in an in-memory queue associated with the room.
     2. Every 200-500ms (or when the buffer hits a size threshold), a background worker pulls the updates from the buffer, opens a database transaction, acquires a dual-key Postgres advisory lock on the note ID (`SELECT pg_advisory_xact_lock(hashtext(note_id), hashtext('nodes'))`), merges the updates, writes the unified binary update to `note_yjs_updates`, and commits the transaction.
   - **Idempotent Recurrence**: Auto-generated tasks created by recurrence jobs must generate their UUID `id` deterministically (e.g., `sha256(template_id + due_date)`). Re-running a failed recurrence job will write to the same key in the `nodes` YMap, ensuring idempotency.
   - **Defense in Depth**: To prevent direct SQL writes to `note_nodes` from bypassing the Yjs synchronization engine, we will revoke `INSERT/UPDATE` privileges on the `note_nodes` table for the AI agent database role. This transforms silent bypass bugs into immediate, test-failing permission errors.
4. **Relational Database Projection**:
   - The Go backend decodes the YDoc, traverses the nodes in the `YMap` sorted by their `position` string, and synchronizes the rows in the `note_nodes` and `tasks` tables (upserting modified/new nodes/tasks, deleting missing nodes/tasks) inside the same database transaction.
   - This triggers the Postgres search and embedding update hooks (`UpdateNotesContentFromNodes`), keeping the relational search, AI agents, and task tables up to date.

---

## 6. Edge Cases & Safety Policies

### Orphans Handling
- If a node's `parent_id` points to a node that does not exist in the current set of nodes, we treat it as a child of the root *for projection and rendering purposes only*. We do **not** write a parent correction back to the YDoc, keeping it clean and avoiding concurrent update cycles.

### Compaction & Tombstone Policy
- Compaction runs when a note is inactive for a given window (e.g. 10 minutes) **OR** if the number of updates in `note_yjs_updates` since the last snapshot exceeds 1,000 (protecting active/hot notes that remain open for long periods).
- It obtains a Postgres transaction advisory lock on the note ID (`SELECT pg_advisory_xact_lock(hashtext(note_id), hashtext('nodes'))`) to prevent race conditions with active writes.
- It consolidates the raw updates from `note_yjs_updates`, updates the `note_yjs_states` snapshot, and prunes logs older than the retention window (30-60 days).

### Fractional Indexing Key Growth
- Due to repetitive adversarial reordering, fractional index position strings may grow long. We will monitor index lengths and, if necessary, perform a periodic background rebalance (redistributing node positions evenly) to keep key sizes small.

### Permission Revocation
- When a user's permission to a note is revoked, the system will immediately close any active WebSocket connections for that user for the given `note_id` (O(1) room lookup). As a safety net, a periodic validation check runs every 5 minutes on active connections.

### Disaster Recovery Pathway
- If a note's `note_yjs_states` and `note_yjs_updates` are ever corrupted or lost, a disaster recovery command/job can be run to **reconstruct a baseline YDoc** directly from the Postgres `note_nodes` and `tasks` tables. While this discards historical Yjs CRDT edit logs, it fully preserves the note's latest user-facing content.

---

## 7. Production Operations, Load Testing & Rollback

### Abuse & Rate Limiting
- To protect against malicious or buggy clients sending too many mutations:
  - Implement a rate limiter per WebSocket connection capped at **50 mutations/second**.
  - If a connection exceeds this limit, it is disconnected immediately, and the client's subsequent reconnect attempts are throttled.

### Telemetry & Observability
We will monitor the health of the synchronization engine using standard metrics:
- `supanotes_active_rooms`: Gauge of concurrent active in-memory YDoc rooms.
- `supanotes_durability_buffer_length`: Gauge of buffered Yjs updates waiting to write to Postgres.
- `supanotes_advisory_lock_latency_ms`: Histograms of wait times to acquire `pg_advisory_xact_lock`.
- `supanotes_compaction_duration_ms`: Histogram of compaction job execution times.
- `supanotes_yjs_updates_growth_per_note`: Gauge tracking the count of uncompressed updates per note.

### Capacity & Load Testing
- Before deployment, we will execute a load-testing harness under `compatibility_test` simulating:
  - **1,000 active concurrent YDocs** to assert heap memory consumption remains below **2MB per active note** (total target memory < 2GB RAM).
  - High concurrency typing profiles (10 users editing a single note concurrently) to measure lock contention and latency.

### Rollout & Rollback Pathway
1. **Gradual Rollout**:
   - Control Yjs sync using a backend feature flag (`SYNC_ENGINE=yjs` or `legacy`).
   - Run the initial rollout targeting a subset of notes (e.g., internal team emails or selected opt-in test users) before general availability.
2. **Zero-Migration Rollback**:
   - Because the Go backend projects YDoc updates back into the relational `note_nodes` and `tasks` tables in real-time, **these tables are always 100% up to date**.
   - If an issue is encountered, the rollout flag can be flipped back to `legacy`. The client will automatically fall back to the HTTP REST pull/push sync operating directly against the existing database tables, with **zero database migration or data translation required** for rollback.

---

## 8. Verification Plan

### Automated Tests
- Run the cross-compatibility test suite to ensure no regressions in binary exchange:
  ```bash
  cd compatibility_test
  validate.bat (on Windows) or ./validate.sh (on Unix)
  ```
- Write Go unit tests in `backend/internal/sync` to check YDoc serialization and projection.
- Write Dart integration tests verifying local SQLite projection from Yjs updates.

### Manual Verification
- Deploy to staging environment.
- Open the same note on two separate devices/browsers.
- Type concurrently and verify real-time merging with no data loss or cursor jumps.
- Disconnect one device, write offline, reconnect, and verify convergence.
- Verify search indexing and embedding extraction still function for edited notes.
