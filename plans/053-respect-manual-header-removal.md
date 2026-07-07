# Plan 053: Respect Manual Header Removal in `KeepFirstLineAsTitleReaction`

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat bfebe7e..HEAD -- lib/features/notes/domain/keep_first_line_as_title_reaction.dart lib/features/notes/presentation/controllers/note_editor_controller.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: MED
- **Depends on**: plans/046-editor-round-trip-characterization-tests.md (recommended; not strict)
- **Category**: bug
- **Planned at**: commit `bfebe7e`, 2026-07-06

## Why this matters

`KeepFirstLineAsTitleReaction` enforces that the first paragraph of every note
always has the `header1` block type. But it does so unconditionally: it
ignores whether the user just explicitly removed the header via the toolbar
(You can change it back to paragraph). The very next keystroke re-applies
`header1`, trapping the user with a note whose first line is ALWAYS a
title — even notes where the user wanted "just a body." Users have no way to
escape the rule. This is the second-most-reported editor quirk per the
commit history ("fix editor stylesheet and others", "fix editor updates and
focus").

The fix is to remember which editors have manually overridden the header
auto-promotion (a simple module-level set of "dismissed" editor ids or, more
preferable, a per-document boolean flag in the `Editor`'s context) and stop
promoting once the user has explicitly chosen a non-header block type for
the first line.

## Current state

### File in scope

`lib/features/notes/domain/keep_first_line_as_title_reaction.dart` — the
entire 29-line file.

### Current code

```dart
import 'package:super_editor/super_editor.dart';

class KeepFirstLineAsTitleReaction extends EditReaction {
  const KeepFirstLineAsTitleReaction();

  @override
  void react(
    EditContext editorContext,
    RequestDispatcher requestDispatcher,
    List<EditEvent> changeList,
  ) {
    final document = editorContext.document;
    if (document.isEmpty) return;

    final firstNode = document.first;
    if (firstNode is ParagraphNode) {
      if (firstNode.text.toPlainText().trim().isEmpty) return;
      final blockType = firstNode.getMetadataValue('blockType');
      if (blockType != header1Attribution) {
        requestDispatcher.execute([
          ChangeParagraphBlockTypeRequest(
            nodeId: firstNode.id,
            blockType: header1Attribution,
          ),
        ]);
      }
    }
  }
}
```

### How it's installed

`note_editor_controller.dart:62`:

```dart
editor!.reactionPipeline.add(const KeepFirstLineAsTitleReaction());
```

The reaction runs on every edit. So when the user changes the first
paragraph's block type from `header1` to `paragraph` (or any other), the very
next edit (typing a character in that now-paragraph) fires this reaction,
which sees `blockType != header1Attribution` and re-applies `header1`.

### Repository conventions

- `EditReaction`s in `super_editor` have read-only access to `EditContext`
  (which contains the document). Storing per-editor boolean state inside a
  stateless `EditReaction` instance is anti-pattern; the `const` constructor
  means the reaction can't have mutable fields. We need an external store.
- Pattern: existing reactions in the editor carry constants (see
  `RandomDividerConversionReaction` on `note_editor_commands.dart:231`,
  which has `final int dividerCount` but no mutable state).
- A `Set<String>` of "dismissed editor keys" at module scope is acceptable
  for this app — the editor lifecycle is bounded; keys are editor-instance
  ids created via `Editor.createNodeId()`. Disposal could leave a stale
  entry, but the set is bounded by total editor instances ever created —
  fine for a personal notes app.
- Alternative: store a `bool titleAutoPromotionDismissed` in a wrapper data
  structure owned by `NoteEditorController` and pass it into the reaction via
  `editor.context`. Check if `editor.context` supports arbitrary attached
  state — read `super_editor` docs or other reactions in repo.
- Do not add code comments unless asked by the plan.

## Commands you will need

| Purpose          | Command                                                              | Expected on success |
|------------------|----------------------------------------------------------------------|---------------------|
| Static analysis  | `dart analyze lib/features/notes/domain/keep_first_line_as_title_reaction.dart lib/features/notes/presentation/controllers/note_editor_controller.dart lib/features/notes/domain/note_editor_commands.dart` | no errors |
| Run tests        | `flutter test test/features/notes/`                                  | all pass            |

## Scope

**In scope** (the only files you should modify):
- `lib/features/notes/domain/keep_first_line_as_title_reaction.dart`
- `lib/features/notes/domain/note_editor_commands.dart` — only if the toolbar needs to mark "dismissed"
- `lib/features/notes/presentation/widgets/note_toolbar.dart` — wire `_setBlockType(non-header)` to mark dismissed
- `lib/features/notes/presentation/controllers/note_editor_controller.dart` — optional: add dispose hook to clear dismissal on editor destruction

**Out of scope** (do NOT touch):
- `RandomDividerConversionReaction` — unrelated.
- `node_sync_manager.dart` — serialization is not affected (header level remains in `metadata['blockType']`).
- The DB schema — no need to persist dismissal across sessions (per-session dismissal is acceptable; title re-promotes on next open).

## Git workflow

- Branch: `fix/053-respect-manual-header-removal`
- Commit: `fix(editor): allow user to override first-line title auto-promotion`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add module-level dismissal set

Open `lib/features/notes/domain/keep_first_line_as_title_reaction.dart`.
Replace the file's contents:

```dart
import 'package:super_editor/super_editor.dart';

/// Tracks editor instances whose user has manually removed the first-line
/// header promotion. Keyed by the editor's first node id at the time of
/// dismissal — stable for the lifetime of the note editor.
final Set<String> _titlePromotionDismissedFor = {};

void markTitlePromotionDismissed(String editorKey) {
  _titlePromotionDismissedFor.add(editorKey);
}

void clearTitlePromotionDismissed(String editorKey) {
  _titlePromotionDismissedFor.remove(editorKey);
}

class KeepFirstLineAsTitleReaction extends EditReaction {
  const KeepFirstLineAsTitleReaction({this.editorKey});

  final String? editorKey;

  @override
  void react(
    EditContext editorContext,
    RequestDispatcher requestDispatcher,
    List<EditEvent> changeList,
  ) {
    if (editorKey != null && _titlePromotionDismissedFor.contains(editorKey)) return;

    final document = editorContext.document;
    if (document.isEmpty) return;

    final firstNode = document.first;
    if (firstNode is ParagraphNode) {
      if (firstNode.text.toPlainText().trim().isEmpty) return;
      final blockType = firstNode.getMetadataValue('blockType');
      if (blockType != header1Attribution) {
        requestDispatcher.execute([
          ChangeParagraphBlockTypeRequest(
            nodeId: firstNode.id,
            blockType: header1Attribution,
          ),
        ]);
      }
    }
  }
}
```

### Step 2: Pass an editor key when constructing the reaction

Open `lib/features/notes/presentation/controllers/note_editor_controller.dart`.
In `_setupEditor` (lines 50-63), the current code:

```dart
editor!.reactionPipeline.add(const KeepFirstLineAsTitleReaction());
```

Replace with a stable key. Use `_noteId` (the note id), which uniquely
identifies the editor within the session:

```dart
editor!.reactionPipeline.add(KeepFirstLineAsTitleReaction(editorKey: _noteId));
```

(`KeepFirstLineAsTitleReaction` is no longer `const` because it has a runtime
field. Drop the `const` keyword.)

In `dispose()` (line 242-249), clear the dismissal so re-opening the note
re-promotes:

```dart
void dispose() {
  _flushAndSaveFinalState();
  if (_noteId != null) clearTitlePromotionDismissed(_noteId!);
  _nodeSyncManager?.dispose();
  editor?.dispose();
  document?.dispose();
  composer?.dispose();
  focusNode.dispose();
}
```

### Step 3: Mark dismissal when user changes first-line block to non-header

The user can change the first-line block type via the toolbar's `_setBlockType`
or `_convertToListItem` or `_convertToTask`. We need to mark dismissal ONLY
when the toolbar acts on the FIRST node and the chosen type is not
`header1`.

Open `lib/features/notes/presentation/widgets/note_toolbar.dart`. The toolbar
already computes `activeNodeId` and `_activeBlockType`. Modify each call site
to mark dismissal when changing the first node.

Add a helper inside `NoteToolbar`:

```dart
void _maybeMarkTitleDismissal(String? activeNodeId, Attribution? newBlockType) {
  if (activeNodeId == null) return;
  if (newBlockType == header1Attribution) return;
  final document = editor.context.document;
  if (document.isEmpty) return;
  if (document.first.id != activeNodeId) return;
  final firstNode = document.first;
  if (firstNode is! ParagraphNode) return;
  final currentBlock = firstNode.getMetadataValue('blockType');
  if (currentBlock != header1Attribution) return;
  // Only mark when first-line header is being changed to something else.
  markTitlePromotionDismissed(firstNode.id);
}
```

Then add import for `keep_first_line_as_title_reaction.dart` at top of the
file. In each of `_setBlockType`, `_convertToListItem`, `_convertToTask`,
add the helper call after the editor execute, passing the active block-type
after the change:

For `_setBlockType` (lines 246-247):

```dart
void _setBlockType(Attribution? blockType) {
  final activeNodeId = _activeNodeId(composer.selection);
  NoteEditorCommands.setBlockType(editor, composer, blockType);
  _maybeMarkTitleDismissal(activeNodeId, blockType);
}
```

For `_convertToListItem` (lines 249-250):

```dart
void _convertToListItem(ListItemType type) {
  final activeNodeId = _activeNodeId(composer.selection);
  NoteEditorCommands.convertToListItem(editor, composer, type);
  // "List item" is not header1 — count as dismissal.
  _maybeMarkTitleDismissal(activeNodeId, listItemAttribution);
}
```

For `_convertToTask` (line 252):

```dart
void _convertToTask() {
  final activeNodeId = _activeNodeId(composer.selection);
  NoteEditorCommands.convertToTask(editor, composer);
  _maybeMarkTitleDismissal(activeNodeId, listItemAttribution);
}
```

Verify with `dart analyze` and check that `_activeNodeId` is reachable from
each method (it already is, used at the top of `build` — replicate the access
in each path).

If a user later wants to re-enable the title auto-promotion, they delete
the heading entirely OR they manually re-apply H1 via the toolbar. Manually
applying H1 should clear dismissal:

In `_setBlockType`:

```dart
void _setBlockType(Attribution? blockType) {
  final activeNodeId = _activeNodeId(composer.selection);
  NoteEditorCommands.setBlockType(editor, composer, blockType);
  if (blockType == header1Attribution) {
    final document = editor.context.document;
    if (document.isNotEmpty &&
        document.first.id == activeNodeId) {
      clearTitlePromotionDismissed(document.first.id);
    }
  } else {
    _maybeMarkTitleDismissal(activeNodeId, blockType);
  }
}
```

Wait — `_maybeMarkTitleDismissal` already early-returns when `newBlockType ==
header1Attribution`. So the `else` branch alone is sufficient. Simplification:
always call `_maybeMarkTitleDismissal(activeNodeId, blockType)` — it handles
the `header1Attribution` itself. But we want to ALSO handle re-enabling. Add
a separate path:

```dart
void _setBlockType(Attribution? blockType) {
  final activeNodeId = _activeNodeId(composer.selection);
  NoteEditorCommands.setBlockType(editor, composer, blockType);
  if (blockType == header1Attribution) {
    final document = editor.context.document;
    if (document.isNotEmpty && document.first.id == activeNodeId) {
      final firstNode = document.first;
      if (firstNode is ParagraphNode) {
        clearTitlePromotionDismissed(firstNode.id);
      }
    }
  } else {
    _maybeMarkTitleDismissal(activeNodeId, blockType);
  }
}
```

**Important keying caveat**: the `_titlePromotionDismissedFor` set is keyed
by `editorKey == _noteId`, but `_maybeMarkTitleDismissal` adds by
`firstNode.id` (the doc node id). These don't match. Choose ONE key.

Decision: key by `firstNode.id`. Update the reaction to take `editorKey:
firstNode.id` instead of `_noteId`. But `firstNode.id` could change if the
first node is deleted (its id is replaced). Trade-off:
- Key by `_noteId`: stable for editor lifetime; but
  `KeepFirstLineAsTitleReaction(editorKey: _noteId)` is constructed in
  `_setupEditor`. Toolbar marks dismissal with `_noteId`? The toolbar
  doesn't know `_noteId`.
- Key by `firstNode.id`: simpler API; toolbar has access to it. But if the
  first paragraph is deleted, the new first node has a different id and the
  dismissal is forgotten — title auto-promotion restarts.

For a notes app, the latter behavior is arguably correct (if first node
changes entirely, the user is probably not in the same "title" mental model).
Choose `firstNode.id` as the key.

Update `KeepFirstLineAsTitleReaction` to NOT take an `editorKey`
parameter. The reaction is keyed by `document.first.id` at run-time — read
it inside `react()`:

```dart
@override
void react(...) {
  final document = editorContext.document;
  if (document.isEmpty) return;

  final firstNode = document.first;
  if (firstNode is ParagraphNode) {
    if (_titlePromotionDismissedFor.contains(firstNode.id)) return;
    if (firstNode.text.toPlainText().trim().isEmpty) return;
    final blockType = firstNode.getMetadataValue('blockType');
    if (blockType != header1Attribution) {
      requestDispatcher.execute([
        ChangeParagraphBlockTypeRequest(
          nodeId: firstNode.id,
          blockType: header1Attribution,
        ),
      ]);
    }
  }
}
```

The reaction re-checks the set on every edit. Cheaper than passing a
constructor arg.

`note_editor_controller.dart` then just does:

```dart
editor!.reactionPipeline.add(const KeepFirstLineAsTitleReaction());
```

(No `editorKey` needed; back to `const` if we drop the field. If the field
is dropped, the reaction is `const` again. Update step accordingly.)

`dispose()`: no need to clear — the dismissal is keyed by paragraph id, which
is no longer relevant when the editor disposes.

Mark dismissal logic in toolbar: the `_maybeMarkTitleDismissal` helper adds
`firstNode.id` to the set when the user is changing the first-line header to
something else.

### Step 4: Verify

**Verify**: `dart analyze lib/features/notes/domain/keep_first_line_as_title_reaction.dart lib/features/notes/presentation/controllers/note_editor_controller.dart lib/features/notes/presentation/widgets/note_toolbar.dart lib/features/notes/domain/note_editor_commands.dart`
→ no errors.

**Verify**: `flutter test test/features/notes/`
→ all pass.

### Step 5: Quick manual smoke test

If possible, run the app in a worktree and:
1. Create a new note — first line should auto-promote to H1.
2. Type "Hello world".
3. Click the H3 button on the toolbar while the cursor is on the first line.
4. Type a character — the H3 styling MUST persist (no auto-revert to H1).
5. Click H1 again — first line goes back to H1; type a new line containing
   "Title" — H1 must persist.
6. Delete the first line entirely. Type a new "Second title" — it should
   auto-promote to H1 (because the new firstNode has a different id;
   dismissal was keyed to the old id).

If step 6 doesn't auto-promote, the dismissal set is leaking across first
node changes — investigate before declaring DONE.

## Test plan

No existing test directly covers `KeepFirstLineAsTitleReaction`. Plan 046
characterization tests don't include it. Consider adding a small unit test
in `test/features/notes/domain/keep_first_line_as_title_reaction_test.dart`
with two cases:
- New note: insert a non-empty paragraph with non-header blockType → reaction fires,
  doc shows header1.
- Dismissed first node: mark firstNode id dismissed via
  `markTitlePromotionDismissed(firstNodeId)` → insert text → reaction skipped,
  blockType unchanged.

Add the test file (optional; nice-to-have). Use `super_editor` test
utilities if available.

- `flutter test test/features/notes/domain/keep_first_line_as_title_reaction_test.dart` → passes (if added)

## Done criteria

- [ ] `dart analyze lib/features/notes/domain/keep_first_line_as_title_reaction.dart` exits 0
- [ ] `flutter test test/features/notes/` exits 0
- [ ] `_titlePromotionDismissedFor` set exists at module scope in `keep_first_line_as_title_reaction.dart`
- [ ] `markTitlePromotionDismissed` and `clearTitlePromotionDismissed` exported functions exist
- [ ] `KeepFirstLineAsTitleReaction.react` consults the set keyed by `document.first.id`
- [ ] `NoteToolbar` calls `markTitlePromotionDismissed` when changing first-line block from header to non-header
- [ ] `NoteToolbar` calls `clearTitlePromotionDismissed` when re-applying `header1Attribution` to first line
- [ ] `git diff --name-only` shows `keep_first_line_as_title_reaction.dart`, `note_toolbar.dart`, (and optionally test file)
- [ ] `plans/README.md` status row for 053 updated to DONE

## STOP conditions

Stop and report back (do not improvise) if:

- `EditReaction.react` signature changed (e.g., now async, or has different
  args). Report and adapt to the new signature.
- `_activeNodeId` is not accessible from `_setBlockType` etc. methods — it's
  currently used in `build` as a local; replicate the call pattern (it's a
  private method, callable from any instance method on `NoteToolbar`).
- Manually testing with the app reveals the reaction fires before the
  toolbar's `editor.execute` completes (race), so the toolbar's
  `markTitlePromotionDismissed` runs AFTER the reaction's check, undoing
  nothing but the next keystroke still re-promotes. If that happens, the
  fix ordering changes: call `markTitlePromotionDismissed` BEFORE
  `editor.execute`. Verify with the smoke test.
- Two-reaction interaction: `RandomDividerConversionReaction` can replace
  the first paragraph with a `HorizontalRuleNode`, changing `document.first`
  to a node type that's not a `ParagraphNode` — the reaction does nothing,
  correct. But if a paragraph is later inserted above the rule, the new
  first paragraph may have a `dismissed` flag from the OLD first paragraph id.
  Verify via smoke test that re-promotion still works after divider
  insertion; if not, augment the dismissal-clear logic in the divider
  path (out of scope — report).
- Dismissal-set grows unbounded across a long session with many note opens:
  confirm with the user whether to also clear on the reaction's `_noteId`
  dispose. The plan currently only keys by paragraph id; if memory pressure
  observed in smoke test, add a clear-on-dispose hook.

## Maintenance notes

- The dismissal set is keyed by `firstNode.id`. If the first paragraph is
  replaced (large delete+insert), the new first node re-enables promotion
  — which matches user intent ("the user is now starting fresh").
- A reviewer should scrutinize: in `_maybeMarkTitleDismissal`, the check
  `currentBlock != header1Attribution` ensures we only mark dismissal when
  we're transitioning OUT of header1. Without that guard, any toolbar click
  on the first line would lock the user out of ever using header1 again via
  auto-promotion. Test via the smoke test above.
- If `RandomDividerConversionReaction` is enhanced to preserve the original
  paragraph id across divider insertion, the dismissal semantics need
  revisiting (currently: id changes when divider splits a paragraph — the
  "after-divider" paragraph has a new id; the "before" is replaced by the
  rule; the dismissal is lost, which is correct).
- Future plans that persist editor-level user preferences (per-note "disable
  auto-title") should consider persisting `_titlePromotionDismissedFor`
  entries in the `notes` table — out of scope here, but a natural
  follow-up.