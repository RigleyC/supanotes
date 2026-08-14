# Task document migration runbook

Status: executed for release `task-document-native-2026-08-14`. No production
cleanup is authorized by this document.

## Scope

The note document is the canonical source for task text, schedule, recurrence,
completion history, and reminders. The relational `tasks` and
`task_completions` tables are legacy projections. This runbook protects their
data while the application moves to document-native task handling.

The runbook does not restore a relational task model, add a runtime fallback,
or copy a conflicting relational value into a note without an approved
decision.

## Required evidence before cutover

Keep these artifacts outside the repository and record their paths and SHA-256
hashes in the release record:

1. A restorable PostgreSQL custom-format backup.
2. A full export of `tasks`, including soft-deleted rows.
3. A full export of `task_completions`, including rows for soft-deleted tasks.
4. A restore rehearsal result from an isolated database.
5. The output of the read-only preflight SQL.
6. The output of the aggregate task-document metadata inventory, including
   immutable historical operation payloads.
7. A classification of every mismatch as corresponding, orphaned, conflicting,
   or not deterministically convertible.
8. A client-cache cutover record showing that the strict client is released
   only after the server backfill and canonical document reads are complete.

Do not store titles, note content, email addresses, tokens, or database URLs in
the repository or in release comments.

## 1. Create the backup

Use the production backup procedure and a protected artifact directory. The
directory must not be inside the repository.

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

The backup is valid only when `pg_restore --list` succeeds and the backup is
readable by the isolated restore step.

## 2. Export the legacy tables

Export complete tables. Do not add a filter on `deleted_at`.

```sh
psql "$DATABASE_URL" --set=ON_ERROR_STOP=1 \
  --command="\\copy (SELECT * FROM tasks) TO STDOUT WITH (FORMAT csv, HEADER true)" \
  > "/secure/task-migration/<release-id>/tasks.csv"

psql "$DATABASE_URL" --set=ON_ERROR_STOP=1 \
  --command="\\copy (SELECT * FROM task_completions) TO STDOUT WITH (FORMAT csv, HEADER true)" \
  > "/secure/task-migration/<release-id>/task_completions.csv"

sha256sum \
  "/secure/task-migration/<release-id>/tasks.csv" \
  "/secure/task-migration/<release-id>/task_completions.csv"
```

Keep the exports encrypted and access-controlled. They are recovery artifacts,
not application input.

## 3. Restore rehearsal

Restore the backup into a new isolated PostgreSQL database. Never test the
restore over the production database.

```sh
createdb supanotes_task_migration_<release-id>
pg_restore --exit-on-error --no-owner \
  --dbname="supanotes_task_migration_<release-id>" \
  "/secure/task-migration/<release-id>/supanotes.dump"

psql "postgresql://.../supanotes_task_migration_<release-id>" \
  --set=ON_ERROR_STOP=1 \
  --command="SELECT COUNT(*) FROM notes; SELECT COUNT(*) FROM tasks; SELECT COUNT(*) FROM task_completions;"
```

The restore gate passes only when the command succeeds and the inventory is
consistent with the production backup record. Delete the isolated database
only under the normal data-retention procedure.

## 4. Run the read-only preflight

Run the checked-in SQL against the restored database first. Then run it against
production through a read-only connection. The SQL contains no `UPDATE`,
`DELETE`, `DROP`, or automatic reconciliation.

```sh
psql "$DATABASE_URL" \
  --set=ON_ERROR_STOP=1 \
  --command="SET SESSION CHARACTERISTICS AS TRANSACTION READ ONLY" \
  --file=backend/db/operations/task_document_migration_preflight.sql \
  > "/secure/task-migration/<release-id>/preflight.txt"

sha256sum "/secure/task-migration/<release-id>/preflight.txt"
```

Review every result section:

- invalid document envelopes, block IDs/types, duplicate IDs, or Delta
  operations;
- missing document blocks for active relational tasks;
- document task blocks without active relational rows;
- orphan completion rows;
- legacy metadata aliases;
- invalid metadata types;
- non-canonical schedule or completion keys;
- duplicate all-day schedule identities.
- legacy values in historical `note_operations` payloads. These are immutable
  audit/rebase records, not canonical task state. They must be reported and
  retained, but they must not be rewritten as part of the document backfill.

Any row in a conflict or non-deterministic category stops the cutover. Do not
solve it by choosing the relational value automatically.

## 4a. Protect local snapshots during cutover

The client stores both a confirmed document snapshot and an effective snapshot
with pending operations. The strict runtime rejects legacy task aliases and
non-canonical schedule values. Therefore:

- complete the server backfill before releasing the strict client;
- verify that `GET document` and sync responses return only canonical snapshots;
- do not open a stale local snapshot offline and rewrite it from the
  relational projection;
- preserve the confirmed snapshot and every pending outbox operation if a
  stale cache is found; stop that rollout cohort for manual rehydration from a
  canonical server snapshot;
- never clear the local database as a cache “fix”, because that can delete
  unsent task edits.

An offline device with a legacy snapshot is a cutover blocker. It requires an
approved operational refresh path before the strict client can be considered
safe for that cohort. This is a release gate, not a permanent runtime
compatibility reader.

## 5. Normalize canonical documents

After the preflight is empty or every exception has an approved disposition,
run the versioned document backfill in a transaction or in small resumable
batches. The backfill must:

- write `dueDate` and completion `scheduledAt` keys without timezone offsets;
- keep `completedAt` as the actual UTC instant;
- preserve the recurrence anchor day, including January 31 to February 28 to
  March 31 behavior;
- preserve multiple early completions;
- convert only values with a deterministic mapping;
- record the note ID, task ID, old key, new key, and backfill version in the
  protected audit record, not in the repository.

An old timed completion key that contains a timezone offset is not converted by
guessing the current operator timezone. Stop it for manual resolution when the
original schedule timezone cannot be established.

After each batch, re-read the document snapshot and confirm that the expected
block count and completion count did not decrease. A failed batch must be
resumable from the last verified cursor.

For release `task-document-native-2026-08-14`, the protected audit record
contains the note ID, task ID, old key, new key, and backfill version for every
changed document value. The production result was:

- 21 notes and 190 task blocks;
- 27 `recurrence` aliases removed while preserving `recurrenceRule`;
- 53 all-day completion keys changed from the old `03:00:00.000Z` encoding to
  local wall-clock `00:00:00.000` keys;
- 53 completion instants and 72 `lastCompletedAt` values preserved;
- zero invalid canonical values or duplicate normalized schedule identities;
- zero rows in the legacy `tasks` and `task_completions` tables before and
  after the backfill.

The production `note_operations` history contains 116 old `recurrence` fields
and 61 old all-day schedule encodings. The history remains immutable. The
server and client use the canonical document snapshot for current state;
historical operations are returned only for OT rebase and are not replayed as
task metadata.

### 5a. Convert legacy Delta shapes exposed by the strict reader

The strict reader does not contain a compatibility fallback. If a persisted
snapshot contains a missing Delta, a null Delta, or an empty non-content Delta
operation, run the versioned operational conversion in
`backend/db/operations/task_document_canonical_delta_repair.sql`.

The conversion is deliberately narrow:

- a missing or null `delta` becomes an empty array;
- an empty or non-content operation is removed;
- text insert operations and their attributes stay unchanged;
- an embed, unknown insert type, invalid block, or unsupported Delta shape
  aborts the transaction for manual review.

For the 2026-08-14 production repair, three notes and five blocks were
converted. Two missing/null Deltas became empty arrays and three empty
operations were removed. The protected audit file records the affected note
and block IDs. The five repaired blocks returned `delta` arrays with zero
invalid operations after the conversion. No `note_operations` history was
rewritten, and no relational task value was used to build the snapshot.

## 6. Deploy and observe

Deploy the application version only after the backup, restore, export, and
preflight gates pass. During the observation window, monitor:

- note operation validation errors;
- sync conflicts and rebased pending operations;
- materialized effective-document rebuilds;
- task metadata rendering;
- notification scheduling and cancellation;
- requests to removed relational task routes.

The scheduler must read the effective document snapshot, including pending
local operations. It must not read the legacy tables.

The backend deployment for this release completed with the database schema
already current, the database pool ready, and `GET /api/v1/health` returning
`{"status":"ok"}` with HTTP 200. The production observation window must still
watch the signals listed above before any destructive cleanup is proposed.

## 7. Rollback and retention

If the new application has a defect, roll back the application version. Do not
rewrite canonical documents from the relational projection during rollback.
Keep the backup, exports, preflight output, and audit record for the approved
retention period.

Physical removal of `task_completions`, `tasks`, old routes, or generated query
bindings is a separate change. It requires a new approval after the observation
window, a successful restore check, zero active consumers, and a retention
sign-off. This runbook never authorizes a table drop.
