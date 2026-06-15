# Plan 012: Add backend test coverage

> **Executor instructions**: Follow this plan step by step.

## Status
- **Priority**: P3
- **Effort**: L
- **Risk**: LOW
- **Depends on**: none
- **Category**: tests

## Why this matters
Critical modules like `contexts`, `routines`, and `settings` lack `_test.go` files, exposing them to silent regressions.

## Scope
**In scope**: `backend/internal/contexts/*`, `backend/internal/routines/*`

## Steps

### Step 1: Add unit tests
Mock the database layer and write unit tests for the core business logic of these packages.

## Done criteria
- [ ] Minimum test suites created.
- [ ] `plans/README.md` updated.
