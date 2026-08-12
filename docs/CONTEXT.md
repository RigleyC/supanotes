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
- Blocks are stored in `blocks` array, each with an immutable UUID `id`, `type`, `text`, and optional metadata (`checked`, `dueDate`, `dueTime`, `recurrence`, `spans`).
- Tasks are blocks with type `task`. They are projected to the relational `tasks` table.
- Task completion events populate `task_completions` derived by document projection.
- Tasks may form a hierarchy within a note: a subtask belongs to one parent task and can be completed independently.
- A parent task with subtasks reports partial progress, remains open while any subtask is open, and toggling its checkbox completes or reopens its subtasks.

## Projections

- `tasks` — relational table projected from document snapshot blocks of type `task`.
- `task_completions` — relational table projected from task completion state transitions in document task blocks.

