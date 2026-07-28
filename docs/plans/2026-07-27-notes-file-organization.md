# Notes file organization

## Goal

Group the Notes implementation by the flows that change together. Keep all
existing Dart import paths as temporary compatibility exports in this change.

## Scope

1. Move the editor lifecycle, document, sync, and editor UI files below
   `features/notes/editor/`.
2. Move the catalog, attachments, sharing, and preferences flows to their
   named folders.
3. Keep a one-line export at each old path. This avoids a behavior change and
   permits later migration of callers by feature.
4. Verify the moved implementation with static analysis and focused tests.

## Non-goals

- Do not change runtime behavior, public types, providers, or REST/OT rules.

## Done criteria

- The editor source is under `editor/application`, `editor/document`,
  `editor/sync`, or `editor/presentation`.
- Old paths only export the new path.
- `flutter analyze` and focused editor/session tests pass.

## Validation

- `flutter analyze`: passed after both migration stages.
- Focused editor and session tests: passed (34 passed, 1 skipped).
- Focused catalog, sharing, preferences, and editor tests: passed (46 passed,
  1 skipped).
- Full `flutter test`: did not finish within 63 seconds. It is not a passing
  result and needs a later complete run.
