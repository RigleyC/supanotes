# Task ownership and migration runbook

Status: operational guard for the independent-task rollout. This document
does not authorize production cleanup or a table drop.

## Scope and data ownership

SupaNotes has two task resources:

- A note task is a `TaskNode` inside `notes.document`, the canonical REST/OT
  snapshot. Its text, schedule, recurrence, reminder and completion state are
  changed through note document operations.
- An independent `Task` is a root resource in PostgreSQL `tasks`. The Drift
  `tasks` table is its local-first copy and `pending_task_operations` is its
  durable outbox.

The two resources are not projections of one another. A note task is never
written into the independent `tasks` table, an independent task is never
copied into a note, and no legacy relational row is promoted automatically.
The Tasks tab may combine read adapters locally, but that view is not a third
persisted model.

This runbook covers the safe reuse of the `tasks` table name, retention of
legacy data, local SQLite quarantine, schema rollback guards and feed rollout
compatibility. Historical migration SQL and old exports remain evidence; they
are not runtime fallbacks or sources for current task state.

## Gates before changing PostgreSQL

The following evidence is required in a protected release record before
applying `000055_tasks_v2.up.sql` or proposing physical cleanup:

1. A restorable PostgreSQL custom-format backup and its SHA-256 hash.
2. Complete exports of the pre-migration `tasks` and `task_completions`
   relations, including soft-deleted rows.
3. A restore rehearsal in an isolated database, with note/task row counts
   recorded without putting production at risk.
4. A read-only preflight and classification of every discrepancy as
   corresponding, orphaned, conflicting or not deterministically convertible.
5. A retention owner and explicit sign-off. A non-empty legacy relation is
   retained and quarantined; it is never silently converted into an
   independent `Task`.
6. A rollout record showing that old clients remain on the notes-only feed
   until clients capable of the task feed have completed their bootstrap.

Keep backups, exports, preflight output and audit records outside this
repository, encrypted and access-controlled. Do not put titles, note content,
email addresses, tokens or database URLs in repository files or release
comments.

## 1. Backup and restore rehearsal

Use the production backup procedure and a protected artifact directory outside
the repository:

```sh
pg_dump "$DATABASE_URL" \
  --format=custom \
  --no-owner \
  --file="/secure/task-migration/<release-id>/supanotes.dump"

pg_restore --list \
  "/secure/task-migration/<release-id>/supanotes.dump" \
  > "/secure/task-migration/<release-id>/supanotes.dump.list"

sha256sum \
  "/secure/task-migration/<release-id>/supanotes.dump" \
  "/secure/task-migration/<release-id>/supanotes.dump.list"
```

The backup gate passes only when `pg_restore --list` succeeds and an isolated
restore can read the dump:

```sh
createdb supanotes_task_migration_<release-id>
pg_restore --exit-on-error --no-owner \
  --dbname="supanotes_task_migration_<release-id>" \
  "/secure/task-migration/<release-id>/supanotes.dump"

psql "postgresql://.../supanotes_task_migration_<release-id>" \
  --set=ON_ERROR_STOP=1 \
  --command="SELECT COUNT(*) FROM notes; SELECT to_regclass('public/tasks'); SELECT to_regclass('public/task_completions');"
```

Use an isolated database only for this rehearsal and remove it only under the
normal data-retention procedure. Never restore over production.

## 2. Export and inventory legacy PostgreSQL data

Run this step before `000055_tasks_v2.up.sql`, while the legacy relations still
have their original names. Do not filter `deleted_at`:

```sh
psql "$DATABASE_URL" --set=ON_ERROR_STOP=1 \
  --command="\\copy (SELECT * FROM tasks) TO STDOUT WITH (FORMAT csv, HEADER true)" \
  > "/secure/task-migration/<release-id>/legacy_tasks.csv"

psql "$DATABASE_URL" --set=ON_ERROR_STOP=1 \
  --command="\\copy (SELECT * FROM task_completions) TO STDOUT WITH (FORMAT csv, HEADER true)" \
  > "/secure/task-migration/<release-id>/legacy_task_completions.csv"

sha256sum \
  "/secure/task-migration/<release-id>/legacy_tasks.csv" \
  "/secure/task-migration/<release-id>/legacy_task_completions.csv"
```

Record counts in the same read-only session immediately before migration:

```sh
psql "$DATABASE_URL" --set=ON_ERROR_STOP=1 <<'SQL'
BEGIN READ ONLY;
SELECT COUNT(*) AS legacy_tasks FROM tasks;
SELECT COUNT(*) AS legacy_task_completions FROM task_completions;
SELECT COUNT(*) AS notes FROM notes;
ROLLBACK;
SQL
```

After `000055_tasks_v2.up.sql`, the old relations must be addressed only by
their quarantine names:

- `tasks_legacy_quarantine_v31`;
- `task_completions_legacy_quarantine_v31`.

The new `tasks` table is the independent-task resource and must not be mixed
into the legacy inventory. Quarantine rows remain excluded from services,
queries and feeds. The up migration never promotes or rewrites them.

The checked-in read-only preflight remains useful for classifying old note
metadata and immutable `note_operations` payloads:

```sh
psql "$DATABASE_URL" \
  --set=ON_ERROR_STOP=1 \
  --command="SET SESSION CHARACTERISTICS AS TRANSACTION READ ONLY" \
  --file=backend/db/operations/task_document_migration_preflight.sql \
  > "/secure/task-migration/<release-id>/preflight.txt"

sha256sum "/secure/task-migration/<release-id>/preflight.txt"
```

Any conflict or non-deterministic conversion stops the cutover. Do not resolve
it by selecting a relational value automatically. Historical operation
payloads are immutable audit/rebase evidence and are retained, not rewritten.

## 3. Apply and observe the PostgreSQL schema

`backend/db/migrations/000055_tasks_v2.up.sql` performs an atomic transition:

1. rename the old PostgreSQL relations into versioned quarantine names;
2. create the independent `tasks` and `task_operations` tables;
3. add nullable `sync_changes.task_id` and task event kinds; and
4. retain the old rows outside the runtime task resource.

The independent task row is authorized by `owner_user_id`. Its mutations use
`task_operations` for `(task_id, operation_id)` idempotency, and the server
emits `task_changed`/`task_deleted` events for the owner. No query in
`internal/tasks` reads a `TaskNode` or a quarantine relation.

After rollout, monitor task API validation/conflict errors, task outbox retry
depth, task feed delivery, note sync conflicts and notification scheduling.
Keep note failures distinct from an unavailable independent-task resource.

## 4. SQLite quarantine and local recovery

The Drift schema upgrade from physical version 32 to 33 checks for old local
relations before creating the current independent tables. It renames any
remaining relation rather than dropping it:

- `tasks` → `tasks_legacy_quarantine_v32`;
- `task_completions` → `task_completions_legacy_quarantine_v32`;
- `local_task_completions` → `local_task_completions_legacy_quarantine_v32`.

If a quarantine name already exists, the migrator appends a numeric suffix and
records the final name and row count in `TaskStorageDiagnostic`. Empty remnants
are still quarantined so the migration is auditable. Non-empty remnants block
only the independent-task resource; notes, their effective snapshots and note
outboxes must remain usable.

Do not ask the user to delete the database and do not clear SQLite as a cache
fix. Preserve confirmed note snapshots and every pending note operation. An
operator may export or remove a quarantined local relation only through an
explicit, approved retention procedure after confirming that it is not the
current independent `Task` table.

The old conditional SQLite upgrades that modified legacy task relations are
historical upgrade steps for installations that predate version 33. They are
not permission to use those relations at runtime. The current Drift `tasks`
declaration and `TasksDao` apply only to independent tasks.

## 5. Rollback guard

An application rollback is the default response to an application defect. It
must not rewrite a canonical note snapshot from a relational row and must not
re-enable legacy task readers.

The PostgreSQL down migration is separately guarded and transactional. It must
stop before changing schema when any of these contains data:

- independent `tasks` rows;
- `task_operations` rows; or
- `sync_changes` rows with `task_changed` or `task_deleted`.

Only after all three checks are empty may it remove the independent schema,
remove the task feed column/kinds and restore the quarantined relation names.
If a guard fails, preserve both the independent data and the quarantine, roll
back the application only, and obtain a new migration decision. Never force the
down migration and never delete the legacy export to make the guard pass.

Physical removal of `tasks_legacy_quarantine_v31`,
`task_completions_legacy_quarantine_v31` or their SQLite equivalents is a
separate change requiring a successful restore check, zero active consumers,
retention sign-off and explicit approval. This runbook never authorizes that
removal.

## 6. Compatible feed rollout

The server preserves old-client behavior:

- `/api/v1/sync/changes` defaults to `scope=notes`, returning only note events;
- new clients opt into `scope=all` after their task bootstrap;
- task events carry `task_id` and do not require `note_id`;
- old clients therefore never receive unknown `task_changed` or
  `task_deleted` events and continue using their existing note cursor; and
- `bootstrapVersion = 2` is written only after notes, independent tasks,
  cursor and version are applied in one local transaction.

The first new-client bootstrap reads a stable feed watermark, fetches note and
independent-task snapshots, then commits both locally. A failed fetch or local
commit leaves the version below 2 and retries without irreversibly advancing
the cursor. Events after the bootstrap watermark are then consumed with
`scope=all`.

Do not add an `includeNoteTasks` API parameter. Note tasks already arrive with
the note document; the Tasks tab composes them locally from effective snapshots
and independent local task rows. Turning off the note-task list option affects
the list/history only, not note reminders.

## Historical evidence retained

The release record `task-document-native-2026-08-14` reported 21 notes, 190
document task blocks, 27 removed `recurrence` aliases, 53 normalized all-day
completion keys, 53 preserved completion instants, 72 preserved
`lastCompletedAt` values, and zero rows in the then-legacy PostgreSQL `tasks`
and `task_completions` relations before and after the document backfill.

That result is historical evidence, not a current inventory. Re-run the
read-only count and retention gates before any schema reuse or cleanup. The
document backfill did not use a relational task value to build a snapshot, and
the old `note_operations` history remains immutable.
