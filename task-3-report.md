# Task 3 — backend standalone tasks

## Evidências

- Added typed SQL in `backend/db/queries/tasks.sql` for owner-scoped bootstrap/get/row locking, operation replay, task writes, feed emission and owner watermark.
- Added `internal/tasks` contract, transactional repository, service and protected Echo handlers for bootstrap, owner reads and mutations.
- Mutation writes run under one PostgreSQL transaction: operation lookup/hash validation, owner row lock, task update/create/delete, operation response persistence and `sync_changes` emission are committed together.
- Retries return the stored canonical response; payload hash mismatches are rejected. Stale revision/schedule generation and tombstones map to `SCHEDULE_CHANGED`/`TASK_DELETED`.
- Routes are registered below the existing JWT-protected group.
- sqlc regenerated with sqlc v1.31.1 (`go run github.com/sqlc-dev/sqlc/cmd/sqlc@v1.31.1 generate`).
- Focused tests passed: `go test ./internal/tasks -run 'TestApplyMutation|TestHandler' -v` and existing `go test ./internal/syncfeed -v` (database integration tests skipped because their database environment variables are not configured).

## Limitações

- PostgreSQL-backed migration/integration tests were not exercised: `SUPANOTES_SYNC_TEST_DATABASE_URL` and `SUPANOTES_TASK_MIGRATION_TEST_DATABASE_URL` are unavailable in this environment.
- `go vet ./...` completed successfully in the local backend checkout.
- Existing unrelated Flutter changes (`pubspec.lock` and Windows generated plugin files) were preserved and are not part of this task.
