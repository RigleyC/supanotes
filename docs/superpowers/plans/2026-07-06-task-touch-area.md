# Task Touch Area & Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify the two duplicated task checkboxes into a single purely-visual `AppTaskCheckbox`, enlarge touch areas to ≥48px, and simplify touch behaviour (tap concludes, long-press opens metadata) on both `TaskTile` and `CustomTaskComponent`.

**Architecture:** Replace `TaskCheckbox` (circle) and `AnimatedTaskCheckbox` (rounded square with `CustomPaint` check) with one `StatefulWidget` named `AppTaskCheckbox` that is purely visual — no `GestureDetector`, no `onChanged`. Animation (container fill + check path drawn progressively) controlled by an internal `AnimationController` driven off `didUpdateWidget`. Parents (`TaskTile`, `CustomTaskComponent`) own all gestures: tap toggles completion, long-press opens metadata, and (editor only) tap on the text region still edits.

**Tech Stack:** Flutter, `dart`, `super_editor`, Riverpod 3.x, `flutter_test`, `mockito`.

**Spec:** `docs/superpowers/specs/2026-07-06-task-touch-area-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `lib/shared/widgets/app_task_checkbox.dart` | **Create** | Purely-visual animated checkbox: circle/rounded variants, `AnimationController`-driven fill + `_CheckmarkPainter` path. |
| `test/shared/widgets/app_task_checkbox_test.dart` | **Create** | Render + animation transitions + shape variants. |
| `lib/features/tasks/presentation/widgets/task_tile.dart` | **Modify** | Replace `TaskCheckbox` w/ `AppTaskCheckbox` (visual). Wrap row in `GestureDetector` (tap→toggle, long-press→open metadata). Remove `Dismissible` + `_SwipeBackground` + `_MetaRow`. |
| `test/features/tasks/presentation/widgets/task_tile_test.dart` | **Modify** | Replace `onTap` param with `onToggleComplete`/`onOpenMetadata`; new tap & long-press assertions; remove swipe tests (none exist). |
| `lib/features/notes/presentation/widgets/task_exit_animator.dart` | **Create** | `StatefulWidget` wrapping `SizeTransition`+`FadeTransition` driven by `AnimationController`; exposes `forward()/reverse()` via `didUpdateWidget`. |
| `lib/features/notes/presentation/widgets/task_text_style_resolver.dart` | **Create** | Pure function `resolveTaskTextStyle(Set<Attribution>, TextStyle base, bool isComplete)` → mutates colour/lineThrough. |
| `test/features/notes/presentation/widgets/task_exit_animator_test.dart` | **Create** | Verifies forward/reverse + `onAnimationComplete` callback. |
| `lib/features/notes/presentation/widgets/custom_task_component.dart` | **Modify** | Slim to ~100 lines: replace `_TaskCheckboxHitTarget`+`AnimatedTaskCheckbox` with `AppTaskCheckbox`; wrap row in `GestureDetector(behavior: translucent, onTap, onLongPress)`; delegate exit animation to `TaskExitAnimator`; delegate styles to `resolveTaskTextStyle`. |
| `test/features/notes/presentation/widgets/custom_task_component_test.dart` | **Modify** | Update `find.byType(AnimatedTaskCheckbox)` → `find.byType(AppTaskCheckbox)`. Verify tap on checkbox location toggles completion. Verify long-press on checkbox location fires callback. Text area tap remains editable. |
| `test/features/tasks/presentation/task_completion_snackbar_test.dart` | **Modify** | Same `AnimatedTaskCheckbox`→`AppTaskCheckbox` rename. |
| `test/features/notes/presentation/note_editor_screen_test.dart` | **Modify** | Same rename. |
| `lib/features/tasks/presentation/widgets/task_checkbox.dart` | **Delete** | After Task 5. |
| `lib/shared/widgets/animated_task_checkbox.dart` | **Delete** | After Task 5. |

---

## Task 1: `AppTaskCheckbox` (purely-visual, animated)

**Files:**
- Create: `lib/shared/widgets/app_task_checkbox.dart`
- Test: `test/shared/widgets/app_task_checkbox_test.dart`

- [ ] **Step 1.1: Write the failing test**

Create `test/shared/widgets/app_task_checkbox_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';

void main() {
  group('AppTaskCheckbox', () {
    testWidgets('renders outlined circle when value=false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTaskCheckbox(value: false),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.color, Colors.transparent);
    });

    testWidgets('renders filled circle when value=true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTaskCheckbox(
              value: true,
              accentColor: const Color(0xFF000000),
            ),
          ),
        ),
      );

      // Wait for the didUpdateWidget-driven animation to settle at 1.0.
      await tester.pumpAndSettle();

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.color, const Color(0xFF000000));
    });

    testWidgets('renders rounded square when shape=rounded', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTaskCheckbox(
              value: true,
              shape: AppTaskCheckboxShape.rounded,
              accentColor: const Color(0xFF000000),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(8));
    });

    testWidgets('is purely visual: tapping it does nothing (no gesture detector)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTaskCheckbox(value: false),
          ),
        ),
      );

      // No GestureDetector wrapping AppTaskCheckbox.
      expect(
        find.ancestor(
          of: find.byType(AppTaskCheckbox),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });
  });
}
```

- [ ] **Step 1.2: Run test to verify it fails**

Run: `flutter test test/shared/widgets/app_task_checkbox_test.dart`
Expected: FAIL — `AppTaskCheckbox` not defined / target of import fails.

- [ ] **Step 1.3: Write minimal implementation**

Create `lib/shared/widgets/app_task_checkbox.dart`:

```dart
import 'package:flutter/material.dart';

enum AppTaskCheckboxShape { circle, rounded }

/// Purely-visual animated checkbox used inside the task row family.
///
/// The widget is display-only: it owns no `GestureDetector` and exposes
/// no `onChanged`/`onLongPress`. Parents are responsible for hit-testing
/// and translating taps/long-presses into actions.
///
/// Animation layers (driven by an internal [AnimationController] reacting
/// to `didUpdateWidget` on `value`):
///  1. Container fill + border colour transition (300ms).
///  2. Check path drawn progressively via [_CheckmarkPainter] over
///     `Interval(0.2, 0.7, curve: easeOut)` — same feel as the legacy
///     `AnimatedTaskCheckbox`.
class AppTaskCheckbox extends StatefulWidget {
  const AppTaskCheckbox({
    super.key,
    required this.value,
    this.accentColor,
    this.inactiveColor,
    this.size = 22.0,
    this.shape = AppTaskCheckboxShape.circle,
  });

  final bool value;
  final Color? accentColor;
  final Color? inactiveColor;
  final double size;
  final AppTaskCheckboxShape shape;

  @override
  State<AppTaskCheckbox> createState() => _AppTaskCheckboxState();
}

class _AppTaskCheckboxState extends State<AppTaskCheckbox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _checkAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _checkAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.7, curve: Curves.easeOut),
    );
    if (widget.value) _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant AppTaskCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.accentColor ?? scheme.primary;
    final inactive = widget.inactiveColor ?? scheme.outline.withValues(alpha: 0.6);

    return Semantics(
      checked: widget.value,
      label: 'Tarefa ${widget.value ? 'concluída' : 'pendente'}',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final fill = Color.lerp(Colors.transparent, accent, t)!;
            final border = Color.lerp(inactive, accent, t)!;
            return Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: fill,
                shape: widget.shape == AppTaskCheckboxShape.circle
                    ? BoxShape.circle
                    : BoxShape.rectangle,
                borderRadius: widget.shape == AppTaskCheckboxShape.rounded
                    ? BorderRadius.circular(8)
                    : null,
                border: Border.all(color: border, width: 2),
              ),
              child: _CheckmarkPainter(
                progress: _checkAnim.value,
                color: Colors.white,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CheckmarkPainter extends StatelessWidget {
  const _CheckmarkPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _CheckmarkPaint(progress: progress, color: color));
  }
}

class _CheckmarkPaint extends CustomPainter {
  _CheckmarkPaint({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.22, size.height * 0.52)
      ..lineTo(size.width * 0.45, size.height * 0.72)
      ..lineTo(size.width * 0.78, size.height * 0.30);

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      final extracted = metric.extractPath(0.0, metric.length * progress);
      canvas.drawPath(extracted, paint);
    }
  }

  @override
  bool shouldRepaint(_CheckmarkPaint oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
```

- [ ] **Step 1.4: Run test to verify it passes**

Run: `flutter test test/shared/widgets/app_task_checkbox_test.dart`
Expected: PASS — 4 tests green.

- [ ] **Step 1.5: Commit**

```bash
git add lib/shared/widgets/app_task_checkbox.dart test/shared/widgets/app_task_checkbox_test.dart
git commit -m "feat(shared): add AppTaskCheckbox (purely-visual, animated)"
```

---

## Task 2: `TaskTile` — unified touch, swipe removal

**Files:**
- Modify: `lib/features/tasks/presentation/widgets/task_tile.dart`
- Modify: `test/features/tasks/presentation/widgets/task_tile_test.dart`

- [ ] **Step 2.1: Write the failing test**

Replace `test/features/tasks/presentation/widgets/task_tile_test.dart` contents with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_tile.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR', null);
  });

  TaskModel buildTask({
    String id = '1',
    String title = 'Buy coffee',
    String status = 'open',
    DateTime? dueDate,
    TaskRecurrence? recurrence,
  }) {
    final now = DateTime(2026, 6, 15);
    return TaskModel(
      id: id,
      userId: 'u',
      noteId: 'n',
      title: title,
      status: status,
      position: 0,
      recurrence: recurrence,
      dueDate: dueDate,
      completedAt: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  testWidgets('renders title from TaskModel', (tester) async {
    final task = buildTask(title: 'Buy coffee');
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TaskTile(task: task))),
    );
    expect(find.text('Buy coffee'), findsOneWidget);
  });

  testWidgets('renders due date badge when dueDate set', (tester) async {
    final task = buildTask(dueDate: DateTime(2026, 6, 15));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TaskTile(task: task))),
    );
    expect(find.byIcon(Icons.event_outlined), findsOneWidget);
  });

  testWidgets('renders recurrence badge when recurrence set', (tester) async {
    final task = buildTask(recurrence: TaskRecurrence.weekly);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TaskTile(task: task))),
    );
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.text('Semanalmente'), findsOneWidget);
  });

  testWidgets('hides meta row when no due date or recurrence', (tester) async {
    final task = buildTask();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TaskTile(task: task))),
    );
    expect(find.byIcon(Icons.event_outlined), findsNothing);
    expect(find.byIcon(Icons.refresh), findsNothing);
  });

  testWidgets('tap on row toggles completion to true when open',
      (tester) async {
    bool? toggled;
    final task = buildTask(status: 'open');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskTile(
            task: task,
            onToggleComplete: (v) => toggled = v,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buy coffee'));
    await tester.pump();

    expect(toggled, isTrue);
  });

  testWidgets('tap on row toggles completion to false when completed',
      (tester) async {
    bool? toggled;
    final task = buildTask(status: 'completed');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskTile(
            task: task,
            onToggleComplete: (v) => toggled = v,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buy coffee'));
    await tester.pump();

    expect(toggled, isFalse);
  });

  testWidgets('long-press on row invokes onOpenMetadata', (tester) async {
    var opened = false;
    final task = buildTask();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskTile(
            task: task,
            onOpenMetadata: () => opened = true,
          ),
        ),
      ),
    );

    await tester.longPress(find.text('Buy coffee'));
    await tester.pump();

    expect(opened, isTrue);
  });

  testWidgets('checkbox is purely visual (no own gesture)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TaskTile(task: buildTask()))),
    );

    expect(
      find.ancestor(
        of: find.byType(AppTaskCheckbox),
        matching: find.byType(GestureDetector),
      ),
      findsOneWidget, // the row-level detector only
    );
  });
}
```

- [ ] **Step 2.2: Run test to verify it fails**

Run: `flutter test test/features/tasks/presentation/widgets/task_tile_test.dart`
Expected: FAIL — `onTap` param no longer exists; `onToggleComplete`/`onOpenMetadata` not accepted.

- [ ] **Step 2.3: Rewrite `TaskTile`**

Replace `lib/features/tasks/presentation/widgets/task_tile.dart` contents with:

```dart
import 'package:flutter/material.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';

import '../../domain/task_model.dart';

/// Row widget that renders a single [TaskModel].
///
/// Touch behaviour is centralised on this widget (the inner
/// [AppTaskCheckbox] is purely visual):
///  * tap anywhere on the row toggles completion.
///  * long-press anywhere on the row opens the metadata sheet
///    via [onOpenMetadata].
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    this.onToggleComplete,
    this.onOpenMetadata,
    this.dense = false,
  });

  final TaskModel task;
  final ValueChanged<bool>? onToggleComplete;
  final VoidCallback? onOpenMetadata;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantics = theme.extension<AppSemanticColors>();
    final taskColor = semantics?.task ?? AppColors.taskAccent;
    final isCompleted = task.isCompleted;

    final titleColor = isCompleted ? scheme.onSurfaceVariant : scheme.onSurface;
    final titleDecoration =
        isCompleted ? TextDecoration.lineThrough : null;

    return Material(
      color: taskColor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggleComplete == null
            ? null
            : () => onToggleComplete!(!isCompleted),
        onLongPress: onOpenMetadata,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: dense ? AppSpacing.sm : AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppTaskCheckbox(
                value: isCompleted,
                accentColor: taskColor,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      task.title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: titleColor,
                        decoration: titleDecoration,
                        decorationColor: titleColor,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (task.dueDate != null || task.recurrence != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      TaskMetadataBadges(
                        dueDate: task.dueDate,
                        recurrence: task.recurrence,
                        isCompleted: isCompleted,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2.4: Run test to verify it passes**

Run: `flutter test test/features/tasks/presentation/widgets/task_tile_test.dart`
Expected: PASS — 8 tests green.

- [ ] **Step 2.5: Commit**

```bash
git add lib/features/tasks/presentation/widgets/task_tile.dart test/features/tasks/presentation/widgets/task_tile_test.dart
git commit -m "refactor(tasks): unify TaskTile touch (tap=toggle, long-press=metadata)"
```

---

## Task 3: `TaskExitAnimator` + `resolveTaskTextStyle` helpers

**Files:**
- Create: `lib/features/notes/presentation/widgets/task_exit_animator.dart`
- Create: `lib/features/notes/presentation/widgets/task_text_style_resolver.dart`
- Create: `test/features/notes/presentation/widgets/task_exit_animator_test.dart`

- [ ] **Step 3.1: Write the failing test for `TaskExitAnimator`**

Create `test/features/notes/presentation/widgets/task_exit_animator_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/presentation/widgets/task_exit_animator.dart';

void main() {
  testWidgets('does not animate when hideCompleted=false', (tester) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskExitAnimator(
            hideCompleted: false,
            isComplete: true,
            onAnimationComplete: () => completed = true,
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(completed, isFalse);
  });

  testWidgets('forwards when hideCompleted && isComplete turns true',
      (tester) async {
    var completed = false;
    var widget = TaskExitAnimator(
      hideCompleted: true,
      isComplete: false,
      onAnimationComplete: () => completed = true,
      child: const SizedBox(width: 10, height: 10),
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
    await tester.pump();

    // Mutate isComplete -> true
    widget = TaskExitAnimator(
      hideCompleted: true,
      isComplete: true,
      onAnimationComplete: () => completed = true,
      child: const SizedBox(width: 10, height: 10),
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));

    // Skip the 300ms delay + the 350ms animation.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
  });
}
```

- [ ] **Step 3.2: Run test to verify it fails**

Run: `flutter test test/features/notes/presentation/widgets/task_exit_animator_test.dart`
Expected: FAIL — `TaskExitAnimator` not defined.

- [ ] **Step 3.3: Implement `TaskExitAnimator`**

Create `lib/features/notes/presentation/widgets/task_exit_animator.dart`:

```dart
import 'package:flutter/material.dart';

const Duration _exitAnimationDelay = Duration(milliseconds: 300);
const Duration _exitAnimationDuration = Duration(milliseconds: 350);

/// Wraps a child with a [SizeTransition] + [FadeTransition] that play
/// when `hideCompleted && isComplete` turn true. Used by
/// [CustomTaskComponent] to gracefully hide completed tasks in the editor.
class TaskExitAnimator extends StatefulWidget {
  const TaskExitAnimator({
    super.key,
    required this.hideCompleted,
    required this.isComplete,
    required this.onAnimationComplete,
    required this.child,
  });

  final bool hideCompleted;
  final bool isComplete;
  final VoidCallback? onAnimationComplete;
  final Widget child;

  @override
  State<TaskExitAnimator> createState() => _TaskExitAnimatorState();
}

class _TaskExitAnimatorState extends State<TaskExitAnimator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _size;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _exitAnimationDuration,
    );
    _fade = Tween<double>(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _size = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onAnimationComplete?.call();
      }
    });

    if (widget.hideCompleted && widget.isComplete) {
      _controller.value = 1.0; // already hidden on first frame
    }
  }

  @override
  void didUpdateWidget(covariant TaskExitAnimator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.hideCompleted) return;

    final becameComplete =
        widget.isComplete && !oldWidget.isComplete;
    final becameIncomplete =
        !widget.isComplete && oldWidget.isComplete;

    if (becameComplete) {
      Future.delayed(_exitAnimationDelay, () {
        if (mounted && widget.isComplete) _controller.forward();
      });
    } else if (becameIncomplete) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _size,
      axisAlignment: 0.0, // top-aligned shrink
      child: FadeTransition(opacity: _fade, child: widget.child),
    );
  }
}
```

- [ ] **Step 3.4: Run test to verify it passes**

Run: `flutter test test/features/notes/presentation/widgets/task_exit_animator_test.dart`
Expected: PASS — 2 tests green.

- [ ] **Step 3.5: Implement `resolveTaskTextStyle`**

Create `lib/features/notes/presentation/widgets/task_text_style_resolver.dart`:

```dart
import 'package:flutter/material.dart';

/// Mutates a base [TextStyle] according to whether the task is complete:
///  * complete: applies [TextDecoration.lineThrough] and fades the color
///    to 50% alpha.
///  * incomplete: keeps the base colour untouched.
TextStyle resolveTaskTextStyle(
  Set<Object> attributions,
  TextStyle Function(Set<Object>) baseBuilder,
  TextStyle baseColor,
  bool isComplete,
) {
  final style = baseBuilder(attributions);
  final color = style.color ?? baseColor;
  if (!isComplete) return style.copyWith(color: color);
  return style.copyWith(
    color: color.withValues(alpha: 0.5),
    decoration: TextDecoration.lineThrough,
  );
}
```

> Note: `Set<Object>` mirrors the `super_editor` `Attribution` dynamic type used in `noStyleBuilder`. If lint complains, replace `Object` with `dynamic` or `Attribution` after importing `package:super_editor/super_editor.dart`.

- [ ] **Step 3.6: Commit**

```bash
git add lib/features/notes/presentation/widgets/task_exit_animator.dart lib/features/notes/presentation/widgets/task_text_style_resolver.dart test/features/notes/presentation/widgets/task_exit_animator_test.dart
git commit -m "refactor(notes): extract TaskExitAnimator + resolveTaskTextStyle"
```

---

## Task 4: Slim `CustomTaskComponent` to use `AppTaskCheckbox` + parent `GestureDetector`

**Files:**
- Modify: `lib/features/notes/presentation/widgets/custom_task_component.dart`
- Modify: `test/features/notes/presentation/widgets/custom_task_component_test.dart`
- Modify: `test/features/tasks/presentation/task_completion_snackbar_test.dart`
- Modify: `test/features/notes/presentation/note_editor_screen_test.dart`

- [ ] **Step 4.1: Update `custom_task_component_test.dart` type+behaviour references**

Apply the following edits to `test/features/notes/presentation/widgets/custom_task_component_test.dart`:

1. Replace the import `import 'package:supanotes/shared/widgets/animated_task_checkbox.dart';` with:
   ```dart
   import 'package:supanotes/shared/widgets/app_task_checkbox.dart';
   ```

2. Replace every occurrence of `find.byType(AnimatedTaskCheckbox)` with `find.byType(AppTaskCheckbox)` (10 occurrences — line 65, 108, 118, 123, 135, 151, 276, 319, 570 plus the `expect(find.byType(AnimatedTaskCheckbox))` count assertions). Use the editor's `replaceAll` semantics.

3. In `testWidgets('toggles completion from checkbox tap', ...)` (line 91), the tap location is now non-interactive but the parent `Row`'s `GestureDetector(translucent)` should catch it. Keep `await tester.tap(find.byType(AppTaskCheckbox))` — it must still fire `setComplete` via the parent detector. (No code change beyond the rename.)

4. In `testWidgets('opens task actions from checkbox long press', ...)` (line 53), same swap. The parent detector catches the long-press.

If any assertion about checkbox `Size(22, 22)` (line 118-120) or first-line alignment (line 130-158) breaks after the implementation, adjust expected constants to match `AppTaskCheckbox` rendering (default `size: 22` ⟹ `Size(22, 22)` should hold). Verify in Step 4.5.

- [ ] **Step 4.2: Update `task_completion_snackbar_test.dart` rename**

In `test/features/tasks/presentation/task_completion_snackbar_test.dart`:
- Replace `find.byType(AnimatedTaskCheckbox)` with `find.byType(AppTaskCheckbox)` (line 133, 136).
- Add import `import 'package:supanotes/shared/widgets/app_task_checkbox.dart';`.

- [ ] **Step 4.3: Update `note_editor_screen_test.dart` rename**

In `test/features/notes/presentation/note_editor_screen_test.dart`:
- Replace every `find.byType(AnimatedTaskCheckbox)` with `find.byType(AppTaskCheckbox)` (line 276, 347, 352, 503, 572).
- Add import `import 'package:supanotes/shared/widgets/app_task_checkbox.dart';`.

- [ ] **Step 4.4: Rewrite `custom_task_component.dart`**

Replace the contents of `lib/features/notes/presentation/widgets/custom_task_component.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/presentation/widgets/task_exit_animator.dart';
import 'package:supanotes/features/notes/presentation/widgets/task_text_style_resolver.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';

const double _taskCheckboxGap = 9.0;

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
      isComplete: _completingTaskIds.contains(node.id) || node.isComplete,
      setComplete: (bool isComplete) async {
        if (isComplete) {
          final isRecurring = taskMetadataById[node.id]?.recurrence != null;

          if (isRecurring) {
            _completingTaskIds.add(node.id);
            requestRebuild?.call();
          }

          if (hideCompleted) {
            _animatingNodeIds.add(node.id);
            FocusManager.instance.primaryFocus?.unfocus();
            composer?.clearSelection();
          }

          try {
            final nextDue = await onTaskComplete?.call(node.id);
            if (nextDue != null && isRecurring) {
              await Future.delayed(const Duration(seconds: 1));
            }
          } finally {
            if (isRecurring) {
              _completingTaskIds.remove(node.id);
              requestRebuild?.call();
            }
          }
        } else {
          await onTaskReopen?.call(node.id);
        }
      },
      text: node.text,
      textDirection: getParagraphDirection(node.text.toPlainText()),
      textAlignment: TextAlign.left,
      textStyleBuilder: noStyleBuilder,
      selectionColor: const Color(0x00000000),
      dueDate: metadata?.dueDate,
      recurrence: metadata?.recurrence,
    );
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! TaskComponentViewModel) return null;

    final nodeId = componentViewModel.nodeId;

    if (hideCompleted &&
        componentViewModel.isComplete &&
        !_animatingNodeIds.contains(nodeId)) {
      return SizedBox(key: componentContext.componentKey, height: 0);
    }

    return CustomTaskComponent(
      key: componentContext.componentKey,
      viewModel: componentViewModel,
      taskMetadata: taskMetadataById[nodeId],
      hideCompleted: hideCompleted,
      onLongPress: onTaskLongPress == null
          ? null
          : () => onTaskLongPress!(nodeId),
      onAnimationComplete: () {
        _animatingNodeIds.remove(componentViewModel.nodeId);
        requestRebuild?.call();
      },
    );
  }
}

class CustomTaskComponentViewModel extends TaskComponentViewModel {
  CustomTaskComponentViewModel({
    required super.nodeId,
    required super.createdAt,
    required super.padding,
    required super.indent,
    required super.isComplete,
    required super.setComplete,
    required super.text,
    required super.textDirection,
    required super.textAlignment,
    required super.textStyleBuilder,
    required super.selectionColor,
    this.dueDate,
    this.recurrence,
  });

  final DateTime? dueDate;
  final TaskRecurrence? recurrence;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CustomTaskComponentViewModel) return false;
    if (super != other) return false;
    return dueDate == other.dueDate && recurrence == other.recurrence;
  }

  @override
  int get hashCode => Object.hash(super.hashCode, dueDate, recurrence);
}

class CustomTaskComponent extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final semantics = Theme.of(context).extension<AppSemanticColors>();
    final taskColor = semantics?.task ?? AppColors.taskAccent;

    final content = Directionality(
      textDirection: viewModel.textDirection,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: viewModel.setComplete == null
            ? null
            : () => viewModel.setComplete!(!viewModel.isComplete),
        onLongPress: onLongPress,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: defaultTaskIndentCalculator(
                viewModel.textStyleBuilder({}),
                viewModel.indent,
              ),
            ),
            AppTaskCheckbox(
              value: viewModel.isComplete,
              accentColor: taskColor,
              inactiveColor: colorScheme.outline,
              shape: AppTaskCheckboxShape.rounded,
            ),
            const SizedBox(width: _taskCheckboxGap),
            Expanded(
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
                    textStyleBuilder: (attributions) =>
                        resolveTaskTextStyle(
                      attributions,
                      viewModel.textStyleBuilder,
                      Theme.of(context).colorScheme.onSurface,
                      viewModel.isComplete,
                    ),
                    inlineWidgetBuilders: viewModel.inlineWidgetBuilders,
                    textSelection: viewModel.selection,
                    selectionColor: viewModel.selectionColor,
                    highlightWhenEmpty: viewModel.highlightWhenEmpty,
                    underlines: viewModel.createUnderlines(),
                  ),
                  if (taskMetadata?.dueDate != null ||
                      taskMetadata?.recurrence != null) ...[
                    const SizedBox(height: 4),
                    TaskMetadataBadges(
                      dueDate: taskMetadata?.dueDate,
                      recurrence: taskMetadata?.recurrence,
                      isCompleted: viewModel.isComplete,
                    ),
                    const SizedBox(height: 4),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return TaskExitAnimator(
      hideCompleted: hideCompleted,
      isComplete: viewModel.isComplete,
      onAnimationComplete: onAnimationComplete,
      child: content,
    );
  }
}
```

> Notes:
> - The `TaskExitAnimator` is now a `StatelessWidget`'s child; the `TickerProvider` lives inside the animator. No `State`/mixin needed on `CustomTaskComponent`.
> - `_cachedFirstLineHeight` and `_computeFirstLineHeight` are intentionally removed. With `crossAxisAlignment: start` on the `Row` and `defaultTaskIndentCalculator` driving the indent width, the checkbox sits at the row's top. The check "circle/rounded square" is 22px and visually aligns with the first text line at default font sizes (16px line ≈ 22px). If visual regression is reported, add a small fixed `SizedBox(height: 1)` above the checkbox after Step 4.5 — but the spec already accepts this risk.

- [ ] **Step 4.5: Run tests to verify they pass**

Run: `flutter test test/features/notes/presentation/widgets/custom_task_component_test.dart test/features/tasks/presentation/task_completion_snackbar_test.dart test/features/notes/presentation/note_editor_screen_test.dart`
Expected: PASS — all green.

> If `toggles completion from checkbox tap` or `opens task actions from checkbox long press` fail because `AppTaskCheckbox` consumes the hit, double-check the parent `GestureDetector(behavior: translucent)` placement. The fix is to wrap only the indent + checkbox + gap (not the `Expanded(text)`) inside a transparent `GestureDetector`. However the existing behaviour requires long-press on the text area NOT to open actions (test at line 71), which `translucent` over the full row satisfies because `TextComponent`'s own gesture recognisers win the gesture arena for taps/long-presses within their bounds. Verify with the test run.

- [ ] **Step 4.6: Commit**

```bash
git add lib/features/notes/presentation/widgets/custom_task_component.dart test/features/notes/presentation/widgets/custom_task_component_test.dart test/features/tasks/presentation/task_completion_snackbar_test.dart test/features/notes/presentation/note_editor_screen_test.dart
git commit -m "refactor(notes): slim CustomTaskComponent, use AppTaskCheckbox + parent gestures"
```

---

## Task 5: Delete legacy checkboxes & verify

**Files:**
- Delete: `lib/features/tasks/presentation/widgets/task_checkbox.dart`
- Delete: `lib/shared/widgets/animated_task_checkbox.dart`

- [ ] **Step 5.1: Delete the files**

Run:
```bash
git rm lib/features/tasks/presentation/widgets/task_checkbox.dart lib/shared/widgets/animated_task_checkbox.dart
```

- [ ] **Step 5.2: Verify no stale references**

Run: `git grep -n "TaskCheckbox\|AnimatedTaskCheckbox"`
Expected: only output should be matches inside `app_task_checkbox_test.dart` referencing `AppTaskCheckbox` (which contains the substring `TaskCheckbox`). If any lib file or test still imports `task_checkbox.dart` / `animated_task_checkbox.dart`, fix before continuing.

- [ ] **Step 5.3: Run full test suite + analyze**

Run:
```bash
flutter analyze
flutter test
```
Expected:
- `flutter analyze`: no new errors/warnings introduced by this work.
- `flutter test`: all tests green.

> If `flutter analyze` flags unused imports from the deleted files, remove them.

- [ ] **Step 5.4: Commit**

```bash
git commit -m "chore(tasks): delete legacy TaskCheckbox and AnimatedTaskCheckbox"
```

> If step 5.2 already staged the deletions, this commit may be empty — in that case skip it. Otherwise commit any remaining cleanup.

- [ ] **Step 5.5: Visual smoke check (manual)**

Run: `flutter run` (or the project's run script).
1. Open a note with tasks.
2. Tap the row of an incomplete task → it should complete (checkbox fills, check draws in).
3. Tap the row of a completed task → it reopens.
4. Long-press a task row → the metadata sheet opens.
5. Tap directly on the task text → caret enters the text (editable).
6. Open the tasks list screen if it exists (`/tasks` or analogous) — confirm same tap/long-press behaviour on `TaskTile`.

> No code change from this step; record any regression in a follow-up.

---

## Self-Review

**Spec coverage:**
- §1 `AppTaskCheckbox` (visual, animated, two shapes) → Task 1 ✓
- §2 `TaskTile` (tap=toggle, long-press=metadata, swipe removed, `_MetaRow`/`_SwipeBackground` deleted, `IgnorePointer` not needed) → Task 2 ✓
- §3 `CustomTaskComponent` slim to ~100 lines, `TaskExitAnimator`, `resolveTaskTextStyle`, parent `GestureDetector(translucent)`, `AppTaskCheckbox(rounded)` → Tasks 3 + 4 ✓
- §4 deletion of `TaskCheckbox` and `AnimatedTaskCheckbox` → Task 5 ✓
- §5 tests (new, modified) → embedded in Tasks 1, 2, 3, 4 ✓
- §6 implementation order (1→5) matches ✓

**Placeholder scan:** No TBD/TODO. All code blocks are complete.

**Type consistency:**
- `AppTaskCheckbox` constructor signature consistent across Tasks 1, 2, 4.
- `AppTaskCheckboxShape` enum used consistently.
- `TaskExitAnimator` constructor signature consistent between Task 3 (definition) and Task 4 (consumer).
- `resolveTaskTextStyle` parameter list matches usage in Task 4 (Step 4.4).
- `TaskTile` constructor uses `onToggleComplete`/`onOpenMetadata` consistently between Step 2.1 (test) and Step 2.3 (impl).

**Risk callouts retained from spec:**
- Verify `translucent` `GestureDetector` does not steal tap from `TextComponent`. Test at `custom_task_component_test.dart:71-89` ("text area long press does not open task actions") is the canary.
- `_cachedFirstLineHeight` removal: visual regression check at Step 5.5.