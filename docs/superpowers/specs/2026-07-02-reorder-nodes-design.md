# Design: Reorder Nodes (Drag and Drop)

**Date**: 2026-07-02  
**Status**: Proposed  
**Author**: Antigravity  

---

## Summary

Implement a drag-and-drop block reordering feature in the SupaNotes editor. Users can touch and hold (long-press) on the left margin/gutter of any block (node) and drag it up or down to reorder the note contents dynamically. 

---

## Requirements

1. **Trigger Gesture**: Reordering starts when the user presses and holds (long-press) specifically on the left margin/gutter (first 32 pixels from the left edge of the screen).
2. **Text Selection Safety**: Long-pressing inside the text area continues to function normally (word selection, menu show) and does not trigger dragging.
3. **Scope of Nodes**: All note node types (paragraphs, headers, checklists, attachments, dividers) can be dragged and reordered.
4. **Visual Feedback during Drag**: 
   - The dragged node is replaced by a translucent placeholder in the document flow.
   - A floating visual representation of the dragged node follows the user's finger.
   - Other nodes dynamically shift up/down to open space as the user drags.
5. **Title Lock**: The first node (index 0) represents the note title. To prevent structural layout issues:
   - The title node cannot be dragged down.
   - Other nodes cannot be dragged above the title node.
6. **Persistence**: Reordering updates the underlying database state automatically and syncs with the server.

---

## Architecture

We leverage Flutter's native declarative drag-and-drop widgets: `LongPressDraggable` and `DragTarget`. Since `SuperEditor` controls its own layout internally, we wrap all component widgets in a custom component builder wrapper.

### Current Flow (Render)
```
SuperEditor
  → componentBuilders (CustomDividerComponentBuilder, CustomTaskComponentBuilder, etc.)
    → Builds components directly
```

### Proposed Flow (Render)
```
SuperEditor
  → wrappedComponentBuilders (Wrapped with ReorderableComponentBuilderWrapper)
    → Original builder builds component
    → Wraps component with DragAndDropNodeWrapper
      → Positioned 32px Left Gutter Overlay (DragTarget + LongPressDraggable)
```

---

## Implementation Details

### 1. Create `DragAndDropNodeWrapper`

**File**: `lib/features/notes/presentation/widgets/drag_and_drop_node_wrapper.dart`

This widget wraps each node component widget in a `Stack`. It defines the transparent 32px left margin gesture area and handles the movement dispatch.

```dart
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

class DragAndDropNodeWrapper extends StatelessWidget {
  final String nodeId;
  final Editor editor;
  final Widget child;

  const DragAndDropNodeWrapper({
    key,
    required this.nodeId,
    required this.editor,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 32, // The invisible left-gutter hot-zone
          child: DragTarget<String>(
            builder: (context, candidateData, rejectedData) {
              return LongPressDraggable<String>(
                data: nodeId,
                feedback: Material(
                  color: Colors.transparent,
                  child: Opacity(
                    opacity: 0.8,
                    child: Transform.scale(
                      scale: 1.02,
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width - 48,
                        child: child,
                      ),
                    ),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.3,
                  child: child,
                ),
                child: const SizedBox.expand(
                  child: ColoredBox(color: Colors.transparent),
                ),
              );
            },
            onWillAcceptWithDetails: (details) {
              final draggedId = details.data;
              if (draggedId == nodeId) return false;

              final doc = editor.document;
              final targetIndex = doc.getNodeIndexById(nodeId);
              final draggedIndex = doc.getNodeIndexById(draggedId);

              // Title Lock (Index 0 is the title node):
              // Reject drag/drop involving index 0.
              if (targetIndex == 0 || draggedIndex == 0) return false;

              if (targetIndex != -1 && draggedIndex != -1 && targetIndex != draggedIndex) {
                editor.execute([
                  MoveNodeRequest(nodeId: draggedId, newIndex: targetIndex),
                ]);
              }
              return true;
            },
          ),
        ),
      ],
    );
  }
}
```

### 2. Create `ReorderableComponentBuilderWrapper`

**File**: `lib/features/notes/presentation/widgets/reorderable_component_builder_wrapper.dart`

```dart
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'drag_and_drop_node_wrapper.dart';

class ReorderableComponentBuilderWrapper implements ComponentBuilder {
  final ComponentBuilder delegate;
  final Editor editor;
  final bool isReadOnly;

  const ReorderableComponentBuilderWrapper({
    required this.delegate,
    required this.editor,
    required this.isReadOnly,
  });

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    return delegate.createViewModel(document, node);
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    final originalWidget = delegate.createComponent(componentContext, componentViewModel);
    if (originalWidget == null) return null;
    if (isReadOnly) return originalWidget;

    return DragAndDropNodeWrapper(
      nodeId: componentViewModel.nodeId,
      editor: editor,
      child: originalWidget,
    );
  }
}
```

### 3. Update `NoteEditor` to wrap builders

**File**: `lib/features/notes/presentation/widgets/note_editor.dart`

```dart
// Helper method to wrap builders:
List<ComponentBuilder> _wrapComponentBuilders(
  List<ComponentBuilder> builders,
  Editor editor,
  bool isReadOnly,
) {
  return builders.map((builder) {
    return ReorderableComponentBuilderWrapper(
      delegate: builder,
      editor: editor,
      isReadOnly: isReadOnly,
    );
  }).toList();
}

// In build():
componentBuilders: _wrapComponentBuilders(
  [
    const CustomDividerComponentBuilder(),
    _taskComponentBuilder,
    AttachmentComponentBuilder(
      editor: controller.editor!,
      collapseImages: widget.collapseImages,
    ),
    ...defaultComponentBuilders,
  ],
  controller.editor!,
  widget.isReadOnly,
),
```

---

## Testing

### Manual Testing
1. **Normal Editing**: Long-press text characters in any paragraph. Confirm that word selection/copy handles appear and drag does not trigger.
2. **Margin Drag**: Long-press the left gutter of any paragraph node. Verify it lifts under the finger. Drag down below the next paragraph. Verify the paragraphs swap places dynamically.
3. **Title Lock**:
   - Try to drag the H1 title node down. Verify it cannot be dragged.
   - Try to drag another node above the H1 title node. Verify it cannot be placed there.
4. **Checklist/Tasks & Divider Drag**: Drag a task node or divider node. Verify it shifts correctly.
5. **Persistence**: Drag a node, exit the note, re-enter, and verify that the reordered position is retained.

### Automated Testing
We will add a widget test to `test/features/notes/presentation/widgets/reorder_nodes_test.dart` to simulate a long press on the margin of a node, dragging it over another node, and verifying that `MoveNodeRequest` is sent and the document layout updates.

---

## Files to Modify / Create

### [NEW]
1. `lib/features/notes/presentation/widgets/drag_and_drop_node_wrapper.dart`
2. `lib/features/notes/presentation/widgets/reorderable_component_builder_wrapper.dart`
3. `test/features/notes/presentation/widgets/reorder_nodes_test.dart`

### [MODIFY]
1. `lib/features/notes/presentation/widgets/note_editor.dart`

---

## Out of Scope
- Multi-node selection and dragging.
- Dragging nodes across different notes.
- Dragging files from device OS files manager directly into a specific index of the note.
