# SupaNotes Context

## Note

A note has no separate user-authored title. The first non-empty line of `content` is the display title. Persisted `notes.title` is removed in this breaking migration. The first line is still part of `content`.

## Empty Note

An empty regular note is determined from content/tasks/attachments/tags, not `title`.
