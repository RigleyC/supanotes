# Plan 002: Refactor Editor Focus, State, and Scroll Views

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report — do not improvise.
>
> **Drift check (run first)**: `git diff --stat b4986cd..HEAD -- lib/features/notes/presentation/controllers/note_editor_controller.dart lib/features/notes/presentation/widgets/custom_task_component.dart lib/features/notes/presentation/widgets/note_editor.dart lib/features/notes/presentation/note_editor_screen.dart`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/001-node-tree-migration.md (or equivalent migration completed)
- **Category**: tech-debt
- **Planned at**: commit `b4986cd`, 2026-07-01

## Why this matters

This plan addresses three distinct symptoms experienced in the note editor:
1. **Focus jumping and keyboard pops**: Triggered by the FocusNode being recreated on every layout update.
2. **Tasks failing to hide when completed**: Caused by custom task component states being destroyed and recreated during document stream updates, leaving them trapped in the visible list forever.
3. **Scroll freezing and white screens**: Caused by nested `CustomScrollView` scrolling layout conflicts between the screen wrapper and the editor itself.

Refactoring these to a Riverpod Notifier, implementing incremental document diffing, and unifying the scroll layout resolves these issues systemically.

## Current state

The relevant files and their roles:
- `lib/features/notes/presentation/controllers/note_editor_controller.dart` — Editor state controller (document, editor, focusNode).
- `lib/features/notes/presentation/widgets/custom_task_component.dart` — Custom rendering component for checklist tasks.
- `lib/features/notes/presentation/widgets/note_editor.dart` — Note editor widget wrapping `SuperEditor`.
- `lib/features/notes/presentation/note_editor_screen.dart` — Note editor screen layout wrapper.

### Excerpts with `file:line` markers

#### note_editor_controller.dart:68
```dart
    focusNode = FocusNode();
```

#### custom_task_component.dart:190-208
```dart
  @override
  void initState() {
    super.initState();
    _isComplete = widget.viewModel.isComplete;
    _exitController = AnimationController(
      vsync: this,
      duration: _exitAnimationDuration,
    );
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeOut),
    );
    _sizeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInOutCubic),
    );
    _exitController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onAnimationComplete?.call();
      }
    });
  }
```

#### note_editor_screen.dart:154-189
```dart
                  SliverFillRemaining(
                    hasScrollBody: true,
                    child: NoteEditor(
                      noteId: widget.noteId,
                      nodes: nodes,
                      taskMetadata: tasksMap,
                      hideCompleted: hideCompleted,
                      collapseImages: note.collapseImages,
                      isReadOnly: isReadOnly,
                      delegate: NoteEditorDelegate(...),
                    ),
                  ),
```

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Run tests | `flutter test`            | exit 0, all pass    |

---

## Scope

**In scope**:
- `lib/features/notes/presentation/controllers/note_editor_provider.dart` (create)
- `lib/features/notes/presentation/controllers/note_editor_controller.dart`
- `lib/features/notes/presentation/widgets/custom_task_component.dart`
- `lib/features/notes/presentation/widgets/note_editor.dart`
- `lib/features/notes/presentation/note_editor_screen.dart`

**Out of scope**:
- Database table changes.
- Sync API endpoints.

---

## Steps

### Step 1: Create NoteEditorController Riverpod Provider

Create the provider family `noteEditorControllerProvider` to manage the lifecycle of `NoteEditorController`.

Create `lib/features/notes/presentation/controllers/note_editor_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'note_editor_controller.dart';

final noteEditorControllerProvider = NotifierProvider.family.autoDispose<
    NoteEditorControllerNotifier, NoteEditorController, String>(
  NoteEditorControllerNotifier.new,
);

class NoteEditorControllerNotifier extends AutoDisposeFamilyNotifier<NoteEditorController, String> {
  @override
  NoteEditorController build(String arg) {
    final userId = ref.watch(currentUserIdProvider)!;
    final controller = NoteEditorController(
      userId: userId,
      database: ref.watch(appDatabaseProvider),
    );
    controller.bind(arg);
    ref.onDispose(() {
      controller.dispose();
    });
    return controller;
  }
}
```

In `lib/features/notes/presentation/controllers/note_editor_controller.dart`:
- Only instantiate `focusNode` if it is null in `_setupEditor()`:
```dart
    focusNode ??= FocusNode();
```
- In `dispose()`, remove `_flushAndSaveFinalState()` if it causes recursive calls on autoDispose, or ensure it runs safely:
```dart
  void dispose() {
    _flushAndSaveFinalState();
    _nodeSyncManager?.dispose();
    document?.dispose();
    composer?.dispose();
    focusNode?.dispose();
  }
```

**Verify**: Run the task component unit tests.
```bash
flutter test test/features/notes/presentation/widgets/custom_task_component_test.dart
```

---

### Step 2: Implement Incremental Document Diffing in Go Controller

Expose a node builder helper in `NodeSyncManager` and write the incremental diff update method in `NoteEditorController` to apply node updates surgically on the existing document tree.

In `lib/features/notes/domain/node_sync_manager.dart`, add:
```dart
  static DocumentNode createNodeFromSchema(NoteNode schema) {
    final type = schema.type;
    final data = jsonDecode(schema.data) as Map<String, dynamic>;
    final text = data['text'] as String? ?? '';
    final spans = data['spans'] as List? ?? [];
    final attributedText = AttributedText(
      text,
      _deserializeSpans(spans),
    );

    if (type == 'task') {
      return TaskNode(
        id: schema.id,
        text: attributedText,
        isComplete: data['completed'] as bool? ?? false,
        indent: data['indent'] as int? ?? 0,
      );
    }
    if (type == 'list_item') {
      return ListItemNode(
        id: schema.id,
        itemType: (data['itemType'] as String?) == 'ordered' ? ListItemType.ordered : ListItemType.unordered,
        text: attributedText,
        indent: data['indent'] as int? ?? 0,
      );
    }
    if (type == 'divider') {
      return HorizontalRuleNode(id: schema.id);
    }
    if (type == 'header') {
      final level = data['level'] as int? ?? 1;
      final blockType = switch (level) {
        1 => header1Attribution,
        2 => header2Attribution,
        3 => header3Attribution,
        4 => header4Attribution,
        5 => header5Attribution,
        _ => header6Attribution,
      };
      return ParagraphNode(
        id: schema.id,
        text: attributedText,
        metadata: {'blockType': blockType},
      );
    }
    return ParagraphNode(id: schema.id, text: attributedText);
  }

  static SpanMarking _parseSpan(Map<String, dynamic> spanMap) {
    final name = spanMap['attribution'] as String;
    Attribution attribution;
    if (name == 'bold') {
      attribution = boldAttribution;
    } else if (name == 'italics') {
      attribution = italicsAttribution;
    } else if (name == 'strikethrough') {
      attribution = strikethroughAttribution;
    } else if (name == 'underline') {
      attribution = underlineAttribution;
    } else if (name.startsWith('link:')) {
      attribution = LinkAttribution(url: Uri.parse(name.substring(5)));
    } else {
      attribution = NamedAttribution(name);
    }
    return SpanMarking(
      attribution: attribution,
      offset: spanMap['start'] as int,
      isStart: true,
    );
  }

  static Spans _deserializeSpans(List spansJson) {
    final list = <SpanMarking>[];
    for (final s in spansJson) {
      final m = s as Map<String, dynamic>;
      final start = m['start'] as int;
      final end = m['end'] as int;
      final parsed = _parseSpan(m);
      list.add(parsed);
      list.add(SpanMarking(
        attribution: parsed.attribution,
        offset: end,
        isStart: false,
      ));
    }
    return Spans(markers: list);
  }
```

In `lib/features/notes/presentation/controllers/note_editor_controller.dart`, add:
```dart
  void updateNodesIncrementally(List<NoteNode> incomingNodes) {
    final doc = document;
    final ed = editor;
    if (doc == null || ed == null) return;

    ed.execute([
      CustomDocumentEditRequest((document) {
        final incomingIds = incomingNodes.map((n) => n.id).toSet();
        final existingIds = document.nodes.map((n) => n.id).toList();

        // 1. Delete removed nodes
        for (final id in existingIds) {
          if (!incomingIds.contains(id)) {
            final node = document.getNodeById(id);
            if (node != null) {
              document.deleteNode(node);
            }
          }
        }

        // 2. Insert or update nodes
        for (int i = 0; i < incomingNodes.length; i++) {
          final incoming = incomingNodes[i];
          final existingNode = document.getNodeById(incoming.id);

          if (existingNode == null) {
            final newNode = NodeSyncManager.createNodeFromSchema(incoming);
            document.insertNodeAt(i, newNode);
          } else {
            _updateNodeProperties(existingNode, incoming);
          }
        }
      })
    ]);
  }

  void _updateNodeProperties(DocumentNode existing, NoteNode incoming) {
    final data = jsonDecode(incoming.data) as Map<String, dynamic>;
    final incomingText = data['text'] as String? ?? '';

    if (existing is TextNode) {
      if (existing.text.toPlainText() != incomingText) {
        final spans = data['spans'] as List? ?? [];
        existing.text = AttributedText(
          incomingText,
          NodeSyncManager._deserializeSpans(spans),
        );
      }
    }

    if (existing is TaskNode) {
      final completed = data['completed'] as bool? ?? false;
      if (existing.isComplete != completed) {
        existing.isComplete = completed;
      }
      final indent = data['indent'] as int? ?? 0;
      if (existing.indent != indent) {
        existing.indent = indent;
      }
    }

    if (existing is ListItemNode) {
      final indent = data['indent'] as int? ?? 0;
      if (existing.indent != indent) {
        existing.indent = indent;
      }
    }
  }
```

**Verify**: Ensure project compiles successfully.

---

### Step 3: Bind NoteEditor to Riverpod and Incremental Diffing

Update `NoteEditor` to resolve the `noteEditorControllerProvider` and apply updates via `updateNodesIncrementally` in `didUpdateWidget`.

In `lib/features/notes/presentation/widgets/note_editor.dart`:
- Import `note_editor_provider.dart`.
- In `initState()`:
```dart
    _controller = ref.read(noteEditorControllerProvider(widget.noteId));
    if (_controller!.document == null) {
      _controller!.initFromNodes(nodes: widget.nodes, noteId: widget.noteId);
    }
```
- In `didUpdateWidget()`:
```dart
    if (!listEquals(widget.nodes, oldWidget.nodes)) {
      _controller?.updateNodesIncrementally(widget.nodes);
    }
```

---

### Step 4: Fix Exit Animations and Unify Scroll View Layout

1. Trigger the task completion exit animation in `initState` if complete and `hideCompleted` is true:
In `lib/features/notes/presentation/widgets/custom_task_component.dart`:
```dart
    if (widget.hideCompleted && _isComplete) {
      _exitController.forward();
    }
```

2. Add `appBar` property to `NoteEditor` and prepend it inside `CustomScrollView`:
In `lib/features/notes/presentation/widgets/note_editor.dart`, accept `final Widget? appBar;` and insert `if (widget.appBar != null) widget.appBar!,` before `SuperEditorAndroidControlsScope`.

3. Simplify `NoteEditorScreen` layout in `lib/features/notes/presentation/note_editor_screen.dart` to return `NoteEditor` directly, passing `AdaptiveSliverNavBar` into `appBar`.

**Verify**: Run all tests.
```bash
flutter test
```

---

## Test plan

- **Checklist Hiding**: Open a note with tasks, check one off, confirm it hides correctly. Wait for sync, reload the screen, and verify the completed task remains hidden and does not reappear.
- **Scroll Concurrency**: Scroll the note editor up and down; confirm no freezes or blank white layouts happen when scrolling past the navigation bar.

## Done criteria

- [ ] `flutter test` exits 0.
- [ ] Nested scroll view in NoteEditorScreen is removed and scroll is smooth.
- [ ] Document is updated incrementally without resetting selections on updates.

## STOP conditions

- If `SuperEditor` selection crashes on incremental updates.
- If Riverpod notifier family fails to dispose FocusNode correctly.
