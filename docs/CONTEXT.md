# SupaNotes Context

## Note

A note has no separate user-authored title. The title is derived from the first non-deleted node (by position) in the YDoc whose `data->>'text'` is non-empty. The first line is still part of `content`, but the display title now comes from the node, not from regex on the content string. `KeepFirstLineAsTitleReaction` enforces H1 styling of the first line in the editor (Apple Notes-style first-line-as-title UX).

## Empty Note

An empty regular note is determined from content/tasks/attachments/tags, not `title`.

## Document Model

- One YDoc per note, stored as `note_yjs_states` (compacted snapshot) + `note_yjs_updates` (pending incremental updates).
- Nodes are stored in `YMap("nodes")` keyed by immutable UUID. Each value is a JSON string with id, type, position, data, createdAt.
- Position uses fractional indexing (sortable strings between any two positions). Moving a node = rewriting its position string.
- Tasks are nodes with type `task` and metadata (completed, dueDate, recurrence) in `data`. They are projected to the relational `tasks` table.
- `lastCompletedAt` in node data drives the `task_completions` projection. Recurrence is computed on the client (Flutter).

## Projections

- `notes.content` — markdown derived from YDoc nodes sorted by position.
- `tasks` — relational table projected from YDoc nodes of type `task`.
- `task_completions` — relational table projected from `lastCompletedAt` transitions in YDoc task node data.
- Embeddings — triggered when `embedding_status = 'pending'` (set by `UpdateNoteContent`).
