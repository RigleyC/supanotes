# 0005: Yjs-First Sync Architecture

## Status

Accepted

## Context

The sync system maintained three representations of note content (notes.content markdown, note_nodes relational rows, and Yjs CRDT binary), synchronized bidirectionally between them, and ran two parallel sync pipelines (HTTP push/pull every 30s for relational rows + WebSocket for real-time Yjs updates). This produced a large amount of code for a conceptually simple problem: an offline-capable notes app with collaborative editing — exactly what Yjs was designed to solve.

## Decision

The Yjs document (YDoc) is the single source of truth for note content. One YDoc per note.

**Sync protocol**: WebSocket Yjs sync when online (real-time and reconnection). REST API for simple CRUD entities (contexts, tags, note_links, preferences). The periodic HTTP push/pull sync loop for note content is eliminated.

**Eliminated artifacts**: The `note_nodes` table (both Postgres and SQLite), HTTP sync of note_nodes/tasks/task_completions rows, `ProduceUpdateFromRows`, synchronous `ProjectCanonicalDoc`, dual-write in agent tools.

**Derived data**: `notes.content` (markdown), `tasks` table, `task_completions`, and embeddings are asynchronous read-only projections computed from the YDoc on the server. The agent reads from these projections and writes via Yjs mutations only.

**Tasks**: A task is a document node with extra metadata (dueDate, recurrence, completed) stored in the YDoc node data. The `tasks` table is a projection for dashboard queries. Recurrence logic runs on the client — completing a recurring task immediately resets the node and advances the due date in the YDoc. The server projection derives `task_completions` records from `lastCompletedAt` changes.

## Considered Options

- **Keep dual sync (HTTP relational + WebSocket Yjs)**: Rejected because it required constant bidirectional translation between relational and CRDT models, which was the primary source of complexity.
- **Yjs for notes only, keep HTTP sync for tasks as separate entity**: Rejected because tasks are conceptually document nodes with metadata, not independent entities. Separating them would require the editor to call a separate API for task mutations, breaking the editing flow.

## Consequences

- The editor and sync client only speak Yjs. No separate API calls for note content or task state changes.
- Mutations from outside the editor (agent, dashboard task completion) must load the YDoc, apply the change, and save the update — slightly more expensive than a direct SQL update, but maintains a single source of truth.
- CRUD entities (contexts, tags) use direct REST API calls with a local queue for offline scenarios, not a sync loop.
- Migration from the current architecture requires careful data verification: existing `note_yjs_states` must be complete and correct before `note_nodes` can be dropped.
