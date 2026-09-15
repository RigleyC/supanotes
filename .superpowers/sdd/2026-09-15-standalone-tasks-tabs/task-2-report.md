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

## Validation

Command (from `backend`):

```text
go test ./internal/tasks -run TestTaskMigration -v
```

Result: PASS with the test skipped because
`SUPANOTES_SYNC_TEST_DATABASE_URL` is not configured. No PostgreSQL instance
was available in this environment, so the SQL was not executed against a live
database. `git diff --check` also completed without whitespace errors.

## Limitations

The empty-schema contract is covered by the integration test. Live verification
of non-empty legacy-row preservation and the guarded down migration requires an
isolated PostgreSQL database; no production database was accessed or changed.
