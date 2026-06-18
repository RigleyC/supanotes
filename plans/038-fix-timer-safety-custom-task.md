# Plan 038: Fix timer safety in CustomTaskComponentBuilder

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 34998f2..HEAD -- lib/features/notes/presentation/widgets/custom_task_component.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
> **Category**: bug
- **Planned at**: commit `34998f2`, 2026-06-18

## Why this matters

When a user completes a recurring task in the note editor, `CustomTaskComponentBuilder` schedules a 400ms `Future.delayed` to visually reset the checkbox. If the user navigates away within that 400ms, the timer fires on a disposed editor, potentially causing a crash or assertion error.

The `exists` check (line 103) guards against the node being removed, but not against the editor itself being disposed.

## Current state

- File: `lib/features/notes/presentation/widgets/custom_task_component.dart`
- Class: `CustomTaskComponentBuilder` (lines 53–143)
- Relevant code (lines 87–109):

```dart
setComplete: (bool isComplete) async {
  _editor.execute([
    ChangeTaskCompletionRequest(nodeId: node.id, isComplete: isComplete),
  ]);

  if (isComplete) {
    await onTaskComplete?.call(node.id);
  } else {
    await onTaskReopen?.call(node.id);
  }

  final taskMeta = taskMetadataById[node.id];
  if (isComplete && taskMeta?.recurrence != null) {
    _pendingResetNodeIds.add(node.id);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!_pendingResetNodeIds.remove(node.id)) return;
      final exists = document.getNodeById(node.id) != null;
      if (exists) {
        _editor.execute([
          ChangeTaskCompletionRequest(nodeId: node.id, isComplete: false),
        ]);
      }
    });
  }
},
```

The `_editor` field is set at construction time (line 63). The builder is created per editor instance in `note_editor.dart` (line 181). When the editor is disposed, `_editor` becomes invalid.

## Commands you will need

| Purpose   | Command                              | Expected on success    |
|-----------|--------------------------------------|------------------------|
| Analyze   | `dart analyze lib/features/notes/presentation/widgets/custom_task_component.dart` | No issues found |

## Scope

**In scope**:
- `lib/features/notes/presentation/widgets/custom_task_component.dart` (only the `Future.delayed` block in `createViewModel`)

**Out of scope**:
- `NoteEditor` widget lifecycle
- `NoteEditorController` disposal
- Other component builders

## Steps

### Step 1: Add a disposed guard to the timer callback

The simplest fix: check if the editor's document is still accessible before executing. The `_editor` object holds a reference to the document via `_editor.context.document`. If the editor is disposed, accessing this will throw.

Wrap the `_editor.execute` call in a try-catch:

```dart
if (isComplete && taskMeta?.recurrence != null) {
  _pendingResetNodeIds.add(node.id);
  Future.delayed(const Duration(milliseconds: 400), () {
    if (!_pendingResetNodeIds.remove(node.id)) return;
    final exists = document.getNodeById(node.id) != null;
    if (exists) {
      try {
        _editor.execute([
          ChangeTaskCompletionRequest(nodeId: node.id, isComplete: false),
        ]);
      } catch (_) {
        // Editor was disposed while the timer was pending — safe to ignore.
      }
    }
  });
}
```

### Step 2: Verify

**Verify**: `dart analyze lib/features/notes/presentation/widgets/custom_task_component.dart` → No issues found

## Test plan

No new tests required — this is a defensive guard against a race condition that's hard to reproduce in unit tests.

## Done criteria

- [ ] `dart analyze lib/features/notes/presentation/widgets/custom_task_component.dart` exits 0
- [ ] The `Future.delayed` callback wraps `_editor.execute` in a try-catch
- [ ] No files outside scope modified

## STOP conditions

- The code at lines 87–109 doesn't match the "Current state" excerpt.
- A step's verification fails twice.
- The fix requires touching files outside `custom_task_component.dart`.

## Maintenance notes

- A more robust solution would be to cancel all pending timers when the editor is disposed, but that requires changes to `NoteEditorController` which is out of scope for this plan.
- The try-catch approach is safe because the only thing that can fail is the editor execution, and if it fails, the task was already completed in the DB by `onTaskComplete`.
