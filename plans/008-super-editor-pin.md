# Plan 008: Pin super_editor git dependency

> **Executor instructions**: Follow this plan step by step.

## Status
- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dependencies

## Why this matters
`super_editor` points to `ref: main` in `pubspec.yaml`. A bad commit upstream can randomly break the build without us changing any code.

## Scope
**In scope**: `pubspec.yaml`

## Steps

### Step 1: Pin to specific commit
Find the current commit hash from `pubspec.lock` and replace `ref: main` with `ref: <commit-hash>` in `pubspec.yaml` (both the main dep and the override).

## Done criteria
- [ ] `super_editor` uses a stable commit hash.
- [ ] `plans/README.md` updated.
