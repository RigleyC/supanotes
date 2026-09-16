# SupaNotes Context

## Note

A note has no separate user-authored title. The title is derived from the first non-deleted block (by position) in the REST/OT document snapshot whose text is non-empty. The first line is still part of the document, but the display title comes from the first block. `KeepFirstLineAsTitleReaction` enforces H1 styling of the first line in the editor (Apple Notes-style first-line-as-title UX).

## Display Title and Note Icon

The **Display Title** is read-only metadata derived from the document snapshot;
there is no separate title field or title-editing mode. A **Note Icon** is
shared note metadata. It is either a native-color Unicode emoji or a color-
selected icon from the fixed catalog. Owners and editors can change it; the
picker saves the change immediately. View-only collaborators can see it but
cannot change it.

## Empty Note

An empty regular note is determined from block content, tasks, attachments, not `title`.

## Document Model

- One REST/OT document snapshot per note, stored in `notes.document` (JSONB) with a `revision` counter.
- Blocks are stored in the `blocks` array, each with an immutable UUID `id`,
  `type`, delta text, and optional metadata.
- A `TaskNode` is a block with type `task`. Its canonical metadata lives in
  the note document: `isCompleted`, `dueDate`, `hasTime`, `recurrenceRule`,
  `reminder`, and recurring `completions`.
- `dueDate` is the recurrence anchor. Each `TaskNode` completion stores the
  scheduled calendar identity separately from the UTC completion instant.
- An independent `Task` is a root resource, not a document block. Its server
  authority is the backend `tasks` table, its local-first copy is the Drift
  `tasks` table, and its writes go through `TaskRepository` and the task API.
- The backend and local `tasks` tables contain independent `Task`s only. They
  are not projections of `TaskNode`, and neither source is automatically copied
  or converted into the other.
- The old `task_completions` relation and other legacy task rows are retained
  only in migration quarantine/evidence; they are not current runtime sources.
- `TaskNode`s may form a hierarchy within a note: a subtask belongs to one
  parent `TaskNode` and can be completed independently.
- A parent `TaskNode` with subtasks reports partial progress, remains open while
  any subtask is open, and toggling its checkbox completes or reopens its
  subtasks.

## Projections

The note editor, `TaskNode` metadata UI, and note-task notification reader read
the canonical note document and mutate it through REST/OT operations. The
independent-task UI reads the local-first `Task` resource through
`TaskRepository`; its outbox/API syncs that resource separately. The global
Tasks view may combine both read adapters, but it is a non-persisted view and
does not make either source a projection of the other.

