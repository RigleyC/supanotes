# Note Editor Keyboard and Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace manual note-editor keyboard geometry with Super Editor's `KeyboardPanelScaffold`, while preserving all compact toolbar and formatting behavior.

**Architecture:** `NoteEditorScreen` owns the ordinary AppBar boundary. `NoteEditor` owns `SoftwareKeyboardController`, `KeyboardPanelController<NoteEditorPanel>`, and the IME connection notifier. The compact toolbar requests panel transitions, while a dedicated formatting panel renders in place of the keyboard.

**Tech Stack:** Flutter, Dart, Riverpod host screen, Super Editor `0.3.0-dev.52` at commit `3bb857bc423240b61dc0fb799f3c269e71feb24a`, Flutter widget tests.

## Global Constraints

- Do not add a dependency.
- Do not preserve the manual keyboard-layout path as a fallback.
- Do not change document data, task behavior, synchronization, attachments, or formatting commands.
- Keep `SuperEditor` as the owner of document scrolling and caret auto-scroll.
- Keep unrelated worktree changes untouched.
- Use ASD-STE100 Simplified Technical English in code comments and documentation.

---

### Task 1: Separate the compact toolbar from the formatting panel

**Files:**
- Create: `lib/features/notes/editor/presentation/widgets/note_formatting_panel.dart`
- Modify: `lib/features/notes/editor/presentation/widgets/note_toolbar.dart`
- Modify: `lib/features/notes/editor/presentation/widgets/note_toolbar_menus.dart`
- Test: `test/features/notes/presentation/widgets/note_toolbar_test.dart`

**Interfaces:**
- Produces: `NoteToolbar({required Editor editor, required MutableDocumentComposer composer, required VoidCallback onOpenFormatting, ...})`.
- Produces: `NoteFormattingPanel({required Editor editor, required MutableDocumentComposer composer, required DocumentSelection? selection, required VoidCallback onClose, required VoidCallback onReturnToTyping})`.
- Removes: `NoteToolbar.focusNode`, `NoteToolbar.softwareKeyboardController`, and `NoteToolbar.onFormattingModeChanged`.

- [ ] **Step 1: Add a failing compact-toolbar ownership test**

Add a test that pumps `NoteToolbar` with `onOpenFormatting`, taps the `Abrir formatação` control, and verifies that the callback runs without replacing the toolbar with `_FormattingToolbarPanel`:

```dart
testWidgets('requests the formatting panel without expanding itself', (tester) async {
  var requests = 0;
  await pumpToolbar(
    tester,
    toolbar: NoteToolbar(
      editor: editor,
      composer: composer,
      onOpenFormatting: () => requests++,
    ),
  );

  await tester.tap(find.bySemanticsLabel('Abrir formatação'));
  await tester.pump();

  expect(requests, 1);
  expect(find.byType(NoteToolbar), findsOneWidget);
  expect(find.byType(NoteFormattingPanel), findsNothing);
});
```

- [ ] **Step 2: Run the focused test and confirm that it fails**

Run:

```powershell
flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart --plain-name "requests the formatting panel without expanding itself"
```

Expected: compile failure because `onOpenFormatting` and `NoteFormattingPanel` do not exist.

- [ ] **Step 3: Extract the formatting presentation**

Move the existing formatting UI and its selection-derived state into `NoteFormattingPanel`. Keep command execution in `NoteEditorCommands` and reuse the existing menu widgets. Give the panel explicit `onClose` and `onReturnToTyping` callbacks. Do not read keyboard insets or manage focus in this widget.

- [ ] **Step 4: Make `NoteToolbar` compact-only**

Remove `_ToolbarMode`, `_selectionForFormatting`, `_focusBeforeFormatting`, `_keyboardWasOpenBeforeFormatting`, `_openFormatting`, `_closeFormatting`, `PopScope`, and bottom padding derived from `MediaQuery.viewInsets`. Replace the format button callback with `widget.onOpenFormatting`. Keep the current compact visual treatment and attachment callbacks.

- [ ] **Step 5: Run toolbar tests**

Run:

```powershell
flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart
```

Expected: all toolbar and formatting command tests pass after tests that target the old expanded mode are moved to `NoteFormattingPanel`.

- [ ] **Step 6: Commit the presentation split**

```powershell
git add -- lib/features/notes/editor/presentation/widgets/note_toolbar.dart lib/features/notes/editor/presentation/widgets/note_toolbar_menus.dart lib/features/notes/editor/presentation/widgets/note_formatting_panel.dart test/features/notes/presentation/widgets/note_toolbar_test.dart
git commit -m "refactor(editor): separate formatting panel"
```

---

### Task 2: Give `NoteEditor` ownership of keyboard and panel transitions

**Files:**
- Modify: `lib/features/notes/editor/presentation/widgets/note_editor.dart`
- Modify: `test/features/notes/presentation/widgets/note_editor_layout_test.dart`

**Interfaces:**
- Produces: `enum NoteEditorPanel { formatting }`.
- Owns: `ValueNotifier<bool> _isImeConnected`.
- Owns: `KeyboardPanelController<NoteEditorPanel> _keyboardPanelController` created with `_softwareKeyboardController`.
- Consumes: `NoteToolbar.onOpenFormatting` and `NoteFormattingPanel` from Task 1.

- [ ] **Step 1: Add failing panel-transition tests**

Add tests that mount `NoteEditor`, establish a non-null composer selection, and verify these transitions:

```dart
await tester.tap(find.bySemanticsLabel('Abrir formatação'));
await tester.pumpAndSettle();

expect(find.byType(NoteToolbar), findsOneWidget);
expect(find.byType(NoteFormattingPanel), findsOneWidget);
expect(controller.composer.selection, initialSelection);
```

Add a second assertion that invokes system back while formatting is open:

```dart
await tester.binding.handlePopRoute();
await tester.pumpAndSettle();

expect(find.byType(NoteFormattingPanel), findsNothing);
expect(find.byType(NoteEditor), findsOneWidget);
```

- [ ] **Step 2: Run the new tests and confirm that they fail**

Run:

```powershell
flutter test test/features/notes/presentation/widgets/note_editor_layout_test.dart
```

Expected: the formatting panel assertions fail because `NoteEditor` still uses a `Column` and an expanding toolbar.

- [ ] **Step 3: Add the Super Editor keyboard scaffold**

Replace the outer editable `Column` with:

```dart
KeyboardPanelScaffold<NoteEditorPanel>(
  controller: _keyboardPanelController,
  isImeConnected: _isImeConnected,
  contentBuilder: (context, openPanel) => Column(
    children: [
      Expanded(child: editorViewport),
      NoteSuggestionOverlay(...),
    ],
  ),
  toolbarBuilder: (context, openPanel) => NoteToolbar(
    editor: controller.editor,
    composer: controller.composer,
    onOpenFormatting: () => _openFormattingPanel(controller.composer.selection),
    onAttachFile: ...,
    onAttachImage: ...,
  ),
  keyboardPanelBuilder: (context, openPanel) => switch (openPanel) {
    NoteEditorPanel.formatting => NoteFormattingPanel(...),
    null => const SizedBox.shrink(),
  },
)
```

Pass `_isImeConnected` to `SuperEditor`. Set `toolbarVisibility` to `KeyboardToolbarVisibility.visible` after the panel controller attaches so the compact toolbar remains visible with no keyboard.

- [ ] **Step 4: Implement explicit transitions**

Capture the current `DocumentSelection?` before `showKeyboardPanel(NoteEditorPanel.formatting)`. Use `hideKeyboardPanel()` for a neutral close. For return to typing, request the editor focus and call `showSoftwareKeyboard()`. Use the open-panel state to set `SuperEditorImePolicies(openKeyboardOnSelectionChange: openPanel == null)`.

- [ ] **Step 5: Dispose keyboard resources**

In `dispose`, call `_softwareKeyboardController.detach()`, dispose `_keyboardPanelController`, and dispose `_isImeConnected`. Remove `_formattingToolbarOpen` and its disposal.

- [ ] **Step 6: Run editor and toolbar tests**

Run:

```powershell
flutter test test/features/notes/presentation/widgets/note_editor_layout_test.dart test/features/notes/presentation/widgets/note_toolbar_test.dart
```

Expected: all tests pass and the selection remains stable across panel transitions.

- [ ] **Step 7: Commit keyboard-panel ownership**

```powershell
git add -- lib/features/notes/editor/presentation/widgets/note_editor.dart test/features/notes/presentation/widgets/note_editor_layout_test.dart
git commit -m "refactor(editor): adopt keyboard panel scaffold"
```

---

### Task 3: Correct the full-screen AppBar and safe-area boundary

**Files:**
- Modify: `lib/features/notes/editor/presentation/note_editor_screen.dart`
- Modify: `test/features/notes/presentation/note_editor_screen_test.dart`

**Interfaces:**
- Consumes: `NoteEditor` keyboard ownership from Task 2.
- Produces: one `KeyboardScaffoldSafeArea` above the screen `Scaffold`.

- [ ] **Step 1: Add a failing full-screen geometry test**

Mount the real screen shell with a fake keyboard inset and assert that the editor starts at or below the AppBar bottom in both keyboard states:

```dart
final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
final editorTop = tester.getTopLeft(find.byType(SuperEditor)).dy;
expect(editorTop, greaterThanOrEqualTo(appBarBottom));
```

Repeat after setting `tester.view.viewInsets = const FakeViewPadding(bottom: 300)`. Also assert that `Scaffold.resizeToAvoidBottomInset` is `false` and `extendBodyBehindAppBar` is `false`.

- [ ] **Step 2: Run the full-screen test and confirm that it fails**

Run:

```powershell
flutter test test/features/notes/presentation/note_editor_screen_test.dart
```

Expected: geometry or property assertion fails because the body currently extends behind the AppBar.

- [ ] **Step 3: Apply the screen boundary**

Wrap the screen `Scaffold` with `KeyboardScaffoldSafeArea`. Set `resizeToAvoidBottomInset: false` and remove `extendBodyBehindAppBar: true`. Remove the redundant top `SafeArea` around the body. Keep top visual treatment inside the AppBar instead of changing the editor viewport.

- [ ] **Step 4: Keep the top of the editor viewport clean**

Keep any top visual treatment inside the `_NoteEditorAppBar` with a surface color or AppBar-owned decoration, instead of changing the editor viewport.

- [ ] **Step 5: Run screen and editor layout tests**

Run:

```powershell
flutter test test/features/notes/presentation/note_editor_screen_test.dart test/features/notes/presentation/widgets/note_editor_layout_test.dart
```

Expected: the editor remains below the AppBar and the caret remains above the compact toolbar on Android and iOS.

- [ ] **Step 6: Commit screen geometry**

```powershell
git add -- lib/features/notes/editor/presentation/note_editor_screen.dart test/features/notes/presentation/note_editor_screen_test.dart
git commit -m "fix(editor): align viewport with app bar"
```

---

### Task 4: Focused verification and Windows debug review

**Files:**
- Modify if needed: `walkthrough.md`
- Verify only: all files changed in Tasks 1-3

**Interfaces:**
- Consumes: completed editor layout.
- Produces: validation evidence and the project walkthrough entry.

- [ ] **Step 1: Format changed Dart files**

```powershell
dart format lib/features/notes/editor/presentation/widgets/note_editor.dart lib/features/notes/editor/presentation/widgets/note_toolbar.dart lib/features/notes/editor/presentation/widgets/note_formatting_panel.dart lib/features/notes/editor/presentation/note_editor_screen.dart test/features/notes/presentation/widgets/note_editor_layout_test.dart test/features/notes/presentation/widgets/note_toolbar_test.dart test/features/notes/presentation/note_editor_screen_test.dart
```

- [ ] **Step 2: Run focused static analysis**

```powershell
flutter analyze lib/features/notes/editor/presentation/widgets/note_editor.dart lib/features/notes/editor/presentation/widgets/note_toolbar.dart lib/features/notes/editor/presentation/widgets/note_formatting_panel.dart lib/features/notes/editor/presentation/note_editor_screen.dart
```

Expected: no issues.

- [ ] **Step 3: Run the focused regression set**

```powershell
flutter test test/features/notes/presentation/widgets/note_editor_layout_test.dart test/features/notes/presentation/widgets/note_toolbar_test.dart test/features/notes/presentation/note_editor_screen_test.dart
```

Expected: all tests pass.

- [ ] **Step 4: Run the Windows app in debug**

```powershell
flutter run -d windows
```

Review one note with enough lines to scroll. Confirm keyboard or IME-equivalent focus, compact toolbar placement, formatting-panel replacement, selection preservation, return to typing, route back handling, AppBar background, and caret visibility. Record any platform limitation: Windows does not reproduce a mobile software keyboard, so Android and iOS keyboard geometry remains covered by widget tests.

- [ ] **Step 5: Update the walkthrough without overwriting unrelated content**

Append a concise section to `walkthrough.md` that lists the architecture change, focused commands, results, and Windows limitation. Preserve all existing local edits.

- [ ] **Step 6: Review the final diff**

```powershell
git diff --check
git status --short
git diff --stat HEAD~3..HEAD
```

Confirm that no task, sync, persistence, or unrelated progressive-fade files entered the implementation commits.

- [ ] **Step 7: Commit validation documentation if changed**

```powershell
git add -- walkthrough.md
git commit -m "docs(editor): record keyboard toolbar migration"
```
