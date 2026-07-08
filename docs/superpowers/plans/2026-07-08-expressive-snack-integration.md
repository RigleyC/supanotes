# Plan 001: Integrate Expressive Snack with Action Support

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 392f2c4..HEAD -- lib/pubspec.yaml lib/main.dart lib/shared/widgets/app_snackbar.dart test/shared/widgets/app_snackbar_test.dart test/features/tasks/presentation/task_completion_snackbar_test.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: UI & UX Refactoring
- **Planned at**: commit `392f2c4`, 2026-07-08

## Why this matters

The current standard Material `SnackBar` doesn't feel modern or premium. Replacing it with `expressive_snack` provides spring-based physics, cards that stack beautifully at the bottom of the screen, duplicate shaking, and swipe-to-dismiss behavior. By vendoring this small package locally, we also support `SnackBarAction` (e.g. Undo), preventing regressions on vital features like undoing task completions.

## Current state

- `lib/main.dart` — App configuration; contains the MaterialApp.router definition.
- `lib/shared/widgets/app_snackbar.dart` — Currently wraps Flutter's standard `ScaffoldMessenger` and `SnackBar`.
- `test/shared/widgets/app_snackbar_test.dart` — Tests checking for standard `SnackBar` widgets in widget tests.
- `test/features/tasks/presentation/task_completion_snackbar_test.dart` — Tests checking task completion and undo behavior via standard snackbars.

Exemplar of MaterialApp builder in `lib/main.dart:100-112`:
```dart
      builder: (context, child) {
        Widget result = child!;
        if (kDebugMode) {
          result = CueDebugTools(child: result);
        }
        if (PlatformInfo.isIOS) {
          result = CupertinoTheme(
            data: CupertinoThemeData(
              brightness: Theme.of(context).brightness,
            ),
            child: result,
          );
        }
        return result;
      },
```

## Commands you will need

| Purpose   | Command                                         | Expected on success |
|-----------|-------------------------------------------------|---------------------|
| Install   | `flutter pub get`                               | exit 0              |
| Analyze   | `flutter analyze`                               | exit 0, no errors   |
| Run tests | `flutter test`                                  | all pass            |

## Scope

**In scope**:
- `pubspec.yaml`
- `lib/main.dart`
- `lib/shared/widgets/app_snackbar.dart`
- `lib/shared/widgets/expressive_snack/*` (new vendored files)
- `test/shared/widgets/app_snackbar_test.dart`
- `test/features/tasks/presentation/task_completion_snackbar_test.dart`

**Out of scope**:
- Modifying other task-completion or snackbar triggering callers in features.

## Git workflow

- Branch: `feat/expressive-snack`
- Commit per step; message style: Conventional Commits (e.g. `feat(ui): add expressive_snack package to dependencies`)

## Steps

### Step 1: Add dependencies to pubspec.yaml

Add `motor` (from pub.dev) and `material_shapes` (from Git repo) to dependencies in `pubspec.yaml`.

**Verify**: Run `flutter pub get` -> exit 0.

### Step 2: Vendor expressive_snack package code

Create the following files under `lib/shared/widgets/expressive_snack/`:

#### File 1: `lib/shared/widgets/expressive_snack/expressive_snack.dart`
```dart
library;

export 'src/show_expressive_snack.dart';
export 'src/snack.dart';
export 'src/snack_overlay.dart';
export 'src/snack_view.dart';
```

#### File 2: `lib/shared/widgets/expressive_snack/src/snack.dart`
```dart
import 'package:flutter/material.dart';
import 'snack_view.dart';

class Snack {
  Snack({
    required this.message,
    required this.icon,
    required this.duration,
    this.action,
  });

  final String message;
  final IconData? icon;
  final Duration duration;
  final SnackBarAction? action;

  final GlobalKey<SnackViewState> key = GlobalKey();
}
```

#### File 3: `lib/shared/widgets/expressive_snack/src/snack_overlay.dart`
```dart
import 'package:flutter/material.dart';
import 'snack.dart';
import 'snack_view.dart';

class SnackOverlay extends StatefulWidget {
  const SnackOverlay({super.key, required this.child});

  final Widget child;

  static void refresh() => _key.currentState?._refresh();

  static Snack add(Snack snack) {
    final state = _key.currentState;
    if (state == null) return snack;

    final duplicate = state._snacks.cast<Snack?>().firstWhere(
      (s) => s != null && s.message == snack.message && s.icon == snack.icon,
      orElse: () => null,
    );

    if (duplicate != null) return duplicate;

    state._add(snack);
    return snack;
  }

  static void remove(Snack snack) => _key.currentState?._remove(snack);

  static final GlobalKey<_SnackOverlayState> _key = GlobalKey();

  @override
  State<_SnackOverlayState> createState() => _SnackOverlayState();
}

class _SnackOverlayState extends State<SnackOverlay> {
  final List<Snack> _snacks = [];

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _add(Snack snack) {
    if (mounted) {
      setState(() {
        _snacks.insert(0, snack);
      });
    }
  }

  void _remove(Snack snack) {
    if (mounted) {
      setState(() {
        _snacks.remove(snack);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeArea = MediaQuery.paddingOf(context);

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          bottom: safeArea.bottom + 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            verticalDirection: VerticalDirection.up,
            children: [
              for (var i = 0; i < _snacks.length && i < 3; i++)
                SnackView(
                  key: _snacks[i].key,
                  snack: _snacks[i],
                  depth: i,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
```

#### File 4: `lib/shared/widgets/expressive_snack/src/show_expressive_snack.dart`
```dart
import 'package:flutter/material.dart';
import 'snack.dart';
import 'snack_overlay.dart';

void showExpressiveSnack({
  required BuildContext context,
  required String message,
  IconData? icon,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 4),
}) {
  final snack = Snack(
    message: message,
    icon: icon,
    duration: duration,
    action: action,
  );
  final actual = SnackOverlay.add(snack);

  if (actual != snack) {
    actual.key.currentState?.shake();
  }
}
```

#### File 5: `lib/shared/widgets/expressive_snack/src/snack_view.dart`
```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:material_shapes/material_shapes.dart';
import 'package:motor/motor.dart';
import 'snack.dart';
import 'snack_overlay.dart';

class SnackView extends StatefulWidget {
  const SnackView({super.key, required this.snack, required this.depth});

  final Snack snack;
  final int depth;

  @override
  State<SnackView> createState() => SnackViewState();
}

class SnackViewState extends State<SnackView> with TickerProviderStateMixin {
  static const double _travel = 160;
  static const double _dismissOffset = 24;
  static const double _dismissVelocity = 300;
  static const double _peek = 12;
  static const double _shrink = 0.05;
  static const double _shade = 0.15;
  static const double _shakeVelocity = 600;

  late final AnimationController _drag = AnimationController.unbounded(
    vsync: this,
  )..value = 0;

  late final AnimationController _shake = AnimationController.unbounded(
    vsync: this,
  )..value = 0;

  bool _visible = false;
  bool _removing = false;
  Timer? _timer;

  bool get isDismissing => _removing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
    _timer = Timer(widget.snack.duration, dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _drag.dispose();
    _shake.dispose();
    super.dispose();
  }

  void dismiss() {
    if (_removing) return;
    _removing = true;
    _timer?.cancel();
    _drag.stop();
    if (mounted) setState(() => _visible = false);
    SnackOverlay.refresh();
    Timer(const Duration(milliseconds: 450), () {
      SnackOverlay.remove(widget.snack);
    });
  }

  void shake() {
    if (_removing) return;
    _timer?.cancel();
    _timer = Timer(widget.snack.duration, dismiss);
    const spring = SpringDescription(mass: 1, stiffness: 400, damping: 10);
    _shake.animateWith(
      SpringSimulation(spring, _shake.value, 0, _shakeVelocity),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final styles = theme.textTheme;

    final background = colors.inverseSurface;
    final foreground = colors.onInverseSurface;
    final hasIcon = widget.snack.icon != null;

    final pill = Material(
      color: background,
      shape: const StadiumBorder(),
      elevation: 6,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasIcon)
              Padding(
                padding: const EdgeInsets.all(6),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Material(
                    color: colors.primary,
                    shape: const MaterialShapeBorder(
                      shape: MaterialShape(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(99),
                          topRight: Radius.circular(99),
                        ),
                      ),
                    ),
                    child: Icon(
                      widget.snack.icon,
                      color: colors.onPrimary,
                      size: 20,
                    ),
                  ),
                ),
              ),
            Flexible(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  hasIcon ? 6 : 24,
                  14,
                  widget.snack.action != null ? 8 : 24,
                  14,
                ),
                child: Text(
                  widget.snack.message,
                  style: styles.bodyMedium?.copyWith(color: foreground),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (widget.snack.action != null) ...[
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: () {
                    widget.snack.action!.onPressed();
                    dismiss();
                  },
                  child: Text(
                    widget.snack.action!.label,
                    style: TextStyle(color: colors.primary),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final depth = widget.depth;
    final scale = 1.0 - (depth * _shrink);
    final translate = depth * _peek;

    const entrySpring = SpringDescription(mass: 1, stiffness: 300, damping: 18);
    const exitSpring = SpringDescription(mass: 1, stiffness: 450, damping: 30);

    return Focus(
      child: Center(
        child: IgnorePointer(
          ignoring: depth > 0,
          child: AnimatedBuilder(
            animation: Listenable.merge([_drag, _shake]),
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(_shake.value, _drag.value - translate),
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.bottomCenter,
                  child: child,
                ),
              );
            },
            child: AnimatedColorAsphalt(
              color: Colors.black.withValues(alpha: depth * _shade),
              child: AnimatedOpacitySpring(
                visible: _visible,
                entrySpring: entrySpring,
                exitSpring: exitSpring,
                child: AnimatedTranslationSpring(
                  visible: _visible,
                  entrySpring: entrySpring,
                  exitSpring: exitSpring,
                  offset: const Offset(0, _travel),
                  child: GestureDetector(
                    onTap: dismiss,
                    onVerticalDragUpdate: (details) {
                      _drag.value += details.primaryDelta!;
                    },
                    onVerticalDragEnd: (details) {
                      final offset = _drag.value;
                      final velocity = details.primaryVelocity!;

                      if (offset > _dismissOffset || velocity > _dismissVelocity) {
                        dismiss();
                        _drag.animateWith(
                          ScrollSpringSimulation(
                            const SpringDescription(
                              mass: 1,
                              stiffness: 450,
                              damping: 30,
                            ),
                            offset,
                            _travel,
                            velocity,
                          ),
                        );
                      } else {
                        const spring = SpringDescription(mass: 1, stiffness: 400, damping: 20);
                        _drag.animateWith(
                          SpringSimulation(spring, offset, 0, velocity),
                        );
                      }
                    },
                    child: pill,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

**Verify**: Run `flutter analyze` -> exit 0, no errors.

### Step 3: Wrap router builder with SnackOverlay in main.dart

Modify `lib/main.dart` builder to wrap the root layout inside `SnackOverlay`.

```dart
      builder: (context, child) {
        Widget result = SnackOverlay(child: child!);
        if (kDebugMode) {
          result = CueDebugTools(child: result);
        }
        if (PlatformInfo.isIOS) {
          result = CupertinoTheme(
            data: CupertinoThemeData(
              brightness: Theme.of(context).brightness,
            ),
            child: result,
          );
        }
        return result;
      },
```

**Verify**: Run `flutter analyze` -> exit 0.

### Step 4: Adapt AppMessenger to use expressive_snack

Modify `lib/shared/widgets/app_snackbar.dart` so all methods delegate to `showExpressiveSnack`.

```dart
import 'package:flutter/material.dart';
import 'package:supanotes/shared/widgets/expressive_snack/expressive_snack.dart';

class AppMessenger {
  AppMessenger._();

  static final GlobalKey<ScaffoldMessengerState> key =
      GlobalKey<ScaffoldMessengerState>();

  static void showSuccess(
    String title, {
    String? subtitle,
    SnackBarAction? action,
    Duration? duration,
  }) {
    final context = key.currentContext;
    if (context == null) return;
    showExpressiveSnack(
      context: context,
      message: subtitle != null ? '$title\n$subtitle' : title,
      icon: Icons.check_circle,
      action: action,
      duration: duration ?? const Duration(seconds: 4),
    );
  }

  static void showError(
    String title, {
    String? subtitle,
    SnackBarAction? action,
    Duration? duration,
  }) {
    final context = key.currentContext;
    if (context == null) return;
    showExpressiveSnack(
      context: context,
      message: subtitle != null ? '$title\n$subtitle' : title,
      icon: Icons.error,
      action: action,
      duration: duration ?? const Duration(seconds: 4),
    );
  }

  static void showInfo(
    String title, {
    String? subtitle,
    SnackBarAction? action,
    Duration? duration,
  }) {
    final context = key.currentContext;
    if (context == null) return;
    showExpressiveSnack(
      context: context,
      message: subtitle != null ? '$title\n$subtitle' : title,
      icon: Icons.info,
      action: action,
      duration: duration ?? const Duration(seconds: 4),
    );
  }

  static void showTaskCompletion({
    required String title,
    String? subtitle,
    required SnackBarAction action,
    Duration? duration,
  }) {
    final context = key.currentContext;
    if (context == null) return;
    showExpressiveSnack(
      context: context,
      message: subtitle != null ? '$title\n$subtitle' : title,
      icon: Icons.task_alt,
      action: action,
      duration: duration ?? const Duration(seconds: 3),
    );
  }
}
```

**Verify**: Run `flutter analyze` -> exit 0.

### Step 5: Update Widget Tests

Update the following files to search for the newly introduced widgets (`SnackView`, `SnackOverlay`, action buttons) instead of the old Material `SnackBar`:
- `test/shared/widgets/app_snackbar_test.dart`
- `test/features/tasks/presentation/task_completion_snackbar_test.dart`

**Verify**: Run `flutter test` -> exit 0, all tests passing.

## STOP conditions

- If the git repository `https://github.com/kamranbekirovyz/bunpod.git` fails to clone/fetch or resolves with dependency version conflicts with the local Flutter SDK environment.
- If `AppMessenger.key.currentContext` returns `null` or doesn't have access to the `SnackOverlay` widget tree.

## Maintenance notes

- Standard material snackbar properties like `backgroundColor` and `shape` are now handled globally inside `SnackView`. Modifying these styles should be done inside `SnackView` itself.
- Tasks completing and undoing actions will trigger `showExpressiveSnack` with the corresponding action.
