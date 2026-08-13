# Note Editor Insets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the duplicated top gap in the note editor and keep the editor and toolbar correctly visible when the software keyboard opens.

**Architecture:** The `Scaffold` owns the app-bar and keyboard resize boundary. `NoteEditor` will provide only document-internal padding, while Super Editor keeps its built-in selection auto-scroll behavior. The editor toolbar will remain anchored to the resized body instead of applying the keyboard inset a second time.

**Tech Stack:** Flutter, Dart, Super Editor, Flutter widget tests.

## Global Constraints

- Keep REST/OT document editing and session ownership unchanged.
- Do not add a manual scroll controller or a compatibility fallback.
- Preserve unrelated working-tree changes.
- Use shared project widgets and existing test conventions.

### Task 1: Add failing editor layout regression tests

**Files:**
- Test: `test/features/notes/presentation/note_editor_screen_test.dart` or the existing focused editor widget test file after locating the current seam.

- [x] Write a test that builds the editable note editor under a `Scaffold` with an app bar and asserts the first document content does not receive the app-bar height twice.
- [x] Write a test that simulates a non-zero bottom view inset and asserts the editor toolbar remains inside the resized body boundary rather than being offset by the inset twice.
- [x] Run the focused tests and confirm they fail on the current implementation for the intended layout assertions.

### Task 2: Remove duplicated layout insets

**Files:**
- Modify: `lib/features/notes/editor/presentation/widgets/note_editor.dart`
- Modify: `lib/features/notes/editor/presentation/note_editor_screen.dart` only if the regression test shows the `Scaffold` configuration needs an explicit resize setting.

- [x] Remove the app-bar-derived value from `documentPadding.top`; keep only the document's own visual top spacing.
- [x] Keep the default `Scaffold` keyboard resize behavior and remove the extra `viewInsets.bottom` offset from the toolbar position when the body is already resized.
- [x] Preserve the editor's existing bottom document padding so the last content remains above the toolbar.
- [x] Run the focused regression tests and confirm they pass.

### Task 3: Verify the editor change

**Files:**
- Inspect only the files changed in Tasks 1-2.

- [x] Run the focused editor widget tests.
- [x] Run `flutter analyze` through the project command convention.
- [x] Run `git diff --check` and inspect the final diff to confirm no unrelated files changed.
