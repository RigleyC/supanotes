# Spec: Transforming Lists and Paragraphs into Tasks in SuperEditor

## Goal
To allow users to seamlessly convert between different text block types in the editor toolbar. Specifically, when a user selects a paragraph, list item, or task item, clicking the corresponding toolbar buttons will convert the selected block into the target block type (task, list item, or paragraph/header) while preserving text content and indentation.

## Design Details

### 1. Task Node Detection in Toolbar
In `NoteToolbar`, we currently have the checklist toolbar button:
```dart
_ToolbarButton(
  icon: Icons.check_box_outlined,
  tooltip: 'Tarefa',
  isActive: false,
  onPressed: _convertToTask,
)
```
We will change `isActive` to evaluate to true if the active node is a `TaskNode`:
```dart
final activeNode = activeNodeId != null ? editor.context.document.getNodeById(activeNodeId) : null;
final isTask = activeNode is TaskNode;
```
And pass `isActive: isTask` to the button.

### 2. Conversions in `_convertToTask`
We will rewrite `_convertToTask` in `NoteToolbar` to support conversions of paragraphs and list items to task nodes, as well as toggling tasks back to paragraphs:
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

### 3. Conversions in `_convertToListItem`
We will update `_convertToListItem` to handle converting `TaskNode` directly to a `ListItemNode`:
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

### 4. Conversions in `_setBlockType` (Headers/Citations)
We will update `_setBlockType` to allow transforming `ListItemNode` or `TaskNode` directly into a styled paragraph (H1, H2, H3, Blockquote) without requiring the user to convert it back to a plain paragraph first:
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

## Verification Plan

### Manual Verification
- Launch the application locally and open a note.
- Create a list item (ordered and unordered), click the Checkbox button, and verify it converts to a task node.
- Click the Checkbox button when a task node is active, and verify it converts back to a paragraph.
- Create a task node, click H1/H2/H3, and verify it converts to the correct header type.
- Create a task node, click the List button, and verify it converts to a list item.
