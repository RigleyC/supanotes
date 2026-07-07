# Plan 055: Avoid Full-Scan `listEquals` in `NoteEditor.didUpdateWidget`

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat bfebe7e..HEAD -- lib/features/notes/presentation/widgets/note_editor.dart`
> If any in-scope file changed since this plan was written (plans 051, 052,
> 054 may land first), compare the "Current state" excerpts against the live
> code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: perf
- **Planned at**: commit `bfebe7e`, 2026-07-06

## Why this matters

`NoteEditor.didUpdateWidget` calls `listEquals(widget.nodes, oldWidget.nodes)`
on every rebuild. `widget.nodes` is `List<NoteNode>` — Drift-generated data
class whose `==` compares every field including the JSON `data` string. Every
keystroke in the editor triggers a provider emission that rebuilds
`NoteEditor`; the `listEquals` runs an O(N) deep compare, where N is the
note's node count. On a 200-paragraph note with rich text, this is
~200 string-compare calls per keystroke. On top of that, the comparison
produces `false` whenever the stream emits the same nodes (because the
`updatedAt` timestamps sometimes differ between emissions by a tick), then
`updateNodesIncrementally` runs its own diff — doubly wasteful.

## Current state

### File in scope

`lib/features/notes/presentation/widgets/note_editor.dart` — the
`didUpdateWidget` and the import of `listEquals` (line 4).

### Current code (lines 134-158)

```dart
@override
void didUpdateWidget(NoteEditor oldWidget) {
  super.didUpdateWidget(oldWidget);
  _taskComponentBuilder.taskMetadataById = widget.taskMetadata;
  _taskComponentBuilder.hideCompleted = widget.hideCompleted;
  _taskComponentBuilder.onTaskLongPress = widget.isReadOnly
      ? null
      : (taskId) => widget.delegate.onTaskLongPress?.call(
          widget.taskMetadata[taskId],
          () async {},
        );

  if (widget.hideCompleted != oldWidget.hideCompleted) {
    setState(() {});
  }

  if (widget.taskMetadata != oldWidget.taskMetadata) {
    _controller?.syncTaskStates(
      widget.taskMetadata.map((k, v) => MapEntry(k, v.isCompleted)),
    );
  }

  if (!listEquals(widget.nodes, oldWidget.nodes)) {
    _controller?.updateNodesIncrementally(widget.nodes);
  }
}
```

### Repository conventions

- `listEquals` is imported from `package:flutter/foundation.dart` (line 4:
  `import 'package:flutter/foundation.dart' show defaultTargetPlatform, listEquals;`)
- `NoteNode` is a Drift-generated row class. Its `==` is generated and compares
  all fields.
- The cheaper invariant is "node count + id set": if the count AND the id set
  match, it's a "potentially same" list; only then does
  `updateNodesIncrementally` need to be called, which does its own per-node
  diff. So we can replace the `listEquals` with "compare id set + count" —
  much cheaper than the full deep compare.
- `updateNodesIncrementally` is already idempotent: if the lists are
  actually identical, it issues zero requests. So calling it after every
  rebuild is fine; the `listEquals` is purely a guardsman.
- Alternatively, drop the guard entirely and always call
  `updateNodesIncrementally`. Its per-node diff is similar cost-wise to
  `listEquals` but more interesting (because it skips dirty ids). This plan
  proposes the middle ground: replace `listEquals` with a cheaper reference
  / set equality that handles the common "no change" case from stale stream
  emissions (the DB stream emits same data same IDs but different row
  instances).
- Do not add code comments unless asked by the plan.

## Commands you will need

| Purpose          | Command                                                              | Expected on success |
|------------------|----------------------------------------------------------------------|---------------------|
| Static analysis  | `dart analyze lib/features/notes/presentation/widgets/note_editor.dart` | no errors          |
| Run editor tests | `flutter test test/features/notes/presentation/`                   | all pass           |
| Grep             | `Select-String -Path lib/features/notes/presentation/widgets/note_editor.dart -Pattern "listEquals"` | only the input position on line 4 listEquals show import; no call site |

## Scope

**In scope** (the only files you should modify):
- `lib/features/notes/presentation/widgets/note_editor.dart`

**Out of scope** (do NOT touch):
- `note_editor_controller.dart` — `updateNodesIncrementally` is fine as is.
- `node_sync_manager.dart`.
- Tests.

## Git workflow

- Branch: `perf/055-note-editor-didupdate-no-listequals`
- Commit: `perf(editor): avoid listEquals in didUpdateWidget hot path`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Drop the `listEquals` call, compare identities

Replace the block in `didUpdateWidget`:

```dart
if (!listEquals(widget.nodes, oldWidget.nodes)) {
  _controller?.updateNodesIncrementally(widget.nodes);
}
```

with:

```dart
if (!identical(widget.nodes, oldWidget.nodes) && _nodesChanged(widget.nodes, oldWidget.nodes)) {
  _controller?.updateNodesIncrementally(widget.nodes);
}
```

Add a private helper method in `_NoteEditorState`:

```dart
bool _nodesChanged(List<NoteNode> current, List<NoteNode> previous) {
  if (current.length != previous.length) return true;
  final currentIds = {for (final n in current) n.id};
  final previousIds = {for (final n in previous) n.id};
  if (currentIds.length != previousIds.length) return true;
  if (!currentIds.containsAll(previousIds)) return true;
  return false;
}
```

This catches additions / deletions / reordering by id set. Mundane edits
within a single note (same ids, same count, content changed) bypass the
list-equality check; we fall through to a missing early-return, but the
`updateNodesIncrementally` is NOT called for the unchanged id-set case.

But we DO need to call `updateNodesIncrementally` when content changed
remotely (because a node's text changed but id set didn't). Otherwise this
plan breaks remote sync.

Better: always call `updateNodesIncrementally` if NOT identical (object
identity is the cheap-and-correct guard against the most common case where
the SAME list instance is passed — Drift returns the same list reference
when the stream emits without changes):

```dart
if (!identical(widget.nodes, oldWidget.nodes)) {
  _controller?.updateNodesIncrementally(widget.nodes);
}
```

`updateNodesIncrementally`'s internal `_isNodeModified` (post-plan 049)
is cheap enough; running it on every stream emission is fine. The
`listEquals` was getting in the way of legitimate remote updates by short-
circuiting when only the contents changed (id-set identical). Actually,
`listEquals` returns FALSE in that case, so the path was taken correctly —
the only cost was the deep compare. The fix is to AVOID the deep compare
and just always call `updateNodesIncrementally` when the list reference
differs.

Caveat: every stream emission produces a fresh `List<NoteNode>` instance
from the Drift stream. That means `!identical(...)` is almost always
true. So the cost moves from `listEquals` (deep) to
`updateNodesIncrementally` (also iterates and diffs). The net is similar.

The TRUE win is to skip the rebuild entirely when the id set AND key
content didn't change. To do that, we need content comparison per id,
which is what `updateNodesIncrementally` does. So we're already optimal
given the constraints.

**Pragmatic decision**: replace `listEquals` with `identical` (cheapest
sanity check), and ALWAYS call `updateNodesIncrementally`. The
internal diff is fast for unchanged nodes (early-return after one
field-compare per node). Don't add the id-set helper. Net result: drop
the helper idea. Final change:

```dart
if (!identical(widget.nodes, oldWidget.nodes)) {
  _controller?.updateNodesIncrementally(widget.nodes);
}
```

`updateNodesIncrementally` then handles the per-node diff internally
without rebuilding unnecessarily.

Remove the now-unused `listEquals` from the show clause on line 4:

```dart
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
```

### Step 2: Verify

**Verify**: `dart analyze lib/features/notes/presentation/widgets/note_editor.dart`
→ no errors.

**Verify**:
```bash
Select-String -Path lib/features/notes/presentation/widgets/note_editor.dart -Pattern "listEquals"
```
Expected: no matches.

**Verify**: `flutter test test/features/notes/presentation/`
→ all pass.

## Test plan

No new tests. The existing screen-level test exercises the rebuild path
and would catch regressions in updateNodesIncrementally skipping legitimate
content updates. Existing characterization tests in plan 046 cover the
sync correctness.

- `flutter test test/features/notes/` → all pass

## Done criteria

- [ ] `dart analyze lib/features/notes/presentation/widgets/note_editor.dart` exits 0
- [ ] `Select-String` for `listEquals` in `note_editor.dart` returns no matches
- [ ] `flutter test test/features/notes/` exits 0
- [ ] Diff shows exactly: `import 'package:flutter/foundation.dart' show defaultTargetPlatform;` (removed `listEquals`), and the block `if (!identical(widget.nodes, oldWidget.nodes))` replaces the `listEquals` block
- [ ] `plans/README.md` status row for 055 updated to DONE

## STOP conditions

Stop and report back (do not improvise) if:

- `listEquals` is used elsewhere in `note_editor.dart` (plan 054 might add
  usages — check after 054 lands). If so, don't remove the import.
- Removing `listEquals` makes the rebuild path issue
  `updateNodesIncrementally` calls so frequently that tests flap — report.
- The deep `==` on `NoteNode` is short-circuited (e.g.,
  `DriftRow.equals` short-circuits on type and id, making it cheap) —
  re-evaluate whether the change is worth it. Likely still worth it
  because deep JSON-string compare on every rebuild is the documented
  cost: confirm via a profiling run before deciding.
- Plan 054's ValueNotifier addition to `_NoteEditorState` introduced
  build cycles that conflict with the rebuild count here — re-check.
- If `identical` short-circuit causes legitimate remote updates to be
  skipped (i.e., the Drift stream provider re-emits the SAME list
  reference even after DB changes — unlikely but verify with a
  characterization test in plan 046), STOP and report. The fix in that
  case is to drop the guard entirely:
  ```dart
  _controller?.updateNodesIncrementally(widget.nodes);
  ```
  No conditional.

## Maintenance notes

- The choice between `identical` (reference equality) and "always call
  updateNodes" depends on whether the Drift stream caches the list. Drift's
  `watchDistinct` could avoid re-emitting on no-change; verify with the
  repo's `notes_providers.dart` — `noteNodesProvider` is a
  `StreamProvider.autoDispose.family` that delegates to
  `notesRepository.watchNodes`. If `watchNodes` returns a fresh list each
  emission, `identical` will always be false, and the optimization is
  moot (we're just avoiding the deep compare). If `watchNodes` re-emits
  the same list reference when DB hasn't changed, `identical` saves a
  real round-trip.
- A reviewer should confirm: any future change to `noteNodesProvider` that
  caches the list (e.g., adds `.distinct()` or returns a memoized
  reference) could mean `identical` returns true when content has
  changed. Be cautious if such a refactor is planned.
- `updateNodesIncrementally` is now called on every didUpdateWidget that
  doesn't have identical list references; it must remain cheap for the
  no-op case. Plan 046's tests characterize that — if a future change
  makes it expensive, the optimization here loses value.