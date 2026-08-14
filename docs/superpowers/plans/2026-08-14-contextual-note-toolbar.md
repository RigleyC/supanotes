# Contextual Note Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the note formatting panel with a focus-aware, contextual toolbar that keeps the caret in the Super Editor viewport.

**Architecture:** Keep `KeyboardScaffoldSafeArea`, `Scaffold(resizeToAvoidBottomInset: false)`, and `KeyboardPanelScaffold` as the owner of keyboard, toolbar, and safe-area geometry. Remove all formatting-panel paths. `NoteToolbar` derives its content from composer selection and active nodes. `NoteEditor` controls toolbar visibility from its focus node.

**Tech Stack:** Flutter, Super Editor `0.3.0-dev.52`, `motor`, flutter_test.

## Global Constraints

- Keep `notes.document` and REST/OT operations as the canonical task data path.
- Use existing `NoteEditorCommands` for every document mutation.
- Keep `KeyboardScaffoldSafeArea` above the screen and keep `resizeToAvoidBottomInset: false`.
- Do not add a custom caret scroll controller or a keyboard panel fallback.
- Toolbar is hidden without editor focus and visible with editor focus.
- Toolbar shell keeps one position and height. Only its action content animates.
- Use `MaterialSpringMotion.standardEffectsFast()` and honor `MediaQuery.disableAnimations`.
- Do not retain `NoteFormattingPanel`, `NoteEditorPanel`, or the `Aa` action.

---

### Task 1: Remove formatting-panel ownership and add focus visibility

**Files:**
- Modify: `lib/features/notes/editor/presentation/widgets/note_editor.dart:18-410`
- Delete: `lib/features/notes/editor/presentation/widgets/note_formatting_panel.dart`
- Modify: `test/features/notes/presentation/widgets/note_editor_layout_test.dart:78-304`

**Interfaces:**
- Consumes: `KeyboardPanelController<Object>`, `KeyboardToolbarVisibility`, and `NoteEditorController.focusNode`.
- Produces: `NoteEditor` with no formatting-panel state and a toolbar visible only while `focusNode.hasFocus`.

- [ ] **Step 1: Write failing focus-visibility tests**

Delete tests that search for `NoteFormattingPanel`, `Abrir formatação`, `Fechar formatação`, and `Voltar a digitar`. Add:

```dart
testWidgets('hides the toolbar until the editor receives focus', (tester) async {
  await pumpEditor(tester);
  expect(find.byType(NoteToolbar), findsNothing);

  controller.focusNode.requestFocus();
  await tester.pump();

  expect(find.byType(NoteToolbar), findsOneWidget);
});

testWidgets('hides the toolbar after editor focus is lost', (tester) async {
  await pumpEditor(tester);
  controller.focusNode.requestFocus();
  await tester.pump();
  controller.focusNode.unfocus();
  await tester.pump();

  expect(find.byType(NoteToolbar), findsNothing);
});
```

Keep the Android and iOS caret geometry test. Focus the editor and assert the toolbar appears before comparing `DocumentKeys.caret` to the toolbar top.

- [ ] **Step 2: Run the focused test and verify failure**

Run:

```powershell
flutter test test/features/notes/presentation/widgets/note_editor_layout_test.dart
```

Expected: FAIL because the toolbar is forced visible and old panel behavior remains.

- [ ] **Step 3: Simplify `NoteEditor`**

Replace the panel type and panel methods with:

```dart
final _keyboardPanelController = KeyboardPanelController<Object>(
  _softwareKeyboardController,
);
```

Attach a focus listener with the session, detach it on session replacement and disposal, and schedule its initial update after the keyboard scaffold attaches:

```dart
void _syncToolbarVisibility() {
  if (!_keyboardPanelController.hasDelegate) return;
  _keyboardPanelController.toolbarVisibility = controller.focusNode.hasFocus
      ? KeyboardToolbarVisibility.visible
      : KeyboardToolbarVisibility.hidden;
}
```

Delete `NoteEditorPanel`, `_formattingSelection`, `_openFormattingPanel`, `_closeFormattingPanel`, `_returnToTyping`, and `_showToolbarWhenAttached`. Keep normal IME policies.

Keep the existing `PopScope > Column > Expanded > SuperEditorAndroidControlsScope > SuperEditor` content subtree and `NoteSuggestionOverlay`. Change its builder parameter to `_` and use `canPop: true`, because no panel can intercept system back. Build the scaffold with no reachable keyboard panel:

```dart
KeyboardPanelScaffold<Object>(
  controller: _keyboardPanelController,
  isImeConnected: _isImeConnected,
  toolbarBuilder: (context, _) => NoteToolbar(
    editor: controller.editor,
    composer: controller.composer,
    onAttachFile: () => controller.pickAndAttachFile(imageOnly: false),
    onAttachImage: () => controller.pickAndAttachFile(imageOnly: true),
  ),
  keyboardPanelBuilder: (_, _) => const SizedBox.shrink(),
)
```

- [ ] **Step 4: Delete the obsolete panel**

Delete `note_formatting_panel.dart`. Remove its imports from production and test files. Do not copy panel callbacks or panel widgets.

- [ ] **Step 5: Verify the lifecycle change**

Run:

```powershell
flutter test test/features/notes/presentation/widgets/note_editor_layout_test.dart
flutter analyze lib/features/notes/editor/presentation/widgets/note_editor.dart test/features/notes/presentation/widgets/note_editor_layout_test.dart
```

Expected: PASS. No layout test references the deleted panel and caret geometry passes on Android and iOS configurations.

- [ ] **Step 6: Commit**

```powershell
git add lib/features/notes/editor/presentation/widgets/note_editor.dart test/features/notes/presentation/widgets/note_editor_layout_test.dart
git rm lib/features/notes/editor/presentation/widgets/note_formatting_panel.dart
git commit -m "refactor(editor): remove formatting panel"
```

### Task 2: Implement normal and contextual toolbar actions

**Files:**
- Modify: `lib/features/notes/editor/presentation/widgets/note_toolbar.dart:1-114`
- Delete: `lib/features/notes/editor/presentation/widgets/note_toolbar_menus.dart`
- Modify: `test/features/notes/presentation/widgets/note_toolbar_test.dart:1-1700`

**Interfaces:**
- Consumes: `Editor`, `MutableDocumentComposer`, `editorSelectionNodes`, `NoteEditorCommands`, and `ToolbarButton`.
- Produces: `NoteToolbar` that derives `_ToolbarMode.normal` or `_ToolbarMode.contextual` from selection and active nodes.

- [ ] **Step 1: Write failing action-set and command tests**

Replace panel harnesses with a `NoteToolbar` harness. Test normal and contextual content:

```dart
expect(find.bySemanticsLabel('Título 1'), findsOneWidget);
expect(find.bySemanticsLabel('Inserir divisor'), findsOneWidget);
expect(find.bySemanticsLabel('Negrito'), findsNothing);

composer.setSelectionWithReason(selectedTextSelection);
await tester.pump();

expect(find.bySemanticsLabel('Negrito'), findsOneWidget);
expect(find.bySemanticsLabel('Tachado'), findsOneWidget);
expect(find.bySemanticsLabel('Lista com marcadores'), findsOneWidget);
expect(find.bySemanticsLabel('Task'), findsOneWidget);
```

Add cases for a collapsed caret in `ListItemNode` and `TaskNode`. Assert indent and outdent are disabled for a paragraph and enabled for list/task. Tap and assert the command result for bold, italic, strikethrough, bulleted list, numbered list, task, indent, and outdent.

- [ ] **Step 2: Run and verify failure**

```powershell
flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart
```

Expected: FAIL because `NoteToolbar` still exposes `Abrir formatação`.

- [ ] **Step 3: Derive toolbar mode and reuse command paths**

Convert `NoteToolbar` to `StatefulWidget`. Listen to `composer.selectionNotifier` and `editor.context.document`; detach the exact listeners in `didUpdateWidget` and `dispose`.

Use:

```dart
bool get _isContextual {
  final selection = composer.selection;
  if (selection == null) return false;
  if (!selection.isCollapsed) return true;
  final node = editor.context.document.getNodeById(selection.extent.nodeId);
  return node is ListItemNode || node is TaskNode;
}
```

Normal order: H1, H2, H3, quote, divider, image, attachment.

Contextual order: bold, italic, strikethrough, bulleted list, numbered list, task, outdent, indent.

Keep mutations in `NoteEditorCommands`:

```dart
NoteEditorCommands.toggleInlineAttribution(editor, composer, boldAttribution);
NoteEditorCommands.convertToListItem(editor, composer, ListItemType.unordered);
NoteEditorCommands.convertToTask(editor, composer);
NoteEditorCommands.indentSelectedBlocks(editor, composer);
NoteEditorCommands.unindentSelectedBlocks(editor, composer);
```

Inline controls are disabled for collapsed selection. Indent controls are enabled only when the selected nodes contain a list item or task.

- [ ] **Step 4: Remove panel-only menu code**

Move any required list option enum and list controls into `note_toolbar.dart`. Delete the `part 'note_toolbar_menus.dart'` relation and delete `note_toolbar_menus.dart`. Do not leave panel-only classes.

- [ ] **Step 5: Verify actions**

```powershell
flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart
```

Expected: PASS. Paragraph, selected-text, list, and task states expose exactly their defined action sets and all command tests pass.

- [ ] **Step 6: Commit**

```powershell
git add lib/features/notes/editor/presentation/widgets/note_toolbar.dart test/features/notes/presentation/widgets/note_toolbar_test.dart
git rm lib/features/notes/editor/presentation/widgets/note_toolbar_menus.dart
git commit -m "feat(editor): add contextual toolbar actions"
```

### Task 3: Animate toolbar content inside a stable shell

**Files:**
- Modify: `lib/features/notes/editor/presentation/widgets/note_toolbar.dart`
- Modify: `test/features/notes/presentation/widgets/note_toolbar_test.dart`

**Interfaces:**
- Consumes: `_ToolbarMode` from Task 2 and current `ToolbarButton` Motor primitives.
- Produces: one toolbar shell whose active action set changes with a Motor effects spring.

- [ ] **Step 1: Write failing transition and semantics tests**

Change a paragraph selection from collapsed to expanded and assert:

```dart
final shellBefore = tester.getTopLeft(
  find.byKey(const ValueKey('note-toolbar-shell')),
);
composer.setSelectionWithReason(selectedTextSelection);
await tester.pump();

expect(
  tester.getTopLeft(find.byKey(const ValueKey('note-toolbar-shell'))),
  shellBefore,
);
expect(find.bySemanticsLabel('Negrito'), findsOneWidget);
expect(find.bySemanticsLabel('Título 1'), findsNothing);
```

Add a `MediaQuery(disableAnimations: true, ...)` case that exposes only the contextual semantic set after one pump.

- [ ] **Step 2: Run and verify failure**

```powershell
flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart
```

Expected: FAIL because there is no stable shell key or mode transition.

- [ ] **Step 3: Add the Motor transition**

Keep the existing `ClipRRect`, blur, decoration, padding, and horizontal scroll container. Give the outer visual container:

```dart
key: const ValueKey('note-toolbar-shell'),
```

Add private `_ContextualToolbarContent`. It receives `ToolbarMode mode`, owns a `SingleMotionController` with:

```dart
const MaterialSpringMotion.standardEffectsFast()
```

Outgoing controls reduce opacity and scale. Incoming controls use opacity, scale, and a short horizontal translation. If animations are disabled, set the controller to the final value and mount only the current row. Do not animate shell height, bottom offset, safe area, keyboard, or the `KeyboardPanelScaffold` overlay.

- [ ] **Step 4: Verify transition and analyzer**

```powershell
flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart
flutter analyze lib/features/notes/editor/presentation/widgets/note_toolbar.dart test/features/notes/presentation/widgets/note_toolbar_test.dart
```

Expected: PASS. Shell geometry stays unchanged and only the current action set is accessible.

- [ ] **Step 5: Commit**

```powershell
git add lib/features/notes/editor/presentation/widgets/note_toolbar.dart test/features/notes/presentation/widgets/note_toolbar_test.dart
git commit -m "feat(editor): animate contextual toolbar"
```

### Task 4: Verify the integrated editor contract

**Files:**
- Modify: `test/features/notes/presentation/widgets/note_editor_layout_test.dart`
- Modify: `test/features/notes/presentation/note_editor_screen_test.dart` only if its safe-area assertion needs adjustment.

**Interfaces:**
- Consumes: focus-aware visibility from Task 1 and toolbar modes from Tasks 2 and 3.
- Produces: regression coverage for screen geometry and no stale formatting-panel references.

- [ ] **Step 1: Add the integrated sequence**

In the editor harness, cover:

```dart
expect(find.byType(NoteToolbar), findsNothing);
controller.focusNode.requestFocus();
await tester.pump();
expect(find.bySemanticsLabel('Título 1'), findsOneWidget);

controller.composer.setSelectionWithReason(selectedTextSelection);
await tester.pump();
expect(find.bySemanticsLabel('Tachado'), findsOneWidget);
expect(find.bySemanticsLabel('Título 1'), findsNothing);
```

Run the simulated 300px keyboard inset loop after this sequence and retain the assertion that the caret bottom is at or above the toolbar top on Android and iOS.

- [ ] **Step 2: Run integrated tests**

```powershell
flutter test test/features/notes/presentation/widgets/note_editor_layout_test.dart test/features/notes/presentation/note_editor_screen_test.dart
```

Expected: PASS. Toolbar visibility follows focus, contextual actions follow selection, and the caret remains above the toolbar.

- [ ] **Step 3: Run source hygiene checks**

```powershell
rg -n "NoteFormattingPanel|NoteEditorPanel|Abrir formatação|Voltar a digitar|Fechar formatação" lib test
git diff --check
```

Expected: `rg` returns no production or test references and `git diff --check` returns no whitespace errors.

- [ ] **Step 4: Run full verification**

```powershell
flutter test
flutter analyze
```

Expected: both commands pass. Record any pre-existing warning separately from test or analyzer failures.

- [ ] **Step 5: Perform device checks before release**

Run the app on one Android device and one iOS device. Check toolbar focus visibility, keyboard resize without an app-bar gap, caret visibility at the end of a long note, list/task contextual controls, and an unchanged toolbar shell during every content transition.

- [ ] **Step 6: Commit regression coverage**

```powershell
git add test/features/notes/presentation/widgets/note_editor_layout_test.dart test/features/notes/presentation/note_editor_screen_test.dart
git commit -m "test(editor): cover contextual toolbar viewport"
```
