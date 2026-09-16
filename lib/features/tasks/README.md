# Tasks

A feature has two task sources with the same scheduling semantics:

- `TaskNode` is a task block inside a note. Its canonical state lives in the
  note's REST/OT document snapshot (`notes.document`) and its effective local
  snapshot. The note editor changes it through document operations.
- `Task` is an independent, user-owned task. Its canonical server state lives
  in PostgreSQL `tasks`; the Drift `tasks` table is its local-first copy and
  `pending_task_operations` is its durable outbox.

These sources are intentionally separate. The independent `tasks` table is not
a projection of `TaskNode`, a note task is never written there, and an
independent task is never copied into a note. No migration promotes old
relational task rows or creates a task from a note block automatically.

## Read and mutation boundaries

- `domain/task.dart`: independent-task contract and canonical JSON.
- `domain/note_task_list_reader.dart`: read-only `NoteTask` adapter with
  `noteId` and `blockId` for note tasks.
- `application/task_list_providers.dart`: combines independent tasks with
  note-task adapters for the Tasks tab when **Mostrar tarefas das notas** is
  enabled. The combined `TaskListItem` is a presentation value, not storage.
- `data/task_repository.dart`: local-first independent-task mutations and
  outbox insertion in one transaction.
- `data/task_sync_service.dart` and `core/sync/task_outbox_worker.dart`:
  idempotent API delivery and retry for independent tasks.
- `presentation/`: task list, completion history, editor and navigation back
  to the source note.

## Completion and notifications

The shared occurrence policy applies to both sources. A note-task checkbox
produces a REST/OT block operation. An independent-task checkbox produces a
`TaskRepository` mutation and a sync operation. Completion history remains in
the source: note-document metadata for `TaskNode`, and `lastCompletedAt` /
`completions` in the independent `Task` row.

The notification scheduler reads the effective note snapshot for `TaskNode`s
and the local independent-task stream for `Task`s. Hiding note tasks from the
Tasks tab affects only list/history composition; it does not disable reminders
for note tasks.

## Migration safety

The PostgreSQL migration quarantines legacy `tasks` and `task_completions`
tables as `*_legacy_quarantine_v31` before creating the independent schema.
The Drift upgrade quarantines local `tasks`, `task_completions` and
`local_task_completions` remnants as `*_legacy_quarantine_v32` (with a numeric
suffix if needed). Quarantined rows are retained for export and retention
review, never read as current tasks, and never converted automatically.

If a local quarantine contains rows, the independent-task resource may be
blocked with a diagnostic while notes continue operating. See
[`docs/operations/task-document-migration-runbook.md`](../../../docs/operations/task-document-migration-runbook.md)
for backup, retention, rollback and old-client feed gates.
