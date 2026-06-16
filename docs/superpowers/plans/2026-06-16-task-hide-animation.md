# Animação de Ocultação de Tarefas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a smooth fade out and size collapse animation when a task is completed and `hideCompleted` is enabled.

**Architecture:** Use `_animatingNodeIds` in `CustomTaskComponentBuilder` to temporarily keep completed tasks in the tree, while `CustomTaskComponent` animates its exit and triggers a callback to finally unmount it.

**Tech Stack:** Flutter, super_editor, Dart

---

### Task 1: Update `CustomTaskComponentBuilder` and `CustomTaskComponent` signatures

**Files:**
- Modify: `lib/features/notes/presentation/widgets/custom_task_component.dart`

- [ ] **Step 1: Make Builder fields mutable and add tracking state**

```dart
// Update CustomTaskComponentBuilder class
class CustomTaskComponentBuilder implements ComponentBuilder {
  CustomTaskComponentBuilder(
    this._editor, {
    this.taskMetadataById = const {},
    this.hideCompleted = false,
    this.onTaskLongPress,
    this.requestRebuild,
  });

  final Editor _editor;
  Map<String, TaskModel> taskMetadataById;
  bool hideCompleted;
  ValueChanged<String>? onTaskLongPress;
  final VoidCallback? requestRebuild;

  final Set<String> _animatingNodeIds = {};

// ...
```

- [ ] **Step 2: Add animation callback to the widget**

```dart
// Update CustomTaskComponent class
class CustomTaskComponent extends StatefulWidget {
  const CustomTaskComponent({
    super.key,
    required this.viewModel,
    this.taskMetadata,
    this.hideCompleted = false,
    this.onLongPress,
    this.onAnimationComplete,
  });

  final TaskComponentViewModel viewModel;
  final TaskModel? taskMetadata;
  final bool hideCompleted;
  final VoidCallback? onLongPress;
  final VoidCallback? onAnimationComplete;

// ...
```

- [ ] **Step 3: Update `createComponent` to pass these down**

```dart
// In CustomTaskComponentBuilder
  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! TaskComponentViewModel) return null;

    return CustomTaskComponent(
      key: componentContext.componentKey,
      viewModel: componentViewModel,
      taskMetadata: taskMetadataById[componentViewModel.nodeId],
      hideCompleted: hideCompleted,
      onLongPress: onTaskLongPress == null
          ? null
          : () => onTaskLongPress!(componentViewModel.nodeId),
      onAnimationComplete: () {
        _animatingNodeIds.remove(componentViewModel.nodeId);
        requestRebuild?.call();
      },
    );
  }
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/notes/presentation/widgets/custom_task_component.dart
git commit -m "refactor: update signatures for task component animation"
```

---

### Task 2: Intercept task completion to track animating nodes

**Files:**
- Modify: `lib/features/notes/presentation/widgets/custom_task_component.dart`

- [ ] **Step 1: Intercept `setComplete` and hide logic in `createViewModel`**

```dart
// Inside CustomTaskComponentBuilder
  @override
  TaskComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is! TaskNode) return null;
    
    if (hideCompleted && node.isComplete) {
      if (!_animatingNodeIds.contains(node.id)) {
        return null;
      }
    }

    return TaskComponentViewModel(
      nodeId: node.id,
      createdAt: node.metadata[NodeMetadata.createdAt],
      padding: EdgeInsets.zero,
      indent: node.indent,
      isComplete: node.isComplete,
      setComplete: (bool isComplete) {
        if (isComplete && hideCompleted) {
          _animatingNodeIds.add(node.id);
        }
        _editor.execute([
          ChangeTaskCompletionRequest(nodeId: node.id, isComplete: isComplete),
        ]);
      },
      text: node.text,
      textDirection: getParagraphDirection(node.text.toPlainText()),
      textAlignment: TextAlign.left,
      textStyleBuilder: noStyleBuilder,
      selectionColor: const Color(0x00000000),
    );
  }
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/notes/presentation/widgets/custom_task_component.dart
git commit -m "feat: track animating nodes in builder"
```

---

### Task 3: Implement Visual Animation

**Files:**
- Modify: `lib/features/notes/presentation/widgets/custom_task_component.dart`

- [ ] **Step 1: Add AnimationController to State**

```dart
// Change signature to include TickerProviderStateMixin
class _CustomTaskComponentState extends State<CustomTaskComponent>
    with ProxyDocumentComponent<CustomTaskComponent>, ProxyTextComposable, TickerProviderStateMixin {
  final _textKey = GlobalKey();
  
  late AnimationController _exitController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _sizeAnimation;

  @override
  void initState() {
    super.initState();
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
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

  @override
  void dispose() {
    _exitController.dispose();
    super.dispose();
  }
// ...
```

- [ ] **Step 2: Trigger animation on widget update**

```dart
  @override
  void didUpdateWidget(CustomTaskComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.hideCompleted && widget.viewModel.isComplete && !oldWidget.viewModel.isComplete) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _exitController.forward();
        }
      });
    }
  }
```

- [ ] **Step 3: Wrap `Row` in Transitions**

```dart
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final semantics = Theme.of(context).extension<AppSemanticColors>();
    final taskColor = semantics?.task ?? AppColors.taskAccent;
    const checkboxSize = 22.0;

    final content = Directionality(
      textDirection: widget.viewModel.textDirection,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: defaultTaskIndentCalculator(
              widget.viewModel.textStyleBuilder({}),
              widget.viewModel.indent,
            ),
          ),
          AnimatedTaskCheckbox(
            size: checkboxSize,
            value: widget.viewModel.isComplete,
            activeColor: taskColor,
            inactiveColor: colorScheme.outline,
            checkmarkColor: Colors.white,
            onChanged: widget.viewModel.setComplete,
            onLongPress: widget.onLongPress,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2, right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextComponent(
                    key: _textKey,
                    text: widget.viewModel.text,
                    textDirection: widget.viewModel.textDirection,
                    textAlign: widget.viewModel.textAlignment,
                    maxLines: widget.viewModel.maxLines,
                    overflow: widget.viewModel.overflow,
                    textStyleBuilder: (attributions) =>
                        _computeStyles(attributions, context),
                    inlineWidgetBuilders:
                        widget.viewModel.inlineWidgetBuilders,
                    textSelection: widget.viewModel.selection,
                    selectionColor: widget.viewModel.selectionColor,
                    highlightWhenEmpty: widget.viewModel.highlightWhenEmpty,
                    underlines: widget.viewModel.createUnderlines(),
                  ),
                  if (widget.taskMetadata?.dueDate != null ||
                      widget.taskMetadata?.recurrence != null) ...[
                    const SizedBox(height: 4),
                    TaskMetadataBadges(
                      dueDate: widget.taskMetadata?.dueDate,
                      recurrence: widget.taskMetadata?.recurrence,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return SizeTransition(
      sizeFactor: _sizeAnimation,
      axisAlignment: -1.0,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: content,
      ),
    );
  }
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/notes/presentation/widgets/custom_task_component.dart
git commit -m "feat: animate task component exit"
```

---

### Task 4: Persist Builder in NoteEditor

**Files:**
- Modify: `lib/features/notes/presentation/widgets/note_editor.dart`

- [ ] **Step 1: Declare and initialize builder in state**

```dart
class _NoteEditorState extends State<NoteEditor> {
  NoteEditorController? _controller;
  final _docLayoutKey = GlobalKey();
  RichSuperEditorIosControlsController? _iosController;
  SuperEditorAndroidControlsController? _androidController;
  RichCommonEditorOperations? _richOps;
  
  late CustomTaskComponentBuilder _taskComponentBuilder;

  @override
  void initState() {
    super.initState();
    _controller = NoteEditorController(
      snapshotSave: widget.snapshotSave,
      emptyNoteExit: widget.emptyNoteExit,
    );
    String content = widget.content;
    if (widget.title != null && widget.title!.isNotEmpty) {
      final title = widget.title!.trim();
      final startsWithH1Title = content.trimLeft().startsWith('# $title') ||
          content.trimLeft().startsWith('#  $title');
      if (!startsWithH1Title) {
        content = '# $title\n\n$content';
      }
    }
    _controller!.bind(widget.noteId);
    _controller!.init(content: content);
    _controller!.document?.addListener(_onDocumentChanged);
    _notifyContentChanged();

    _taskComponentBuilder = CustomTaskComponentBuilder(
      _controller!.editor!,
      taskMetadataById: widget.taskMetadata,
      hideCompleted: widget.hideCompleted,
      onTaskLongPress: (taskId) => widget.onTaskLongPress?.call(
        taskId,
        () => _controller!.persistSnapshotNow(),
      ),
      requestRebuild: () {
        if (mounted) setState(() {});
      },
    );
  }
```

- [ ] **Step 2: Update builder fields in `didUpdateWidget`**

```dart
  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _taskComponentBuilder.taskMetadataById = widget.taskMetadata;
    _taskComponentBuilder.hideCompleted = widget.hideCompleted;
    _taskComponentBuilder.onTaskLongPress = (taskId) => widget.onTaskLongPress?.call(
      taskId,
      () => _controller?.persistSnapshotNow() ?? Future.value(),
    );
  }
```

- [ ] **Step 3: Use builder in `SuperEditor`**

In the `build` method, replace the inline `CustomTaskComponentBuilder` instantiation:

```dart
                      componentBuilders: [
                        const CustomDividerComponentBuilder(),
                        ...defaultComponentBuilders,
                        _taskComponentBuilder,
                      ],
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/notes/presentation/widgets/note_editor.dart
git commit -m "feat: persist CustomTaskComponentBuilder to support exit animations"
```
