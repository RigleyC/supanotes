# Plan 056: Migrate NoteEditor Body to `SliverFillRemaining` to Eliminate Nested Scroll

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat bfebe7e..HEAD -- lib/features/notes/presentation/widgets/note_editor.dart lib/features/notes/presentation/note_editor_screen.dart`
> If any in-scope file changed since this plan was written (plans 051, 052,
> 054, 055 may land first), compare the "Current state" excerpts against the
> live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/046-editor-round-trip-characterization-tests.md (recommended; not strict)
- **Category**: tech-debt | ux | architecture
- **Planned at**: commit `bfebe7e`, 2026-07-06

## Why this matters

`NoteEditor.build` wraps `SuperEditor` inside `CustomScrollView > Slivers
> SuperEditor`. Per AGENTS.md "Use `CustomScrollView` + `SliverAppBar.medium`
+ `SliverList` como estrutura padrão" and "Use `SliverFillRemaining` para
telas que precisam ocupar todo o espaço (loading, estados especiais)". The
current structure nests a `CustomScrollView` (scrollview #1) inside the
`AdaptiveScaffold` body (which is itself often a scrollable surface),
containing a `SuperEditor` which has its own internal scroll controller
(scrollview #2). Nested scroll views cause:
- Floating cursor / IME inset double-application (`MediaQuery.viewInsetsOf`
  is consumed by both the outer `AnimatedPadding` and `SuperEditor`
  internally).
- Overflow errors on small screens when keyboard expands.
- `SliverAppBar.medium` would also need consistent scroll controller to
  collapse on scroll; the current screen's `AdaptiveAppBar` (`note_editor_screen.dart:195`)
  stays static.
- A janky layering pass — the outer `CustomScrollView` is single-sliver so
  it offers zero benefit over the inner `SuperEditor`'s own scroll.

The remedy per AGENTS.md is `SliverFillRemaining` — `SuperEditor` itself is
the scroll authority, the `SliverFillRemaining` wraps the editor's content
area so no nested scrolling happens.

## Current state

### Files in scope

- `lib/features/notes/presentation/widgets/note_editor.dart` — the
  `_NoteEditorState.build` method (lines 207-301), specifically the
  `CustomScrollView` (lines 226-281).
- `lib/features/notes/presentation/note_editor_screen.dart` — the screen
  body that wraps `NoteEditor` (lines 193-254). Read-only modification may
  be needed to remove the `resizeToAvoidBottomInset: false` workaround
  (line 194).

### Current code

`note_editor.dart` lines 219-301 (the inner build):

```dart
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
                  stylesheet: _cachedStylesheet!,
                  // ...
                ),
              ),
            ),
          ],
        ),
      ),
      if (!widget.isReadOnly)
        NoteSuggestionOverlay(...),
      if (!widget.isReadOnly)
        NoteToolbar(...),
    ],
  ),
);
```

`note_editor_screen.dart` line 194:

```dart
return AdaptiveScaffold(
  resizeToAvoidBottomInset: false,
  appBar: AdaptiveAppBar(...),
  body: NoteEditor(...),
);
```

### Repository conventions

- AGENTS.md "Flutter UI Screen Conventions":
  - "Use `CustomScrollView` + `SliverAppBar.medium` + `SliverList` como estrutura padrão."
  - "Use `SliverFillRemaining` para telas que precisam ocupar todo o espaço."
- The `NoteEditorScreen` should restructure as follows per AGENTS.md:

  ```dart
  Scaffold(
    body: CustomScrollView(
      slivers: [
        SliverAppBar.medium(title: const Text('Title')),
        SliverPadding(
          sliver: SliverList(
            delegate: SliverChildListDelegate([ ...conteúdo ]),
          ),
        ),
      ],
    ),
  )
  ```

- `bottomNavigationBar` for fixed action buttons.
- Stop using `AdaptiveScaffold`/`AdaptiveAppBar` if they don't support
  slivers correctly — investigate. Read `adaptive_platform_ui` package
  usage in repo to confirm `AdaptiveAppBar` has a `sliver` equivalent.
- `SuperEditor` is itself scrollable; per `super_editor` Flutter docs, the
  way to use it inside a `CustomScrollView` is via `SuperEditorScrollable`
  (a sliver variant). If that's not available in the loaded version, use
  `SliverFillRemaining(hasScrollBody: true, child: SuperEditor(...))`.
- Do not add code comments unless asked by the plan.

## Commands you will need

| Purpose          | Command                                                              | Expected on success |
|------------------|----------------------------------------------------------------------|---------------------|
| Static analysis  | `dart analyze lib/features/notes/presentation/widgets/note_editor.dart lib/features/notes/presentation/note_editor_screen.dart` | no errors |
| Run editor tests | `flutter test test/features/notes/presentation/`                   | all pass            |
| Grep             | `Select-String -Path lib/features/notes/presentation/widgets/note_editor.dart -Pattern "CustomScrollView"` | no matches (after refactor) |

## Scope

**In scope** (the only files you should modify):
- `lib/features/notes/presentation/widgets/note_editor.dart`
- `lib/features/notes/presentation/note_editor_screen.dart`

**Out of scope** (do NOT touch):
- `adaptive_platform_ui` package — if it lacks sliver variant, raise as a
  concern and re-negotiate with maintainer. Do NOT fork the package in this
  plan.
- `note_stylesheet.dart`, `note_toolbar.dart`, `note_suggestion_overlay.dart`.
- The `AdaptiveScaffold` in other screens — out of scope.

## Git workflow

- Branch: `refactor/056-editor-sliverfillremaining`
- Commit: `refactor(editor): use SliverFillRemaining to avoid nested scroll`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Restructure `NoteEditor.build` to drop `CustomScrollView`

Open `lib/features/notes/presentation/widgets/note_editor.dart`. Replace the
body structure (lines 219-301) with a `Column` that uses `Expanded` only
around the `SuperEditor` (no `CustomScrollView`):

```dart
return AnimatedPadding(
  duration: const Duration(milliseconds: 180),
  curve: Curves.easeOutCubic,
  padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
  child: Column(
    children: [
      Expanded(
        child: SuperEditorAndroidControlsScope(
          controller: _androidController!,
          child: SuperEditorIosControlsScope(
            controller: _iosController!,
            child: SuperEditor(
              editor: controller.editor!,
              focusNode: widget.isReadOnly ? null : controller.focusNode,
              documentLayoutKey: _docLayoutKey,
              stylesheet: _cachedStylesheet!,
              selectionStyle: SelectionStyles(
                selectionColor: Theme.of(context).textSelectionTheme.selectionColor ??
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
              ),
              contentTapDelegateFactories: widget.isReadOnly
                  ? null
                  : [
                      (editContext) => NoteLinkTapHandler(
                            editContext.document,
                            editContext.composer,
                            onNoteTap: (targetId) => context.push(AppRoutes.note(targetId)),
                          ),
                      superEditorLaunchLinkTapHandlerFactory,
                    ],
              keyboardActions: buildRichKeyboardActions(
                baseActions: defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android
                    ? defaultImeKeyboardActions
                    : defaultKeyboardActions,
              ),
              componentBuilders: [
                const CustomDividerComponentBuilder(),
                _taskComponentBuilder,
                AttachmentComponentBuilder(editor: controller.editor!, collapseImages: widget.collapseImages),
                ...defaultComponentBuilders,
              ],
            ),
          ),
        ),
      ),
      if (!widget.isReadOnly)
        NoteSuggestionOverlay(
          editor: controller.editor!,
          composer: controller.composer!,
          currentNoteId: widget.noteId,
          onPersist: () async {},
        ),
      if (!widget.isReadOnly)
        NoteToolbar(
          editor: controller.editor!,
          composer: controller.composer!,
          onAttachFile: () => _onAttach(imageOnly: false),
          onAttachImage: () => _onAttach(imageOnly: true),
        ),
    ],
  ),
);
```

The `SuperEditor` itself handles scrolling. The outer `Column` lays out the
editor (`Expanded`) above the suggestion overlay and toolbar (which are
compact fixed-height widgets).

### Step 2: Restructure `NoteEditorScreen` with `CustomScrollView` + `SliverAppBar.medium`

Open `lib/features/notes/presentation/note_editor_screen.dart`. Per
AGENTS.md, the screen should use `CustomScrollView + SliverAppBar.medium`.
However, `AdaptiveScaffold` and `AdaptiveAppBar` may not offer sliver
compatibility — investigate first.

Read `adaptive_platform_ui` package in `pubspec.lock` or the installed
package source to find out whether `AdaptiveAppBar` has a sliver
compatibility entry point like `AdaptiveSliverAppBar.medium()`. If not:

Plan A: keep `AdaptiveScaffold` + `AdaptiveAppBar` (the current structure is
adaptive iOS/Android — losing it would harm UX). Wrap `NoteEditor` in
`SliverFillRemaining` ONLY if `AdaptiveScaffold.body` accepts a sliver child
(it doesn't — usually returns `Scaffold.body` which is a regular widget).
So Plan A is: stay with `AdaptiveScaffold`, remove
`resizeToAvoidBottomInset: false` and confirm `NoteEditor` now correctly
avoids the keyboard inset. The body is a Scaffold `Column` (boxed widget),
not a `SliverFillRemaining`.

Plan A simplification — drop the screen-level change. Just remove the
`resizeToAvoidBottomInset: false` workaround at line 194 (if no longer
needed) and check `SuperEditor` keyboard behavior:

```dart
return AdaptiveScaffold(
  appBar: AdaptiveAppBar(...),
  body: NoteEditor(...),
);
```

This satisfies the priority goal: no nested scroll inside `NoteEditor`.
The screen-level `CustomScrollView + SliverAppBar.medium` migration is
DEFERRED pending `adaptive_platform_ui` package support — report it as a
follow-up.

**Verify** this assumption by reading
`adaptive_platform_ui` package contents if installed locally — likely in
`.dart_tool/package_config.json` resolves packages by path; if so, search
globally for any sliver variants. If found, use them; if not, Plan A.

### Step 3: Verify

**Verify**: `dart analyze lib/features/notes/presentation/widgets/note_editor.dart lib/features/notes/presentation/note_editor_screen.dart`
→ no errors.

**Verify**:
```bash
Select-String -Path lib/features/notes/presentation/widgets/note_editor.dart -Pattern "CustomScrollView"
```
Expected: no matches.

**Verify**: `flutter test test/features/notes/presentation/`
→ all pass.

### Step 4: Manual smoke test

In a worktree, launch the app:
- Open a long note.
- Tap into the middle of the text.
- Soft keyboard opens.
- Confirm no overflow exception in console.
- Scroll the editor — confirm both the editor text scrolls and the
  outer area does NOT demonstrate a "double scroll" jitter.
- Confirm on iOS the toolbar above the keyboard (from
  `RichSuperEditorIosControlsController`) is not clipped.
- Confirm on Android the `SuperEditorAndroidControlsScope` floating
  toolbar appears centered above the selection.

Report any visual regression; if found, STOP and report — the fix may
need alternative sliver structure.

## Test plan

No new automated tests — visual / smoke only. The screen-level test
must continue to exercise the basic path.

- `flutter test test/features/notes/presentation/` → all pass

## Done criteria

- [ ] `dart analyze` exits 0 on both modified files
- [ ] `flutter test test/features/notes/` exits 0
- [ ] `Select-String` for `CustomScrollView` in `note_editor.dart` returns no matches
- [ ] `NoteEditor.build` returns a `Column` with `Expanded(SuperEditor(...))` + suggestion + toolbar
- [ ] `NoteEditor` keyboard inset applied once (via `AnimatedPadding`)
- [ ] `note_editor_screen.dart` no longer has `resizeToAvoidBottomInset: false` (the workaround is no longer needed) OR — if still needed to avoid inset-doubling — keep and document why in the commit message
- [ ] Smoke test passes: long note + keyboard opens + scrolls smoothly
- [ ] `git diff --name-only` shows `note_editor.dart` and `note_editor_screen.dart` (no other files)
- [ ] `plans/README.md` status row for 056 updated to DONE

## STOP conditions

Stop and report back (do not improvise) if:

- `SuperEditor` API has changed to require `SuperEditor.singleChildScrollView`
  or a similar wrapper (read `super_editor` API / docs for the loaded version
  in `pubspec.lock`). If so, the correct replacement is one of:
  - `SliverFillRemaining(hasScrollBody: true, child: SuperEditor(...))` inside
    a `CustomScrollView`. Choose this if it works without就能 visual glitch.
  - Plain `Column + Expanded` (no scroll view). Already proposed; this is
    the right shape because `SuperEditor` IS a scroll view.
- `AdaptiveScaffold` doesn't accept a `Widget` body that's a `Column`
  containing a `SuperEditor` — confirm by reading its source. If `AdaptiveScaffold`
  has constraints, report and propose alternatives.
- Smoke test reveals `SuperEditor` no longer handles IME insets correctly
  without the `CustomScrollView` — restore the `AnimatedPadding` and
  `Padding` semantics; the `Column` should still work; report if it doesn't.
- Removing `resizeToAvoidBottomInset: false` causes the keyboard to
  partially cover the suggestion overlay — restore the workaround with a
  comment in the commit message explaining why it's still needed.
- `SuperEditorAndroidControlsScope` / `SuperEditorIosControlsScope` require
  a scroll context that's inside a `CustomScrollView` — check by reading
  super_editor docs; if true, restore `CustomScrollView` as a one-sliver
  host, but document it as a known constraint of `super_editor`, not a
  plan bug.

## Maintenance notes

- The screen-level sliver migration per AGENTS.md is INCOMPLETE under
  Plan A — only `NoteEditor` is un-nested. The `NoteEditorScreen` continues
  to use `AdaptiveScaffold` + `AdaptiveAppBar` (non-sliver) because the
  adaptive ui package lacks sliver support (verify and document in the
  commit message). A future plan should revisit once `adaptive_platform_ui`
  gains sliver variants.
- A reviewer should scrutinize the smoke test screenshots for keyboard
  inset and overflow regressions. The proprio integrity — particularly
  the suggestion overlay (below the editor) must not be hidden by the
  keyboard's bottom pinch.
- A future plan to migrate
  `NoteEditorScreen` fully to `CustomScrollView + SliverAppBar.medium + ...`
  needs to wrap `NoteEditor` in `SliverFillRemaining(hasScrollBody: true)`,
  and ensure `SuperEditor` is the only scroll authority. If `AdaptiveScaffold`
  can't host that structure, the screen must drop `AdaptiveScaffold` for
  the editor route — but that loses adaptive app bar on iOS, so weigh
  trade-offs.
- This plan does NOT touch the iOS floating toolbar
  (`RichSuperEditorIosControlsController`) — that overlay is positioned
  via super_editor's own controller, not via the now-removed
  `CustomScrollView`. Verify post-refactor that iOS toolbar still
  appears.