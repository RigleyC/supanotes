# Node Reordering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement drag-and-drop node reordering by long-pressing on the left margin gutter in the SupaNotes editor.

**Architecture:** Wrap the editor's component builders in a custom reorderable wrapper. Use Flutter's native `LongPressDraggable` and `DragTarget` inside a `Stack` overlay for hit-testing left-margin gestures (32px width), and execute `MoveNodeRequest` via the `Editor` context. Reject reordering involving the title node (index 0).

**Tech Stack:** Flutter, Super Editor, Dart.

---

### Task 1: Create `DragAndDropNodeWrapper`

**Files:**
- Create: `lib/features/notes/presentation/widgets/drag_and_drop_node_wrapper.dart`
- Test: `test/features/notes/presentation/widgets/reorder_nodes_test.dart`

- [ ] **Step 1: Create the test file with a placeholder test**
  Create the test file `test/features/notes/presentation/widgets/reorder_nodes_test.dart` to verify that our wrapper compiles and can be imported.
  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';

  void main() {
    testWidgets('placeholder test for drag and drop node wrapper', (tester) async {
      expect(true, isTrue);
    });
  }
  ```

- [ ] **Step 2: Run test to verify setup**
  Run: `flutter test test/features/notes/presentation/widgets/reorder_nodes_test.dart`
  Expected: PASS

- [ ] **Step 3: Create `DragAndDropNodeWrapper`**
  Create `lib/features/notes/presentation/widgets/drag_and_drop_node_wrapper.dart`:
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

- [ ] **Step 4: Commit Task 1**
  ```bash
  git add lib/features/notes/presentation/widgets/drag_and_drop_node_wrapper.dart test/features/notes/presentation/widgets/reorder_nodes_test.dart
  git commit -m "feat(notes): create DragAndDropNodeWrapper"
  ```

---

### Task 2: Create `ReorderableComponentBuilderWrapper`

**Files:**
- Create: `lib/features/notes/presentation/widgets/reorderable_component_builder_wrapper.dart`

- [ ] **Step 1: Create `ReorderableComponentBuilderWrapper`**
  Create `lib/features/notes/presentation/widgets/reorderable_component_builder_wrapper.dart`:
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

- [ ] **Step 2: Commit Task 2**
  ```bash
  git add lib/features/notes/presentation/widgets/reorderable_component_builder_wrapper.dart
  git commit -m "feat(notes): create ReorderableComponentBuilderWrapper"
  ```

---

### Task 3: Integrate with `NoteEditor`

**Files:**
- Modify: `lib/features/notes/presentation/widgets/note_editor.dart`

- [ ] **Step 1: Modify `NoteEditor` to wrap the builders**
  Add imports and wrap the builder list inside `note_editor.dart`.
  ```diff
  diff --git a/lib/features/notes/presentation/widgets/note_editor.dart b/lib/features/notes/presentation/widgets/note_editor.dart
  index 12345..67890 100644
  --- a/lib/features/notes/presentation/widgets/note_editor.dart
  +++ b/lib/features/notes/presentation/widgets/note_editor.dart
  @@ -27,6 +27,8 @@ import 'package:supanotes/shared/widgets/app_snackbar.dart';
   import 'package:supanotes/features/tasks/domain/task_model.dart';
   import 'package:supanotes/shared/widgets/app_snackbar.dart';
  +import 'package:supanotes/features/notes/presentation/widgets/reorderable_component_builder_wrapper.dart';
   
   class NoteEditor extends ConsumerStatefulWidget {
  @@ -273,15 +275,28 @@ class _NoteEditorState extends ConsumerState<NoteEditor> {
                         contentTapDelegateFactories: widget.isReadOnly
                             ? null
                             : [
  @@ -273,15 +278,28 @@ class _NoteEditorState extends ConsumerState<NoteEditor> {
                             ],
                         keyboardActions: buildRichKeyboardActions(
                           baseActions:
                               defaultTargetPlatform == TargetPlatform.iOS ||
                                   defaultTargetPlatform == TargetPlatform.android
                               ? defaultImeKeyboardActions
                               : defaultKeyboardActions,
                         ),
  -                      componentBuilders: [
  -                        const CustomDividerComponentBuilder(),
  -                        _taskComponentBuilder,
  -                        AttachmentComponentBuilder(
  -                          editor: controller.editor!,
  -                          collapseImages: widget.collapseImages,
  -                        ),
  -                        ...defaultComponentBuilders,
  -                      ],
  +                      componentBuilders: _wrapComponentBuilders(
  +                        [
  +                          const CustomDividerComponentBuilder(),
  +                          _taskComponentBuilder,
  +                          AttachmentComponentBuilder(
  +                            editor: controller.editor!,
  +                            collapseImages: widget.collapseImages,
  +                          ),
  +                          ...defaultComponentBuilders,
  +                        ],
  +                        controller.editor!,
  +                        widget.isReadOnly,
  +                      ),
                       ),
                     ),
                   ),
  @@ -304,4 +322,17 @@ class _NoteEditorState extends ConsumerState<NoteEditor> {
         ),
       );
     }
  +
  +  List<ComponentBuilder> _wrapComponentBuilders(
  +    List<ComponentBuilder> builders,
  +    Editor editor,
  +    bool isReadOnly,
  +  ) {
  +    return builders.map((builder) {
  +      return ReorderableComponentBuilderWrapper(
  +        delegate: builder,
  +        editor: editor,
  +        isReadOnly: isReadOnly,
  +      );
  +    }).toList();
  +  }
   }
   ```

- [ ] **Step 2: Verify the codebase compiles and runs test suite**
  Run: `flutter test`
  Expected: PASS

- [ ] **Step 3: Commit Task 3**
  ```bash
  git add lib/features/notes/presentation/widgets/note_editor.dart
  git commit -m "feat(notes): wrap component builders with reorderable wrapper in NoteEditor"
  ```

---

### Task 4: Add Widget Tests for Node Reordering

**Files:**
- Modify: `test/features/notes/presentation/widgets/reorder_nodes_test.dart`

- [ ] **Step 1: Write tests in `reorder_nodes_test.dart`**
  Modify `test/features/notes/presentation/widgets/reorder_nodes_test.dart` to render a `SuperEditor` and simulate a drag-and-drop operation, checking that nodes are reordered correctly and that title lock prevents index 0 moves.
  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:super_editor/super_editor.dart';
  import 'package:supanotes/features/notes/presentation/widgets/drag_and_drop_node_wrapper.dart';
  import 'package:supanotes/features/notes/presentation/widgets/reorderable_component_builder_wrapper.dart';

  void main() {
    testWidgets('Reorders nodes on drag and drop and respects title lock', (WidgetTester tester) async {
      final doc = MutableDocument(nodes: [
        ParagraphNode(id: '0', text: AttributedText('Title')),
        ParagraphNode(id: '1', text: AttributedText('First item')),
        ParagraphNode(id: '2', text: AttributedText('Second item')),
      ]);

      final composer = MutableDocumentComposer();
      final editor = createDefaultDocumentEditor(document: doc, composer: composer);

      final builders = [
        const ParagraphComponentBuilder(),
      ].map((b) => ReorderableComponentBuilderWrapper(
            delegate: b,
            editor: editor,
            isReadOnly: false,
          )).toList();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SuperEditor(
              editor: editor,
              componentBuilders: builders,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find the wrappers or gutters
      final firstGutterFinder = find.descendant(
        of: find.byWidgetPredicate((w) => w is DragAndDropNodeWrapper && w.nodeId == '1'),
        matching: find.byType(LongPressDraggable<String>),
      );

      final secondGutterFinder = find.descendant(
        of: find.byWidgetPredicate((w) => w is DragAndDropNodeWrapper && w.nodeId == '2'),
        matching: find.byType(DragTarget<String>),
      );

      expect(firstGutterFinder, findsOneWidget);
      expect(secondGutterFinder, findsOneWidget);

      // Drag node '1' to node '2' target position
      final gesture = await tester.startGesture(tester.getCenter(firstGutterFinder));
      await tester.pump(const Duration(seconds: 1)); // Wait for long-press trigger
      await gesture.moveTo(tester.getCenter(secondGutterFinder));
      await gesture.up();
      await tester.pumpAndSettle();

      // Verify node 1 moved to index 2 (below index 1)
      expect(doc.first.id, equals('0'));
      expect(doc.getNodeAt(1)!.id, equals('2'));
      expect(doc.getNodeAt(2)!.id, equals('1'));

      // Try dragging node '1' (now at index 2) to title (index 0)
      final titleTargetFinder = find.descendant(
        of: find.byWidgetPredicate((w) => w is DragAndDropNodeWrapper && w.nodeId == '0'),
        matching: find.byType(DragTarget<String>),
      );
      final node1GutterFinder = find.descendant(
        of: find.byWidgetPredicate((w) => w is DragAndDropNodeWrapper && w.nodeId == '1'),
        matching: find.byType(LongPressDraggable<String>),
      );

      final gesture2 = await tester.startGesture(tester.getCenter(node1GutterFinder));
      await tester.pump(const Duration(seconds: 1));
      await gesture2.moveTo(tester.getCenter(titleTargetFinder));
      await gesture2.up();
      await tester.pumpAndSettle();

      // Verify that the title lock prevented the move
      expect(doc.first.id, equals('0'));
      expect(doc.getNodeAt(1)!.id, equals('2'));
      expect(doc.getNodeAt(2)!.id, equals('1'));
    });
  }
  ```

- [ ] **Step 2: Run the test to verify it passes**
  Run: `flutter test test/features/notes/presentation/widgets/reorder_nodes_test.dart`
  Expected: PASS

- [ ] **Step 3: Commit Task 4**
  ```bash
  git add test/features/notes/presentation/widgets/reorder_nodes_test.dart
  git commit -m "test(notes): add reordering and title lock widget tests"
  ```
