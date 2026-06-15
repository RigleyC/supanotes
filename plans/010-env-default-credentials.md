# Plan 010: Remove .env from git tracking

> **Executor instructions**: Follow this plan step by step.

## Status
- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security

## Why this matters
`backend/.env` is tracked in Git and contains connection strings and JWT secrets. Developers might accidentally commit real credentials.

## Scope
**In scope**: `.gitignore`

## Steps

### Step 1: Git rm
Run `git rm --cached backend/.env`.
Ensure `backend/.env` is listed in `.gitignore`.

## Done criteria
- [ ] `backend/.env` is no longer tracked.
- [ ] `plans/README.md` updated.
