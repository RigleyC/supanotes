# Plan 017: DX Improvements

> **Executor instructions**: Follow this plan step by step.

## Status
- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx

## Why this matters
Onboarding is hard because `README.md` is empty, `.editorconfig` is missing, and tests aren't running in CI.

## Scope
**In scope**: `README.md`, `.editorconfig`, `.github/workflows/*.yml`

## Steps

### Step 1: Add .editorconfig
Create `.editorconfig` enforcing 2 spaces for `*.dart` and `*.yaml`, and `indent_style = tab` for `*.go`.

### Step 2: Update README
Add setup steps for Docker, `.env`, and `make migrate-up`.

### Step 3: Add `flutter test` to CI
In `android.yml` and `ios-build.yml`, add a step `run: flutter test` after `flutter analyze`.

## Done criteria
- [ ] `.editorconfig` created.
- [ ] `README.md` updated.
- [ ] Actions updated.
