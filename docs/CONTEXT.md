# SupaNotes Context

## Note

A note has no separate user-authored title. The title is derived from the first non-deleted `note_nodes` row (by position) whose `data->>'text'` is non-empty. The first line is still part of `content`, but the display title now comes from the node, not from regex on the content string. `KeepFirstLineAsTitleReaction` enforces H1 styling of the first line in the editor (Apple Notes-style first-line-as-title UX).

## Empty Note

An empty regular note is determined from content/tasks/attachments/tags, not `title`.
