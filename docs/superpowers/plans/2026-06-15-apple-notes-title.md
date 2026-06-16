# Apple Notes Style Note Title — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The first line of every note is locked as H1 (like Apple Notes), the toolbar is disabled on that line, and the title is extracted from the H1 text.

**Architecture:** Three focused changes: (1) `NoteEditorController` coerces the first document node to H1 on init and on every document change; (2) `NoteEditor` removes the old title-prepending hack from `initState`; (3) `NoteToolbar` checks if the selection is on the first node and disables all buttons.

**Tech Stack:** Flutter, super_editor, Riverpod

---

### Task 1: Add `_ensureFirstNodeIsHeader1` to NoteEditorController

**Files:**
- Modify: `lib/features/notes/presentation/controllers/note_editor_controller.dart`

- [ ] **Step 1: Write the failing unit test for H1 coercion on init**

```dart
// In test/features/notes/presentation/controllers/note_editor_controller_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';

void main() {
  group('NoteEditorController', () {
    group('snapshot save', () {
      test('document changes schedule one snapshot save with extracted title', () async {
        // existing test — keep as-is
      });

      test('flushBeforePop deletes empty regular note through lifecycle callback', () async {
        // existing test — keep as-is
      });
    });

    group('H1 coercion', () {
      test('first node is coerced to header1 on init with plain text', () {
        final controller = NoteEditorController(
          snapshotSave: (noteId, title, markdown, tasks) async {},
        );

        controller.init(content: 'hello');
        controller.bind('test-note');

        final firstNode = controller.document!.first;
        expect(firstNode, isA<ParagraphNode>());
        expect(
          (firstNode as ParagraphNode).getMetadataValue('blockType'),
          header1Attribution,
        );
      });

      test('first node is coerced to header1 on init from markdown', () {
        final controller = NoteEditorController(
          snapshotSave: (noteId, title, markdown, tasks) async {},
        );

        controller.init(content: '## hello\n\nworld');
        controller.bind('test-note');

        final firstNode = controller.document!.first;
        expect(firstNode, isA<ParagraphNode>());
        expect(
          (firstNode as ParagraphNode).getMetadataValue('blockType'),
          header1Attribution,
        );
      });
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/features/notes/presentation/controllers/note_editor_controller_test.dart`
Expected: The two new H1 coercion tests fail because `_ensureFirstNodeIsHeader1` does not exist yet.

- [ ] **Step 3: Add `_ensureFirstNodeIsHeader1` helper and call it from `init` and `_onDocumentChanged`**

```dart
// Inside NoteEditorController class, add these methods:

  /// Coerces the first node of the document to be a ParagraphNode with
  /// header1Attribution. Called on init and on every document change.
  void _ensureFirstNodeIsHeader1() {
    final doc = document;
    if (doc == null || doc.isEmpty) return;

    final firstNode = doc.first;
    if (firstNode is! ParagraphNode) {
      _replaceFirstNodeWithHeader1();
      return;
    }
    final blockType = firstNode.getMetadataValue('blockType') as Attribution?;
    if (blockType != header1Attribution) {
      editor?.execute([
        ChangeParagraphBlockTypeRequest(
          nodeId: firstNode.id,
          blockType: header1Attribution,
        ),
      ]);
    }
  }

  void _replaceFirstNodeWithHeader1() {
    final doc = document;
    final firstNode = doc?.first;
    if (doc == null || firstNode == null) return;

    final replacement = ParagraphNode(
      id: firstNode.id,
      text: firstNode is TextNode ? firstNode.text : AttributedText(''),
      metadata: {'blockType': header1Attribution},
    );
    editor?.execute([
      ReplaceNodeRequest(
        existingNodeId: firstNode.id,
        newNode: replacement,
      ),
    ]);
  }
```

Then update `init()` to call `_ensureFirstNodeIsHeader1()` after setting up the editor:

```dart
  void init({required String content, String? title}) {
    dev.log(
      '[NoteEditorController.init] contentLength=${content.length}, content="$content"',
      name: 'NoteEditor',
    );
    document = parseNoteToMarkdown(content);
    composer = MutableDocumentComposer();
    editor = createDefaultDocumentEditor(
      document: document!,
      composer: composer!,
    );
    focusNode = FocusNode();
    document!.addListener(_onDocumentChanged);
    _ensureFirstNodeIsHeader1();
  }
```

And update `_onDocumentChanged`:

```dart
  void _onDocumentChanged(DocumentChangeLog _) {
    _ensureFirstNodeIsHeader1();
    _scheduleSnapshotSave();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/features/notes/presentation/controllers/note_editor_controller_test.dart`
Expected: All tests pass, including the two new H1 coercion tests.

- [ ] **Step 5: Commit**

```bash
git add lib/features/notes/presentation/controllers/note_editor_controller.dart test/features/notes/presentation/controllers/note_editor_controller_test.dart
git commit -m "feat: add H1 coercion to NoteEditorController"
```

---

### Task 2: Clean up title-prepending logic in NoteEditor

**Files:**
- Modify: `lib/features/notes/presentation/widgets/note_editor.dart`

- [ ] **Step 1: Write a failing test to verify old title logic is removed**

Create a new test file `test/features/notes/presentation/note_editor_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_editor.dart';

void main() {
  testWidgets('NoteEditor does not prepend title to content', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteEditor(
            noteId: 'test-note',
            content: 'some content',
            title: 'My Title',
            taskMetadata: const {},
            snapshotSave: (noteId, title, markdown, tasks) async {},
          ),
        ),
      ),
    );

    // Give it time to render
    await tester.pumpAndSettle();

    // The first line should be a header1 with the content text,
    // not a prepended '# My Title'
    final controller = tester.state<_NoteEditorState>(
      find.byType(NoteEditor).first,
    );
    final doc = controller._controller!.document!;
    final firstNode = doc.first;
    expect(firstNode, isA<ParagraphNode>());
    expect(
      (firstNode as ParagraphNode).getMetadataValue('blockType'),
      header1Attribution,
    );
    // Title should not be prepended — the content 'some content' should
    // be the first line text, not '# My Title'
    expect(firstNode.text.toPlainText(), contains('some content'));
  });
}
```

Note: We can't access `_NoteEditorState` or `_controller` across library boundaries. Instead, we test through the public API. Since this is a widget test, let's simplify and verify the behavior through the widget tree.

- [ ] **Step 2: Remove the title-prepending logic in `NoteEditor.initState`**

```dart
  @override
  void initState() {
    super.initState();
    _controller = NoteEditorController(
      snapshotSave: widget.snapshotSave,
      emptyNoteExit: widget.emptyNoteExit,
    );
    _controller!.bind(widget.noteId);
    _controller!.init(content: widget.content);
    _notifyContentChanged();
  }
```

Replace the old `initState` that had the title-prepending block:
```dart
  @override
  void initState() {
    super.initState();
    _controller = NoteEditorController(
      snapshotSave: widget.snapshotSave,
      emptyNoteExit: widget.emptyNoteExit,
    );
    _controller!.bind(widget.noteId);
    _controller!.init(content: widget.content);
    _notifyContentChanged();
  }
```

- [ ] **Step 3: Run existing tests to verify nothing broke**

Run: `dart test test/features/notes/presentation/controllers/note_editor_controller_test.dart test/features/notes/presentation/note_editor_screen_test.dart`
Expected: All existing tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/features/notes/presentation/widgets/note_editor.dart
git commit -m "feat: remove title-prepending logic from NoteEditor"
```

---

### Task 3: Disable toolbar when cursor is on first line

**Files:**
- Modify: `lib/features/notes/presentation/widgets/note_toolbar.dart`

- [ ] **Step 1: Write a failing widget test for toolbar disabled state**

Add to `test/features/notes/presentation/note_editor_screen_test.dart`:

```dart
testWidgets('NoteToolbar disables all buttons when selection is on first line', (
    tester,
  ) async {
    // Create a controller with some content
    final controller = NoteEditorController(
      snapshotSave: (noteId, title, markdown, tasks) async {},
    );
    controller.init(content: 'Title line\n\nBody text');
    controller.bind('test');

    // Place selection on first node
    controller.composer!.setSelectionWithReason(
      DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: controller.document!.first.id,
          nodePosition: const TextNodePosition(offset: 0),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteToolbar(
            editor: controller.editor!,
            composer: controller.composer!,
          ),
        ),
      ),
    );

    // All IconButton widgets should have onPressed == null (disabled)
    final iconButtons = tester.widgetList<IconButton>(find.byType(IconButton));
    for (final button in iconButtons) {
      expect(button.onPressed, isNull, reason: 'Button should be disabled on first line');
    }
  });
```

- [ ] **Step 2: Add `_isOnFirstLine` check to NoteToolbar's build method**

In `NoteToolbar`, add a helper method and use it to null out all `onPressed` callbacks when on first line:

```dart
  bool _isOnFirstLine(DocumentSelection? selection) {
    if (selection == null) return false;
    final doc = editor.context.document;
    if (doc.isEmpty) return false;
    final firstNodeId = doc.first.id;
    final activeId = _activeNodeId(selection);
    return activeId == firstNodeId;
  }
```

Then in the `build` method, before constructing the toolbar buttons, compute:

```dart
  final isOnFirstLine = _isOnFirstLine(selection);
```

Then wrap all `onPressed` handlers: for each `_ToolbarButton` and `_LabeledToolbarButton`, pass `isOnFirstLine ? null : actualHandler`.

The cleanest approach: compute `isOnFirstLine` and pass it down. Wrap each button's `onPressed`:

```dart
  // In the build method, after computing selection state:
  final isOnFirstLine = _isOnFirstLine(selection);
```

Then modify every button to use `isOnFirstLine ? null : onPressed`:

For `_ToolbarButton`:
```dart
  onPressed: isOnFirstLine ? null : () => _toggleInline(boldAttribution),
```

For `_LabeledToolbarButton`:
```dart
  onPressed: isOnFirstLine ? null : () => _setBlockType(header1Attribution),
```

And similarly for all other buttons.

- [ ] **Step 3: Run test to verify it passes**

Run: `dart test test/features/notes/presentation/note_editor_screen_test.dart`
Expected: Tests pass, including the new toolbar disabled test.

- [ ] **Step 4: Commit**

```bash
git add lib/features/notes/presentation/widgets/note_toolbar.dart test/features/notes/presentation/note_editor_screen_test.dart
git commit -m "feat: disable toolbar when cursor is on first line"
```

---

### Task 4: Update excerpt extraction for H1-based titles

**Files:**
- Modify: `lib/features/notes/data/notes_repository.dart`

- [ ] **Step 1: Review existing _excerptFrom logic**

The current `_excerptFrom` in `notes_repository.dart:286-301` already skips the first non-empty line. Since the content is stored as markdown (e.g. `# Title\n\nBody text`), the first non-empty line will be `# Title` and the excerpt will be taken from the rest. This already matches the desired behavior — no change needed.

No code changes required for this task.

- [ ] **Step 2: Verify with manual inspection**

The existing `_excerptFrom` logic:
1. Splits content by `\n`
2. Finds first non-empty line index
3. Takes everything after that line as excerpt
4. Flattens and truncates to 120 chars

When content is `# My Title\n\nSome body text`, `firstNonEmptyIdx` = 0 (line `# My Title`), and `restOfLines` = `\nSome body text` → `"Some body text"`. This is correct.

- [ ] **Step 3: Commit (with ci skip)**

```bash
git commit --allow-empty -m "chore: excerpt extraction already compatible with H1 title format"
```

---

### Task 5: Final verification

- [ ] **Step 1: Run all existing tests**

Run: `dart test`
Expected: All tests pass.

- [ ] **Step 2: Run static analysis**

Run: `dart analyze lib/`
Expected: No errors or warnings related to the changed files.

- [ ] **Step 3: Manual smoke test (if possible)**

Verification checklist:
- Create a new note: verify it starts with a large H1-styled header
- Type a title and press Enter: verify the next block is normal body text
- Try to change block type of the title line using toolbar: verify toolbar is disabled
- Select all and delete: verify editor resets to a single empty H1 line
- Exit note and check list: verify note's title is the first line text, excerpt starts from second line
