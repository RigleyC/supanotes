# Notes file organization

## Goal

Group the Notes implementation by the flows that change together. Keep the
legacy paths only until all callers have moved to the real module paths.

## Scope

1. Move the editor lifecycle, document, sync, and editor UI files below
   `features/notes/editor/`.
2. Move the catalog, attachments, sharing, and preferences flows to their
   named folders.
3. Migrate callers to the real module paths, then remove the one-line
   compatibility exports when no references remain.
4. Verify the moved implementation with static analysis and focused tests.

## Non-goals

- Do not change runtime behavior, public types, providers, or REST/OT rules.

## Done criteria

- The editor source is under `editor/application`, `editor/document`,
  `editor/sync`, or `editor/presentation`.
- No legacy `data/`, `domain/`, or `presentation/` compatibility paths remain.
- `flutter analyze` and focused editor/session tests pass.

## Validation

- `flutter analyze`: passed after both migration stages.
- Focused editor and session tests: passed (34 passed, 1 skipped).
- Focused catalog, sharing, preferences, and editor tests: passed (46 passed,
  1 skipped).
- Legacy import migration: passed (61 Dart files updated and 68 compatibility
  exports removed).
- Full `flutter test`: passed (563 passed, 1 skipped).
