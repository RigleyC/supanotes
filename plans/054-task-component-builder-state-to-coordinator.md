# Plan 054: Extract `CustomTaskComponentBuilder` State Into a Dedicated Coordinator Widget

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat bfebe7e..HEAD -- lib/features/notes/presentation/widgets/custom_task_component.dart lib/features/notes/presentation/widgets/note_editor.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: tech-debt | architecture
- **Planned at**: commit `bfebe7e`, 2026-07-06

## Why this matters

`CustomTaskComponentBuilder` is a `ComponentBuilder` — a stateless factory
that produces a view model and a widget per document node. But it carries
mutable per-node state: `_animatingNodeIds` and `_completingTaskIds`
(line 34-35). It `requestRebuild?.call()`s — meaning it mutates the parent
`_NoteEditorState` from within a builder that the `SuperEditor` invokes
during its layout pass. This is the architecture smell behind several
intermittent animation glitches: the builder instance is shared across
builds, but Riverpod's `autoDispose` and the `SuperEditor`'s scheduler can
re-instantiate the part-List it iterates, leaving the builder with
references to node ids whose animation `_exitController` is now disposed.
The state belongs in a `StatefulWidget`, where lifecycle and listener
removal are explicit.

## Current state

### Files in scope

- `lib/features/notes/presentation/widgets/custom_task_component.dart` — the
  builder (lines 16-122) and the component widget (lines 156-345).
- `lib/features/notes/presentation/widgets/note_editor.dart` — where the
  builder is constructed (lines 78-93) and used in `componentBuilders`
  (line 271).
- `lib/features/notes/presentation/widgets/note_editor.dart` `didUpdateWidget`
  (lines 134-158) — which mutates the builder's fields directly.

### Current code

`custom_task_component.dart` (lines 16-35):

```dart
class CustomTaskComponentBuilder implements ComponentBuilder {
  CustomTaskComponentBuilder({
    this.composer,
    this.taskMetadataById = const {},
    this.hideCompleted = false,
    this.onTaskLongPress,
    this.onTaskComplete,
    this.onTaskReopen,
    this.requestRebuild,
  });

  final MutableDocumentComposer? composer;
  Map<String, TaskModel> taskMetadataById;
  bool hideCompleted;
  ValueChanged<String>? onTaskLongPress;
  final Future<DateTime?> Function(String taskId)? onTaskComplete;
  final Future<void> Function(String taskId)? onTaskReopen;
  final VoidCallback? requestRebuild;
  final Set<String> _animatingNodeIds = {};
  final Set<String> _completingTaskIds = {};
```

`note_editor.dart` (lines 78-93):

```dart
_taskComponentBuilder = CustomTaskComponentBuilder(
  composer: _controller!.composer,
  taskMetadataById: widget.taskMetadata,
  hideCompleted: widget.hideCompleted,
  onTaskLongPress: widget.isReadOnly
      ? null
      : (taskId) => widget.delegate.onTaskLongPress?.call(
          widget.taskMetadata[taskId],
          () async {},
        ),
  onTaskComplete: widget.delegate.onTaskComplete,
  onTaskReopen: widget.delegate.onTaskReopen,
  requestRebuild: () {
    if (mounted) setState(() {});
  },
);
```

`note_editor.dart` (lines 134-158) — mutations during `didUpdateWidget`:

```dart
@override
void didUpdateWidget(NoteEditor oldWidget) {
  super.didUpdateWidget(oldWidget);
  _taskComponentBuilder.taskMetadataById = widget.taskMetadata;
  _taskComponentBuilder.hideCompleted = widget.hideCompleted;
  _taskComponentBuilder.onTaskLongPress = widget.isReadOnly
      ? null
      : (taskId) => widget.delegate.onTaskLongPress?.call(
          widget.taskMetadata[taskId],
          () async {},
        );
  // ...
```

Mutating an object held by `SuperEditor` mid-build is brittle.

### Repository conventions

- `ComponentBuilder`s in `super_editor` are typically stateless. Existing
  examples in `defaultComponentBuilders` are pure.
- Flutter conventions: `StatefulWidget` for state-set interaction with
  `setState` callbacks; `InheritedWidget` / `Provider` for shared state.
- For this builder, a coordinator pattern fits: a `StatefulWidget` owns the
  task animation state; it sits ABOVE the `SuperEditor`, exposes methods
  for the component to call; on dispose, the state is gc'd naturally.
- The existing `_NoteEditorState` already plays the role of a coordinator —
  the `requestRebuild: () { if (mounted) setState(() {}); }` callback
  pattern confirms this. We need to formalize it: move
  `_animatingNodeIds` and `_completingTaskIds` from `CustomTaskComponentBuilder`
  to the `_NoteEditorState` and pass them via a lightweight
  `InheritedWidget` or callback closures to the builder.
- Do not add code comments unless asked by the plan.

## Commands you will need

| Purpose          | Command                                                              | Expected on success |
|------------------|----------------------------------------------------------------------|---------------------|
| Static analysis  | `dart analyze lib/features/notes/presentation/widgets/custom_task_component.dart lib/features/notes/presentation/widgets/note_editor.dart` | no errors |
| Run editor tests | `flutter test test/features/notes/presentation/`                   | all pass            |

## Scope

**In scope** (the only files you should modify):
- `lib/features/notes/presentation/widgets/custom_task_component.dart`
- `lib/features/notes/presentation/widgets/note_editor.dart`

**Out of scope** (do NOT touch):
- `attachment_components.dart` — applies a similar pattern but is simpler
  (no animation). Out of scope for this plan.
- `_CustomTaskComponentState` — keeps its local `_exitController`. The
  builder-coordination is the bug we're fixing.
- `task_model.dart`, `task_recurrence.dart` — domain types unchanged.
- Tests.

## Git workflow

- Branch: `refactor/054-task-component-builder-state"`
- Commit: `refactor(editor): move task animation state to NoteEditor coordinator`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Define a `TaskAnimationCoordinator` InheritedWidget

Open `lib/features/notes/presentation/widgets/custom_task_component.dart`.
At the top, after imports, add a coordinator widget:

```dart
class TaskAnimationCoordinator extends InheritedWidget {
  const TaskAnimationCoordinator({
    super.key,
    required this.animatingNodeIds,
    required this.completingTaskIds,
    required this.markAnimating,
    required this.markCompleting,
    required this.unmarkAnimating,
    required this.unmarkCompleting,
    required super.child,
  });

  final Set<String> animatingNodeIds;
  final Set<String> completingTaskIds;
  final void Function(String nodeId) markAnimating;
  final void Function(String nodeId) markCompleting;
  final void Function(String nodeId) unmarkAnimating;
  final void Function(String nodeId) unmarkCompleting;

  static TaskAnimationCoordinator of(BuildContext context) {
    final coordinator = context
        .dependOnInheritedWidgetOfExactType<TaskAnimationCoordinator>();
    assert(coordinator != null, 'TaskAnimationCoordinator not found in ancestor');
    return coordinator!;
  }

  @override
  bool updateShouldNotify(TaskAnimationCoordinator oldWidget) {
    return !setEquals(animatingNodeIds, oldWidget.animatingNodeIds) ||
        !setEquals(completingTaskIds, oldWidget.completingTaskIds);
  }
}

bool setEquals(Set<String> a, Set<String> b) {
  if (a.length != b.length) return false;
  return a.containsAll(b);
}
```

(Or use `package:collection`'s `SetEquality` if it's already in pubspec —
read pubspec.lock and prefer using existing package; otherwise the manual
equality is fine.)

### Step 2: Remove state fields from `CustomTaskComponentBuilder`

In the same file, remove `_animatingNodeIds` and `_completingTaskIds` from
`CustomTaskComponentBuilder`. The builder now reads coordination state from
the context via `TaskAnimationCoordinator.of(context)` inside
`createComponent` (where it has access to `BuildContext`).

```dart
class CustomTaskComponentBuilder implements ComponentBuilder {
  CustomTaskComponentBuilder({
    this.composer,
    this.taskMetadataById = const {},
    this.hideCompleted = false,
    this.onTaskLongPress,
    this.onTaskComplete,
    this.onTaskReopen,
  });

  final MutableDocumentComposer? composer;
  Map<String, TaskModel> taskMetadataById;
  bool hideCompleted;
  ValueChanged<String>? onTaskLongPress;
  final Future<DateTime?> Function(String taskId)? onTaskComplete;
  final Future<void> Function(String taskId)? onTaskReopen;
```

Drop `requestRebuild` too — it's no longer needed because the
coordinator's `setState` will trigger the rebuild via the InheritedWidget's
`updateShouldNotify`.

### Step 3: Use coordinator in `createViewModel` / `createComponent`

In `CustomTaskComponentBuilder.createViewModel`, the `setComplete` callback
uses `_completingTaskIds`. Without the builder field, the callback must
obtain the coordinator at the moment the user interacts with the checkbox,
which is inside `createComponent` (where `BuildContext` is available):

Update `createViewModel` to take `setCompleteBuilder` callback that's
injected from `createComponent`:

```dart
@override
TaskComponentViewModel? createViewModel(
  Document document,
  DocumentNode node,
) {
  if (node is! TaskNode) return null;

  final metadata = taskMetadataById[node.id];

  return CustomTaskComponentViewModel(
    nodeId: node.id,
    createdAt: node.metadata[NodeMetadata.createdAt],
    padding: EdgeInsets.zero,
    indent: node.indent,
    isComplete: node.isComplete,
    setComplete: null, // Filled by createComponent via coordinator
    text: node.text,
    textDirection: getParagraphDirection(node.text.toPlainText()),
    textAlignment: TextAlign.left,
    textStyleBuilder: noStyleBuilder,
    selectionColor: const Color(0x00000000),
    dueDate: metadata?.dueDate,
    recurrence: metadata?.recurrence,
  );
}
```

Wait — `createViewModel` may not have access to `BuildContext`. Check the
super_editor API: `ComponentBuilder.createViewModel(Document, DocumentNode)`
receives NO context. So the coordinator lookup must happen in
`createComponent`.

Approach: leave the `setComplete` callback as `null` during
`createViewModel`, then in `createComponent`, find the matching
`TaskComponentViewModel` and inject the real callback. But
`componentViewModel` passed to `createComponent` is the view model freshly
built; we can mutate it. Alternatively, recreate a new
`TaskComponentViewModel` instance with `setComplete` injected.

Simpler approach: continue to construct `setComplete` inside
`createViewModel`, but have it look up the coordinator LAZILY (only when
called by the user, which is after `createComponent` ran with a context,
and the `_CustomTaskComponentState` is mounted). To pass context into
`setComplete`, we need a builder function:

```dart
class CustomTaskComponentBuilder implements ComponentBuilder {
  // ...
  final BuildContext Function()? contextResolver;
  // ...
}
```

No — `ComponentBuilder` is called without a context, the resolver would
return stale context. Better: in `createComponent`, where `context` is
available, look up the coordinator, then COPY the view model with the
correct `setComplete`:

```dart
@override
Widget? createComponent(
  SingleColumnDocumentComponentContext componentContext,
  SingleColumnLayoutComponentViewModel componentViewModel,
) {
  if (componentViewModel is! CustomTaskComponentViewModel) return null;

  final nodeId = componentViewModel.nodeId;
  final coordinator = TaskAnimationCoordinator.of(componentContext.context);

  if (hideCompleted &&
      componentViewModel.isComplete &&
      !coordinator.animatingNodeIds.contains(nodeId)) {
    return SizedBox(key: componentContext.componentKey, height: 0);
  }

  // Inject the real setComplete with coordinator logic
  final modifiedViewModel = CustomTaskComponentViewModel(
    nodeId: nodeId,
    createdAt: componentViewModel.createdAt,
    padding: componentViewModel.padding,
    indent: componentViewModel.indent,
    isComplete: coordinator.completingTaskIds.contains(nodeId) ||
        componentViewModel.isComplete,
    setComplete: (bool isComplete) async {
      final taskNode = componentViewModel;
      if (isComplete) {
        final isRecurring =
            taskMetadataById[nodeId]?.recurrence != null;

        if (isRecurring) {
          coordinator.markCompleting(nodeId);
        }

        if (hideCompleted) {
          coordinator.markAnimating(nodeId);
          FocusManager.instance.primaryFocus?.unfocus();
          composer?.clearSelection();
        }

        try {
          final nextDue = await onTaskComplete?.call(nodeId);
          if (nextDue != null && isRecurring) {
            await Future.delayed(const Duration(seconds: 1));
          }
        } finally {
          if (isRecurring) {
            coordinator.unmarkCompleting(nodeId);
          }
        }
      } else {
        await onTaskReopen?.call(nodeId);
      }
    },
    text: componentViewModel.text,
    textDirection: componentViewModel.textDirection,
    textAlignment: componentViewModel.textAlignment,
    textStyleBuilder: componentViewModel.textStyleBuilder,
    selectionColor: componentViewModel.selectionColor,
    dueDate: (componentViewModel as CustomTaskComponentViewModel).dueDate,
    recurrence: (componentViewModel as CustomTaskComponentViewModel).recurrence,
  );

  return CustomTaskComponent(
    key: componentContext.componentKey,
    viewModel: modifiedViewModel,
    taskMetadata: taskMetadataById[nodeId],
    hideCompleted: hideCompleted,
    onLongPress: onTaskLongPress == null ? null : () => onTaskLongPress!(nodeId),
    onAnimationComplete: () {
      coordinator.unmarkAnimating(nodeId);
    },
  );
}
```

`SingleColumnDocumentComponentContext` — confirm the field name by
inspecting super_editor API. Likely `componentContext.context` is the
super's BuildContext; check existing `AttachmentComponentBuilder.createComponent`
for clues — it doesn't use context, so re-read the super_editor API to find
which `BuildContext` is passed.

If `SingleColumnDocumentComponentContext` doesn't expose `BuildContext`, an
`InheritedWidget` lookup during the `createComponent` call won't work. In
that case, use a **callback-driven coordinator**: store the
`TaskAnimationCoordinator` in `CustomTaskComponentBuilder` via a setter
called from `_NoteEditorState`, OR use a `ValueNotifier` set passed in the
constructor.

Simpler approach — use `ValueNotifier<Set<String>>` for both
`_animatingNodeIds` and `_completingTaskIds`, passed from
`_NoteEditorState`. The builder reads via `.value`, listens via
`addListener`. No InheritedWidget needed:

```dart
class CustomTaskComponentBuilder implements ComponentBuilder {
  CustomTaskComponentBuilder({
    this.composer,
    this.taskMetadataById = const {},
    this.hideCompleted = false,
    this.onTaskLongPress,
    this.onTaskComplete,
    this.onTaskReopen,
    this.animatingNodeIds,
    this.completingTaskIds,
    this.onAnimationComplete,
  });

  final MutableDocumentComposer? composer;
  Map<String, TaskModel> taskMetadataById;
  bool hideCompleted;
  ValueChanged<String>? onTaskLongPress;
  final Future<DateTime?> Function(String taskId)? onTaskComplete;
  final Future<void> Function(String taskId)? onTaskReopen;
  final ValueNotifier<Set<String>>? animatingNodeIds;
  final ValueNotifier<Set<String>>? completingTaskIds;
  final ValueChanged<String>? onAnimationComplete;
```

`_NoteEditorState` creates and disposes these `ValueNotifier`s. The
callback `onAnimationComplete` is wired through to `CustomTaskComponent`'s
own lifecycle.

Choose the `ValueNotifier` approach if `BuildContext` is unavailable in
`createComponent`; otherwise prefer the InheritedWidget.

### Step 4: Update `_NoteEditorState` to manage the notifier state

In `lib/features/notes/presentation/widgets/note_editor.dart`:

Add fields (after `RichCommonEditorOperations? _richOps;` at line 58):

```dart
final _animatingNodeIds = ValueNotifier<Set<String>>(const {});
final _completingTaskIds = ValueNotifier<Set<String>>(const {});
```

In `initState`, after `_taskComponentBuilder = CustomTaskComponentBuilder(...)`
(lines 78-93), update the constructor to pass these notifiers:

```dart
_taskComponentBuilder = CustomTaskComponentBuilder(
  composer: _controller!.composer,
  taskMetadataById: widget.taskMetadata,
  hideCompleted: widget.hideCompleted,
  onTaskLongPress: widget.isReadOnly ? null : (taskId) => widget.delegate.onTaskLongPress?.call(widget.taskMetadata[taskId], () async {}),
  onTaskComplete: widget.delegate.onTaskComplete,
  onTaskReopen: widget.delegate.onTaskReopen,
  animatingNodeIds: _animatingNodeIds,
  completingTaskIds: _completingTaskIds,
  onAnimationComplete: (nodeId) {
    final current = Set<String>.from(_animatingNodeIds.value);
    current.remove(nodeId);
    _animatingNodeIds.value = current;
  },
);
```

Drop the `requestRebuild` parameter — no longer needed.

Update `setComplete` helper methods in the builder that mutate
`_animatingNodeIds` / `_completingTaskIds` to instead mutate the notifiers
(opaquely through the builder's `markAnimating`/`markCompleting` helpers).
The easiest is to expose helper methods on the builder:

```dart
void _markAnimating(String nodeId) {
  final current = Set<String>.from(animatingNodeIds?.value ?? const {});
  current.add(nodeId);
  animatingNodeIds?.value = current;
}

void _unmarkAnimating(String nodeId) {
  final current = Set<String>.from(animatingNodeIds?.value ?? const {});
  current.remove(nodeId);
  animatingNodeIds?.value = current;
}
// (Same for completingTaskIds)
```

And call `_markAnimating(node.id)` / `_unmarkAnimating(node.id)` /
`_markCompleting(node.id)` / `_unmarkCompleting(node.id)` inside the
`setComplete` callback.

Add `addListener` to these notifiers so the `SuperEditor` rebuilds on
change. In `_NoteEditorState.initState`:

```dart
_animatingNodeIds.addListener(_onTaskAnimationsChanged);
_completingTaskIds.addListener(_onTaskAnimationsChanged);
```

Add the listener method:

```dart
void _onTaskAnimationsChanged() {
  if (mounted) setState(() {});
}
```

In `dispose`:

```dart
_animatingNodeIds.removeListener(_onTaskAnimationsChanged);
_completingTaskIds.removeListener(_onTaskAnimationsChanged);
_animatingNodeIds.dispose();
_completingTaskIds.dispose();
```

### Step 5: Update `didUpdateWidget` to use the new field shape

In `note_editor.dart` `didUpdateWidget` (lines 134-158), remove the
`_taskComponentBuilder.requestRebuild` reference and ensure the same
field-mutation pattern works without it. The mutations of `taskMetadataById`
and `hideCompleted` remain; only `requestRebuild` is no longer needed.

### Step 6: Verify

**Verify**: `dart analyze lib/features/notes/presentation/widgets/custom_task_component.dart lib/features/notes/presentation/widgets/note_editor.dart`
→ no errors.

**Verify**: `flutter test test/features/notes/presentation/`
→ all pass.

**Verify**:
```bash
Select-String -Path lib/features/notes/presentation/widgets/custom_task_component.dart -Pattern "_animatingNodeIds|_completingTaskIds"
```
Expected: no matches as INSTANCE FIELDS on `CustomTaskComponentBuilder` (still allowed as references through the `animatingNodeIds` / `completingTaskIds` constructor fields with the notifier; just no own mutable set).

## Test plan

No new tests — the existing screen-level tests pass through the same
NoteEditor. The change is internal state relocation.

- `flutter test test/features/notes/` → all pass

## Done criteria

- [ ] `CustomTaskComponentBuilder` no longer declares mutable `_animatingNodeIds` / `_completingTaskIds` set fields
- [ ] `_NoteEditorState` owns `ValueNotifier<Set<String>>` for both, with proper listener / dispose
- [ ] `setComplete` callback uses notifier mutations via builder helper methods
- [ ] `onAnimationComplete` updates notifier value (not a static field)
- [ ] `requestRebuild` parameter removed from builder and from all call sites
- [ ] `dart analyze` exits 0 for both modified files
- [ ] `flutter test test/features/notes/` exits 0
- [ ] `git diff --name-only` shows only `custom_task_component.dart` and `note_editor.dart`
- [ ] `plans/README.md` status row for 054 updated to DONE

## STOP conditions

Stop and report back (do not improvise) if:

- `SingleColumnDocumentComponentContext.context` exists in the live
  super_editor API version, and the InheritedWidget approach is
  preferable to ValueNotifier — choose whichever fares better; document
  the choice in the commit message. If you choose InheritedWidget, drop
  the ValueNotifier fields and rely on `updateShouldNotify`.
- The `ComponentBuilder.createViewModel` API needs a context — if
  `super_editor` exposes a `BuildContext` parameter, simplify the plan
  by reading the coordinator directly inside `createViewModel` instead
  of injecting through `createComponent`. STOP and report; do not
  improvise API.
- `setState` from a notifier listener causes an exception
  ("setState() called after dispose()") — confirm the listener is removed
  in `dispose()` BEFORE the notifier is disposed. If tests still fail,
  restructure so `setState` is guarded by `mounted`.
- Smoke-testing recurring task animation reveals the
  `_completingTaskIds` notifier rebuild is delayed; investigate timing
  — the `Future.delayed(const Duration(seconds: 1))` should be inside
  `setComplete` as before; if removed accidentally, restore it.
- Tests reveal `IncrementalSet` equality issues with `setEquals` — use
  `SetEquality<String>().equals(a, b)` from `package:collection` if it's
  in pubspec (check pubspec.lock).

## Maintenance notes

- Adding new per-node animation state in the task component MUST follow
  this coordinator pattern: never add a field to
  `CustomTaskComponentBuilder` again. Use a `ValueNotifier` on
  `_NoteEditorState`.
- A reviewer should scrutinize: did `_NoteEditorState.dispose()` remove
  the listeners BEFORE disposing the notifiers? Otherwise the
  `setState()` guard will fire on a disposed state — must remove
  listeners first.
- Future plans that add other node-type animation (e.g.,
  `AttachmentComponentBuilder` progress bar) should follow the same
  pattern: `ValueNotifier` on `_NoteEditorState`, never on the builder.
- The closing feedback loop (toolbar reads from `composingTaskIds`) is
  not affected — toolbar doesn't read these notifiers. Don't wire that
  unless needed.
- Recurring-task delay (`await Future.delayed(const Duration(seconds: 1))`)
  is preserved; it's the time the visual checkbox stays "checked" before
  the DB stream updates it back to "open" for the next occurrence. Don't
  remove it.