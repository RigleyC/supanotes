# Plan 049: Compare All Node Types in `_isNodeModified`

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
- **Risk**: LOW
- **Depends on**: plans/046-editor-round-trip-characterization-tests.md
- **Category**: bug
- **Planned at**: commit `bfebe7e`, 2026-07-06

## Why this matters

`NoteEditorController.updateNodesIncrementally` is the only reactive path that
brings remote node updates into the open document. For image and attachment
nodes, link previews (`RichLinkNode`), and dividers, the diff function
`_isNodeModified` always returns `false` — so even when a remote sync
improves the metadata (image URL refreshed, link preview's title/description
filled in by the server), the doc open on screen is never updated. User must
close and reopen the note to see the change, despite the DB having the new
data. This breaks the sync model silently.

## Current state

### File in scope

`lib/features/notes/presentation/controllers/note_editor_controller.dart` —
the diff helpers (`_isNodeModified` on lines 191-214).

### Current code (lines 191-214)

```dart
bool _isNodeModified(DocumentNode existing, DocumentNode incoming) {
  if (existing.runtimeType != incoming.runtimeType) return true;

  if (existing is TextNode && incoming is TextNode) {
    if (existing.text != incoming.text) return true;
  }

  if (existing is ParagraphNode && incoming is ParagraphNode) {
    if (existing.metadata['blockType'] != incoming.metadata['blockType'])
      return true;
  }

  if (existing is TaskNode && incoming is TaskNode) {
    if (existing.isComplete != incoming.isComplete) return true;
    if (existing.indent != incoming.indent) return true;
  }

  if (existing is ListItemNode && incoming is ListItemNode) {
    if (existing.indent != incoming.indent) return true;
    if (existing.type != incoming.type) return true;
  }

  return false;
}
```

Note the absence of `ImageNode`, `DocumentAttachmentNode`,
`HorizontalRuleNode`, `RichLinkNode`. For all of those, the function falls to
`return false`.

### Available serialization

`NodeSyncManager._nodeData(DocumentNode node)` (lines 387-449) produces the
authoritative JSON for each node type. The deserialization
`NodeSyncManager.createNodeFromSchema` (lines 465-510) is what
`updateNodesIncrementally` calls to produce `incoming` from the schema —
same JSON, so calling `_nodeData` on `existing` and `incoming` will produce
strings directly comparable.

### Repository conventions

- `_nodeData` is private to `NodeSyncManager`. To use it for diffing from the
  controller, add a public static helper:

```dart
static String serializeNodeForDiff(DocumentNode node) => _nodeData(node);
```

  (`_nodeData` itself is already the right shape; only static-callable.)
  Alternatively, since `_nodeData` doesn't reference instance state (no `this._db`
  reads etc.), you could simply change its declaration from `String _nodeData`
  to `static String _nodeData`. Check the current signature — if it's instance,
  prefer the `static` change and update the single call site on `_nodeToCompanion`
  (line 292). Both changes are cosmetic.
- Do not add code comments unless asked by the plan.

## Commands you will need

| Purpose          | Command                                                                                         | Expected on success |
|------------------|-------------------------------------------------------------------------------------------------|---------------------|
| Flip test        | `flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart --plain-name "049"` | all pass after flip |
| Run all notes tests | `flutter test test/features/notes/`                                                          | all pass            |
| Static analysis  | `dart analyze lib/features/notes/presentation/controllers/note_editor_controller.dart lib/features/notes/domain/node_sync_manager.dart` | no errors |

## Scope

**In scope** (the only files you should modify):
- `lib/features/notes/presentation/controllers/note_editor_controller.dart`
- `lib/features/notes/domain/node_sync_manager.dart` — only the `_nodeData` → `static` declaration change (or expose via `static String serializeNodeForDiff`)
- `test/features/notes/presentation/controllers/note_editor_controller_test.dart` — flip the `BUG 049` assertion, optionally add a second case for `RichLinkNode` and `DocumentAttachmentNode`

**Out of scope** (do NOT touch):
- `_nodeToCompanion`, `_nodeType` in `NodeSyncManager`. They are serialization
  hot paths; this fix must NOT change them.
- `_nodeFromData` (parallel deserialize path used by `documentFromNodes`).
  The plan only uses `createNodeFromSchema`, which is the path
  `updateNodesIncrementally` already uses.

## Git workflow

- Branch: `fix/049-node-modified-covers-all-types`
- Commit: `fix(editor): diff all node types when reconciling stream updates`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Flip the characterization test

Open `test/features/notes/presentation/controllers/note_editor_controller_test.dart`,
find the test prefixed `BUG 049` ("ImageNode remote updates are ignored").
The current assertion is approximately:

```dart
final node = doc.getNodeById('i1');
expect(node, isA<ImageNode>());
expect((node as ImageNode).imageUrl, 'oldurl',
    reason: 'BUG 049: ImageNode remote updates are ignored');
```

Change to assert the FIXED behavior:

```dart
final node = doc.getNodeById('i1');
expect(node, isA<ImageNode>());
expect((node as ImageNode).imageUrl, 'newurl',
    reason: 'Plan 049: ImageNode remote updates are now applied');
```

Additionally, add two more cases immediately after the flipped one (model
pattern identical — set up existing, call `updateNodesIncrementally` with
different incoming data, assert replacement happened):

```dart
test('plan 049: RichLinkNode remote updates are applied', () {
  // Set up doc with RichLinkNode(id: 'l1', url: 'old', title: 'old')
  // Call updateNodesIncrementally([NoteNode(id: 'l1', type: 'link' /* if applicable, else 'attachment' */, data: '{"url":"new","title":"new"}')])
  // Assert doc.getNodeById('l1') has url='new' and title='new'
});

test('plan 049: DocumentAttachmentNode keeps its id when remote data unchanged', () {
  // Set up doc with DocumentAttachmentNode(id: 'a1')
  // Call updateNodesIncrementally([NoteNode(id: 'a1', type: 'attachment', data: '{"id":"a1"}')])
  // Assert doc.getNodeById('a1') is DocumentAttachmentNode with id='a1'
  // (no ReplaceNodeRequest needed — _isNodeModified must return false for identical data)
});
```

Read `node_sync_manager.dart:438-447` for the exact `RichLinkNode` /
`DocumentAttachmentNode` constructor arg names before writing these tests. If
`RichLinkNode` is `type: 'attachment'` (per `_nodeType` returning `'attachment'`
for `AttachmentNode`), use that. If it's its own type, report and use whatever
`_nodeType` returns.

**Verify**: `flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart --plain-name "049"`
→ all three `049` tests FAIL (fix not in yet).

### Step 2: Make `_nodeData` static (or expose via wrapper)

Open `lib/features/notes/domain/node_sync_manager.dart`. At line 387:

```dart
Map<String, dynamic> _serializeAttributedText(AttributedText text) { ... }

String _nodeData(DocumentNode node) { ... }
```

Change `String _nodeData(DocumentNode node)` to `static String _nodeData(DocumentNode node)`.

Search the file for all callers of `_nodeData(` — there's one in
`_nodeToCompanion` (line 292). Replace that call with `NodeSyncManager._nodeData(node)`,
or `static` allows calling without prefix inside the class (no change needed
within the class — `static` methods are callable from instance methods
unqualified).

Actually: `static` replaces the implicit `this` reference. Existing call sites
within the class continue to work; external callers need to qualify with the
class name. The only external caller will be `NoteEditorController._isNodeModified`
(Step 3). So just adding `static` is enough; no other changes inside
`NodeSyncManager`.

**Verify**: `dart analyze lib/features/notes/domain/node_sync_manager.dart`
→ no errors. (If `static` breaks a test helper that called `_nodeData` on an
instance, change that helper to call `NodeSyncManager._nodeData(...)` or mark
the helper `@visibleForTesting` static as well.)

### Step 3: Use serialized-data comparison as fallback in `_isNodeModified`

Open `lib/features/notes/presentation/controllers/note_editor_controller.dart`.
Add an import if not already there:

```dart
import 'package:supanotes/features/notes/domain/node_sync_manager.dart';
```

(this import provides `NodeSyncManager` for the static `_nodeData` call. May
already exist — check line 12.)

Replace the body of `_isNodeModified` with a version that keeps the existing
fast paths but adds a fallback. Use this exact shape:

```dart
bool _isNodeModified(DocumentNode existing, DocumentNode incoming) {
  if (existing.runtimeType != incoming.runtimeType) return true;

  if (existing is TextNode && incoming is TextNode) {
    if (existing.text != incoming.text) return true;
  }

  if (existing is ParagraphNode && incoming is ParagraphNode) {
    if (existing.metadata['blockType'] != incoming.metadata['blockType']) {
      return true;
    }
  }

  if (existing is TaskNode && incoming is TaskNode) {
    if (existing.isComplete != incoming.isComplete) return true;
    if (existing.indent != incoming.indent) return true;
  }

  if (existing is ListItemNode && incoming is ListItemNode) {
    if (existing.indent != incoming.indent) return true;
    if (existing.type != incoming.type) return true;
  }

  return NodeSyncManager._nodeData(existing) !=
      NodeSyncManager._nodeData(incoming);
}
```

The final line replaces the unconditional `return false`. For `TextNode`,
`ParagraphNode`, `TaskNode`, `ListItemNode`, this fallback compares the same
serialization that the early returns already used (and is therefore a no-op
when the early-return conditions don't fire — e.g., a `ParagraphNode` whose
text changed but whose `blockType` didn't: the early `ParagraphNode` branch
compares only blockType, falling through to the serialization compare, which
compares text. Correct.). For `ImageNode`, `DocumentAttachmentNode`,
`HorizontalRuleNode`, `RichLinkNode`, the fallback catches all field changes.

Confirm: indentation 2-space, files use trailing commas per existing style.

**Verify**: `flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart --plain-name "049"`
→ all pass.

**Verify**: `flutter test test/features/notes/`
→ all pass.

**Verify**: `dart analyze lib/features/notes/presentation/controllers/note_editor_controller.dart lib/features/notes/domain/node_sync_manager.dart`
→ no errors.

## Test plan

The 046 plan wrote the characterization test. This plan flips it and adds
two more cases for `RichLinkNode` and `DocumentAttachmentNode`.

- `flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart` → all pass (original 049 flipped + 2 new cases)
- `flutter test test/features/notes/` → all pass

## Done criteria

- [ ] `flutter test test/features/notes/` exits 0
- [ ] `dart analyze lib/features/notes/presentation/controllers/note_editor_controller.dart lib/features/notes/domain/node_sync_manager.dart` exits 0
- [ ] `_nodeData` in `node_sync_manager.dart` is now `static`
- [ ] `_isNodeModified` ends with the `NodeSyncManager._nodeData` comparison fallback; the four explicit type branches remain unchanged
- [ ] `git diff --name-only` shows exactly `node_sync_manager.dart`, `note_editor_controller.dart`, and the test file
- [ ] `plans/README.md` status row for 049 updated to DONE

## STOP conditions

Stop and report back (do not improvise) if:

- `_nodeData` is NOT just `String _nodeData(DocumentNode node)` — e.g., if it
  reads instance state (it shouldn't, per plan verification; but if it does,
  STOP and propose a wrapper static method instead).
- `_nodeData` is already `static` — proceed without the change to that file;
  only the controller needs the import and the fallback line.
- A `RichLinkNode` constructor in the live `super_editor` version requires
  parameters not in `_nodeData`'s JSON shape — read `node_sync_manager.dart:438-447`
  for the exact constructor the repo uses, and use the same args in tests.
- Constructing a `DocumentAttachmentNode` fails — confirm it only needs `id`
  per `attachment_nodes.dart`. If constructor requires more, report.
- The flipped `049` test fails AFTER the fix with a reason unrelated to the
  diff logic (e.g., the `NoteNode` JSON shape for `link` is `'attachment'`
  not `'link'` — `_nodeType` returns `'attachment'` for `AttachmentNode`, which
  is the supertype of `RichLinkNode`; verify via `_nodeType` on line 308 and
  use the matching schema `type` in the test's `NoteNode`).

## Maintenance notes

- Future node types added to the editor (e.g., a `TableNode`) require adding a
  case to `_nodeType` and `_nodeData` in `NodeSyncManager` — the new
  `_isNodeModified` fallback automatically supports them as long as the JSON
  serialization fully captures the diffable state. A reviewer adding a new
  type should verify `_nodeData(newType)` produces different output for any
  state difference.
- The fallback runs `_nodeData` twice per `updateNodesIncrementally` call per
  non-early-return node. For typical note sizes (~50-200 nodes) this is cheap;
  for pathological cases (~5000+ nodes per diff pass) it's still negligible
  compared to the existing `_buildContentSnapshot` iteration that runs on
  every flush. Do NOT pre-optimize.
- A reviewer should scrutinize: did the executor accidentally remove the
  existing explicit branches, eliminating the fast paths? The deletion would
  still pass tests (the fallback covers them) but at a small perf cost. The
  branches must remain.