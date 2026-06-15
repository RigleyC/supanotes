# Plan 019: Simplify CustomTaskComponent while keeping animated checkbox

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 4639d85..HEAD -- lib/features/notes/presentation/widgets/custom_task_component.dart test/features/notes/presentation/widgets/custom_task_component_test.dart lib/shared/widgets/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: 018
- **Category**: tech-debt
- **Planned at**: commit `4639d85`, 2026-06-15
- **Issue**: (none)

## Why this matters

`CustomTaskComponent` today has 468 lines. It reimplements pointer detection, caret placement, and a checkbox animation that overlaps with `super_editor`'s built-in `TaskComponent`. The product requires the checkbox to remain animated, but the surrounding code can be much simpler. The goal is to keep the animated visual and the metadata badges, while delegating text interaction and task editing semantics back to `super_editor` primitives. This reduces the file to ~150 lines, removes brittle pointer/caret code, and makes the widget easier to test.

## Current state

- `lib/features/notes/presentation/widgets/custom_task_component.dart` (468 lines)
  - `CustomTaskComponentBuilder` — creates `TaskComponentViewModel` and `CustomTaskComponent`.
  - `CustomTaskComponent` — `StatefulWidget` with `ProxyDocumentComponent`, `ProxyTextComposable`, pointer handling, long-press timer, caret placement.
  - `_AnimatedTaskCheckbox` + `_CheckmarkPainter` + `_CheckmarkPaint` — custom checkbox animation (~150 lines).
- `test/features/notes/presentation/widgets/custom_task_component_test.dart` — existing widget tests.
- `lib/features/tasks/presentation/widgets/task_metadata_badges.dart` — badges for due date/recurrence.

Current excerpt (pointer handling, lines 178–214):

```dart
void _onPointerDown(PointerDownEvent event) { ... }
void _onPointerMove(PointerMoveEvent event) { ... }
void _onPointerUp(PointerUpEvent event) { ... }
void _onPointerCancel(PointerCancelEvent event) { ... }
```

Current excerpt (caret placement, lines 140–167):

```dart
void _placeCaretAt(Offset globalOffset) {
  final editor = widget.editor;
  final textContext = _textKey.currentContext;
  ...
  widget.focusNode?.requestFocus();
  editor.execute([ChangeSelectionRequest(...)]);
}
```

Repo conventions:
- Widgets go in `lib/features/<feature>/presentation/widgets/`.
- Reusable UI primitives go in `lib/shared/widgets/`.
- File naming: `snake_case.dart`.

## Commands you will need

| Purpose   | Command | Expected on success |
|-----------|---------|---------------------|
| Analyze   | `flutter analyze lib/features/notes` | no issues |
| Tests     | `flutter test test/features/notes/presentation/widgets/custom_task_component_test.dart` | all pass |
| Tests     | `flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart` | all pass |
| Tests     | `flutter test test/features/notes` | all pass |
| Tests     | `flutter test` | all pass |

## Suggested executor toolkit

- Read `super_editor/src/default_editor/tasks.dart` at the pinned ref to see the default `TaskComponent` and `TaskComponentViewModel`.
- Use `flutter-add-widget-test` skill if writing new widget tests.

## Scope

**In scope**:
- `lib/features/notes/presentation/widgets/custom_task_component.dart` — rewrite
- `lib/shared/widgets/animated_task_checkbox.dart` — create
- `test/features/notes/presentation/widgets/custom_task_component_test.dart` — update
- `lib/features/notes/presentation/note_editor_screen.dart` — update `componentBuilders` if needed
- `lib/features/notes/presentation/inbox_screen.dart` — update `componentBuilders` if needed

**Out of scope**:
- Changing `TaskModel` or task storage.
- Changing `TaskMetadataBadges` design.
- Removing the animated checkbox visual.
- Refactoring the toolbar or screen shells (covered by plan 021/022).

## Git workflow

- Branch: `feat/019-simplify-task-component`
- Commit per step; messages like `refactor(notes): simplify custom task component`, `feat(shared): extract animated task checkbox`, `test(notes): update task component tests`.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Extract the animated checkbox into a reusable shared widget

Create `lib/shared/widgets/animated_task_checkbox.dart` containing only the animated checkbox extracted from `custom_task_component.dart`:

```dart
class AnimatedTaskCheckbox extends StatefulWidget {
  const AnimatedTaskCheckbox({
    super.key,
    required this.value,
    required this.activeColor,
    required this.inactiveColor,
    this.checkmarkColor = Colors.white,
    this.size = 22.0,
    this.onChanged,
  });

  final bool value;
  final Color activeColor;
  final Color inactiveColor;
  final Color checkmarkColor;
  final double size;
  final ValueChanged<bool>? onChanged;

  @override
  State<AnimatedTaskCheckbox> createState() => _AnimatedTaskCheckboxState();
}
```

Move `_AnimatedTaskCheckboxState`, `_CheckmarkPainter`, and `_CheckmarkPaint` into this file. Keep the existing animation behavior exactly.

**Verify**: `flutter analyze lib/shared/widgets/animated_task_checkbox.dart` → no issues.

### Step 2: Rewrite `CustomTaskComponent` to remove manual pointer/caret handling

The new `CustomTaskComponent` should:

- Wrap the default `super_editor` text handling with a `GestureDetector` for long press.
- Use `AnimatedTaskCheckbox` for the checkbox.
- Display `TaskMetadataBadges` below the text when metadata exists.
- No longer implement `ProxyDocumentComponent` or `ProxyTextComposable` manually; rely on `super_editor`'s `TaskComponent` or on a `TextComponent` wrapped correctly.

Recommended shape:

```dart
class CustomTaskComponentBuilder implements ComponentBuilder {
  CustomTaskComponentBuilder(
    this._editor, {
    this.taskMetadataById = const {},
    this.focusNode,
    this.onTaskLongPress,
  });

  final Editor _editor;
  final FocusNode? focusNode;
  final Map<String, TaskModel> taskMetadataById;
  final ValueChanged<String>? onTaskLongPress;

  @override
  TaskComponentViewModel? createViewModel(Document document, DocumentNode node) {
    if (node is! TaskNode) return null;
    return TaskComponentViewModel(
      nodeId: node.id,
      createdAt: node.metadata[NodeMetadata.createdAt],
      padding: EdgeInsets.zero,
      indent: node.indent,
      isComplete: node.isComplete,
      setComplete: (bool isComplete) {
        _editor.execute([ChangeTaskCompletionRequest(nodeId: node.id, isComplete: isComplete)]);
      },
      text: node.text,
      textDirection: getParagraphDirection(node.text.toPlainText()),
      textAlignment: TextAlign.left,
      textStyleBuilder: noStyleBuilder,
      selectionColor: const Color(0x00000000),
    );
  }

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
      onLongPress: onTaskLongPress == null
          ? null
          : () => onTaskLongPress!(componentViewModel.nodeId),
    );
  }
}
```

```dart
class CustomTaskComponent extends StatelessWidget {
  const CustomTaskComponent({
    super.key,
    required this.viewModel,
    this.taskMetadata,
    this.onLongPress,
  });

  final TaskComponentViewModel viewModel;
  final TaskModel? taskMetadata;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final semantics = Theme.of(context).extension<AppSemanticColors>();
    final taskColor = semantics?.task ?? AppColors.taskAccent;
    final checkboxSize = 22.0;

    return Directionality(
      textDirection: viewModel.textDirection,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: defaultTaskIndentCalculator(
              viewModel.textStyleBuilder({}),
              viewModel.indent,
            ),
          ),
          AnimatedTaskCheckbox(
            size: checkboxSize,
            value: viewModel.isComplete,
            activeColor: taskColor,
            inactiveColor: colorScheme.outline,
            checkmarkColor: Colors.white,
            onChanged: viewModel.setComplete,
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPress: onLongPress,
              child: Padding(
                padding: const EdgeInsets.only(top: 2, right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextComponent(
                      text: viewModel.text,
                      textDirection: viewModel.textDirection,
                      textAlign: viewModel.textAlignment,
                      maxLines: viewModel.maxLines,
                      overflow: viewModel.overflow,
                      textStyleBuilder: _computeStyles,
                      inlineWidgetBuilders: viewModel.inlineWidgetBuilders,
                      textSelection: viewModel.selection,
                      selectionColor: viewModel.selectionColor,
                      highlightWhenEmpty: viewModel.highlightWhenEmpty,
                      underlines: viewModel.createUnderlines(),
                    ),
                    if (taskMetadata?.dueDate != null || taskMetadata?.recurrence != null) ...[
                      const SizedBox(height: 4),
                      TaskMetadataBadges(
                        dueDate: taskMetadata?.dueDate,
                        recurrence: taskMetadata?.recurrence,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _computeStyles(Set<Attribution> attributions) {
    final style = viewModel.textStyleBuilder(attributions);
    final baseColor = style.color ?? Colors.black; // fallback handled by theme
    final muted = baseColor.withValues(alpha: viewModel.isComplete ? 0.5 : 1.0);
    return viewModel.isComplete
        ? style.copyWith(decoration: TextDecoration.lineThrough, color: muted)
        : style.copyWith(color: baseColor);
  }
}
```

Notes:
- The `TextComponent` no longer needs a `GlobalKey` unless tests depend on it.
- `GestureDetector` with `behavior: HitTestBehavior.translucent` handles long press reliably.
- The checkbox `onChanged` is `ValueChanged<bool>?`; the callback can toggle directly inside `setComplete` of the view model, or you can pass `viewModel.setComplete` directly if it already receives the new value.

**Verify**: `flutter analyze lib/features/notes/presentation/widgets/custom_task_component.dart` → no issues.

### Step 3: Update screen builders if signature changed

If `CustomTaskComponentBuilder` constructor signature stayed the same, no change is needed. If you removed `editor`/`focusNode` from the constructor (because the component no longer needs them), update:

- `note_editor_screen.dart` line 207
- `inbox_screen.dart` line 226
- `note_toolbar_test.dart` lines 62, 154, 205, 268, 330, 384, 438, 544, 598

**Verify**: `flutter analyze lib/features/notes` → no issues.

### Step 4: Update task component tests

Update `test/features/notes/presentation/widgets/custom_task_component_test.dart`:

- Keep tests that verify:
  - Text remains editable inside the component.
  - Long press opens task actions.
  - Checkbox tap toggles completion.
  - Empty task converts to paragraph correctly (this tests `super_editor` behavior through the component).
- Remove tests that verified manual pointer coordinates or caret placement — that code is gone.
- Add a test that verifies `AnimatedTaskCheckbox` animates between states (pump frames and check scale/opacity changes).

**Verify**: `flutter test test/features/notes/presentation/widgets/custom_task_component_test.dart` → all pass.

### Step 5: Run regression suite

**Verify**:
- `flutter test test/features/notes/presentation/widgets/note_toolbar_test.dart` → all pass.
- `flutter test test/features/notes` → all pass.
- `flutter test` → all pass.
- `flutter analyze` → no issues.

## Test plan

- Update `custom_task_component_test.dart` to match the simplified widget.
- Add one new test for `AnimatedTaskCheckbox` animation state change.
- Keep `note_toolbar_test.dart` green as regression guard for task conversion.
- Keep `note_editor_screen_test.dart` green as regression guard for screen integration.

## Done criteria

- [ ] `lib/shared/widgets/animated_task_checkbox.dart` exists and contains only the extracted checkbox animation.
- [ ] `lib/features/notes/presentation/widgets/custom_task_component.dart` is reduced to ~150–200 lines and no longer contains manual pointer/caret logic.
- [ ] `flutter analyze lib/features/notes` exits 0.
- [ ] `flutter test test/features/notes/presentation/widgets/custom_task_component_test.dart` exits 0.
- [ ] `flutter test test/features/notes` exits 0.
- [ ] `flutter test` exits 0.
- [ ] `plans/README.md` status row for plan 019 updated to DONE.

## STOP conditions

Stop and report if:
- Removing `ProxyDocumentComponent` / `ProxyTextComposable` breaks text selection or caret behavior inside tasks in integration tests.
- `GestureDetector.onLongPress` does not fire on the text area in widget tests.
- The animated checkbox no longer animates after extraction.
- Any screen needs changes beyond constructor signature updates.

## Maintenance notes

- Future visual changes to the checkbox should only touch `lib/shared/widgets/animated_task_checkbox.dart`.
- Future task metadata display changes should only touch `CustomTaskComponent` build method.
- Reviewers should confirm that task text selection, checkbox toggle, and long-press still work on device/emulator — widget tests may not catch all gesture interactions.
