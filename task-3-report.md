# Task 3 — backend standalone tasks

## Evidências

- Fix round 2: reminder is metadata-only; changing it no longer increments `scheduleGeneration` or clears completion history. Generic completion patches now validate the resolved recurrence and `hasTime` shape (and reject non-recurring completion history) before merging. Concurrent create/upsert conflicts use `ON CONFLICT DO NOTHING`, reload the owner row and replay the operation response instead of surfacing a duplicate-key error.
- Added regression coverage for reminder history preservation, schedule-shaped completion patches, and concurrent create conflict/replay without PostgreSQL.
- Round 1 fixed idempotent replay to lock the authenticated owner task first and query operations by `(task_id, operation_id)`; the global operation-id index was removed so the contract is task-scoped. Payload hashes are canonicalized across JSON key order.
- Create/upsert/update now persist title, `dueDate`, `hasTime`, recurrence, reminder and completion metadata in one write. A create returns revision 1; schedule changes increment `scheduleGeneration` and clear prior completions.
- Exact mutation kinds are enforced: `create`, `upsert`, `update`, `complete_occurrence`, `reopen_occurrence` and `delete`. Occurrence payloads validate canonical wall-clock/UTC timestamps, respect `hasTime`, merge or remove one completion key, update completion state/timestamp, and reject stale generations or no-ops.
- Bootstrap now uses a read-only `REPEATABLE READ` transaction for the task snapshot and owner watermark.
- The sync feed keeps `scope=notes` as the default and excludes task events for old clients; `scope=all` explicitly returns `task_changed`/`task_deleted` with `taskId`. Invalid scopes return 400.
- Typed SQL, contracts, repository, service and protected Echo handlers remain under the existing JWT group. sqlc was regenerated with v1.31.1 (`go run github.com/sqlc-dev/sqlc/cmd/sqlc@v1.31.1 generate`).
- Fix round 2 validation passed: `go test ./...`, `go vet ./...`, `git diff --check`, and pinned sqlc generation (`go run github.com/sqlc-dev/sqlc/cmd/sqlc@v1.31.1 generate`). The task and feed PostgreSQL integration tests remain discovered but skipped without their configured database URLs.

## Limitações

- PostgreSQL-backed migration/feed integration tests were not exercised: `SUPANOTES_SYNC_TEST_DATABASE_URL` and `SUPANOTES_TASK_MIGRATION_TEST_DATABASE_URL` are unavailable in this environment. The migration and feed SQL still require PostgreSQL validation before rollout.
- `make -C backend sqlc` is unavailable because `make` is not installed on this Windows host; the equivalent pinned sqlc command completed successfully.
- Existing unrelated Flutter changes (`pubspec.lock`, Windows generated plugin files and pre-existing sqlc output changes) were preserved and are not part of this task.
