# Node Conversion to Task Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable bidirectional conversion between paragraphs, list items, and task nodes in the editor toolbar.

**Architecture:** Modify `NoteToolbar` to detect the active node type and dispatch the correct super_editor `EditRequest` for each conversion. The toolbar already handles paragraph→task; we add list→task, task→paragraph, task→list, and list/task→header conversions.

**Tech Stack:** Flutter, Dart, super_editor (git dependency), flutter_test

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/features/notes/presentation/widgets/note_toolbar.dart` | Modify | Add node type detection and conversion branches |
| `test/features/notes/presentation/widgets/note_toolbar_test.dart` | Create | Widget tests for all conversion paths |

---

## Task 1: Test infrastructure and TaskNode isActive detection

**Files:**
- Create: `test/features/notes/presentation/widgets/note_toolbar_test.dart`
- Modify: `lib/features/notes/presentation/widgets/note_toolbar.dart:123-128`

- [ ] **Step 1: Create test file with helper to build a NoteToolbar inside a SuperEditor**

Create `test/features/notes/presentation/widgets/note_toolbar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_toolbar.dart';

/// Creates a [SuperEditor] with a [NoteToolbar] below it.
///
/// [nodes] populate the document. [selection] sets the initial caret.
Widget buildEditorHarness({
  required List<DocumentNode> nodes,
  DocumentSelection? selection,
}) {
  final document = MutableDocument(nodes: nodes);
  final composer = MutableDocumentComposer();
  final editor = createDefaultDocumentEditor(
    document: document,
    composer: composer,
  );

  if (selection != null) {
    composer.selection = selection;
  }

  return MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          Expanded(
            child: SuperEditor(
              editor: editor,
              componentBuilders: defaultComponentBuilders,
            ),
          ),
          NoteToolbar(editor: editor, composer: composer),
        ],
      ),
    ),
  );
}

/// Returns a collapsed [DocumentSelection] at the start of [nodeId].
DocumentSelection caretSelection(String nodeId) {
  return const DocumentSelection.collapsed(
    position: DocumentPosition(
      nodeId: 'node-1',
      nodePosition: TextNodePosition(offset: 0),
    ),
  );
}

void main() {
  group('Task button isActive', () {
    testWidgets('is inactive when cursor is on a ParagraphNode', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildEditorHarness(
          nodes: [
            ParagraphNode(
              id: 'node-1',
              text: AttributedText('Hello'),
            ),
          ],
          selection: const DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: 'node-1',
              nodePosition: TextNodePosition(offset: 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final checkbox = find.byIcon(Icons.check_box_outlined);
      expect(checkbox, findsOneWidget);

      final iconButton = tester.widget<IconButton>(checkbox);
      expect(iconButton.isSelected, isFalse);
    });

    testWidgets('is active when cursor is on a TaskNode', (tester) async {
      await tester.pumpWidget(
        buildEditorHarness(
          nodes: [
            TaskNode(
              id: 'node-1',
              text: AttributedText('Buy milk'),
              isComplete: false,
            ),
          ],
          selection: const DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: 'node-1',
              nodePosition: TextNodePosition(offset: 0),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final checkbox = find.byIcon(Icons.check_box_outlined);
      expect(checkbox, findsOneWidget);

      final iconButton = tester.widget<IconButton>(checkbox);
      expect(iconButton.isSelected, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart -v`
Expected: Both tests FAIL because `isActive` is hardcoded to `false` on the task button.

- [ ] **Step 3: Add isActive detection for TaskNode in NoteToolbar**

In `lib/features/notes/presentation/widgets/note_toolbar.dart`, inside the `build` method, after `final isListItem = blockType == listItemAttribution;` (line 34), add:

```dart
final activeNode = activeNodeId != null
    ? editor.context.document.getNodeById(activeNodeId)
    : null;
final isTask = activeNode is TaskNode;
```

Then change the task button's `isActive` from `false` to `isTask` (line 126):

```dart
_ToolbarButton(
  icon: Icons.check_box_outlined,
  tooltip: 'Tarefa',
  isActive: isTask,
  onPressed: _convertToTask,
),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart -v`
Expected: Both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/notes/presentation/widgets/note_toolbar.dart test/features/notes/presentation/widgets/note_toolbar_test.dart
git commit -m "feat(toolbar): highlight task button when cursor is on a TaskNode"
```

---

## Task 2: _convertToTask handles ListItemNode and toggles TaskNode back to paragraph

**Files:**
- Modify: `lib/features/notes/presentation/widgets/note_toolbar.dart:229-235`
- Modify: `test/features/notes/presentation/widgets/note_toolbar_test.dart`

- [ ] **Step 1: Write failing tests for ListItemNode→TaskNode and TaskNode→ParagraphNode**

Append to `test/features/notes/presentation/widgets/note_toolbar_test.dart`:

```dart
group('_convertToTask', () {
  testWidgets('converts ParagraphNode to TaskNode', (tester) async {
    final document = MutableDocument(nodes: [
      ParagraphNode(id: 'node-1', text: AttributedText('Buy milk')),
    ]);
    final composer = MutableDocumentComposer();
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );
    composer.selection = const DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: 'node-1',
        nodePosition: TextNodePosition(offset: 0),
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Expanded(
            child: SuperEditor(
              editor: editor,
              componentBuilders: defaultComponentBuilders,
            ),
          ),
          NoteToolbar(editor: editor, composer: composer),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.check_box_outlined));
    await tester.pumpAndSettle();

    expect(document.first, isA<TaskNode>());
    expect(
      (document.first as TaskNode).text.toPlainText(),
      'Buy milk',
    );
  });

  testWidgets('converts ListItemNode to TaskNode', (tester) async {
    final document = MutableDocument(nodes: [
      ListItemNode.unordered(id: 'node-1', text: AttributedText('Buy milk')),
    ]);
    final composer = MutableDocumentComposer();
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );
    composer.selection = const DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: 'node-1',
        nodePosition: TextNodePosition(offset: 0),
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Expanded(
            child: SuperEditor(
              editor: editor,
              componentBuilders: defaultComponentBuilders,
            ),
          ),
          NoteToolbar(editor: editor, composer: composer),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.check_box_outlined));
    await tester.pumpAndSettle();

    expect(document.first, isA<TaskNode>());
    expect(
      (document.first as TaskNode).text.toPlainText(),
      'Buy milk',
    );
  });

  testWidgets('converts TaskNode back to ParagraphNode', (tester) async {
    final document = MutableDocument(nodes: [
      TaskNode(
        id: 'node-1',
        text: AttributedText('Buy milk'),
        isComplete: false,
      ),
    ]);
    final composer = MutableDocumentComposer();
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );
    composer.selection = const DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: 'node-1',
        nodePosition: TextNodePosition(offset: 0),
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Expanded(
            child: SuperEditor(
              editor: editor,
              componentBuilders: defaultComponentBuilders,
            ),
          ),
          NoteToolbar(editor: editor, composer: composer),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.check_box_outlined));
    await tester.pumpAndSettle();

    expect(document.first, isA<ParagraphNode>());
    expect(
      (document.first as ParagraphNode).text.toPlainText(),
      'Buy milk',
    );
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart -v`
Expected: The "converts ListItemNode to TaskNode" and "converts TaskNode back to ParagraphNode" tests FAIL. The "converts ParagraphNode to TaskNode" test already passes.

- [ ] **Step 3: Rewrite _convertToTask to handle all three node types**

In `lib/features/notes/presentation/widgets/note_toolbar.dart`, replace the `_convertToTask` method (lines 229-235) with:

```dart
void _convertToTask() {
  final nodeId = _activeNodeId(composer.selection);
  if (nodeId == null) return;
  final node = editor.context.document.getNodeById(nodeId);
  if (node is ParagraphNode) {
    editor.execute([ConvertParagraphToTaskRequest(nodeId: nodeId)]);
  } else if (node is ListItemNode) {
    final taskNode = TaskNode(
      id: node.id,
      text: node.text,
      isComplete: false,
      indent: node.indent,
    );
    editor.execute([
      ReplaceNodeRequest(
        existingNodeId: node.id,
        newNode: taskNode,
      ),
    ]);
  } else if (node is TaskNode) {
    editor.execute([
      ConvertTaskToParagraphRequest(nodeId: nodeId),
    ]);
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart -v`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/notes/presentation/widgets/note_toolbar.dart test/features/notes/presentation/widgets/note_toolbar_test.dart
git commit -m "feat(toolbar): support list-to-task and task-to-paragraph conversions"
```

---

## Task 3: _convertToListItem handles TaskNode

**Files:**
- Modify: `lib/features/notes/presentation/widgets/note_toolbar.dart:213-227`
- Modify: `test/features/notes/presentation/widgets/note_toolbar_test.dart`

- [ ] **Step 1: Write failing tests for TaskNode→ListItemNode**

Append to the test file:

```dart
group('_convertToListItem', () {
  testWidgets('converts TaskNode to unordered ListItemNode', (tester) async {
    final document = MutableDocument(nodes: [
      TaskNode(
        id: 'node-1',
        text: AttributedText('Buy milk'),
        isComplete: false,
      ),
    ]);
    final composer = MutableDocumentComposer();
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );
    composer.selection = const DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: 'node-1',
        nodePosition: TextNodePosition(offset: 0),
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Expanded(
            child: SuperEditor(
              editor: editor,
              componentBuilders: defaultComponentBuilders,
            ),
          ),
          NoteToolbar(editor: editor, composer: composer),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.format_list_bulleted));
    await tester.pumpAndSettle();

    expect(document.first, isA<ListItemNode>());
    final item = document.first as ListItemNode;
    expect(item.text.toPlainText(), 'Buy milk');
    expect(item.itemType, ListItemType.unordered);
  });

  testWidgets('converts TaskNode to ordered ListItemNode', (tester) async {
    final document = MutableDocument(nodes: [
      TaskNode(
        id: 'node-1',
        text: AttributedText('Buy milk'),
        isComplete: false,
      ),
    ]);
    final composer = MutableDocumentComposer();
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );
    composer.selection = const DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: 'node-1',
        nodePosition: TextNodePosition(offset: 0),
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Expanded(
            child: SuperEditor(
              editor: editor,
              componentBuilders: defaultComponentBuilders,
            ),
          ),
          NoteToolbar(editor: editor, composer: composer),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.format_list_numbered));
    await tester.pumpAndSettle();

    expect(document.first, isA<ListItemNode>());
    final item = document.first as ListItemNode;
    expect(item.text.toPlainText(), 'Buy milk');
    expect(item.itemType, ListItemType.ordered);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart -v`
Expected: Both new tests FAIL because `_convertToListItem` currently returns early when node is not a `ListItemNode` or `ParagraphNode`.

- [ ] **Step 3: Update _convertToListItem to handle TaskNode**

In `lib/features/notes/presentation/widgets/note_toolbar.dart`, replace the `_convertToListItem` method (lines 213-227) with:

```dart
void _convertToListItem(ListItemType type) {
  final nodeId = _activeNodeId(composer.selection);
  if (nodeId == null) return;
  final node = editor.context.document.getNodeById(nodeId);
  if (node is ListItemNode) {
    editor.execute([
      ChangeListItemTypeRequest(nodeId: nodeId, newType: type),
    ]);
    return;
  }
  if (node is TaskNode) {
    final listItemNode = ListItemNode(
      id: node.id,
      itemType: type,
      text: node.text,
      indent: node.indent,
    );
    editor.execute([
      ReplaceNodeRequest(
        existingNodeId: node.id,
        newNode: listItemNode,
      ),
    ]);
    return;
  }
  if (node is! ParagraphNode) return;
  editor.execute([
    ConvertParagraphToListItemRequest(nodeId: nodeId, type: type),
  ]);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart -v`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/notes/presentation/widgets/note_toolbar.dart test/features/notes/presentation/widgets/note_toolbar_test.dart
git commit -m "feat(toolbar): support task-to-list-item conversion"
```

---

## Task 4: _setBlockType handles ListItemNode and TaskNode

**Files:**
- Modify: `lib/features/notes/presentation/widgets/note_toolbar.dart:203-211`
- Modify: `test/features/notes/presentation/widgets/note_toolbar_test.dart`

- [ ] **Step 1: Write failing tests for ListItemNode/TaskNode→Header**

Append to the test file:

```dart
group('_setBlockType', () {
  testWidgets('converts ListItemNode to H1', (tester) async {
    final document = MutableDocument(nodes: [
      ListItemNode.unordered(
        id: 'node-1',
        text: AttributedText('Heading text'),
      ),
    ]);
    final composer = MutableDocumentComposer();
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );
    composer.selection = const DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: 'node-1',
        nodePosition: TextNodePosition(offset: 0),
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Expanded(
            child: SuperEditor(
              editor: editor,
              componentBuilders: defaultComponentBuilders,
            ),
          ),
          NoteToolbar(editor: editor, composer: composer),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('H1'));
    await tester.pumpAndSettle();

    expect(document.first, isA<ParagraphNode>());
    final para = document.first as ParagraphNode;
    expect(para.text.toPlainText(), 'Heading text');
    expect(
      para.getMetadataValue('blockType'),
      header1Attribution,
    );
  });

  testWidgets('converts TaskNode to H2', (tester) async {
    final document = MutableDocument(nodes: [
      TaskNode(
        id: 'node-1',
        text: AttributedText('Heading text'),
        isComplete: false,
      ),
    ]);
    final composer = MutableDocumentComposer();
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );
    composer.selection = const DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: 'node-1',
        nodePosition: TextNodePosition(offset: 0),
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Expanded(
            child: SuperEditor(
              editor: editor,
              componentBuilders: defaultComponentBuilders,
            ),
          ),
          NoteToolbar(editor: editor, composer: composer),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('H2'));
    await tester.pumpAndSettle();

    expect(document.first, isA<ParagraphNode>());
    final para = document.first as ParagraphNode;
    expect(para.text.toPlainText(), 'Heading text');
    expect(
      para.getMetadataValue('blockType'),
      header2Attribution,
    );
  });

  testWidgets('converts TaskNode to Blockquote', (tester) async {
    final document = MutableDocument(nodes: [
      TaskNode(
        id: 'node-1',
        text: AttributedText('Quoted text'),
        isComplete: false,
      ),
    ]);
    final composer = MutableDocumentComposer();
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: composer,
    );
    composer.selection = const DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: 'node-1',
        nodePosition: TextNodePosition(offset: 0),
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Expanded(
            child: SuperEditor(
              editor: editor,
              componentBuilders: defaultComponentBuilders,
            ),
          ),
          NoteToolbar(editor: editor, composer: composer),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.format_quote));
    await tester.pumpAndSettle();

    expect(document.first, isA<ParagraphNode>());
    final para = document.first as ParagraphNode;
    expect(para.text.toPlainText(), 'Quoted text');
    expect(
      para.getMetadataValue('blockType'),
      blockquoteAttribution,
    );
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart -v`
Expected: All three new tests FAIL because `_setBlockType` currently returns early when node is not a `ParagraphNode`.

- [ ] **Step 3: Update _setBlockType to handle ListItemNode and TaskNode**

In `lib/features/notes/presentation/widgets/note_toolbar.dart`, replace the `_setBlockType` method (lines 203-211) with:

```dart
void _setBlockType(Attribution? blockType) {
  final nodeId = _activeNodeId(composer.selection);
  if (nodeId == null) return;
  final node = editor.context.document.getNodeById(nodeId);
  if (node is ParagraphNode) {
    editor.execute([
      ChangeParagraphBlockTypeRequest(nodeId: nodeId, blockType: blockType),
    ]);
  } else if (node is ListItemNode) {
    editor.execute([
      ConvertListItemToParagraphRequest(
        nodeId: nodeId,
        paragraphMetadata: {
          'blockType': blockType,
        },
      ),
    ]);
  } else if (node is TaskNode) {
    editor.execute([
      ConvertTaskToParagraphRequest(
        nodeId: nodeId,
        paragraphMetadata: {
          'blockType': blockType,
        },
      ),
    ]);
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart -v`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/notes/presentation/widgets/note_toolbar.dart test/features/notes/presentation/widgets/note_toolbar_test.dart
git commit -m "feat(toolbar): support list/task to header/blockquote conversion"
```

---

## Task 5: Run full test suite and verify

**Files:** None (verification only)

- [ ] **Step 1: Run all tests**

Run: `flutter test`
Expected: All tests PASS, no regressions.

- [ ] **Step 2: Run analysis**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 3: Final commit (if any fixes needed)**

If analysis or tests revealed issues, fix and commit:

```bash
git add -A
git commit -m "fix(toolbar): address review findings"
```

---

## Self-Review Checklist

1. **Spec coverage:**
   - ✅ Task node detection in toolbar (Task 1)
   - ✅ `_convertToTask` handles ParagraphNode, ListItemNode, TaskNode toggle (Task 2)
   - ✅ `_convertToListItem` handles TaskNode (Task 3)
   - ✅ `_setBlockType` handles ListItemNode and TaskNode (Task 4)

2. **Placeholder scan:** No TBD/TODO/placeholders found. All steps have complete code.

3. **Type consistency:**
   - `TaskNode` constructor: `id`, `text`, `isComplete`, `indent` — matches super_editor API
   - `ListItemNode` constructor: `id`, `itemType`, `text`, `indent` — matches super_editor API
   - `ReplaceNodeRequest`: `existingNodeId`, `newNode` — matches super_editor API
   - `ConvertTaskToParagraphRequest`: `nodeId`, `paragraphMetadata` — matches super_editor API
   - `ConvertListItemToParagraphRequest`: `nodeId`, `paragraphMetadata` — matches super_editor API
