# Yjs-First Sync Architecture

## Problem Statement

SupaNotes maintains three separate representations of the same note content: a markdown string in `notes.content`, relational rows in `note_nodes`, and a Yjs CRDT binary in `note_yjs_states`. These three representations are kept in sync through two parallel pipelines: an HTTP push/pull loop every 30 seconds for relational rows, and a WebSocket connection for real-time Yjs updates. This produces a large amount of code for a conceptually simple problem — an offline-capable notes app with collaborative editing — and creates constant risk of the three representations diverging. The `note_nodes` table is mutated by at least four independent code paths (HTTP Push, agent tools, YDoc projection, and the sync coordinator), each with its own permission checks and error handling. Every new feature that touches note content must be implemented three times across the three representations.

## Solution

Make the Yjs document (YDoc) the single source of truth for note content, with one YDoc per note. Eliminate the `note_nodes` table entirely (both Postgres and SQLite). Eliminate the HTTP push/pull sync loop for note content — WebSocket Yjs sync handles everything (real-time and offline reconnect). Convert `notes.content` (markdown), `tasks`, and `task_completions` into asynchronous read-only projections computed from the YDoc on the server. The agent writes via Yjs mutations only — no dual-write to relational tables. REST API remains for simple CRUD entities only (contexts, tags, note_links, preferences).

## User Stories

1. As a user, I want to edit a note on my phone and see the changes appear instantly on my laptop, so that I can switch devices seamlessly.
2. As a user, I want to edit a note while offline and have my changes sync automatically when I reconnect, so that I never lose work.
3. As a user, I want to collaborate on a note with another user in real time, so that we can work together without sending files back and forth.
4. As a user, I want the note content to be identical across all my devices after sync completes, so that I don't encounter conflicting versions.
5. As a user, I want my note titles to appear correctly in search results and the note list, so that I can find notes quickly.
6. As a user, I want tasks with due dates and recurrence to work correctly even after switching devices, so that my task management is reliable.
7. As a user, I want the agent to be able to append content to my notes, so that I can use AI to help me write.
8. As a user, I want the agent to create new notes from a prompt, so that I can quickly capture ideas.
9. As a user, I want the agent to read my note content accurately, so that it can answer questions about my notes.
10. As a user, I want my notes to be searchable by content, so that I can find information across all my notes.
11. As a user, I want task completion to work offline and sync later, so that I can track my progress anywhere.
12. As a user, I want recurring tasks to reset correctly after completion, so that my recurring workflows are maintained.
13. As a user, I want note contexts and tags to sync via the REST API, so that my organizational structure is consistent.
14. As a user, I want note links to sync via the REST API, so that my knowledge graph is preserved across devices.
15. As a user, I want my user preferences (favorite, archived, hide completed) to sync, so that my view settings are consistent.
16. As a user, I want the sync to happen in the background without blocking my editing, so that the app feels responsive.
17. As a user, I want the app to handle sync conflicts gracefully, so that I don't lose data when two devices edit the same note.
18. As a user, I want the embedding pipeline to update my note embeddings after content changes, so that semantic search stays current.
19. As a user, I want the agent to read task metadata (due dates, recurrence) from my notes, so that it can help me manage my schedule.
20. As a user, I want the dashboard to show accurate task counts, so that I can see my workload at a glance.

## Implementation Decisions

### Single Source of Truth

The YDoc (one per note) is the sole source of truth for all note content and task state. The `note_nodes` table (both Postgres and SQLite) is eliminated. The `notes.content` column becomes an async read-only projection derived from the YDoc.

### Sync Protocol

- **Note content**: WebSocket Yjs sync protocol (real-time when online, reconnect after offline). The periodic HTTP push/pull sync loop for note content is eliminated.
- **CRUD entities** (contexts, tags, note_links, preferences): REST API with a local queue for offline scenarios. These are not part of the YDoc.

### Eliminated Artifacts

- `note_nodes` table (Postgres) — dropped via migration
- `note_nodes` table (SQLite/Drift) — dropped from schema
- HTTP sync of `note_nodes`, `tasks`, `task_completions` rows
- `ProduceUpdateFromRows` function (Go)
- Synchronous `ProjectCanonicalDoc` in the Push path
- Dual-write in agent tools (`AppendToNoteContent` + Yjs)
- `ReconstructYDocFromNodes` function (Go)
- `_reconstructFromLocal` method (Flutter)
- `_projectToNodes` method (Flutter)

### Derived Data (Projections)

- `notes.content` — markdown string derived from YDoc node structure and YText content
- `tasks` table — projection for dashboard queries (task counts, due dates, recurrence)
- `task_completions` — derived from `lastCompletedAt` changes in YDoc node data
- Embeddings — derived from `notes.content` projection by existing embedding worker

### Task Metadata

A task is a document node with extra metadata (dueDate, recurrence, completed) stored in the YDoc node data. The `tasks` table is a projection for dashboard queries only. Recurrence logic runs on the client — completing a recurring task immediately resets the node and advances the due date in the YDoc. The server projection derives `task_completions` records from `lastCompletedAt` changes.

### Agent Integration

- Agent reads note content from `notes.content` projection (read-only)
- Agent writes via Yjs mutations only — no direct SQL writes to `note_nodes` or `notes.content`
- `AddNoteTool`: creates note with empty content, then writes YDoc — projection derives `notes.content`
- `AppendToNoteTool`: writes YDoc update only — projection derives `notes.content`
- `GetNoteTool`: reads from `notes.content` projection (unchanged)

### Backend (Go) Changes

- `sync/service.go` — gutted to remove `note_nodes`/`tasks` from `SyncPayload`, `Pull`, and `Push`
- `sync/projection.go` — refactored to async projection worker (`ProjectNoteContentFromYDoc`)
- `sync/sync_task.go` — deleted (task rows no longer synced via HTTP)
- `agent/tools/notes_tools.go` — dual-write removed, writes via Yjs only
- `notes/service.go` — `AppendToNoteContent` removed
- `db/queries/nodes.sql` — deleted entirely
- `db/queries/notes.sql` — `AppendToNoteContent` removed
- `db/queries/sync.sql` — `GetSyncNoteNodes`, `UpsertNoteNode` removed
- `db/queries/search.sql` — title derivation changed from `note_nodes` to `notes.content`
- `db/queries/ai.sql` — title derivation changed from `note_nodes` to `notes.content`
- New migration: drop `note_nodes` and `tasks` tables

### Flutter (Dart) Changes

- `sync/sync_service.dart` — `note_nodes`/`tasks` removed from push payload and pull processing
- `sync/sync_mapper.dart` — `noteNodeToJson`/`noteNodeFromJson`/`taskToJson`/`taskFromJson` removed
- `sync/yjs_sync_manager.dart` — `_reconstructFromLocal`, `_projectToNodes`, `_mergeOfflineNodeIntoDoc` removed; YDoc loaded only from `local_yjs_states`
- `database/tables/note_nodes.dart` — deleted
- `database/tables/tasks.dart` — `isDirty` removed (projection-only)
- `database/tables/task_completions.dart` — `isDirty` removed (projection-only)
- `features/notes/domain/note_sync_coordinator.dart` — simplified (no relational projection)

### Eventual Consistency

The `notes.content` projection is eventually consistent — there may be a brief window where the markdown content is stale after a YDoc mutation. This is acceptable for search, agent reads, and dashboard queries. The `tasks` table projection is similarly eventually consistent.

## Testing Decisions

- **What makes a good test**: Test external behavior (what the sync produces), not internal implementation details (how the YDoc is merged). Tests should verify that a note edited on one device appears correctly on another, that offline edits merge without data loss, and that the agent reads consistent content.
- **Backend Go tests**: Unit tests for `ProjectNoteContentFromYDoc` (derives correct markdown from YDoc), integration tests for the simplified Push/Pull endpoint (rejects `note_nodes` in payload), WebSocket sync integration tests.
- **Flutter tests**: Widget tests for the note editor (CRDT operations work correctly), integration tests for the sync flow (offline edits persist, reconnect syncs), unit tests for `YjsSyncManager` (loads from `local_yjs_states` only).
- **Prior art**: Existing test files at `test/crdt_validation/crdt_convergence_test.dart` and `test/crdt_validation/crdt_websocket_test.dart` provide the pattern for CRDT convergence and WebSocket sync testing. Backend tests in `backend/internal/sync/` provide patterns for sync service testing.

## Out of Scope

- **WebSocket server changes**: The WebSocket Yjs server already exists and works. No changes needed.
- **Embedding pipeline**: Embeddings are derived from `notes.content` projection — no changes needed to the embedding worker itself.
- **Offline conflict resolution**: The current approach (YDoc merge via CRDT) handles this. No new conflict resolution logic.
- **dart_crdt migration**: This is a separate effort (`2026-07-10-dart-crdt-migration.md`). This spec assumes `dart_crdt` is already in use.
- **Data migration for existing users**: Existing `note_yjs_states` must be complete and correct before `note_nodes` can be dropped. A verification step (not implementation) should confirm this before executing the migration.
- **New collaborative features**: This spec consolidates existing sync, it does not add new collaborative editing features.

## Further Notes

- The `note_yjs_states` and `note_yjs_updates` tables already exist (migration `000029_yjs_sync`). No new tables are needed for Yjs state storage.
- The `tasks` table is kept as a projection (not dropped) because the dashboard needs indexed access to task metadata for counts, filtering, and sorting. Dropping it would require rewriting all dashboard queries to parse YDoc binary.
- Recurrence logic runs entirely on the client. When a recurring task is completed, the client mutates the YDoc directly (reset node, advance dueDate, set lastCompletedAt). The server projection derives `task_completions` from `lastCompletedAt` changes.
- The `notes.content` projection should be triggered by the WebSocket Yjs server after applying an update, not by a polling loop.
- The migration must be applied carefully: verify `note_yjs_states` completeness for all notes before dropping `note_nodes`. A script comparing YDoc node counts against `note_nodes` row counts can validate this.
