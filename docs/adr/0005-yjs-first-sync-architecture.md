# 0005: Yjs-First Sync Architecture

## Status

Accepted for the note-document migration; the task-projection decision is
historical and superseded.

## Scope note

This ADR preserves the Yjs-first, note-only architecture that was decided
during the earlier migration. The document-source decision remains the
historical context for `TaskNode`s inside notes. The task passages below that
describe the relational `tasks`/`task_completions` tables as projections, or
reject a separate task API, are superseded by the current independent `Task`
resource. They are retained as historical evidence and must not be used as the
current ownership contract. The current contract is documented in
[`CONTEXT.md`](../../CONTEXT.md) and [`lib/features/tasks/README.md`](../../lib/features/tasks/README.md).

## Context

The sync system maintained three representations of note content (notes.content markdown, note_nodes relational rows, and Yjs CRDT binary), synchronized bidirectionally between them, and ran two parallel sync pipelines (HTTP push/pull every 30s for relational rows + WebSocket for real-time Yjs updates). This produced a large amount of code for a conceptually simple problem: an offline-capable notes app with collaborative editing — exactly what Yjs was designed to solve.

## Decision

The Yjs document (YDoc) is the single source of truth for note content. One YDoc per note.

**Sync protocol**: WebSocket Yjs sync when online (real-time and reconnection). REST API for simple CRUD entities (contexts, tags, note_links, preferences). The periodic HTTP push/pull sync loop for note content is eliminated.

**Historical eliminated artifacts**: For the note-only migration, the
`note_nodes` table (both Postgres and SQLite), HTTP sync of
`note_nodes`/legacy task rows, `ProduceUpdateFromRows`, synchronous
`ProjectCanonicalDoc`, and dual-write in agent tools were eliminated. This
does not eliminate the current independent `Task` API or its `tasks` table.

**Historical derived-data decision (superseded for tasks)**: In the note-only
architecture, `notes.content` (markdown), the relational `tasks` table,
`task_completions`, and embeddings were asynchronous read-only projections
computed from the YDoc on the server. The current independent `Task` is stored
and mutated as its own resource through the task API/repository; it is not a
projection of a note document. The old completion relation is migration
quarantine/evidence, not a current source.

**Historical task decision (superseded for independent tasks)**: At the time of
this ADR, a task meant a document node with extra metadata (dueDate,
recurrence, completed) stored in the YDoc node data. The `tasks` table was a
projection for dashboard queries, and the server projection derived
`task_completions` from `lastCompletedAt` changes. Today that model describes
only a `TaskNode`; an independent `Task` has its own server row, local-first
copy, API/repository mutation path, and completion history.

## Considered Options

- **Historical option — keep dual sync (HTTP relational + WebSocket Yjs)**:
  Rejected because it required constant bidirectional translation between
  relational and CRDT models, which was the primary source of complexity.
- **Historical rejected option, now superseded — Yjs for notes only, keep HTTP
  sync for tasks as a separate entity**: Rejected by the note-only architecture
  because tasks were then treated as document nodes. The current product has
  since introduced the independent `Task` resource; its separate API and
  repository are now the intended mutation path for that resource.

## Consequences

- **Historical consequence**: The note-only editor and sync client spoke only
  Yjs, with no separate API calls for note content or task state changes.
- **Current boundary**: Mutations to a `TaskNode` still enter through the note
  document flow. Mutations to an independent `Task` use `TaskRepository` and
  the task API/outbox; they do not load a note YDoc or write a note snapshot.
- CRUD entities (contexts, tags) use direct REST API calls with a local queue for offline scenarios, not a sync loop.
- Migration from the current architecture requires careful data verification: existing `note_yjs_states` must be complete and correct before `note_nodes` can be dropped.
