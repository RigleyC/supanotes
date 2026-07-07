# Plan 052: Stop Mutating `_controller` During `NoteEditor.build`

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat bfebe7e..HEAD -- lib/features/notes/presentation/widgets/note_editor.dart lib/features/notes/presentation/controllers/note_editor_provider.dart`
> If any in-scope file changed since this plan was written (plan 051 may
> land first), compare the "Current state" excerpts against the live code
> before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: MED
- **Depends on**: plans/051-memoize-editor-stylesheet.md (only for line-number stability; safe to run before if 051 hasn't landed)
- **Category**: bug | perf
- **Planned at**: commit `bfebe7e`, 2026-07-06

## Why this matters

`NoteEditor.build` does `final controller = ref.watch(noteEditorControllerProvider(widget.noteId)); _controller = controller;`.
The watch means every provider invalidation schedules a rebuild (cheap),
BUT the assignment mutates `_controller` to whatever the provider last
returned. The provider is `Provider.autoDispose.family`, so if the
controller is disposed and recreated mid-session (e.g., when all listeners
briefly go away during a `NoteEditor` unmount + remount cycle that
`autoDispose` tolerates), the new controller has `document == null`. The
guard at line 211 returns `CircularProgressIndicator()` and never
re-initializes the document — the editor hangs in a perpetual spinner. Worse
than that: `setState` would prompt re-build, but `ref.watch` in `build` with
autoDispose can leave a half-disposed controller cached. The fix is to
remove the redundant watch and use the controller created in `initState`
(and updated via `didUpdateWidget` if `widget.noteId` changes).

## Current state

### Files in scope

- `lib/features/notes/presentation/widgets/note_editor.dart` —
  `_NoteEditorState` and its `build`.
- `lib/features/notes/presentation/controllers/note_editor_provider.dart` —
  reference for the provider definition. **Modify only if a refactor to
  keep the controller alive is necessary**, see Step 3.

### Current code

`note_editor.dart` lines 62-67 (initState — already creates the controller):

```dart
@override
void initState() {
  super.initState();
  _controller = ref.read(noteEditorControllerProvider(widget.noteId));
  if (_controller!.document == null) {
    _controller!.initFromNodes(nodes: widget.nodes, noteId: widget.noteId);
  }
  // ...
}
```

`note_editor.dart` lines 207-217 (build — redundant watch + mutation):

```dart
@override
Widget build(BuildContext context) {
  final controller = ref.watch(noteEditorControllerProvider(widget.noteId));   // ← REMOVE
  _controller = controller;                                                     // ← REMOVE

  if (controller.document == null ||
      controller.editor == null ||
      controller.composer == null) {
    return const Center(child: CircularProgressIndicator());
  }

  _setupControls(context);
  // ...
```

`note_editor.dart` line 233 and 287 — `controller.editor!`,
`controller.composer!`, etc. These read the local `controller`, which is the
just-watched one. After removing the watch, replace with `_controller!`
referencing the field set in initState.

### Provider definition (`note_editor_provider.dart`):

```dart
final noteEditorControllerProvider = Provider.autoDispose
    .family<NoteEditorController, String>((ref, noteId) {
      final userId = ref.watch(currentUserIdProvider)!;
      final controller = NoteEditorController(
        userId: userId,
        database: ref.watch(appDatabaseProvider),
      );
      controller.bind(noteId);
      ref.onDispose(() {
        controller.dispose();
      });
      return controller;
    });
```

`autoDispose` means the controller is disposed when no listeners remain. If
`NoteEditor` briefly unmounts (e.g., during a route transition overlay), the
controller disposes; when `NoteEditor` remounts, `initState` calls
`ref.read(...)` which constructs a fresh controller with `document == null`.
`initState` then calls `initFromNodes` — but only `if
(_controller!.document == null)`, which IS the case for a fresh
controller. So why is the spinner infinite? Two cases:

1. **widget.nodes is empty** AND there's no initializer fallback — the new
   controller has an empty doc, `controller.document!.isEmpty`? Actually
   `initFromNodes` with `nodes: []` results in `MutableDocument.empty()`
   (line 460 in node_sync_manager.dart). So `document != null` — the guard
   passes, and editor renders. Not the case.

2. **During the brief unmount, user's edits are lost** — dispose runs the
   final flush (plan 048), but the new controller has no nodes until the
   stream emits again. If the parent passes the same `widget.nodes` list
   (from its own `combinedNoteEditorStateProvider` cache), `initState` calls
   `initFromNodes` with a STALE snapshot. Worse, if the widget rebuilds DURING
   the unmount-remount overhead, the local `controller = ref.watch(...)`
   catches a new controller that hasn't been initialized yet — `document ==
   null` — returns spinner. `initState` already happened; nothing calls
   `initFromNodes` on the new controller. Spinner forever.

So the bug manifests in the second case. Removing the watch prevents the
build from using a fresh-disposed controller.

### Repository conventions

- Riverpod 3.x conventions per AGENTS.md: "Use `StreamProvider.family` para
  dados... Use `FutureProvider.family` para fetch único." Controllers
  ourselves manage should use `ref.read` in `initState`, NOT `ref.watch` in
  `build`. The `build` method should only `ref.watch` reactive STATE
  providers, not imperative controller providers.
- Existing pattern in repo: look at
  `lib/features/.../controllers/...` for similar controllers. Read the
  `NoteEditorController` setup in `initState` — it uses `ref.read`. Pattern
  is already right in `initState`; just need to remove the bad `ref.watch`
  in `build`.
- Do not add code comments unless asked by the plan.

## Commands you will need

| Purpose          | Command                                                              | Expected on success |
|------------------|----------------------------------------------------------------------|---------------------|
| Static analysis  | `dart analyze lib/features/notes/presentation/widgets/note_editor.dart` | no errors          |
| Run editor tests | `flutter test test/features/notes/presentation/`                   | all pass           |
| Grep             | `Select-String -Path lib/features/notes/presentation/widgets/note_editor.dart -Pattern "ref.watch\(noteEditorControllerProvider"` | no matches |

## Scope

**In scope** (the only files you should modify):
- `lib/features/notes/presentation/widgets/note_editor.dart`
- (optionally) `lib/features/notes/presentation/controllers/note_editor_provider.dart` — only if Step 3's keepAlive is needed; consult STOP conditions

**Out of scope** (do NOT touch):
- `note_editor_controller.dart`, `node_sync_manager.dart` — internal logic
  unchanged.
- Tests in `test/features/notes/presentation/` — they may use
  `ProviderScope` overrides; the behavior of `noteEditorControllerProvider`
  must remain observable. Don't change tests.

## Git workflow

- Branch: `fix/052-stop-mutating-controller-in-build`
- Commit: `fix(editor): use controller from initState, not ref.watched in build`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Replace `ref.watch(...)` + `_controller = controller` with read from `_controller`

Open `lib/features/notes/presentation/widgets/note_editor.dart`. Replace
lines 208-209 and the references downstream:

Original (lines 207-217):

```dart
@override
Widget build(BuildContext context) {
  final controller = ref.watch(noteEditorControllerProvider(widget.noteId));
  _controller = controller;

  if (controller.document == null ||
      controller.editor == null ||
      controller.composer == null) {
    return const Center(child: CircularProgressIndicator());
  }

  _setupControls(context);
```

After:

```dart
@override
Widget build(BuildContext context) {
  final controller = _controller;

  if (controller == null ||
      controller.document == null ||
      controller.editor == null ||
      controller.composer == null) {
    return const Center(child: CircularProgressIndicator());
  }

  _setupControls(context);
```

`_controller` is now nullable; add the `controller == null` check.

### Step 2: Replace remaining `controller.X` references inside `build` with `_controller!`

The body of `build` after line 217 still references the outer `controller`
local (lines 233, 234, 273, 286, 287, 288 — see `controller.editor!`,
`controller.composer!`, `controller.focusNode`). The `controller` local now
has type `NoteEditorController?` after the null check above? Actually no —
after the `if (controller == null || ...) return CircularProgressIndicator()`,
below that block Dart's type promotion kicks in only when `controller` is a
local final. Since `controller` IS a local `final`, the early-return promotes
it to non-null. Confirm by `dart analyze`.

Verify: `controller.editor!` etc. still compile. If Dart can't promote
because the early return condition has multiple `||` clauses, replace
`controller` references with `_controller!` and remove the `final controller`
local entirely:

```dart
@override
Widget build(BuildContext context) {
  final controller = _controller;
  if (controller == null) return const Center(child: CircularProgressIndicator());
  if (controller.document == null ||
      controller.editor == null ||
      controller.composer == null) {
    return const Center(child: CircularProgressIndicator());
  }

  _setupControls(context);

  return AnimatedPadding(
    // ... existing code, all `controller.editor!` references now valid (type promoted)
  );
}
```

Split the null check into two `if`s for clean type promotion. The body stays
as-is using `controller.editor!`, `controller.composer!`, etc.

### Step 3: Handle didUpdateWidget when `widget.noteId` changes

`NoteEditor` currently doesn't handle the case where `widget.noteId`
changes mid-flight (e.g., parent passes a new note id). Find
`didUpdateWidget` (lines 134-158):

```dart
@override
void didUpdateWidget(NoteEditor oldWidget) {
  super.didUpdateWidget(oldWidget);
  _taskComponentBuilder.taskMetadataById = widget.taskMetadata;
  // ...
}
```

Add at the top of `didUpdateWidget`:

```dart
@override
void didUpdateWidget(NoteEditor oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (widget.noteId != oldWidget.noteId) {
    if (!widget.isReadOnly) {
      _controller?.document?.removeListener(_onDocumentChanged);
    }
    _iosController?.dispose();
    _androidController?.dispose();
    _iosController = null;
    _androidController = null;
    _richOps = null;
    _controller = ref.read(noteEditorControllerProvider(widget.noteId));
    if (_controller!.document == null) {
      _controller!.initFromNodes(nodes: widget.nodes, noteId: widget.noteId);
    }
    if (!widget.isReadOnly) {
      _controller!.document?.addListener(_onDocumentChanged);
    }
    _notifyContentChanged();
  }
  _taskComponentBuilder.taskMetadataById = widget.taskMetadata;
  // ... rest of existing didUpdateWidget
}
```

If `widget.noteId` doesn't change in practice (the screen always routes a
fresh `NoteEditor` for each note via `GoRoute`), the executor should
verify this is the only creation site. Look at `note_editor_screen.dart:30-36`:
`NoteEditorScreen` is constructed per-route with a fixed `noteId` from path
param. The router doesn't swap `noteId` — it creates a new screen. So the
parent rebuilds never change `widget.noteId`. The `didUpdateWidget` tweak
is defensive; if confirmed, the executor can SKIP this step entirely.

**To verify**: `grep -rn "NoteEditor(noteId" lib/`. If only
`note_editor_screen.dart` constructs `NoteEditor` and it's always created
fresh on navigation (via `GoRoute.builder`), the `if (widget.noteId !=
oldWidget.noteId)` branch is dead but harmless.

If uncertain, include the defensive code — costs nothing at runtime.

### Step 4: Verify

**Verify**:
```bash
Select-String -Path lib/features/notes/presentation/widgets/note_editor.dart -Pattern "ref.watch\(noteEditorControllerProvider"
```
Expected: no matches.

**Verify**: `dart analyze lib/features/notes/presentation/widgets/note_editor.dart`
→ no errors (type promotion should kick in).

**Verify**: `flutter test test/features/notes/presentation/`
→ all pass.

## Test plan

No new tests. Existing screen-level test passes if controller creation
patterns remain observable. If a test mocks the provider via `ProviderScope`
overrides, the override should still work because `ref.read` in `initState`
goes through the same `ProviderContainer` resolution.

- `flutter test test/features/notes/presentation/note_editor_screen_test.dart` → all pass

## Done criteria

- [ ] `dart analyze lib/features/notes/presentation/widgets/note_editor.dart` exits 0
- [ ] `flutter test test/features/notes/presentation/` exits 0
- [ ] `Select-String` for `ref.watch(noteEditorControllerProvider` in `note_editor.dart` returns no matches
- [ ] `_controller` is set once in `initState` and (optionally) in `didUpdateWidget` for `noteId` change
- [ ] `build` uses the field `_controller`, not `ref.watch`
- [ ] Null-check guard throws or returns spinner if `_controller == null`
- [ ] `git diff --name-only` shows only `note_editor.dart` (unless Step 3 also touched the provider — then it should NOT, see STOP)
- [ ] `plans/README.md` status row for 052 updated to DONE

## STOP conditions

Stop and report back (do not improvise) if:

- `_controller` is not assigned in `initState` (codebase drift) — re-anchor
  on actual setup pattern.
- After removing `ref.watch`, the `autoDispose` family disposes the
  controller between sessions even though `_NoteEditorState` holds a
  reference. This is because Riverpod `autoDispose` keys on listener count,
  not reference holding. If `flutter test test/features/notes/` reveals
  disposal happening mid-session, the fix is to keep the provider alive
  via `ref.onAddListener` or by removing `autoDispose` from
  `noteEditorControllerProvider` per AGENTS.md exceptions list ("auth,
  goRouter, appDatabase, apiClient, authLocalStorage, authRepository,
  syncService, syncState, connectivityMonitor, sessionCache" — note editor
  controller is NOT in that list, but AGENTS.md does say "exceções" — check
  with maintainer before changing provider disposition). STOP and report —
  the executor should NOT silently change `autoDispose` to non-autoDispose
  without aligning with project rules.
- The `didUpdateWidget` `widget.noteId != oldWidget.noteId` defensive block
  requires updating `_taskComponentBuilder` recreation — if
  `CustomTaskComponentBuilder` is `final` (it's `late final` on line 59),
  reassigning requires changing the field. STOP if rearchitecting
  `_NoteEditorState` fields is necessary.
- Plan 051 has landed and shifted the stylesheet cache logic; the
  `_setupControls(context)` call site must remain AFTER the null-guard return
  in `build`. Match the structure.
- If the test `note_editor_screen_test.dart` fails because it relies on
  building the controller via `ref.watch` in `build` to lazy-create it —
  report. The fix is to pre-create the controller in the test setup, not
  re-introduce the bad pattern in `lib/`.

## Maintenance notes

- This plan removes "magic dependency injection" — the controller is now
  created deterministically in `initState`. Tests that need to override the
  controller must do so via `ProviderScope` overrides BEFORE
  `NoteEditorScreen.mounts`, not by re-watching in `build`.
- A reviewer should scrutinize: are there OTHER `ref.watch(noteEditorControllerProvider...)`
  usages in `note_editor.dart`? Check `NoteSuggestionOverlay`, `NoteToolbar`,
  `AttachmentComponentBuilder` — none of these reference the controller
  provider directly (they receive the editor/composer via constructor
  params). Only `NoteEditor.build` did. Confirm via grep.
- If a future plan introduces a per-screen survival (controlling
  `autoDispose` lifetime), revisit this in concert with plan 052.
- Changing `noteEditorControllerProvider`'s `autoDispose` disposition is
  OUT OF SCOPE; the bug-fix side is sufficient. The provider-disposition
  question is a separate AGENTS.md decision.