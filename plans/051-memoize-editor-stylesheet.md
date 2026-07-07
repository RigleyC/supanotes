# Plan 051: Memoize the Editor Stylesheet per (Theme, hideCompleted)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat bfebe7e..HEAD -- lib/features/notes/presentation/widgets/note_editor.dart lib/features/notes/presentation/note_stylesheet.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: perf
- **Planned at**: commit `bfebe7e`, 2026-07-06

## Why this matters

`NoteEditor.build` constructs a fresh `noteStylesheet(...)` on every build —
every keystroke, every selection change, every IME event. Each construction
calls `defaultStylesheet.copyWith(...)` (which clones the immutable rules
list) and instantiates 14 `_StyleRule` closures. The `SuperEditor` widget
sees a new `Stylesheet` identity each time and re-evaluates styling on the
entire document. Typing lag in long notes is partly attributable to this. The
fix is a 3-field cache keyed on the only two inputs that affect the
stylesheet: `theme.colorScheme` and `widget.hideCompleted`. Stays valid for
the life of the `_NoteEditorState`.

## Current state

### Files in scope

- `lib/features/notes/presentation/widgets/note_editor.dart` — the
  `_NoteEditorState` class and its `build` method (lines 53-301).
- `lib/features/notes/presentation/note_stylesheet.dart` — the
  `noteStylesheet` factory; the executor does NOT need to modify this file
  (it's pure and cheap to call once per cache miss).

### Current code

`note_editor.dart` lines 53-60:

```dart
class _NoteEditorState extends ConsumerState<NoteEditor> {
  NoteEditorController? _controller;
  final _docLayoutKey = GlobalKey();
  RichSuperEditorIosControlsController? _iosController;
  SuperEditorAndroidControlsController? _androidController;
  RichCommonEditorOperations? _richOps;
  late CustomTaskComponentBuilder _taskComponentBuilder;
```

No stylesheet cache fields.

`note_editor.dart` lines 207-242 (build method context — focus on stylesheet
construction):

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

  return AnimatedPadding(
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SuperEditorAndroidControlsScope(
                controller: _androidController!,
                child: SuperEditorIosControlsScope(
                  controller: _iosController!,
                  child: SuperEditor(
                    editor: controller.editor!,
                    focusNode: widget.isReadOnly ? null : controller.focusNode,
                    documentLayoutKey: _docLayoutKey,
                    stylesheet: noteStylesheet(
                      context,
                      hideCompleted: widget.hideCompleted,
                    ),
                    // ...
```

### Repository conventions

- Cache-instance-fields pattern is fine — `_iosController`, `_richOps`,
  `_androidController` are all instance-side caches already (lines 56-58).
  The convention for one-time setup with theme-bound identity is similar to
  `/shared/widgets/` patterns; the executor can verify by reading any shared
  widget that caches a derived object.
- Flutter `Theme.of(context)` returns a `ThemeData` whose `colorScheme` is the
  identity we care about. Caching on `ThemeData` would over-invalidate (font
  scale, etc.) — use `ColorScheme`.
- Do not add code comments unless asked by the plan.
- Note: plan 052 separately removes the redundant `ref.watch` /
  `_controller = controller` lines on lines 208-209. THIS plan does NOT touch
  those lines — coordinate by running in sequence (051 first, 052 next).

## Commands you will need

| Purpose         | Command                                                                                  | Expected on success |
|-----------------|------------------------------------------------------------------------------------------|---------------------|
| Static analysis | `dart analyze lib/features/notes/presentation/widgets/note_editor.dart`                 | no errors           |
| Run editor tests | `flutter test test/features/notes/presentation/`                                       | all pass            |
| Grep            | `Select-String -Path lib/features/notes/presentation/widgets/note_editor.dart -Pattern "noteStylesheet\("` | exactly 1 match (the cache-miss call site) |

## Scope

**In scope** (the only files you should modify):
- `lib/features/notes/presentation/widgets/note_editor.dart`

**Out of scope** (do NOT touch):
- `note_stylesheet.dart` — the factory stays pure.
- The `ref.watch` / `_controller = controller` lines (208-209) — those are
  plan 052.
- Any other file.

## Git workflow

- Branch: `perf/051-memoize-editor-stylesheet`
- Commit: `perf(editor): cache stylesheet by theme+hideCompleted identity`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add cache fields to `_NoteEditorState`

Open `lib/features/notes/presentation/widgets/note_editor.dart`. In the
state class (lines 53-60), add three fields:

```dart
class _NoteEditorState extends ConsumerState<NoteEditor> {
  NoteEditorController? _controller;
  final _docLayoutKey = GlobalKey();
  RichSuperEditorIosControlsController? _iosController;
  SuperEditorAndroidControlsController? _androidController;
  RichCommonEditorOperations? _richOps;
  late CustomTaskComponentBuilder _taskComponentBuilder;

  Stylesheet? _cachedStylesheet;
  ColorScheme? _cachedColorScheme;
  bool? _cachedHideCompleted;
```

### Step 2: Compute or reuse the stylesheet in `build`

Inside `build`, AFTER the null-check return (lines 211-215) and AFTER
`_setupControls(context)` (line 217), insert the cache check:

```dart
_setupControls(context);

final theme = Theme.of(context);
if (_cachedStylesheet == null ||
    _cachedHideCompleted != widget.hideCompleted ||
    !identical(_cachedColorScheme, theme.colorScheme)) {
  _cachedHideCompleted = widget.hideCompleted;
  _cachedColorScheme = theme.colorScheme;
  _cachedStylesheet = noteStylesheet(
    context,
    hideCompleted: widget.hideCompleted,
  );
}
```

Then change the `stylesheet:` argument to `SuperEditor` (line ~238) from:

```dart
stylesheet: noteStylesheet(
  context,
  hideCompleted: widget.hideCompleted,
),
```

to:

```dart
stylesheet: _cachedStylesheet!,
```

### Step 3: Verify

**Verify**: `dart analyze lib/features/notes/presentation/widgets/note_editor.dart`
→ no errors.

**Verify**:
```bash
Select-String -Path lib/features/notes/presentation/widgets/note_editor.dart -Pattern "noteStylesheet\("
```
Expected: exactly 1 match — inside the cache-miss block in `build`.

**Verify**: `flutter test test/features/notes/presentation/`
→ all pass.

## Test plan

No new tests. The editor's screen-level test (`note_editor_screen_test.dart`)
already exercises the `build` path with a non-null controller — it should
still pass after this refactor since the stylesheet is identical, just cached.
Confirm by running it.

- `flutter test test/features/notes/presentation/note_editor_screen_test.dart` → all pass

## Done criteria

- [ ] `dart analyze lib/features/notes/presentation/widgets/note_editor.dart` exits 0
- [ ] `flutter test test/features/notes/presentation/` exits 0
- [ ] Exactly one `noteStylesheet(` call site in `note_editor.dart` (inside the cache-miss block)
- [ ] Cache fields `_cachedStylesheet`, `_cachedColorScheme`, `_cachedHideCompleted` exist in `_NoteEditorState`
- [ ] Theme reuse uses `identical(_cachedColorScheme, theme.colorScheme)` (identity check, not `==`, to avoid `ColorScheme.==` if it's overridden to compare values; identity is the cheaper and correct invariant — `Theme.of(context)` returns a stable `ThemeData` for unchanged theme, and the `colorScheme` field is the same object as long as theme didn't change)
- [ ] `git diff --name-only` shows only `note_editor.dart`
- [ ] `plans/README.md` status row for 051 updated to DONE

## STOP conditions

Stop and report back (do not improvise) if:

- `_NoteEditorState` no longer has fields at lines 53-60 (refactor happened);
  place the cache alongside other cache fields wherever they now live.
- `noteStylesheet` signature differs (e.g., takes a `Brightness` parameter);
  use whatever signature is current and key the cache on the equivalents.
- `ColorScheme` doesn't expose an identity check easily — `identical(a, b)` is
  the right Dart primitive; it works on any reference type, no need for
  `==`. Use `identical` as planned.
- If `widget.hideCompleted` is no longer a `bool` field on `NoteEditor`
  (e.g., was renamed to `hideCompletedTasks`), update the cache key
  accordingly — STOP and report if signature change.
- Plan 052 has already landed — its removal of `ref.watch`/`_controller` lines
  may have shifted line numbers; the cache-miss block must still be placed
  AFTER `_setupControls(context)` and BEFORE the `return AnimatedPadding(`
  call. Match by code shape, not line numbers.
- `Theme.of(context)` should be called once per build; if you find the code
  already retrieves it elsewhere in `build`, reuse the existing local
  `theme` variable rather than calling `Theme.of(context)` twice.

## Maintenance notes

- The cache is per-state-instance. The state instance lives for the
  NoteEditor widget's lifetime; if the parent re-creates `NoteEditor`
  (e.g., switching notes by changing the `noteId` prop), the cache is
  rebuilt. That's acceptable because the `noteId` swap is rare relative to
  keystrokes, and the rebuild cost is tiny.
- A reviewer should scrutinize: any place that toggles `hideCompleted` in
  real-time (e.g., the popup menu in `note_editor_screen.dart`) now triggers a
  stylesheet rebuild — that's the desired behavior, no further action needed.
- Adding new stylesheet parameters to `noteStylesheet(...)` requires adding
  the matching cache key field and the equality check; otherwise stale
  stylesheets will be served after the parent passes new parameter values.
- The `identical(_cachedColorScheme, theme.colorScheme)` is critical — `==`
  would compare value-equality and could over-correct. Don't "improve" to
  `==` without understanding the cost.