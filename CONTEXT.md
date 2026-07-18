# SupaNotes

A personal notes app with offline support, collaborative editing, and proactive AI capabilities.

## Language

**Note**:
A rich text document containing paragraphs, headings, bullets, and tasks. Persisted as a Yjs CRDT document.
_Avoid_: Document, page, entry

**YDoc**:
The Yjs CRDT document instance for a single note. Source of truth for all note content and task state.
_Avoid_: Yjs state, CRDT, document state

**Task**:
A node within a note that has a checkbox and optional metadata (due date with optional time, recurrence). Not an independent entity — it exists only inside a note.
_Avoid_: Todo, action item, checklist item

**Reminder**:
A user-defined rule that specifies when they should receive a notification for a task (e.g., "at task time", "5 mins before", "9AM"). Reminders are relative to the task's due date.
_Avoid_: Notification rule, alert time

**Task Completion**:
An event record created when a task transitions to completed. Derived by the server projection from YDoc changes, never written directly by the client.
_Avoid_: Completion log, history entry

**Projection**:
Derived relational data (tasks table, notes.content, embeddings) computed asynchronously from a YDoc. Read-only — never written to directly.
_Avoid_: Materialized view, cache, index

**Context**:
A user-defined category that groups notes (e.g., "Work", "Personal"). A note belongs to at most one context.
_Avoid_: Folder, workspace, category

**Vault**:
The entirety of a user's data — all notes, tasks, contexts, and tags.
_Avoid_: Account, workspace, library
