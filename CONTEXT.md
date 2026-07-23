# SupaNotes — Domain Terminology & Concepts

A personal notes app with offline support, real-time REST/OT synchronization, and proactive AI capabilities.

## Domain Vocabulary

**Note**:
A rich text document containing paragraphs, headings, lists, images, and tasks. Persisted as a versioned REST/OT JSON document snapshot (`notes.document`).
_Avoid_: Page, entry, file

**Document Snapshot**:
The canonical versioned JSON snapshot for a single note (`schemaVersion: 1`, array of structured blocks). Single source of truth for all note content and task state.
_Avoid_: YDoc, Yjs state, CRDT, document state

**Block**:
A discrete structural node inside a note document (e.g. `header`, `paragraph`, `listItem`, `task`, `image`, `horizontalRule`). Keyed by an immutable string `id`.
_Avoid_: Element, widget, chunk

**Task**:
A block within a note document with `type: "task"` that has text content, checkbox state (`checked`), and optional task metadata (`dueDate`, `dueTime`, `recurrence`). Not an independent root entity — it exists within a note document.
_Avoid_: Todo, action item, checklist item

**Assignee**:
The single collaborator (user) assigned to a task within a shared note.
_Avoid_: Task owner, delegate, responsible user

**Reminder / Notification**:
A local notification scheduled relative to a task's due date and time.
_Avoid_: Notification rule, alert time

**Task Completion**:
An event record created in `task_completions` when a task transitions to completed. Derived by the relational projection from document snapshot changes, never written directly by custom UI endpoints.
_Avoid_: Completion log, history entry

**Projection**:
Derived relational data (`tasks` table, `task_completions` table) computed deterministically from the canonical REST/OT document snapshot by `TaskProjectionEngine`. Read-only — never written to directly by the UI.
_Avoid_: Materialized view, cache, index

**Vault**:
The entirety of a user's data — all notes, tasks, attachments, and preferences.
_Avoid_: Account, workspace, library

