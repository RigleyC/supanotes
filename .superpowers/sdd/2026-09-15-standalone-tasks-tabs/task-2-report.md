# Task 2 report — PostgreSQL task schema and legacy quarantine

## Implemented

- `backend/db/migrations/000055_tasks_v2.up.sql`
  - Renames the historical `tasks` and `task_completions` tables to their
    versioned quarantine names before creating the independent-task schema.
  - Creates `tasks` and `task_operations` with owner, tombstone, recurrence,
    completion-history, revision and idempotency fields.
  - Extends `sync_changes` with nullable `task_id` and task event kinds.
  - Keeps the migration atomic with an explicit transaction.
- `backend/db/migrations/000055_tasks_v2.down.sql`
  - Refuses rollback if independent tasks, operation records, or task feed
    events exist.
  - Restores the original feed shape and quarantine table names only after the
    guard passes, in one transaction.
- `backend/internal/tasks/migration_test.go`
  - Contract test for the new columns, operation log columns, quarantine table
    names and feed `task_id` column.
  - Uses the existing `SUPANOTES_SYNC_TEST_DATABASE_URL` integration-test
    convention and skips with an explicit reason when PostgreSQL is absent.

## Round 1 fixes

- `applyMigrations` now treats `migrate.ErrNoChange` as success, matching the
  shared backend migration helper.
- `due_date` is `TIMESTAMP WITHOUT TIME ZONE`, preserving the task's wall-clock
  `dueDate` components alongside `has_time`.
- Added an isolated-database contract covering legacy-row preservation without
  promotion, successful empty down migration restoration, and atomic down
  guards for task rows, operation rows and task feed events.

## Round 2 fixes

- Rollback-guard scenarios now run in a fresh PostgreSQL schema per scenario.
  This intentionally preserves golang-migrate's dirty state after a failed
  down migration and then discards only that isolated schema, instead of
  trying to continue from a dirty migration version.
- The legacy fixture now includes one `task_completions` row. The test checks
  both quarantine counts after up and restored row counts after an empty down.

## Round 3 fixes

- The isolated-schema assertions now filter `information_schema` by
  `table_schema = current_schema()`.
- The down migration checks `task_operations` before `tasks`, so the
  operation-guard scenario is independently observable despite its foreign
  key; the test asserts the guard cause.
- Empty rollback verification now checks restored legacy task title/status and
  completion timestamps/date, including `scheduled_at`.

## Round 4 fixes

- Restored completion assertions now compare the complete UTC timestamp values
  (date, hour, minute and second) and the exact wall-clock due date.

## Validation

Command (from `backend`):

```text
go test ./internal/tasks -run TestTaskMigration -v
```

Result: PASS with both migration tests skipped because
`SUPANOTES_SYNC_TEST_DATABASE_URL` and
`SUPANOTES_TASK_MIGRATION_TEST_DATABASE_URL` are not configured. No PostgreSQL
instance was available in this environment, so the SQL and rollback guards
were not executed against a live database. `git diff --check` also completed
without whitespace errors.

## Limitations

Live verification of empty and non-empty migration paths requires the isolated
PostgreSQL URL above; no production database was accessed or changed.
