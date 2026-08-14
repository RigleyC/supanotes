# Progressive Content Fade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a real 48-pixel opacity fade to the top of the notes list and note editor.

**Architecture:** A shared `ProgressiveFade` owns the `ShaderMask` geometry. Screens wrap their content viewport and keep the transparent AppBar outside the mask.

**Tech Stack:** Flutter, Dart, flutter_test

## Global Constraints

- Use `bounds.height` for shader geometry.
- Keep AppBar controls outside the fade.
- Preserve unrelated worktree changes.
- Do not add compatibility paths or new packages.

---

### Task 1: Shared progressive fade

**Files:**
- Create: `lib/shared/widgets/progressive_fade.dart`
- Create: `test/shared/widgets/progressive_fade_test.dart`

**Interfaces:**
- Produces: `ProgressiveFade({required Widget child, double height = 48})`

- [ ] Write a widget test for the destination-in mask, 48-pixel default, and bounds-based curve.
- [ ] Run the focused test and confirm that it fails because `ProgressiveFade` is absent.
- [ ] Implement the minimal bounds-based `ShaderMask`.
- [ ] Run the focused test and confirm that it passes.

### Task 2: Screen integration

**Files:**
- Modify: `lib/features/notes/catalog/presentation/notes_list_screen.dart`
- Modify: `lib/features/notes/editor/presentation/note_editor_screen.dart`

**Interfaces:**
- Consumes: `ProgressiveFade`

- [ ] Remove the obsolete AppBar background gradients.
- [ ] Wrap each screen's content viewport in `ProgressiveFade`.
- [ ] Format the changed Dart files.
- [ ] Run the focused test and static analysis.
- [ ] Inspect the final diff and confirm unrelated changes remain intact.
