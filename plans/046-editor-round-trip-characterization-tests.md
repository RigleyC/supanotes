# Plan 046: Editor Round-Trip Characterization Tests

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat bfebe7e..HEAD -- lib/features/notes/domain/node_sync_manager.dart lib/features/notes/presentation/controllers/note_editor_controller.dart pubspec.yaml`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `bfebe7e`, 2026-07-06

## Why this matters

The editor's sync loop (`MutableDocument → NodeSyncManager → Drift → Drift stream
→ noteNodesProvider → NoteEditor.didUpdateWidget → updateNodesIncrementally →
MutableDocument`) has had ~18 regression fix commits in the last sprint ("fix words
disappering", "fix editor crashing and syncing", "fix perf issues"). It is the
most bug-prone area of the app and has zero characterization tests. Plans 047
through 049 fix real correctness bugs here; without this plan, any of those fixes
is a gamble — and the next regression will reopen for the same reason. This plan
locks in current behavior so bugs fixed in 047-049 stay fixed.

## Current state

### Files in scope and their role

- `lib/features/notes/domain/node_sync_manager.dart` — listens to
  `MutableDocument`, debounces 500ms, batches ops into a Drift transaction via
  `_writeLock`. Exposes `locallyDirtyNodeIds`, `suspendSync`, `resumeSync`,
  `documentFromNodes`, `createNodeFromSchema`. (lines 39-77 for core, 126-179
  for drain, 451-510 for deserialization.)
- `lib/features/notes/presentation/controllers/note_editor_controller.dart` —
  owns `MutableDocument`, `Editor`, `MutableDocumentComposer`, and
  `NodeSyncManager`. `updateNodesIncrementally` (lines 146-189) diffs incoming
  `NoteNode` stream against current document and emits `EditRequest`s.
- `lib/core/database/database.dart` — Drift `AppDatabase`. Construct via
  `AppDatabase(NativeDatabase.memory())` for tests.
- `pubspec.yaml` — already depends on `flutter_test`, `drift`,
  `super_editor`. Test file capability exists.

### Code shape (what the executor is locking in)

#### `_drainQueue` — current behavior on flush (node_sync_manager.dart:180-279)

Ops queued in `_pendingOps` drain via `_db.transaction`. For each op:
- `InsertOp` → computes position via `_calculatePositionForInsert`,
  inserts `noteNodes` companion, plus `tasks` companion if `TaskNode`.
- `UpdateOp` → preserves existing `position`, upserts companion.
- `MoveOp` → recomputes position, writes only `position` + `isDirty`.
- `DeleteOp` → writes `deletedAt` + `isDirty` on `noteNodes` AND `tasks`.

After all ops: writes `notes.content/excerpt/updatedAt/isDirty` via
`_flushNoteExcerptFromSnapshot`.

**Current bug locked here (will be fixed by 048)**: `_drainQueue` is async and
called unawaited in `dispose()` (line 709). Tests must assert this is currently
racy, so 048 can prove the fix.

#### `updateNodesIncrementally` — current behavior (note_editor_controller.dart:146-189)

1. Suspends `NodeSyncManager`.
2. Computes `incomingIds` set.
3. For each node in doc not in `incomingIds`: `DeleteNodeRequest`.
4. For each `incoming` (in order): if `existingNode == null` →
   `InsertNodeAtIndexRequest`. Else if `dirtyIds.contains(incoming.id)` → SKIP
   (local pending edit, DB stale). Else if `_isNodeModified` returns true →
   `ReplaceNodeRequest`.
5. Executes all requests, resumes sync.

**Current bug locked here (will be fixed by 047)**: Step 3 deletes nodes without
checking `locallyDirtyNodeIds`. Tests must assert this currently nukes a
just-typed node when the stream emits from a non-local source.

**Current bug locked here (will be fixed by 049)**: `_isNodeModified` (lines
191-214) only inspects `TextNode`, `ParagraphNode`, `TaskNode`, `ListItemNode`.
For `ImageNode`, `DocumentAttachmentNode`, `HorizontalRuleNode`, `RichLinkNode`,
returns `false`. Tests must assert this currently ignores remote updates to
images / link previews / dividers.

### Repository conventions

- Test framework: `flutter_test`. Existing pattern to model after:
  `test/features/notes/presentation/note_editor_screen_test.dart` — uses
  `ProviderScope`, `MaterialApp`, fakes repositories. Read it before writing.
- Database tests pattern: use `NativeDatabase.memory()` (drift in-memory).
- Drift is sync-by-default for in-memory queries; some streams need
  `await Future.delayed(...)` to let watch streams emit. See pattern in
  `test/` for any existing Drift stream test.

## Commands you will need

| Purpose        | Command                                   | Expected on success |
|----------------|-------------------------------------------|---------------------|
| Run tests      | `flutter test test/features/notes/domain/node_sync_manager_test.dart` | all pass |
| Run all notes tests | `flutter test test/features/notes/`  | all pass            |
| Static analysis | `dart analyze lib/features/notes/domain/node_sync_manager.dart test/features/notes/domain/node_sync_manager_test.dart` | no errors |

## Scope

**In scope** (the only files you should modify):
- `test/features/notes/domain/node_sync_manager_test.dart` — create
- `test/features/notes/presentation/controllers/note_editor_controller_test.dart` — create
- `test/features/notes/_helpers/test_note_database.dart` — shared helper, create

**Out of scope** (do NOT touch):
- Any file under `lib/`. Do NOT fix bugs found while writing tests — flag them
  in the test names as " characterization of known bug, fix in plan 047/048/049"
  but keep the test asserting the *current* (buggy) behavior. Once 047-049 land,
  those assertions will be flipped with a follow-up commit; the helper is what
  lets them flip in one place.
- Existing tests. Don't modify `note_editor_screen_test.dart` or
  `note_editor_link_test.dart`.

## Git workflow

- Branch: `tests/046-editor-round-trip-characterization`
- Commit per test group (sync side, controller side). Conventional Commits:
  `test(notes): characterize NodeSyncManager flush behavior` etc.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Create the in-memory test database helper

Create `test/features/notes/_helpers/test_note_database.dart`:

```dart
import 'package:drift/native.dart';

import 'package:supanotes/core/database/database.dart';

/// In-memory AppDatabase for tests. Caller is responsible for calling
/// `.close()` at end of test (or use a tearDown).
AppDatabase createTestDatabase() {
  return AppDatabase(NativeDatabase.memory());
}
```

Run: `dart analyze test/features/notes/_helpers/test_note_database.dart`
Expected: no errors. If `AppDatabase` constructor signature differs, adjust
the import path — read `lib/core/database/database.dart` first.

### Step 2: NodeSyncManager — insert/update/move/delete round-trip

Create `test/features/notes/domain/node_sync_manager_test.dart`:

Test group `NodeSyncManager flush round-trip`. For each test, spin up
`createTestDatabase()`, build a `MutableDocument` with given nodes, wire a
`NodeSyncManager`, drive document edits, then `await _writeLock` (expose via
`flushNow()` test helper if needed — but try `db.customSelect('SELECT ...')` to
read rows directly after a `Future.delayed(Duration(milliseconds: 600))`).

Cases:
1. **Insert**: start empty doc, insert a paragraph — assert `noteNodes` table
   has one row with matching `type`, decode `data` JSON and assert text.
2. **Update**: insert a paragraph, debounce, then change its text —
   `_drainQueue` produces an `UpdateOp`; assert DB row's `data.text` updated,
   `updatedAt` changed, `isDirty = true`.
3. **Move**: insert 3 paragraphs, swap the first and last positions by
   `MoveNodeRequest` — assert DB `position` column was recomputed by
   `_calculatePositionForMove` and the moved node's position sits between its
   new neighbors.
4. **Delete**: insert a paragraph, then delete via `DeleteNodeRequest` —
   assert DB row still exists (NOT physically removed), with `deletedAt != null`
   and `isDirty = true`.
5. **Task insert produces both `noteNodes` and `tasks` rows**: insert a
   `TaskNode`, assert both tables have a row with matching id, the `tasks` row
   has `status = 'open'` / `status = 'done'` matching `isComplete`.
6. **Debounce coalescing**: insert a node, immediately change its text 3 times
   within the 500ms window — assert only one `noteNodes` insert + one update
   happen in the DB (or a single upsert), confirming `_pendingOps` batching.
7. **suspendSync / resumeSync**: call `suspendSync()`, mutate doc, wait 600ms,
   assert NO DB row. `resumeSync()`, mutate again, assert row written.
8. **Note excerpt is updated**: after any flush, `notes.content` equals the
   plaintext snapshot and `notes.excerpt` is non-empty (per
   `deriveNoteExcerpt`).

For each test, name and document the assertion purpose. Use
`expect(actual, equals(expected))`. Do NOT assert against
`locallyDirtyNodeIds` directly unless you can show it changes synchronously.

**Verify**: `flutter test test/features/notes/domain/node_sync_manager_test.dart`
→ all 8 tests pass.

### Step 3: NoteEditorController — updateNodesIncrementally integration

Create `test/features/notes/presentation/controllers/note_editor_controller_test.dart`:

Test group `updateNodesIncrementally`. Construct `NoteEditorController` with
an in-memory `AppDatabase`, call `initFromNodes(nodes: [], noteId: 'n1')`,
then drive `updateNodesIncrementally(incomingNodes)`.

Cases:
1. **Add a node not yet in doc**: incoming has 1 paragraph with id 'p1', doc
   empty. After call: doc has 1 node, 'p1', text matches.
2. **Remove a node missing from incoming**: doc has 'p1', incoming empty.
   After call: doc has 0 nodes.
3. **Replace text on existing paragraph**: doc has 'p1' with text 'A',
   incoming has 'p1' with text 'B'. After call: doc has 'p1' with text 'B'.
4. **Locally-dirty paragraph is protected from text overwrite**: insert 'p1'
   in doc via `editor.execute([InsertNodeAtIndexRequest])`, manually mark
   `_nodeSyncManager.locallyDirtyNodeIds.add('p1')` (this may require exposing
   it for tests — use `@visibleForTesting` if necessary, do NOT modify the
   production logic). Then call `updateNodesIncrementally` with 'p1' having a
   different text. **Assertion should confirm the CURRENT BUG**: the text
   currently DOES get overwritten on the dirty-node protection path because the
   protection only kicks in via `_isNodeModified` returning false — but
   **wait**, re-read lines 172-173 of note_editor_controller.dart:
   `if (dirtyIds.contains(incoming.id)) continue;` — that DOES skip the
   replacement. The bug is in the *deletion* path (Step 3 above). So this test
   should assert the dirty paragraph **stays** in the doc with its local text
   (current correct behavior). This is the test of bug 047 unrelated to this
   case.
5. **Locally-dirty paragraph survives stream-side deletion (CURRENT BUG)**:
   insert paragraph 'p1' with text 'fresh' in doc via
   `editor.execute([InsertNodeAtIndexRequest])`. Mark
   `locallyDirtyNodeIds.add('p1')`. Call `updateNodesIncrementally([])` (an
   empty incoming list — represents a sync where 'p1' has not yet been flushed
   to the DB but the stream emitted without it). **Assert the current buggy
   behavior**: `doc.getNodeById('p1')` returns `null` (deletion has happened).
   Name the test
   `test('BUG 047: locally-dirty paragraph is deleted by stale stream emission')`
   so reviewers grep for it. When plan 047 lands, flip the assertion to
   `expect(node, isNotNull)`.
6. **ImageNode update is currently ignored (BUG 049)**: insert
   `ImageNode(id: 'i1', imageUrl: 'oldurl')` directly into the doc
   (`editor.execute([InsertNodeAtIndexRequest])`). Call
   `updateNodesIncrementally([NoteNode(id: 'i1', type: 'image',
   data: '{"url":"newurl","alt":""}')])`. Assert the current buggy behavior:
   `doc.getNodeById('i1')` is an `ImageNode` whose `imageUrl == 'oldurl'`
   (ignored). Name it `test('BUG 049: ImageNode remote updates are ignored')`.
   When plan 049 lands, flip assertion.

**Verify**: `flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart`
→ all pass. The ones prefixed `BUG 04X` are testing CURRENT (broken)
behavior; the executor of plan 047/048/049 will flip them as part of those
plans. **Do NOT flip them here**.

### Step 4: dispose timing (BUG 048 characterization)

In the same controller test file, add:

```dart
test('BUG 048: dispose does not await final flush — last 500ms of edits lost', () async {
  final db = createTestDatabase();
  final controller = NoteEditorController(userId: 'u1', database: db);
  controller.bind('n1');
  // Initialize with an existing note row first (seed notes table), see Step 1.
  controller.initFromNodes(nodes: [], noteId: 'n1');
  controller.editor!.execute([
    InsertNodeAtIndexRequest(nodeIndex: 0, newNode: ParagraphNode(id: 'p1', text: AttributedText('last words'))),
  ]);
  // Don't wait. Dispose immediately.
  controller.dispose();
  // Trigger any pending timers
  await Future.delayed(const Duration(milliseconds: 50));
  final rows = await db.noteNodes().get();
  // Current behavior: row may or may not exist (race). Assert it does NOT
  // exist or exists-but-data is wrong, documenting the bug. Pick whichever
  // the live code produces. Run the test once to see which assertion holds,
  // then name it:
  // 'BUG 048: dispose does not await final flush'
  expect(rows.any((r) => r.id == 'p1'), isFalse,
      reason: 'The debounce timer was cancelled mid-flush during dispose. '
              'Plan 048 makes this assertion true by waiting.');
});
```

You may need to insert a `notes` row first (FK constraint). Read
`lib/features/notes/data/notes_repository.dart`'s create flow if constraint
fires. Use `db.into(db.notes).insert(NotesCompanion.insert(...))` with all
required fields.

**Verify**: `flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart`
→ passes.

## Test plan

- Run: `flutter test test/features/notes/` → all pass.
- All tests with names prefixed `BUG 04X:` are intentional characterization of
  known bugs (to be flipped by plans 047, 048, 049).
- `dart analyze test/features/notes/` → no warnings or errors.

## Done criteria

- [ ] `flutter test test/features/notes/domain/node_sync_manager_test.dart` exits 0, all 8 flush cases pass.
- [ ] `flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart` exits 0, all cases pass (including the `BUG 04X` characterization ones).
- [ ] `dart analyze test/features/notes/` exits 0.
- [ ] No files under `lib/` modified (`git status --short lib/` empty).
- [ ] All `BUG 04X` tests left asserting CURRENT broken behavior (NOT fixed in this plan).
- [ ] `plans/README.md` status row for 046 updated to DONE.

## STOP conditions

Stop and report back (do not improvise) if:

- The code at `note_editor_controller.dart:146-189` or
  `node_sync_manager.dart:126-179` doesn't match the excerpts above
  (the codebase has drifted since this plan was written).
- `AppDatabase` constructor refuses `NativeDatabase.memory()` — read
  `lib/core/database/database.dart` and the existing tests in
  `test/features/notes/` before reporting; the executor should not modify the
  constructor signature.
- `MutableDocument` API differs from what's shown in `super_editor` imports —
  re-read `node_sync_manager.dart:451-510` for the exact constructor calls the
  repo uses, and mirror them.
- Constructing a `TaskNode` / `ImageNode` fails for missing required parameters
  — read their usages in `node_sync_manager.dart:472-509` and match.
- The existing `note_editor_screen_test.dart` uses a pattern fundamentally
  different from `ProviderScope` overrides — report and propose the existing
  test pattern instead.
- After reading the live code, you discover plan 047/048/049 has already been
  merged — do NOT flip the `BUG 04X` tests yourself; report back.

## Maintenance notes

- Future regression fixes in the editor sync loop MUST add or extend a test in
  these files. Reviewers should reject fixes that don't.
- When 047/048/049 land, the executor of those plans must grep for
  `'BUG 047'`, `'BUG 048'`, `'BUG 049'` in this test file and flip the
  assertions to assert the FIXED behavior. They must NOT delete the test.
- Adding a new node type to serialization (in `NodeSyncManager._nodeFromData`)
  requires a new round-trip case here in `node_sync_manager_test.dart`.
- Do not refactor `NodeSyncManager._drainQueue` without running this test
  suite first. The `_pendingOps` batching is load-bearing for the
  debounce-coalescing test.