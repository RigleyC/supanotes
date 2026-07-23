# SupaNotes Context

## Note

A note has no separate user-authored title. The title is derived from the first non-deleted block (by position) in the REST/OT document snapshot whose text is non-empty. The first line is still part of the document, but the display title comes from the first block. `KeepFirstLineAsTitleReaction` enforces H1 styling of the first line in the editor (Apple Notes-style first-line-as-title UX).

## Empty Note

An empty regular note is determined from block content, tasks, attachments, not `title`.

## Document Model

- One REST/OT document snapshot per note, stored in `notes.document` (JSONB) with a `revision` counter.
- Blocks are stored in `blocks` array, each with an immutable UUID `id`, `type`, `text`, and optional metadata (`checked`, `dueDate`, `dueTime`, `recurrence`, `spans`).
- Tasks are blocks with type `task`. They are projected to the relational `tasks` table.
- Task completion events populate `task_completions` derived by document projection.

## Projections

- `tasks` — relational table projected from document snapshot blocks of type `task`.
- `task_completions` — relational table projected from task completion state transitions in document task blocks.

