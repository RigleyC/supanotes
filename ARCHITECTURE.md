# SupaNotes — Architecture Guide

> **Last updated:** 2026-07-14
>
> This document describes the current architecture of SupaNotes: how the
> editor, sync engine, AI agent, and projection layer work together, why
> specific decisions were made, and how the pieces fit into a coherent
> whole.

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Data Model & CRDT Strategy](#2-data-model--crdt-strategy)
3. [Editor Architecture](#3-editor-architecture)
4. [Sync Architecture](#4-sync-architecture)
5. [Backend Architecture](#5-backend-architecture)
6. [AI Agent Integration](#6-ai-agent-integration)
7. [Projection Layer](#7-projection-layer)
8. [Conflict Resolution](#8-conflict-resolution)
9. [Package Choices & Modifications](#9-package-choices--modifications)
10. [Offline & Online Paths](#10-offline--online-paths)
11. [Gotchas, Edge Cases & Non-Obvious Behavior](#11-gotchas-edge-cases--non-obvious-behavior)
12. [Future Work (Deferred)](#12-future-work-deferred)

---

## 1. System Overview

SupaNotes is a personal notes application with proactive AI capabilities.
The architecture is split into two main tiers:

- **Flutter frontend** (`lib/`): Rich-text editor, local SQLite (Drift),
  Yjs CRDT documents, WebSocket client, REST sync client, Riverpod state.
- **Go backend** (`backend/`): REST API, WebSocket relay, Yjs state
  management, document projection (YDoc → relational), AI agent integration.

The key architectural insight: **the Yjs document (YDoc) is the single source
of truth for note content and task state.** Relational tables (`notes`,
`tasks`, `task_completions`) are read-only projections derived from the
YDoc. Edits flow YDoc → SQLite (local) / YDoc → WebSocket → Server → YDoc → PostgreSQL (server)
→ projection → relational tables.

```
┌──────────────────────────────────────────────────────────────────┐
│                         Flutter Client                           │
│                                                                   │
│  ┌──────────┐    ┌────────────────┐    ┌───────────────────┐     │
│  │ super_editor│──▶│YjsDocEditorBridge│──▶│ YjsSyncManager   │     │
│  │ (Document) │◀──│ (mediador)     │◀──│ (YDoc cache/     │     │
│  └──────────┘    └────────────────┘    │  DB persistence)  │     │
│       │                                └───────┬───────────┘     │
│  ┌────▼────────────┐                          │                  │
│  │ NodeSyncManager │    ┌──────────────────────▼──────┐          │
│  │ (dirty tracking)│    │  YjsWebSocketClient         │          │
│  │ (local flush)   │    │  (WS Yjs sync protocol)    │          │
│  └─────────────────┘    └──────────┬──────────────────┘          │
│                                    │                              │
│  ┌─────────────────────────────┐   │                              │
│  │ SyncService                 │   │                              │
│  │ (REST push/pull + WS)      │   │                              │
│  └─────────────────────────────┘   │                              │
└────────────────────────────────────┼──────────────────────────────┘
                                     │
     ═════════════════════════════════╪══════════════════════════════
                                     │
┌────────────────────────────────────┼──────────────────────────────┐
│                         Go Server                                │
│                                 │                                 │
│  ┌─────────────┐    ┌──────────▼──────────┐    ┌──────────────┐  │
│  │  ws_handler  │◀──▶│   RoomManager      │    │ YDocService  │  │
│  │  (WS relay)  │    │   (rooms per note) │───▶│ (in-memory   │  │
│  └─────────────┘    │   (broadcast)       │    │  YDoc cache) │  │
│                     └─────────────────────┘    └──────┬───────┘  │
│                                                        │          │
│  ┌──────────────────────────────────────────────────┐  │          │
│  │ ProjectNoteContentFromYDoc                       │◀─┘          │
│  │ (YDoc → notes.content, tasks, task_completions)  │             │
│  └──────────────────────────┬───────────────────────┘             │
│                             │                                     │
│                     ┌───────▼────────┐                            │
│                     │  PostgreSQL    │                            │
│                     │  (relational)  │                            │
│                     └────────────────┘                            │
└──────────────────────────────────────────────────────────────────┘
```

---

## 2. Data Model & CRDT Strategy

### 2.1 Why Yjs (CRDT) Instead of Plain SQLite/PostgreSQL

We chose Yjs (via `dart_crdt` on the client, `github.com/reearth/ygo/crdt`
on the server) because:

1. **Offline-first editing:** Users can edit anywhere, anytime. CRDTs merge
   concurrent edits deterministically without a central conflict resolver.
2. **Real-time collaboration (future):** Same CRDT that enables offline edits
   also enables multi-device/multi-user sync over WebSocket.
3. **No operational transforms:** Unlike OT (Operational Transformation),
   CRDTs don't require a central ordering server. Every peer can merge
   changes independently and converge to the same state.
4. **Position stability:** Node positions use Fractional Indexing (strings),
   not array indices. Inserting a node doesn't change the position of
   existing nodes, so concurrent inserts don't conflict.

### 2.2 YDoc Schema (Flat Keys & Composite Properties)

Each note is a Yjs document (`YDoc`) with this structure:

```
YDoc
├── YMap("nodes")        
│    ├── { nodeId → JSON{ id, type, position, parentId, data{...}, createdAt } }
│    │       where `data` NO LONGER contains task fields.
│    ├── { nodeId:completed → boolean }
│    ├── { nodeId:dueDate → string }
│    └── { nodeId:recurrence → string }
└── YText("content/<id>")  per node, holds the text content
```

**Why composite keys instead of nested YMaps or JSON strings?** The `dart_crdt` library
(which wraps `lib0`/`y-crdt` internals for Dart) does not fully support
nested `Y.Map` instances. Previously, task fields were serialized as a giant JSON
string, which caused "last-writer-wins" collisions at the task level. By migrating
to flat composite keys (`$nodeId:completed`), we regain true field-level CRDT 
merging semantics. Each property can be updated independently by different clients
without overwriting each other.

### 2.3 Task State Migration (P4)

Originally, task fields (`completed`, `dueDate`, `recurrence`,
`lastCompletedAt`) were stored **inline** in the node's `data` map:

```json
{ "id": "abc", "type": "task", "data": { "text": "Buy milk", "completed": true, "dueDate": "2026-07-15" } }
```

This was migrated to a **flat keys schema** where `YMap("nodes")` holds
task metadata under composite keys and node `data` only keeps `text`/`indent`:

```json
// YMap("nodes") entries
"abc" -> { "id": "abc", "type": "task", "data": { "text": "Buy milk" } }
"abc:completed" -> true
"abc:dueDate" -> "2026-07-15"
```

**Why migrate?** Moving task metadata out of the JSON string blob ensures
granular merging in the CRDT (toggling a task's completed status doesn't
overwrite a concurrent dueDate edit). The server projection and client widget 
read from these composite keys for task state.

**Migration strategy:** Both Flutter and Go previously maintained a dual-write 
compatibility layer, but that transition is complete. The YDoc is now the single
source of truth for task metadata, and SQLite relies purely on the projection.

### 2.4 Two Representations: YDoc Nodes vs. Markdown Content

The system maintains **two representations** of the same note:

| Representation | Format | Storage | Purpose |
|---------------|--------|---------|---------|
| YDoc nodes | Structured (typed blocks: paragraph, task, list, image, etc.) | PostgreSQL `note_yjs_states`, local SQLite `local_yjs_states` | Editing, sync, CRDT merge, real-time collaboration |
| Markdown content | Plain text (rendered from nodes) | PostgreSQL `notes.content` | Full-text search, AI agent context, REST API list views, legacy consumers |

**Why do both exist?** The YDoc nodes are the source of truth — they
preserve rich structure (task state, indentation, block types, positions).
Markdown is a projection of those nodes for consumers that don't need
the full structure. This is a deliberate trade-off: YDoc is optimized
for editing and sync, markdown is optimized for search and summarization.

**Why not just use YDoc for everything?** Because:

1. **Full-text search:** PostgreSQL can index and search `notes.content`
   with `tsvector`/`tsquery`. Querying inside Yjs binary state would
   require extracting and indexing text from every node, which is much
   more expensive.
2. **AI agent context:** The agent receives note content as markdown
   (plain text). It doesn't need to know about positions, indentation
   levels, or CRDT internals. Markdown is the simplest representation
   for the LLM to consume.
3. **Legacy API:** Existing REST endpoints return `notes.content` as a
   string. Changing all consumers to decode Yjs state would be a large
   migration with no clear benefit.

**Where do nodes appear in the flows?**

| Flow | Nodes used? | Markdown used? | Why |
|------|-------------|----------------|-----|
| User editing | ✅ YMap("nodes") | — | Editor reads/writes nodes via bridge |
| WS sync | ✅ Binary Yjs update | — | Yjs sync protocol operates on nodes |
| REST push/pull | ✅ As `note_yjs_states` | ✅ `notes.content` | Both representations are synced |
| Note list screen | — | ✅ `notes.content` | Preview text, no editor needed |
| Full-text search | — | ✅ `notes.content` | PostgreSQL `tsvector` index |
| AI agent reads | — | ✅ `notes.content` | Markdown is token-efficient context |
| AI agent writes | ✅ Builds YDoc nodes | — | Agent goes through YDoc for correctness |
| Task dashboard | — | Reads from `tasks` SQL (projection) | Projection has already flattened task state |

**The projection bridge:** `ProjectNoteContentFromYDoc` on the server
and `YjsSyncManager.projectNodes()` on the client are the bridge between
the two representations. They take YDoc nodes and derive:
- `notes.content` (markdown) → for search + list views + agent context
- `tasks` (relational rows) → for the task dashboard SQL query
- `task_completions` (history rows) → for completion tracking

Without the projection, any code that reads `notes.content` or queries
`tasks` would need to decode and parse Yjs binary state — which is what
the projection does in a centralized, debounced way.

---

## 3. Editor Architecture

### 3.1 Stack

| Layer | Library | Purpose |
|-------|---------|---------|
| Editor widget | `super_editor` | Rich text editing, document model, undo |
| Document model | `super_editor`'s `MutableDocument` | In-memory node tree |
| CRDT bridge | `YjsDocEditorBridge` | Mediates YDoc ↔ `MutableDocument` sync |
| Dirty tracking | `NodeSyncManager` | Tracks locally-modified nodes |
| Coordinator | `NoteSyncCoordinator` | Wraps `NodeSyncManager` + applies remote changes |
| CRDT engine | `dart_crdt` | Yjs-compatible CRDT implementation |

### 3.2 Editing Flow (Local)

```
User types → super_editor emits DocumentNode change
→ NodeSyncManager marks node as locally dirty
→ Flush debounce fires → NodeSyncManager serializes dirty ops
→ YjsDocEditorBridge.onLocalFlush():
    1. Sets _isFlushingLocal=true (re-entrancy guard)
    2. Applies ops to YDoc via doc.transact()
    3. Encodes YDoc state → byte[] update
    4. Calls _sendUpdate(update) → WS or REST
    5. Sets _isFlushingLocal=false
```

**Why the re-entrancy guard (`_isFlushingLocal`)?** Without it, applying
ops to the YDoc inside `transact()` would fire YMap observers, which
would try to re-apply the same changes to `MutableDocument`, causing an
infinite loop. The guard skips YMap observation during our own mutations.

### 3.3 Remote Change Reception

```
WS message received → YjsWebSocketClient._handleMessage()
→ applyUpdate(YDoc, message)
→ YMap("nodes") observer fires → YjsDocEditorBridge._onNodesChanged()
→ Either incremental (≤5 keys) or full rebuild
→ Coordinator.updateNodesIncrementally()
→ suspendSync() (prevent local dirty tracking)
→ Apply changes to MutableDocument via Editor.execute()
→ resumeSync()
```

**Why the threshold of 5?** When a small number of keys change, it's
cheaper to read only those keys and apply minimal edits. When many keys
change (e.g., initial sync, full doc reload), reading all nodes and doing
a full comparison is faster than N individual lookups. The threshold of 5
was empirically chosen.

### 3.4 NodeSyncManager — Dirty Tracking

`NodeSyncManager` is the local-change oracle. It:

- Intercepts `DocumentNode` changes via `MutableDocument` listener
- Maintains `locallyDirtyNodeIds` — set of node IDs changed since last ack
- Serializes ops on flush (InsertOp, DeleteOp, UpdateOp, MoveOp)
- Serializes node data to JSON via `nodeData(DocumentNode) → String`
- `suspendSync()` / `resumeSync()` pair suppresses dirty tracking during
  remote change application (preventing local overwrites of remote data)

**Why not just rely on YDoc observation for everything?** Because the
editor uses `MutableDocument` (super_editor's format), not YDoc directly.
NodeSyncManager bridges the gap by tracking which local changes haven't
been reflected to the YDoc yet, and serializing them on demand.

### 3.5 Task Completion Flow

```
User taps checkbox → CustomTaskComponent → setComplete()
→ Editor.execute([ChangeTaskCompletionRequest])
→ TaskNode.isComplete changes → NodeSyncManager marks node dirty
→ (For recurring tasks) TasksDao.completeTask() → calculates next dueDate
→ onRecurringTaskComplete() → YjsDocEditorBridge.completeRecurringTask()
    → doc.transact():
        1. Sets completed=false, dueDate=next, lastCompletedAt=now
           using composite keys ($nodeId:completed) in YMap("nodes")
        2. Encodes update → sends via WS/REST
```

**Dual-Write eliminated:** Previously, during the P4 migration transition, 
both the JSON `data` and dedicated `YMap("tasks")` were written for backwards 
compatibility. This technical debt has been removed. The UI writes ONLY to 
the YDoc via `NoteEditorController.updateTaskMetadataInYDoc`. The projection 
handles SQLite automatically, ensuring no silent task dual-writes occur.

### 3.6 Note Creation Flow

When a user creates a new note, the following happens:

```
User taps "New Note" → notes list screen
1. Backend creates note row in PostgreSQL (notes table, empty)
2. Backend creates empty note_yjs_states row (no YDoc state yet)
3. Response returns note ID

User taps on the new note → editor screen opens
4. Flutter creates local note row in SQLite (Drift)
5. YjsSyncManager.loadDoc(noteId) → no state in DB → new empty Doc()
6. YjsDocEditorBridge is constructed:
    a. Observes YMap("nodes") and YMap("tasks")
    b. Calls _onNodesChanged(null) → note has no nodes
    c. Editor shows a single empty paragraph (super_editor default)
7. YjsWebSocketClient connects to WS for this note:
    a. sends SyncStep1 (empty vector)
    b. receives SyncStep2 from server (empty — no state)
    c. handshakeDone = true

User types content
8. After the first local flush (debounced), YDoc state now has:
    - YMap("nodes") with one entry
    - YText("content/<id>") with the text
9. encodeStateAsUpdate(doc) → byte[] update
10. _sendUpdate(update) → WS to server
11. Server: ApplyNodeMutation → buffer → debounced projection
12. Projection creates notes.content (markdown) from the node
13. Periodic YjsSyncManager.persist() saves state to local SQLite
```

**Why create the note as empty and populate later?** The note exists as
a relational row first so it appears in lists, can be shared, and has
an ID. The YDoc state grows organically as the user edits. There's no
benefit in pre-populating the YDoc with empty state — the first edit
creates it naturally.

### 3.7 Editing Lifecycle (Step by Step)

When the user types a single character:

```
1. super_editor captures keystroke → updates MutableDocument
   → DocumentNode.text changes (e.g., "h" → "he")

2. NodeSyncManager's listener fires:
   → marks node.id as locally dirty in _locallyDirtyNodeIds
   → this prevents remote updates from overwriting this node
     until the change is flushed to the YDoc

3. Debounce timer (NodeSyncManager._flushTimer) resets
   → waits for idle (no more keystrokes)

4. On timer fire: _onFlushNeeded()
   → collects all dirty nodes since last flush
   → serializes each as NodeOperation (UpdateOp, InsertOp, etc.)
   → calls onFlush(ops) → bridge.onLocalFlush

5. Bridge.onLocalFlush(ops):
   a. Sets _isFlushingLocal = true (prevents recursive observation)
   b. doc.transact():
      - Reads current YMap("nodes") entry for the changed node
      - Updates node data (text, position, etc.) via _serializeNode
      - Also writes to YText("content/<id>") via _updateYTextIncrementally
      - For task nodes: also writes to YMap("tasks")
   c. encodeStateAsUpdate(doc)
   d. _sendUpdate(update) → WS (or REST if WS unavailable)
   e. Sets _isFlushingLocal = false

6. WS sends update bytes to server

7. NodeSyncManager clears dirty flags for flushed nodes
   → remote updates for these nodes will now be accepted again
```

**Why the debounce?** Serializing and sending every keystroke would be
wasteful. The debounce batches contiguous edits into a single YDoc
mutation and network send. The debounce is short (tens of milliseconds)
so the UI feels responsive while sending efficient batch updates.

---

## 4. Sync Architecture

SupaNotes uses two independent sync channels because no single channel
satisfies all requirements: real-time collaboration, offline resilience,
metadata sync, and initial load. The two paths complement each other.

### 4.1 Two Paths: WebSocket + REST

| Feature | WebSocket | REST |
|---------|-----------|------|
| Protocol | Yjs sync protocol (Step1/Step2) | HTTP POST/GET |
| Real-time | Yes (immediate broadcast) | No (poll/push frequency) |
| Offline | Disconnected | Push pending updates on reconnect |
| Payload | Binary Yjs updates | JSON (notes, tags, prefs, Yjs states) |
| Auth | Token in query string | Bearer header |
| Scope | Per-note (currently open note only) | Global (all user data) |

**Why two paths?**

| Requirement | Solved by | Why not the other? |
|-------------|-----------|-------------------|
| Real-time collab while editing | WS | REST is poll-based — no live broadcast |
| Offline edits reach server | REST | WS is disconnected offline |
| Metadata sync (contexts, tags, prefs) | REST | No editor edits these — no need for WS |
| Initial data load on login | REST | WS is per-note; 100 notes would need 100 WS |
| Note list preview updates | REST (`notes.content`) | WS only covers the open note |
| Task dashboard completion | REST + Projection | Tasks are derived from YDoc, not synced directly |

### 4.2 Sync Decision Tree

When an edit happens, the client decides how to send it:

```
Edit happens → YDoc mutated → update encoded

Is WS connected for this note?
  │
  ├── YES → send update via WS immediately
  │         → server applies + broadcasts + projects
  │
  └── NO  → mark note as "has pending Yjs state"
            → debounced persist(YDoc) to local SQLite
            → on next periodic push: include note_yjs_states
              → server applies (skips if WS room active)
```

Concretely:

- **Note A is open in the editor:** WS is connected. Every `_sendUpdate`
  goes through WS. Server broadcasts to other clients in real-time. REST
  push for note A includes `note_yjs_states` but the server skips it
  (WS room is active).
- **Note B was edited 2 hours ago and closed:** No WS for note B. The
  YDoc state was persisted locally. On next REST push (periodic or
  manual), the dirty state is sent as `note_yjs_states`. Server applies
  it (no WS room for note B, so the REST path is canonical).
- **Note C was created offline:** Same as B — YDoc state accumulates
  locally, pushed via REST on reconnect, server applies and projects.

### 4.3 WebSocket Protocol

The WS channel implements the Yjs sync protocol (binary, not JSON). This
is the same protocol used by y-websocket, y-sync, and the Yjs ecosystem.

**Message types:**

| Type | Direction | Content | Purpose |
|------|-----------|---------|---------|
| SyncStep1 (0) | Client → Server | Client state vector | "Here's what I have" |
| SyncStep2 (1) | Server → Client | Missing updates | "Here's what you need" |
| Update (2) | Bidirectional | Incremental changes | "Here's what changed" |

**Handshake flow:**

```
Client opens WS → server creates/joins Room for noteId
→ Server sends SyncStep1 (server state vector) to client
→ Client receives Server SyncStep1, sends SyncStep2 (updates server needs)
→ Client sends SyncStep1 (client state vector) to server
→ Server receives Client SyncStep1, sends SyncStep2 (updates client needs)
→ Both sides converge to the same state
→ Both sides: handshakeDone = true
→ Client sends Update on every local mutation
→ Server broadcasts Update to all other clients in room
```

Step by step:

1. **Connection:** Client opens a WS to `ws://host/ws?noteId=X&token=Y`.
   Server validates the token and resolves the note ID.
2. **Bidirectional SyncStep1:** 
   - Server serializes its state vector and immediately pushes it to the client.
   - Client replies with a SyncStep2 to bring the server up to date.
   - Simultaneously, Client sends its own SyncStep1.
3. **SyncStep2:** Server computes the diff between the client's vector
   and the server's canonical state. Server sends them as a single SyncStep2 message.
   This bidirectional handshake avoids silent data loss if one peer falls behind.
4. **Handshake complete:** Both sides set `handshakeDone=true`. From now
   on, only incremental `Update` messages are exchanged.
5. **Updates:** Every local mutation is encoded as a binary Yjs update
   and sent. The server applies it to its YDoc, broadcasts to other
   room members, buffers for DB flush, and triggers debounced projection.
6. **Keep-alive:** Server pings every 30s. Client has 60s idle timeout.
   If no message received in 60s, client reconnects.
7. **Reconnect:** On disconnect, client waits 500ms then reconnects.
   The handshake repeats (SyncStep1/SyncStep2) to catch up on missed
   updates.

**Why relay instead of direct P2P?** The Go server relays Yjs updates
between clients sharing the same note room. This avoids NAT traversal
issues, provides access control, and persists updates to the database.
The server mutates its own in-memory YDoc and broadcasts the update.

**What happens on the server when a WS update arrives?**

```
WS message received → ws_handler.handleMessage()
→ message is a Yjs binary update
→ YDocService.ApplyNodeMutation(noteId, update):
    1. Acquire per-doc mutex lock
    2. DocFor(noteId) → load YDoc (cache or DB)
    3. crdt.ApplyUpdateV1(doc, update, "remote")
    4. Append update to in-memory buffer
    5. Broadcast to other room clients: go BroadcastIfActive(noteId, update)
    6. RunDebouncedProjection(noteId) → async
    7. Release lock
→ WS handler sends acknowledgment if needed
```

### 4.5 REST Push/Pull

The REST channel syncs everything that the WS channel doesn't cover:
metadata (contexts, tags, prefs), Yjs states for closed notes, and the
initial data load on login.

**Push (client → server, POST):**

Called periodically (every 30s) and on explicit sync triggers (reconnect,
note saved). The client collects all locally modified data and sends:

```json
{
  "notes": [
    { "id": "uuid", "content": "", "embedding_status": "pending", ... }
    // content is empty — derived from YDoc projection on server
  ],
  "contexts": [{ "id": "uuid", "slug": "work", "name": "Work" }],
  "tags": [{ "id": "uuid", "name": "important" }],
  "note_tags": [{ "note_id": "uuid", "tag_id": "uuid" }],
  "note_links": [{ "id": "uuid", "source_id": "uuid", "target_id": "uuid" }],
  "user_note_preferences": [{ "note_id": "uuid", "hide_completed": true }],
  "note_yjs_states": [
    { "note_id": "...", "state": "<base64 state>", "updated_at": "..." }
  ]
}
```

The client sends `note_yjs_states` for any note whose local YDoc state
has changed since the last ack (`updatedAt > lastSyncedAt`). The state
is base64-encoded because Yjs state is binary.

**Server Push processing:**

```
→ Auth + permission check (canEditNote per note)
→ Upsert notes, contexts, tags, note_tags, note_links in transaction
→ Upsert user_note_preferences
→ For each note_yjs_state:
    1. Parse note UUID + base64 decode state
    2. Permission check for this note
    3. Check: is there an active WS room for this note?
       YES → skip (WS is canonical, don't apply stale state)
       NO  → YDocService.ApplyNodeMutation(ctx, noteId, state)
             → applies to in-memory YDoc
             → buffers for DB flush
             → broadcasts to room (none — no WS)
             → triggers debounced projection
             → FlushUpdates to persist merged state to note_yjs_updates
    4. If no YDocService (legacy path), upsert note_yjs_states directly
→ Commit transaction
```

**Pull (server → client, GET):**

Invoked on login or periodic sync. Query params:
- `last_synced_at` (ISO 8601) — only return records updated after this
- `limit` (default 100) — pagination

Returns the same `SyncPayload` shape as Push, filtered:
- Notes, contexts, tags, prefs modified since `lastSyncedAt`
- `note_yjs_states` joined with notes table, filtered by user ownership
  and sharing, ordered by `updated_at ASC`

**Pull client-side processing:**

```
Client receives SyncPayload → sync_service.dart
→ For each entity type (notes, contexts, tags, ...):
    1. Upsert into local Drift SQLite
→ For each note_yjs_state:
    1. Base64 decode state
    2. Upsert into local_yjs_states Drift table
    3. evictDoc(noteId) — remove from YjsSyncManager in-memory cache
→ Next loadDoc(noteId) will re-read from updated local_yjs_states
```

**Why evict instead of merge (pull)?** The pulled state from the server
is the canonical merged state. Evicting forces reload from the updated
local DB snapshot, which is simpler and safer than trying to merge
delta-updates on the client. The next WS connect will re-sync from the
canonical state. This is safe because:
- The server always has the authoritative merged state
- Any in-flight local changes are tracked by NodeSyncManager dirty flags
  and will be re-applied after the evicted doc is reloaded
- The WS handshake (SyncStep1/SyncStep2) will catch up if needed

### 4.6 SyncService — The Client Orchestrator

`SyncService` on the Flutter side manages both sync paths:

| Role | Detail |
|------|--------|
| Push timer | Every 30s, collect dirty data + send POST |
| Pull on login | Full sync on app start |
| Pull on reconnect | Incremental sync after WS reconnect |
| WS lifecycle | Connect/disconnect per active note |
| Debounce guard | Prevents concurrent push/pull overlap |
| Dirty tracking | `isDirty` flag per entity type |

**Key design choice:** Push sends `note_yjs_states` even when WS is
active. The server silently skips them. This is simpler than trying to
selectively exclude them — the server-side check is the authority.

### 4.7 Offline YDoc Sync (P2)

When a note is edited offline and never re-opened (no WS connection for it):

1. YDoc state is persisted locally to `local_yjs_states` via Drift
   (`YjsSyncManager.persist()`)
2. On next push (`SyncService.push()`), dirty `local_yjs_states` entries
   are collected (by `updatedAt > lastSyncedAt`) and sent as base64
3. Server checks: if the note has an active WS room → skip (WS is
   canonical). Otherwise, apply via `YDocService.ApplyNodeMutation()`
   and flush to DB

**Why skip when WS room is active?** The WS path is real-time and
canonical. If a note has a live WS connection, the server already has
the latest state. Applying a potentially stale REST push could revert
recent changes. The client will receive real-time updates via WS instead.

---

## 5. Backend Architecture

### 5.1 YDocService — In-Memory YDoc Cache

`YDocService` is the core of the backend sync engine. It:

- **Caches** YDoc instances per note ID in memory (`docs map[string]*crdt.Doc`)
- **Applies** mutations via `ApplyNodeMutation()` and `ApplyNodeMutationLocked()`
- **Buffers** updates in memory (`buffers map[string][][]byte`)
- **Flushes** buffered updates to PostgreSQL (`note_yjs_updates` table)
- **Broadcasts** to active WebSocket rooms after each mutation
- **Projects** the YDoc state to relational tables (via `projectionRunner`)
- **Locks** per-doc mutex for concurrent access safety
- **Tracks** failure count for exponential backoff / alerting

Key flow:

```
ApplyNodeMutation(noteID, update):
  1. acquire per-doc lock
  2. DocFor() → load from cache or DB
  3. crdt.ApplyUpdateV1(doc, update)
  4. append update to in-memory buffer
  5. trigger debounced projection (async)
  6. go s.roomMgr.BroadcastIfActive(noteID, update)
  7. release lock

FlushUpdates(noteID):
  1. swap buffer → local variable
  2. merge buffered updates
  3. DB transaction: advisory lock → insert → commit
  4. on failure: append back to buffer + increment failure count
```

**Why advisory lock on flush?** Prevents concurrent flushes for the same
note from different server instances (horizontal scaling future). The
advisory lock is per-note-ID, so different notes flush independently.

**Why goroutine for broadcast?** Broadcasting to WebSocket connections
can block if a client is slow. Putting broadcast in a goroutine ensures
the YDoc lock is released immediately, preventing head-of-line blocking
for other mutations.

### 5.2 RoomManager — WebSocket Rooms

- Each note has a `Room` (created on first WS connect)
- Room tracks connected clients, leases, heartbeats
- `BroadcastIfActive(noteID, update)` sends framed Yjs update to all
  clients in the room (except the sender)
- `HasActiveRoom(noteID)` is used by REST Push to skip stale offline
  state application

### 5.3 Compactor

The compactor periodically merges pendings updates (`note_yjs_updates`)
into the snapshot (`note_yjs_states`):

1. Load current snapshot + all pending updates
2. Merge via `crdt.MergeUpdatesV1()`
3. Replace snapshot with merged state
4. Delete processed pending updates
5. This prevents unbounded growth of the `note_yjs_updates` table

### 5.4 Handler Layer

Go handlers are thin — they parse requests, delegate to services, format
responses. All business logic lives in service or sync packages.

---

## 6. AI Agent Integration

### 6.1 Agent Architecture

The AI agent runs as part of the Go backend (`internal/agent/`). It:

1. Receives requests via REST API
2. Maintains conversation context
3. Selects tools to execute (add notes, append content, complete tasks)
4. Executes tools via YDoc mutations
5. Returns structured responses

### 6.2 AppendToNoteTool — How It Works

When the agent appends content to a note:

1. **Permissions check:** Verify the agent owns the note
2. **Load YDoc:** `YDocService.WithDoc(noteID, ...)` loads the YDoc
3. **Find max position:** Scans `YMap("nodes")` for the highest position
   string (Fractional Indexing ensures lexicographic ordering)
4. **Generate positions:** `GenerateKeyBetween(maxPosition, "")` produces
   a position after the last node; chain subsequent nodes
5. **Build new nodes:** Each new paragraph/image node is serialized to
   YMap("nodes") + YText("content/<id>")
6. **Apply + Broadcast:** `ApplyNodeMutation()` applies to in-memory YDoc
   and broadcasts to active WS rooms via goroutine
7. **Project:** `RunDebouncedProjection()` updates relational tables

**Why not just write directly to SQL?** Because the YDoc is the source of
truth. Writing directly to SQL would be overwritten by the next projection.
Going through YDoc ensures consistency, broadcasts to live clients, and
properly integrates with CRDT merge semantics.

### 6.3 Agent Mutations Broadcast

Before P0.4 fix, agent mutations were not broadcast to WebSocket clients.
Now, `ApplyNodeMutationLocked()` calls
`go s.roomMgr.BroadcastIfActive(noteID, update)` after every mutation,
so live clients see agent edits in real-time.

---

## 7. Projection Layer

### 7.1 What Is Projection?

Projection is the process of deriving relational data from the YDoc.
It converts CRDT state back to SQL tables for querying, search, and
legacy API compatibility. The projection is the bridge between the
two representations described in §2.4: YDoc nodes → markdown + tasks.

The projection runs:

- **On the server** after every YDoc mutation (debounced)
- **On the client** as `YjsSyncManager.projectNodes()` for local SQLite
  projection

### 7.2 ProjectNoteContentFromYDoc (Server)

The server projection function has three phases:

1. **Load YDoc state** — fetch snapshot + pending updates from PostgreSQL,
   reconstruct `crdt.Doc`
2. **Derive projections**:
   - `deriveMarkdownFromDoc()` — iterates nodes sorted by position,
     generates markdown content for `notes.content`
   - `deriveTasksFromDoc()` — reads `YMap("tasks")` (with fallback to
     node `data`), returns task list sorted by position
3. **Persist to SQL** (within a single transaction):
   - `UpdateNoteContent` — writes content + sets `embedding_status='pending'`
   - `GetTasksByNoteID` — reads existing tasks (for transition detection)
   - `DeleteTasksByNoteID` — removes orphaned tasks (in DB but not in YDoc)
   - `UpsertTask` — inserts/updates each task
   - `UpsertTaskCompletion` — inserts completion record when
     `CompletedAt` transitions from nil → value (deterministic UUID v5
     from task_id + timestamp for idempotency)

**Why a single transaction?** Consistency. If the projection crashes
mid-way, partial writes should roll back. The YDoc is always the source
of truth — the projection can be safely retried.

**Why delete orphans?** If a user deletes a task node from the document,
the YDoc no longer has it. Without orphan deletion, the task would remain
in the `tasks` table forever (ghost task). `task_completions` are NOT
deleted (historical record).

### 7.3 Client-Side Projection

`YjsSyncManager.projectNodes()` projects `YMap("nodes")` to the local
SQLite `tasks` table:

- Reads nodes from YMap, filtering for `type == "task"`
- Reads `YMap("tasks")` entry for each task node
- Resolves `completed` from both sources (YMap("tasks") preferred)
- Upserts to SQLite via `InsertMode.insertOrReplace`
- Deletes orphaned tasks

---

## 8. Conflict Resolution

### 8.1 How CRDTs Resolve Concurrent Edits

Yjs uses a state-based CRDT (specifically, YATA algorithm) with these
properties:

- **Commutative:** Applying updates in any order produces the same final
  state
- **Idempotent:** Applying the same update twice is a no-op
- **Associative:** Merges can be batched

For text: inserts are positioned relative to a unique client ID +
timestamp. Concurrent inserts at the same position merge deterministically
(client with lower ID inserts first lexicographically).

For maps (`YMap("nodes")`, `YMap("tasks")`): last-writer-wins per key.
Concurrent sets to the same key converge to one value (deterministic
based on clock + client ID).

### 8.2 Position Conflicts

Node positions use Fractional Indexing (strings like `"a0"`, `"a1"`,
`"a0b"`). When two peers insert at the same position:

- Peer A generates `GenerateKeyBetween(prev, next)` → `"a0b"`
- Peer B generates `GenerateKeyBetween(prev, next)` → `"a0c"`
- Both inserts appear in the document, sorted lexicographically

This is superior to array-index-based ordering where concurrent insertions
at the same index create conflicts.

### 8.3 Task State Conflicts

If two devices toggle the same task concurrently:

- Both write to `YMap("tasks")` entry with different `completed` values
- Yjs resolves via last-writer-wins (deterministic)
- The projection only inserts `task_completions` on nil→value transition
  (tracked per entry by comparing old vs new `CompletedAt`)

---

## 9. Package Choices & Modifications

### 9.1 super_editor

**Why:** It is the most mature rich-text editor for Flutter with a
proper `Document` model, structured nodes (paragraph, task, list,
image, horizontal rule), and extensible component builders.

**Modifications / custom components:**
- `CustomTaskComponentBuilder` — wraps super_editor's task support with
  recurring task logic, metadata badges (due date, recurrence), exit
  animation, and Yjs-based completion persistence
- `ResolveTaskTextStyle` — custom text styling for completed tasks
  (strikethrough)

### 9.2 dart_crdt (Flutter) / ygo/crdt (Go)

**Why:** These packages implement the Yjs CRDT protocol, providing
cross-platform compatibility. The Go package is the server-side
equivalent of the Flutter `dart_crdt` package.

**Why not use a different CRDT library?** Yjs is the most widely adopted
CRDT for text editing. Using compatible implementations (dart_crdt for
Dart, ygo/crdt for Go) ensures the binary update format is compatible
between client and server, making the WebSocket relay possible.

**Known limitation:** `dart_crdt` does not support nested `Y.Map` as
children of another `Y.Map`. This is why task state is stored as JSON
strings within `YMap("tasks")` rather than nested YMap objects.

### 9.3 Riverpod (State Management)

**Why Riverpod 3.x over alternatives:**
- Provider of choice for Flutter (better than BLoC for this use case)
- Manual provider declaration (no codegen) — avoids build_runner latency
  and generated-file conflicts
- `AsyncValue.when()` pattern enforces exhaustive loading/data/error
  handling (no missing states)
- `.autoDispose` by default prevents memory leaks

**Why NOT codegen (`@riverpod`)?** The team found codegen adds friction
(build_runner rebuilds, generated files in git, IDE lag). Manual providers
are explicit, searchable, and don't require code generation.

### 9.4 Drift (Local SQLite)

**Why Drift:** Type-safe SQLite access with Dart. Query verification at
compile time, auto-migration support, reactive queries (`.watch()`).

**Why not raw SQLite / sqflite?** Drift catches SQL errors at build time,
provides type-safe row models, and integrates with Riverpod via
`.watch()` streams.

### 9.5 sqlc (Go SQL)

**Why sqlc:** Generates type-safe Go code from SQL queries. Eliminates
runtime SQL errors, provides compile-time query verification, and
generates clean Go structs.

**Why not GORM / Ent?** sqlc is unopinionated about your database schema
— you write SQL, it generates Go. This is preferred for a project with
complex queries and existing schema migrations.

### 9.6 Fractional Indexing

**Flutter:** `fractional_indexing_dart` (Greenspan algorithm)
**Go:** `roci.dev/fracdex` (same algorithm)

**Why:** Both implement the standard fractional indexing algorithm by
David Greenspan (used by Google's AppEngine and Replicache). Strings
are lexicographically orderable and never collide. This is the same
algorithm used by the editor for node positioning.

### 9.7 pgx (PostgreSQL Driver)

**Why pgx v5:** The most performant PostgreSQL driver for Go, with
native support for `pgtype`, connection pooling, and advisory locks.

---

## 10. Offline & Online Paths

All paths operate primarily on YDoc nodes (§2.4). The markdown projection
(`notes.content`) is only derived asynchronously via the projection layer
(§7). This means even in offline mode, edits are stored as structured
nodes in the local YDoc — markdown is never edited directly.

### 10.1 Online (WS Connected)

```
Edit → NodeSyncManager dirty → flush → YDoc nodes mutate → WS send
→ Server: ApplyNodeMutation → broadcast YDoc update → rest of clients
→ Server: debounced ProjectNoteContentFromYDoc → markdown + tasks
→ Other clients: WS receive → applyUpdate(YDoc) → observer → rebuild widget
```

### 10.2 Online but Note Not Open (No WS)

```
Edit offline → YDoc persisted to local_yjs_states via Drift
→ Reconnect → SyncService.push() sends note_yjs_states
→ Server: skip if WS room active, else ApplyNodeMutation + flush
→ Pull: client evicts doc, next loadDoc() picks up merged state
```

### 10.3 Offline

```
All edits go to local YDoc → persisted to local_yjs_states
NodeSyncManager tracks dirty nodes locally
On reconnect: push pending states via REST
WS connects for active note → real-time sync resumes
```

---

## 11. Gotchas, Edge Cases & Non-Obvious Behavior

### 11.1 Yjs Updates Are Idempotent — Double-Sending Is Safe

Yjs state-based CRDT means applying the same update twice is a no-op
(the second apply sees all clocks are already at or past the update).
This is critical because:

- WS and REST may both carry the same update (edge case: WS sends an
  update, then the periodic REST push includes the same state for that
  note). On the server, the WS path applied it; the REST path skips it
  because the WS room is active.
- On reconnect, SyncStep2 may include updates the client already has
  locally. Applying them again is harmless.
- The server's `ApplyNodeMutation` buffers updates and later flushes
  them. If a flush fails and retries, partial updates are re-applied.

### 11.2 Empty Content in Push Is Intentional

In REST push, notes are sent with `"content": ""`:

```go
Content: "", // Derived by projection (ProjectNoteContentFromYDoc)
```

This is intentional. Content is derived from the YDoc on the server via
projection. If the client sent content, the server would project it
anyway, potentially overwriting the client value. The content field is
kept in the payload only for schema compatibility.

### 11.3 Local YDoc Cache Corruption Recovery

If `local_yjs_states` in Drift becomes corrupted (e.g., app crash during
persist), `YjsSyncManager.loadDoc()` will catch the error:

```dart
try {
  applyUpdate(doc, stateRow.state);
} catch (e) {
  // Delete corrupted snapshot from DB
  await _db.delete(...).go();
  // Return empty doc; next pull or WS sync will repopulate
  return Doc();
}
```

The corrupted row is deleted and an empty YDoc is returned. The next WS
connect (SyncStep1/SyncStep2) or REST pull will repopulate the state
from the server. No data loss — the server always has the canonical
state.

### 11.4 Concurrent Offline Edits — Two Devices, Same Note

If Device A and Device B both edit the same note offline:

1. Both persist their YDoc states locally
2. On reconnect, both push their `note_yjs_states` via REST
3. Server applies A's state first → YDoc now has A's changes
4. Server applies B's state → CRDT merge combines A + B changes
   - Concurrent text edits merge via Yjs YATA algorithm
   - Concurrent position assignments merge via Fractional Indexing
   - Concurrent task toggles resolve via last-writer-wins (deterministic)
5. Both clients pull the merged state → both converge to same result

This works because the server serializes mutations through
`ApplyNodeMutation` (per-doc mutex). The second apply sees the state
from the first and merges deterministically.

### 11.5 Deterministic UUID for Task Completions

Task completions use a deterministic UUID v5 derived from
`task_id + completed_at`:

```go
completionUUID := uuid.NewSHA1(uuid.NameSpaceURL,
  []byte(taskID.String() + completedAt.Format(time.RFC3339Nano)))
```

This prevents duplicate completion records when the projection re-runs
(on every YDoc mutation). Without this, reprojecting the same YDoc would
insert a new `task_completions` row every time — inflating completion
counts. The `ON CONFLICT (id) DO NOTHING` in the SQL query guarantees
idempotency.

### 11.6 Soft Deletes vs. YDoc Persistence

Notes use soft deletes (`deleted_at` in PostgreSQL). When a note is
"deleted":

1. `notes.deleted_at` is set to now
2. The note disappears from lists and searches
3. The YDoc state (`note_yjs_states`, `note_yjs_updates`) is NOT deleted
4. If the note is restored (deleted_at → null), the YDoc is intact

This means YDoc state persists even for deleted notes. There is
currently no garbage collection for YDoc state of permanently deleted
notes — a future compactor could clean these up.

### 11.7 createdAt Is num (Milliseconds Since Epoch), Not String

In `YMap("nodes")` entries, `createdAt` is stored as a `num` (milliseconds
since epoch), not an ISO 8601 string. This was a bug fix — originally it
was stored as a string, which caused type mismatches between Dart and Go
deserialization. The `_readCreatedAt` helper in the bridge handles both
formats for backwards compatibility:

```dart
num? _readCreatedAt(dynamic raw) {
  final meta = jsonDecode(raw) as Map<String, dynamic>;
  return meta['createdAt'] as num?;  // works for both int and double
}
```

### 11.8 NodeSyncManager Dirty Retry on Flush Failure

When `NodeSyncManager.onFlush(ops)` is called and the flush fails (e.g.,
network error), the dirty node IDs are NOT cleared. They remain in
`_locallyDirtyNodeIds` and will be included in the next flush. This
provides automatic retry:

```
Flush 1 fails → dirty IDs preserved → WS reconnect
→ Flush 2 includes same ops → server applies → success → dirty IDs cleared
```

The downside: if the callback succeeds (no exception) but the data
doesn't actually reach the server (e.g., WS message lost), the dirty
flags ARE cleared. The WS protocol handles this via Yjs sync
acknowledgment — missed updates are caught on reconnect via SyncStep2.

### 11.9 The YMap("tasks") JSON Schema Must Match Across Languages

The task entry in `YMap("tasks")` is written by Dart and read by Go
(and vice versa). The JSON shape must match exactly:

```json
{
  "nodeId": "uuid-string",
  "completed": true,
  "title": "Task text",
  "dueDate": "2026-07-15",
  "recurrence": "daily",
  "lastCompletedAt": "2026-07-14T10:00:00Z"
}
```

If the Dart code adds a field that Go doesn't expect, Go silently ignores
it (JSON unmarshaling is lenient). If Go adds a field that Dart doesn't
read, Dart silently ignores it. **The danger is renaming or removing a
field** — Go would leave it as zero value (e.g., `completed: false`),
effectively resetting the task.

**Therefore:** Any change to the task entry schema must be applied to
both `_buildTaskEntry` (Dart) and `taskDataEntry` / `readTaskFromYMap`
(Go) simultaneously.

### 11.10 Adding Fields to YMap("nodes") Without Updating Projection

The `nodesFromDoc` function in `projection.go` parses node entries with
a hardcoded struct:

```go
var nd struct {
    ID       string          `json:"id"`
    Type     string          `json:"type"`
    Position any             `json:"position"`
    Data     json.RawMessage `json:"data"`
}
```

Adding a new field to the node JSON in the Flutter bridge (e.g., a new
metadata field) will NOT cause a compilation error — Go will simply
ignore the unknown JSON key. **But** if the projection needs to read
that field, it must be added to this struct. Always check both the
serialization side (bridge) and the deserialization side (projection)
when adding fields.

### 11.11 Common Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Writing to `notes.content` directly via SQL | Next projection overwrites it | Write to YDoc instead, let projection derive content |
| Adding a field to `YMap("nodes").data` without updating `yjs_node_codec.dart` | Field silently missing on the other side | Update both `_serializeNode` (write) and `noteNodeFromYDoc` (read) |
| Modifying `migrateLegacyDoc` only in Dart or only in Go | Docs migrated on one platform but not the other | Update both files (they have WARNING comments) |
| Sending task completions via REST Push | Server ignores them (field removed from payload) | Must go through YDoc → projection derives task_completions |
| Directly querying `note_yjs_states.state` | Binary data — not human-readable | Use YDoc reconstruction or projection |
| Forgetting `handshakeDone` before sending updates via WS | Server rejects update (pre-handshake) | `YjsWebSocketClient._handshakeDone` gate blocks sends |
| Concurrent `persist()` calls for same note | Race condition on SQLite write | `_persistLock` serializes persists via `then(_)` chain |

---

## 12. Future Work (Deferred)

### 11.1 P5 — Agent as Operation Executor

Currently, the agent builds YDoc state directly (e.g., `AppendToNoteTool`
creates nodes programmatically). The planned evolution is to define a
vocabulary of declarative operations (`MoveBlock`, `CreateTask`,
`InsertParagraph`, `DeleteBlock`) and have the agent emit these ops
instead of constructing doc state. Each op would be applied atomically
within `doc.Transact()`, broadcast, and projected.

**Why deferred:** The current approach works for the existing tool set.
The operation vocabulary becomes more valuable when the agent supports a
wider range of editing actions. Tracked as plan 060.

### 11.2 P6 — Presence + Notifications

- **Presence:** In-memory room presence (cursor, selection) with broadcast
  to room members. Currently tracked as plan 059.
- **Event-driven notifications:** Event bus on task completion, @mentions,
  etc., dispatched via push/email/Telegram.

**Why deferred:** Presence requires UI work on the Flutter side (cursor
rendering, selection sharing). Notifications depend on an event bus
infrastructure not yet built.

---

## Appendices

### A. Key Files Map

| File | Purpose |
|------|---------|
| `lib/features/notes/domain/yjs_doc_editor_bridge.dart` | Mediates YDoc ↔ super_editor document |
| `lib/features/notes/domain/node_sync_manager.dart` | Local dirty node tracking & serialization |
| `lib/features/notes/domain/note_sync_coordinator.dart` | Remote change application to editor |
| `lib/core/sync/yjs_sync_manager.dart` | YDoc cache, persistence, legacy migration |
| `lib/core/sync/yjs_websocket_client.dart` | WS client (Yjs sync protocol) |
| `lib/core/sync/sync_service.dart` | REST push/pull + WS orchestration |
| `backend/internal/sync/ydoc_service.go` | Server-side YDoc cache + mutations |
| `backend/internal/sync/room.go` | WS room manager + broadcast |
| `backend/internal/sync/service.go` | REST push/pull handler |
| `backend/internal/sync/projection.go` | YDoc → relational projection |
| `backend/internal/sync/ws_handler.go` | WebSocket upgrade + relay |
| `backend/internal/agent/tools/notes_tools.go` | Agent note manipulation tools |
| `lib/features/notes/presentation/widgets/custom_task_component.dart` | Custom task checkbox widget |

### B. Environment Variables

See `backend/.env.example` for all required variables. Key ones:

- `DATABASE_URL` — PostgreSQL connection
- `JWT_SECRET` — Auth token signing
- `OPENAI_API_KEY` — AI agent model access
- `WS_ORIGINS` — Allowed WebSocket origins (comma-separated)

### C. Migration History

| Migration | What Changed |
|-----------|-------------|
| 0000–0023 | Initial schema (note_nodes, notes, tasks, etc.) |
| 0024–0033 | Yjs support (note_yjs_states, note_yjs_updates, drop note_nodes) |
| P4 (2026-07) | Task state moved from node data to YMap("tasks") |
| P4 migration | On-load migration for legacy docs (Go + Dart) |

---

*This document reflects the codebase as of commit `2be0c77` + the
P0–P4 implementation session (2026-07-14). Plans 059 (Presence) and
060 (Agent Ops) are pending.*
