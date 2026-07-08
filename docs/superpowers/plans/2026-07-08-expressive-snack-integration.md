# Expressive Snack Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate the `expressive_snack` package (with spring-based card-stacking snackbars) into SupaNotes, adapting the current `AppMessenger` class and wrapping the application root layout with `SnackOverlay`.

**Architecture:** We will add `motor` dependency from pub.dev, and `material_shapes` / `expressive_snack` as Git dependencies in `pubspec.yaml`. Then we will wrap the main router builder with `SnackOverlay`, and adapt `AppMessenger` in `lib/shared/widgets/app_snackbar.dart` to delegate to `showExpressiveSnack`.

**Tech Stack:** Flutter, Dart, Riverpod, expressive_snack, motor, material_shapes.

---

### Task 1: Add Dependencies to pubspec.yaml

**Files:**
- Modify: [pubspec.yaml](file:///c:/Users/rigleyc/projects/supanotes/pubspec.yaml)

- [ ] **Step 1: Edit pubspec.yaml to add dependencies**
Add `motor`, `material_shapes`, and `expressive_snack` under `dependencies:` section in `pubspec.yaml`:
```yaml
  motor: ^1.0.0

  material_shapes:
    git:
      url: https://github.com/kamranbekirovyz/bunpod.git
      ref: main
      path: packages/material_shapes

  expressive_snack:
    git:
      url: https://github.com/kamranbekirovyz/bunpod.git
      ref: main
      path: packages/expressive_snack
```

- [ ] **Step 2: Run flutter pub get to fetch dependencies**
Run: `flutter pub get`
Expected: Resolution completes successfully without errors.

- [ ] **Step 3: Commit dependency changes**
```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(deps): add expressive_snack dependencies"
```

---

### Task 2: Wrap Application with SnackOverlay in main.dart

**Files:**
- Modify: [main.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/main.dart)

- [ ] **Step 1: Update MaterialApp.router builder**
Import the package in `lib/main.dart`:
```dart
import 'package:expressive_snack/expressive_snack.dart';
```
And add `builder` property inside `MaterialApp.router` (around line 95):
```dart
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      scaffoldMessengerKey: AppMessenger.key,
      builder: (context, child) {
        return SnackOverlay(child: child!);
      },
```

- [ ] **Step 2: Run flutter analyze to verify no compiler errors**
Run: `flutter analyze`
Expected: Analysis passes.

- [ ] **Step 3: Commit**
```bash
git add lib/main.dart
git commit -m "feat(ui): wrap MaterialApp.router with SnackOverlay"
```

---

### Task 3: Adapt AppMessenger to use expressive_snack

**Files:**
- Modify: [app_snackbar.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/shared/widgets/app_snackbar.dart)

- [ ] **Step 1: Replace AppMessenger implementation**
Import `expressive_snack` and `flutter/material.dart` and modify the methods:
```dart
import 'package:flutter/material.dart';
import 'package:expressive_snack/expressive_snack.dart';

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
      duration: duration ?? const Duration(seconds: 3),
    );
  }
}
```

- [ ] **Step 2: Run flutter analyze to verify**
Run: `flutter analyze`
Expected: Analysis passes.

- [ ] **Step 3: Commit**
```bash
git add lib/shared/widgets/app_snackbar.dart
git commit -m "feat(ui): adapt AppMessenger to use showExpressiveSnack"
```
