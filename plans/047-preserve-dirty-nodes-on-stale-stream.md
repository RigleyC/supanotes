# Plan 047: Don't Delete Locally-Dirty Nodes During Stale Stream Emission

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat bfebe7e..HEAD -- lib/features/notes/presentation/controllers/note_editor_controller.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: MED
- **Depends on**: plans/046-editor-round-trip-characterization-tests.md
- **Category**: bug
- **Planned at**: commit `bfebe7e`, 2026-07-06

## Why this matters

When a user types a new paragraph, the edit lives in the `MutableDocument`
immediately but doesn't reach SQLite until the 500ms debounce fires. During
that window, `noteNodesProvider` can emit an empty-`p1` snapshot for reasons
**unrelated to that flush** — a remote sync push, an FCM-triggered refresh, or
another window changing the note. When that emission arrives,
`NoteEditor.didUpdateWidget` calls `updateNodesIncrementally`, which deletes
any doc node whose id isn't in `incomingIds`. The just-typed paragraph (whose
`dirtyId` is still in `locallyDirtyNodeIds`) is silently deleted from the doc.
The user sees their sentence vanish. Commit `610c923` ("fix words disappering
when cursor changes") chased this same symptom and only got a partial fix.

## Current state

### File in scope

`lib/features/notes/presentation/controllers/note_editor_controller.dart` —
owns the editor controller; `updateNodesIncrementally` (lines 146-189)
diffs incoming stream-emitted `NoteNode`s against the current doc and emits
`EditRequest`s. `locallyDirtyNodeIds` is accessible via
`_nodeSyncManager?.locallyDirtyNodeIds`.

### Current buggy code (lines 146-189)

```dart
void updateNodesIncrementally(List<NoteNode> incomingNodes) {
  final doc = document;
  final ed = editor;
  if (doc == null || ed == null) return;

  _nodeSyncManager?.suspendSync();
  try {
    final dirtyIds = _nodeSyncManager?.locallyDirtyNodeIds ?? const {};

    final requests = <EditRequest>[];
    final incomingIds = incomingNodes.map((n) => n.id).toSet();

    for (final node in doc) {
      if (!incomingIds.contains(node.id)) {
        requests.add(DeleteNodeRequest(nodeId: node.id));   // ← BUG: no dirty-check
      }
    }

    for (int i = 0; i < incomingNodes.length; i++) {
      final incoming = incomingNodes[i];
      final existingNode = doc.getNodeById(incoming.id);

      if (existingNode == null) {
        final newNode = NodeSyncManager.createNodeFromSchema(incoming);
        requests.add(InsertNodeAtIndexRequest(nodeIndex: i, newNode: newNode));
      } else {
        if (dirtyIds.contains(incoming.id)) continue;        // ← UPDATE path: protected
        final newNode = NodeSyncManager.createNodeFromSchema(incoming);
        if (_isNodeModified(existingNode, newNode)) {
          requests.add(ReplaceNodeRequest(existingNodeId: incoming.id, newNode: newNode));
        }
      }
    }

    if (requests.isNotEmpty) {
      ed.execute(requests);
    }
  } finally {
    _nodeSyncManager?.resumeSync();
  }
}
```

Note line 172's protection for the **update** branch. The **delete** branch on
line 160 has no equivalent guard. Asymmetric, and missing exactly when it
matters.

### Repository conventions

- Error handling: callers here don't catch; `NodeSyncManager` already
  handles DB errors inside `_writeLock`. Don't add try/catch here.
- Logging: `import 'dart:developer' as dev; dev.log(..., name: 'NoteEditor')`.
  The controller already imports this on line 3.
- `locallyDirtyNodeIds` is the canonical "this node has local changes the DB
  hasn't acknowledged yet" set — that's the contract; treat it as the source
  of truth, do NOT add a second mechanism.
- AGENTS.md rule: "State is UI local" — do not introduce a new field;
  reuse `locallyDirtyNodeIds`.
- Do not add code comments unless asked by the plan.

## Commands you will need

| Purpose          | Command                                                                | Expected on success |
|------------------|------------------------------------------------------------------------|---------------------|
| Flip test        | `flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart --plain-name "BUG 047"` | the test still passes — it now asserts the FIXED behavior (node remains) |
| Run all editor tests | `flutter test test/features/notes/`                                | all pass            |
| Static analysis  | `dart analyze lib/features/notes/presentation/controllers/note_editor_controller.dart` | no errors |

## Scope

**In scope** (the only files you should modify):
- `lib/features/notes/presentation/controllers/note_editor_controller.dart`
- `test/features/notes/presentation/controllers/note_editor_controller_test.dart` — flip the `BUG 047` test assertion only, do NOT add new tests here (those were already written in 046)

**Out of scope** (do NOT touch):
- `node_sync_manager.dart` — the `locallyDirtyNodeIds` set semantics stay as is.
- `note_editor.dart` — `didUpdateWidget` already calls this method correctly; no change.
- `notes_providers.dart` — stream structure is fine.

## Git workflow

- Branch: `fix/047-dirty-node-deletion-race`
- One commit: `fix(editor): preserve locally-dirty nodes on stale stream emission`
  (Conventional Commits per AGENTS.md).
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Flip the characterization test

Open `test/features/notes/presentation/controllers/note_editor_controller_test.dart`:

Find the test prefixed `BUG 047` (its name contains the substring
"locally-dirty paragraph is deleted by stale stream emission"). The current
assertion is, approximately:

```dart
expect(doc.getNodeById('p1'), isNull,
    reason: 'BUG 047: locally-dirty paragraph is deleted by stale stream emission');
```

Change to:

```dart
expect(doc.getNodeById('p1'), isA<ParagraphNode>(),
    reason: 'Plan 047: locally-dirty paragraph is preserved against stale stream');
```

Leave the test name as-is or rename to include "preserved":
`test('plan 047: locally-dirty paragraph is preserved on stale stream emission')`.

**Verify**: `flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart --plain-name "047"`
→ test FAILS (because the fix isn't in yet). This is expected and confirms the test
will catch the regression.

### Step 2: Guard the delete loop

Open `lib/features/notes/presentation/controllers/note_editor_controller.dart`,
find `updateNodesIncrementally`.

Change only the delete loop:

```dart
for (final node in doc) {
  if (!incomingIds.contains(node.id)) {
    requests.add(DeleteNodeRequest(nodeId: node.id));
  }
}
```

to:

```dart
for (final node in doc) {
  if (!incomingIds.contains(node.id)) {
    if (dirtyIds.contains(node.id)) continue;
    requests.add(DeleteNodeRequest(nodeId: node.id));
  }
}
```

Do not add anything else. Do not touch the insert or update branches.
Do not log — `locallyDirtyNodeIds` swallow is intentional and silent.

**Verify**: `flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart`
→ all tests pass (including the flipped `047` one and the unchanged `048`,
`049` ones still asserting the buggy behavior).

### Step 3: Run the full notes editor test suite

**Verify**: `flutter test test/features/notes/`
→ all pass.

**Verify**: `dart analyze lib/features/notes/presentation/controllers/note_editor_controller.dart`
→ exit 0, no warnings or errors.

## Test plan

The 046 plan already wrote the characterization test. This plan flips it from
"asserts current buggy behavior" to "asserts fixed behavior". No new tests
needed.

- `flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart` → all pass
- Specifically the test previously named `BUG 047` (now renamed as above) must pass with the fixed assertion.

## Done criteria

- [ ] `flutter test test/features/notes/` exits 0
- [ ] `dart analyze lib/features/notes/presentation/controllers/note_editor_controller.dart` exits 0
- [ ] `git diff --name-only` shows only `note_editor_controller.dart` and the test file
- [ ] Diff in controller is exactly the added `if (dirtyIds.contains(node.id)) continue;` line, no other changes
- [ ] The flipped `047` test passes
- [ ] `plans/README.md` status row for 047 updated to DONE

## STOP conditions

Stop and report back (do not improvise) if:

- `updateNodesIncrementally`'s current code doesn't match the excerpt above
  (the codebase has drifted; the dirty-check may already be there, in which
  case confirm via the test passing BEFORE the fix and re-evaluate).
- `_nodeSyncManager?.locallyDirtyNodeIds` access fails — the field is public
  on `NodeSyncManager` (line 63); if it has been made private, STOP and
  report.
- The 046 plan hasn't landed yet (i.e., `note_editor_controller_test.dart`
  doesn't contain a test with `047` in its name) — STOP, this plan's
  prerequisite isn't met.
- The flipped test fails AFTER the fix with a different reason than expected
  (e.g., the dirty-node never enters `locallyDirtyNodeIds` because the
  `InsertNodeAtCaretRequest` path doesn't enqueue an `InsertOp` — that would
  imply a deeper `NodeSyncManager` bug; report, do not fix it here).

## Maintenance notes

- Whenever `NodeSyncManager.locallyDirtyNodeIds` semantics change (e.g., a
  node whose flush errored is removed from the set), this guard must be
  re-evaluated. The intent of `locallyDirtyNodeIds` exactly matches the
  guard's intent: "DB hasn't acknowledged this node yet, so a stream
  emission without it is stale relative to local state."
- Do NOT simplify this to "skip all updates if there are dirty nodes" —
  only the deletion-not-in-incoming path is suppressed; updates to clean
  nodes still go through.
- A reviewer should scrutinize: did the executor accidentally also guard the
  insert branch? That would prevent legitimately-new remote nodes from
  appearing in the doc. The diff must show the guard ONLY in the delete
  loop.