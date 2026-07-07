# Plan 057: Unify Editor Document Diff Logic (Stretch Plan)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat bfebe7e..HEAD -- lib/features/notes/presentation/controllers/note_editor_controller.dart lib/features/notes/domain/node_sync_manager.dart`
> If any in-scope file changed since this plan was written (plans 047, 048,
> 049, 050, 054, 055 will definitely land first), compare the "Current state"
> excerpts against the live code before proceeding; on a mismatch, treat it
> as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: plans/046-editor-round-trip-characterization-tests.md, plans/047-preserve-dirty-nodes-on-stale-stream.md, plans/048-flush-sync-manager-before-dispose.md, plans/049-diff-covers-all-node-types.md
- **Category**: tech-debt | architecture
- **Planned at**: commit `bfebe7e`, 2026-07-06

## Why this matters

The editor has two parallel diff systems doing the same conceptual job —
syncing a `MutableDocument` against a `List<NoteNode>` (and vice versa) —
in two places that don't share types or code:

1. **`NoteEditorController.updateNodesIncrementally`** (lines 146-189):
   diff incoming `NoteNode`s (DB representation) against current doc nodes,
   issue `EditRequest`s (Insert/Delete/Replace) — driven by stream
   emissions.

2. **`NodeSyncManager._onDocumentChanged` + `_drainQueue`** (lines
   126-179, 180-279): observe `DocumentChangeLog` events
   (`NodeInsertedEvent` / `NodeRemovedEvent` / `NodeMovedEvent` /
   `NodeChangeEvent`), enqueue `NodeOperation`s
   (`InsertOp` / `UpdateOp` / `MoveOp` / `DeleteOp`), then persist
   each to Drift — driven by user edits.

Both have to know:
- How to map a `DocumentNode` → a `NoteNode` (and back).
- How to skip dirty ids during reactive updates.
- How to suspend/resume during conflict.
- How to handle ordering by position.

They've diverged: `updateNodesIncrementally` skips only the Update branch
for dirty ids (plan 047 adds the Delete branch to that skip);
`_drainQueue` has no concept of "remote override" (it always writes
local-first). Bugs in one don't surface in tests of the other. This is
the biggest tech-debt in the editor subsystem.

A unified design: pull both into a single `NoteSyncCoordinator` class
that owns the concurrency/suspension invariants and exposes two methods
(`applyRemoteNodes(List<NoteNode>)` and `applyLocalDocumentChange(...)`)
that go through the same dirty-tracking, position computation,
serialization pipeline.

## Current state

### Files in scope

- `lib/features/notes/domain/node_sync_manager.dart` — the side that writes
  locally. Lines 39-77 (NodeSyncManager core), 126-179 (onDocumentChanged),
  180-279 (_drainQueue), 281-306 (op node id + node to companion), 451-510
  (documentFromNodes + createNodeFromSchema).
- `lib/features/notes/presentation/controllers/note_editor_controller.dart`
  — the side that reads remotely. Lines 146-189
  (`updateNodesIncrementally`), 191-214 (`_isNodeModified`), 111-144
  (`suspendSync`/`resumeSync`/`syncTaskStates`).
- `lib/features/notes/domain/note_editor_commands.dart` — `selectedNodes`
  helper, may move richer diff helpers here.
- `lib/features/notes/presentation/widgets/note_editor.dart` — the
  `didUpdateWidget` Path A sync (already simplified by plan 054 via the
  task builder coordinator refactor). Verify callsites.

### Repository conventions

- The plan MUST be a non-breaking refactor — no behavior change captured by
  the existing characterization tests (plan 046).
- Match the existing serialization (`NodeSyncManager._nodeData`) which is
  the source of truth for node JSON.
- `EditRequest`s stay the API for mutating the editor — `Editor.execute`
  is the only write path.
- Don't reuse `NodeOperation` types across responsibilities; they currently
  describe enqueue intent, not diff intent. We want a richer `DiffOp` for
  plan purposes.
- Do not add code comments unless asked by the plan.

## Commands you will need

| Purpose            | Command                                                                                                                                          | Expected on success |
|--------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|---------------------|
| Run all editor tests | `flutter test test/features/notes/`                                                                                                             | all pass (after 046-049 land) |
| Run all repo tests  | `flutter test`                                                                                                                                  | all pass            |
| Static analysis    | `dart analyze lib/features/notes/domain/node_sync_manager.dart lib/features/notes/presentation/controllers/note_editor_controller.dart`        | no errors           |
| Grep               | `Select-String -Path lib/features/notes/presentation/ -Pattern "updateNodesIncrementally\|syncTaskStates\|suspendSync\|resumeSync"` | matches only through the new coordinator's public API |

## Scope

**In scope** (the only files you should modify):
- `lib/features/notes/domain/note_sync_coordinator.dart` — create (new home for the unified coordinator)
- `lib/features/notes/domain/node_sync_manager.dart` — extract shared helpers, slim down
- `lib/features/notes/presentation/controllers/note_editor_controller.dart` — slim `NoteEditorController`,
  delegate to the coordinator
- `lib/features/notes/presentation/widgets/note_editor.dart` — update callsites only (the path B
  task sync call is already abstracted by plan 054; touch here only if the call signature changes)

**Out of scope** (do NOT touch):
- `note_editor_provider.dart`, `notes_providers.dart` — provider shapes unchanged.
- The serialization (`_nodeData` / `_nodeFromData` / `createNodeFromSchema`). These are correct
  and shared (plan 049 already makes `_nodeData` static, accessible).
- The `_writeLock` plumbing (plan 048 already addressed flushing).
- The structured-logging fix (plan 050).
- Existing tests. The characterization tests from 046 are the safety net.

## Git workflow

- Branch: `refactor/057-unify-editor-diff`
- Commits per step (4-5 total). Conventional Commits.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Design NoteSyncCoordinator

Create `lib/features/notes/domain/note_sync_coordinator.dart`. Define
the contract:

```dart
import 'package:drift/drift.dart';
import 'package:super_editor/super_editor.dart';

import '../../../core/database/database.dart';
import 'node_sync_manager.dart';

/// Diff operation issued by the coordinator from either side.
sealed class DiffOp {}

class DiffInsert extends DiffOp {
  final DocumentNode node;
  final int index;
  DiffInsert(this.node, this.index);
}

class DiffDelete extends DiffOp {
  final String nodeId;
  DiffDelete(this.nodeId);
}

class DiffReplace extends DiffOp {
  final String existingNodeId;
  final DocumentNode newNode;
  DiffReplace(this.existingNodeId, this.newNode);
}

class DiffMove extends DiffOp {
  final String nodeId;
  final int toIndex;
  DiffMove(this.nodeId, this.toIndex);
}

/// Coordinates between the editor's MutableDocument and the persisted NoteNode
/// records in Drift. Owns the dirty-tracking, serialization, and concurrency
/// invariants.
class NoteSyncCoordinator {
  NoteSyncCoordinator({
    required AppDatabase database,
    required String noteId,
    required String userId,
    required MutableDocument document,
    required Editor editor,
  })  : _db = database,
        _noteId = noteId,
        _userId = userId,
        _document = document,
        _editor = editor {
    _document.addListener(_onDocumentChanged);
  }

  final AppDatabase _db;
  final String _noteId;
  final String _userId;
  final MutableDocument _document;
  final Editor _editor;
  final List<NodeOperation> _pendingOps = [];   // reuse from NodeSyncManager
  final Set<String> _locallyDirtyNodeIds = {};
  Timer? _debounceTimer;
  bool _suspended = false;

  // The local-first write pipeline (was NodeSyncManager._drainQueue).
  // ... (delegate to NodeSyncManager internals or extract)
}
```

Decide if the coordinator OWNS the `NodeSyncManager` instance or ALL its
internal methods. Cleanest: coordinator delegates to `NodeSyncManager`
for persistence and to a new `RemoteNodeApplicator` for the apply path.

### Step 2: Extract `RemoteNodeApplicator`

Create a new class in the same file:

```dart
class RemoteNodeApplicator {
  RemoteNodeApplicator({
    required this.coordinator,
  });

  final NoteSyncCoordinator coordinator;

  /// Applies a stream emission of NoteNodes to the local document.
  /// Skips locally-dirty ids for both replace and delete.
  void applyIncomingNodes(List<NoteNode> incomingNodes) {
    if (coordinator._suspended) return;

    final doc = coordinator._document;
    final dirtyIds = coordinator._locallyDirtyNodeIds;
    final incomingIds = incomingNodes.map((n) => n.id).toSet();

    final requests = <EditRequest>[];
    for (final node in doc) {
      if (!incomingIds.contains(node.id)) {
        if (dirtyIds.contains(node.id)) continue;
        requests.add(DeleteNodeRequest(nodeId: node.id));
      }
    }

    for (int i = 0; i < incomingNodes.length; i++) {
      final incoming = incomingNodes[i];
      final existingNode = doc.getNodeById(incoming.id);
      if (existingNode == null) {
        final newNode = NodeSyncManager.createNodeFromSchema(incoming);
        requests.add(InsertNodeAtIndexRequest(nodeIndex: i, newNode: newNode));
      } else {
        if (dirtyIds.contains(incoming.id)) continue;
        final newNode = NodeSyncManager.createNodeFromSchema(incoming);
        if (NodeSyncManager._nodeData(existingNode) != NodeSyncManager._nodeData(newNode)) {
          requests.add(ReplaceNodeRequest(existingNodeId: incoming.id, newNode: newNode));
        }
      }
    }

    if (requests.isNotEmpty) coordinator._editor.execute(requests);
  }

  /// Applies a tasks-table snapshot to the doc — same dirty-tracking.
  void applyTaskCompletionStates(Map<String, bool> taskCompletionMap) {
    if (coordinator._suspended) return;

    final requests = <EditRequest>[];
    for (final node in coordinator._document) {
      if (node is TaskNode) {
        final isDbCompleted = taskCompletionMap[node.id] ?? false;
        if (node.isComplete != isDbCompleted) {
          requests.add(ChangeTaskCompletionRequest(
            nodeId: node.id,
            isComplete: isDbCompleted,
          ));
        }
      }
    }
    if (requests.isNotEmpty) coordinator._editor.execute(requests);
  }
}
```

Coordinator exposes:

```dart
void suspendSync() => _suspended = true;
void resumeSync() => _suspended = false;
Set<String> get locallyDirtyNodeIds => _locallyDirtyNodeIds;
```

### Step 3: Slim `NoteEditorController`

In `lib/features/notes/presentation/controllers/note_editor_controller.dart`,
remove `updateNodesIncrementally`, `_isNodeModified`, `syncTaskStates`
bodies — they relocate to the coordinator's `RemoteNodeApplicator`. Replace
with thin delegates:

```dart
void updateNodesIncrementally(List<NoteNode> incomingNodes) {
  final coordinator = _coordinator;
  if (coordinator == null) return;
  coordinator.suspendSync();
  try {
    coordinator.remoteApplicator.applyIncomingNodes(incomingNodes);
  } finally {
    coordinator.resumeSync();
  }
}

void syncTaskStates(Map<String, bool> taskCompletionMap) {
  final coordinator = _coordinator;
  if (coordinator == null) return;
  coordinator.suspendSync();
  try {
    coordinator.remoteApplicator.applyTaskCompletionStates(taskCompletionMap);
  } finally {
    coordinator.resumeSync();
  }
}
```

Keep public API names — they're called from `note_editor.dart:didUpdateWidget`
which plan 054 may have touched; verify call signature compatibility.

### Step 4: Move `NodeSyncManager` into the coordinator OR keep it and have the coordinator own a NodeSyncManager instance

Decision tree:
- If `NodeSyncManager` has any external callers (check `grep -rn "NodeSyncManager\." lib/`):
  - **Yes** — keep `NodeSyncManager` as a public class. The coordinator composes it.
  - **No** — inline `NodeSyncManager` into the coordinator (delete the old class file).

Likely there ARE external callers — `documentFromNodes`,
`createNodeFromSchema`, `extractTasks` are utility parses used elsewhere.
DON'T inline — keep NodeSyncManager as the persistence side, coordinator
composes it for write-path access and uses serialize/deserialize.

### Step 5: Verify

**Verify**: `dart analyze lib/features/notes/`
→ no errors.

**Verify**: `flutter test test/features/notes/`
→ all pass (characterization tests are the safety net).

**Verify**: `flutter test`
→ all pass.

## Test plan

No new tests required — the 046 characterization tests now exercise the
unified coordinator via the same screen path. Any divergence falls into:
- Existing characterization tests catching it.
- New unit tests for `RemoteNodeApplicator` / `NoteSyncCoordinator` should
  be added only if the coordinator's public API differs in test-relevant
  ways. Possible additions:
  - `test/features/notes/domain/note_sync_coordinator_test.dart` with two
    tests: (1) one-directional remote insertion creates a new node;
    (2) two-way concurrent edits to dirty vs non-dirty nodes.

If added:
- `flutter test test/features/notes/domain/note_sync_coordinator_test.dart` → passes

## Done criteria

- [ ] `dart analyze lib/features/notes/` exits 0
- [ ] `flutter test test/features/notes/` exits 0
- [ ] `flutter test` exits 0
- [ ] `NoteEditorController.updateNodesIncrementally` and `syncTaskStates` are <20 lines each, only delegating to the coordinator
- [ ] `NoteSyncCoordinator` and `RemoteNodeApplicator` exist as documented
- [ ] `goto` edit path: simplify code review
- [ ] `_isNodeModified` removed from `NoteEditorController` (replaced by `NodeSyncManager._nodeData` comparison inside the applicator)
- [ ] `git diff --name-only` shows: `note_sync_coordinator.dart` (new), `note_editor_controller.dart`, `node_sync_manager.dart`, and optionally `note_editor.dart` (callsites only)
- [ ] `Select-String -Path lib/features/notes/ -Pattern "updateNodesIncrementally\|syncTaskStates"` matches only in the coordinator's delegate methods
- [ ] `plans/README.md` status row for 057 updated to DONE

## STOP conditions

Stop and report back (do not improvise) if:

- ANY characterization test from plan 046 fails after the refactor —
  diff behavior changed and you need to find the divergence by debug.
  STOP and report; don't force the consolidation by adjusting tests
  unless those tests are themselves testing for an obsolete behavior.
- The 047/048/049 fixes weren't merged (verify by re-reading the
  controller and node_sync_manager before starting this plan).
- `NodeSyncManager` has external callers that depend on instance
  methods not exposed via the static API — g.e. `_nodeData` is now
  `static`, accessible as `NodeSyncManager._nodeData`. If your refactor
  in Step 2 needs to call it from outside the class, either re-import
  access via a public wrapper or stay within the file. STOP and report
  if you need to expose the method publicly.
- After extraction, `NoteEditorController.dispose` ordering is critical
  — coordinator MUST dispose BEFORE the editor/document. Confirm by
  re-running the 048 comportation test: the final-flush path must still
  work. If the refactor broke this, restore the flush ordering.
- If `RemoteNodeApplicator` needs to suspend-resume the coordinator from
  inside itself (recursive call), add a recursion guard — STOP and
  report before doing so.
- If tests reveal that removing `_isNodeModified` entirely (replaced
  by `NodeSyncManager._nodeData` string comparison) causes a
  performance regression in notes with many nodes — STOP and re-evaluate.
  Wave the unification scope and keep `_isNodeModified` as a fast-path
  before the serdeg comparison.
- Plan 054's `ValueNotifier` architecture for task builder must still
  receive `taskMetadataById` updates. If the unified coordinator
  changes the contract for `taskMetadataById` updates from
  `didUpdateWidget`, adapt the callsite.
- After Step 3, if `NoteEditorController` no longer holds a
  `NodeSyncManager` instance but holds a `NoteSyncCoordinator`, the call
  to `_nodeSyncManager?.locallyDirtyNodeIds` (in any remaining private
  method) must be replaced with `_coordinator.locallyDirtyNodeIds`. Grep
  for `_nodeSyncManager` references and refactor each.

## Maintenance notes

- This is the riskiest plan in the editor roadmap — schedule a careful
  review with manual smoke testing (multi-window edit conflicts, sync
  offline/online transitions, recurring task toggles).
- A reviewer should confirm:
  1. No new linter warnings introduced.
  2. The new `NoteSyncCoordinator` and `RemoteNodeApplicator` classes
     have proper docs at the class level explaining the invariant
     (single write authority, dirty-tracking semantics).
  3. All public API surface renamed or removed in `NoteEditorController`
     has call sites updated.
- Future direction: now that the diff logic is unified, a follow-up plan
  could replace the position-based ordering with CRDT semantics for
  cross-device conflict resolution. Don't attempt here; would require
  server cooperation.
- After this lands, `NodeSyncManager` becomes a thin persistence delegate.
  If it shrinks sufficiently, consider renaming to `NoteNodeRepository`
  or merging into `notes_repository.dart`. Don't do this within this
  plan.