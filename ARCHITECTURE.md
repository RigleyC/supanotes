# SupaNotes — REST/OT Architecture

This document describes the canonical REST/OT synchronization architecture in SupaNotes.

---

## Single Source of Truth

The REST/OT canonical document snapshot and OT operation log is the **single source of truth** for all notes and task metadata.
- **Yjs/YDoc**: Legacy CRDT format replaced entirely by REST/OT block operations.
- **SQLite Database (`notes`, `tasks`)**: Purely read-only projections derived deterministically from the canonical REST/OT document snapshot.

---

## Core Modules & Responsibilities

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          NoteSyncSession                                    │
│  (Sole owner of active note sync lifecycle: local edit capture, outbox,   │
│   rebase, remote operation application, flush, and dispose)                 │
└───────────────────────┬─────────────────────────────┬───────────────────────┘
                        │                             │
                        ▼                             ▼
              NoteDocumentCodec                   TaskProjectionEngine
  (Unified node conversion & OT codec)      (Idempotent relational task sync)
                        │                             │
                        ▼                             ▼
                 NoteSyncClient                   Drift SQLite DAO
     (REST/OT remote API & catalog sync)             (tasks table)
```

### 1. `NoteSyncSession` ([note_sync_session.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/domain/note_sync_session.dart))
- Sole owner of the active note editor synchronization session.
- Manages the `NoteOperationAdapter`, whose internal `EditorOperationCapture` holds the **single active listener** attached to SuperEditor `MutableDocument`.
- Captures local edits into `OperationRequest` instances, buffers pending outbox operations, triggers relational document & task projections (`TaskProjectionEngine`), and orchestrates polling/reconciliation.

### 2. `NoteDocumentCodec` ([note_document_codec.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/domain/note_document_codec.dart))
- Consolidated codec responsible for converting SuperEditor `DocumentNode` objects to/from REST/OT JSON blocks and delta operations.
- Handles text attributions (bold, italics, headers, quotes, tasks) and span markers consistently.

### 3. `TaskProjectionEngine` ([task_projection_engine.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/tasks/domain/task_projection_engine.dart))
- Accepts canonical REST/OT document snapshots and projects task blocks into relational SQLite task records (`TasksDao`).
- Guarantees idempotent updates so recurring task due dates and completion history are updated strictly through document projections.

### 4. `NoteSyncClient` ([note_sync_client.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/features/notes/data/note_sync_client.dart))
- Unified facade around `NoteOperationsApiClient` for fetching document snapshots, pushing OT operations, and listing remote catalog notes.
- Guards active notes (`NoteSyncSession.isActive(noteId)`) during background catalog syncs to prevent local edit overwrites.

---

## Verification Criteria

1. **No Duplicate Listeners**: Exactly one listener per open note attached to `MutableDocument`.
2. **Single Operation Capture**: Each local edit emits at most one operation request.
3. **Idempotent Projections**: Relational task tables are strictly derived from document snapshots; direct non-projection mutations are prohibited.
