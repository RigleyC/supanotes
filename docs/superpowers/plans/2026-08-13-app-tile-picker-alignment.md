# AppTile Picker Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the shared `AppTile` with the compact action rows in the emoji picker and restore the selected title/icon color.

**Architecture:** Keep `AppTile` as the single custom row implementation. Use the same 48 px one-line rhythm and 20 px visual icon size as the emoji picker action row, while preserving caller-owned outer padding. Make selected foreground color explicit for the title, leading icon, and default check icon; migrate the picker action row to `AppTile`.

**Tech Stack:** Flutter, Dart, `flutter_test`, `motor`.

## Global Constraints

- Do not reintroduce `ListTile` as the shared tile implementation.
- Keep outer sheet padding in the feature pages; `AppTile` owns row layout and interaction feedback.
- Do not add a dependency or compatibility layer.
- Verify the selected state through rendered widget styles, not only the presence of a check icon.

---

### Task 1: Capture the shared tile contract with regression tests

**Files:**
- Modify: `test/shared/widgets/app_tile_test.dart`
- Modify: `test/features/notes/catalog/presentation/widgets/note_icon_picker_test.dart` only if the picker migration needs an integration assertion

**Interfaces:**
- Consumes: the existing `AppTile` constructor and `AppSpacing.tileHeight`.
- Produces: deterministic assertions for row height, compact icon sizing, and selected foreground color.

- [x] **Step 1: Write the failing tests**

Add focused widget tests that:

1. render a selected `AppTile` with a leading icon and inspect the title `Text.style.color` and leading `IconTheme` color; both must equal `Theme.of(context).colorScheme.primary`;
2. assert the one-line tile height is `48.0` and the supplied leading icon is rendered at `20.0` visual pixels;
3. keep the existing interaction and trailing-action tests unchanged.

- [x] **Step 2: Run the focused tests and verify the expected failure**

Run:

```powershell
rtk flutter test test/shared/widgets/app_tile_test.dart
```

Expected: the new height, icon-size, or selected-color assertion fails against the current 44 px/custom-spacing implementation.

### Task 2: Implement the compact shared tile and picker migration

**Files:**
- Modify: `lib/shared/theme/app_spacing.dart`
- Modify: `lib/shared/widgets/app_tile.dart`
- Modify: `lib/features/notes/catalog/presentation/widgets/note_icon_picker_components.dart`

**Interfaces:**
- Consumes: the failing `AppTile` contract from Task 1.
- Produces: `AppTile` with the picker-compatible compact row contract and `_PickerAction` rendered through it.

- [x] **Step 1: Update the shared sizing tokens**

Change `AppSpacing.tileHeight` from `44.0` to `48.0`, matching Flutter's dense one-line `ListTile` minimum used by the emoji picker.

- [x] **Step 2: Make `AppTile` own the compact visual rules**

Keep the existing press scale and semantics. Set the default leading visual size to `20.0` without changing custom trailing controls. Apply selected `scheme.primary` through the title text style and leading icon theme, and keep the selected check icon in the same color. Preserve disabled colors and caller-provided padding.

- [x] **Step 3: Replace `_PickerAction`'s `ListTile`**

Render `_PickerAction` with `AppTile`, passing zero content padding because `NoteIconPickerRootPage` already supplies the sheet's outer `AppSpacing.lg` inset, a 20 px leading icon, and the existing haptic-wrapped callback.

- [x] **Step 4: Run the focused tests and verify green**

Run:

```powershell
rtk flutter test test/shared/widgets/app_tile_test.dart test/features/notes/catalog/presentation/widgets/note_icon_picker_test.dart
```

Expected: all focused tests pass with no analyzer or layout errors.

### Task 3: Verify affected consumers

**Files:**
- Verify: `lib/features/settings/presentation/settings_screen.dart`
- Verify: `lib/features/tasks/presentation/widgets/task_metadata_sheet.dart`
- Verify: `lib/features/tasks/presentation/widgets/task_metadata_selection_page.dart`
- Verify: `lib/features/tasks/presentation/widgets/task_metadata_date_page.dart`

- [x] **Step 1: Run static analysis**

```powershell
rtk dart analyze lib/shared/widgets/app_tile.dart lib/features/notes/catalog/presentation/widgets/note_icon_picker.dart lib/features/tasks/presentation/widgets lib/features/settings/presentation/settings_screen.dart
```

- [x] **Step 2: Inspect the final diff**

```powershell
rtk proxy git diff --check
rtk proxy git diff --stat
```

Confirm that only the shared sizing/style, picker migration, regression tests, and this plan changed.
