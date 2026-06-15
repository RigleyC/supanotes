# Plan 006: Eliminate N+1 queries in inbox

> **Executor instructions**: Follow this plan step by step.
> **Drift check**: `git diff --stat HEAD -- backend/internal/notes/service.go`

## Status
- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: perf

## Why this matters
`ApplyOrganization` iterates through notes one by one, executing a database insert/update per item. This N+1 loop slows down batch inbox organization significantly. It needs to use batching or a single transaction with bulk operations.

## Scope
**In scope**: `backend/internal/notes/service.go`

## Steps

### Step 1: Use a transaction for the entire loop
Ensure the entire `ApplyOrganization` loop is wrapped in a transaction using `db.Begin(ctx)`. Wait, it might already be. If not, add `tx, err := s.db.Begin(ctx)` and use `s.q.WithTx(tx)`.

### Step 2: Use bulk copy or batch inserts
Use `pgx.Batch` to queue up `CreateNote` and `AppendToNoteContent` operations, then send the batch in one round-trip.

## Done criteria
- [ ] DB round-trips are batched.
- [ ] `plans/README.md` updated.
