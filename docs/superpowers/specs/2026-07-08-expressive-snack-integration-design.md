# Design Spec: Expressive Snack Integration

Integration of the `expressive_snack` package into SupaNotes to replace the current standard material snackbar with spring-based stackable pills.

## Proposed Changes

### Dependencies
Update [pubspec.yaml](file:///c:/Users/rigleyc/projects/supanotes/pubspec.yaml) to include `motor` from pub.dev and `material_shapes` and `expressive_snack` from the GitHub repository `kamranbekirovyz/bunpod`.

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

### Layout Integration
Wrap the main application router with `SnackOverlay` inside `MaterialApp.router` in [main.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/main.dart).

```dart
return MaterialApp.router(
  ...
  routerConfig: router,
  builder: (context, child) {
    return SnackOverlay(child: child!);
  },
);
```

### AppMessenger Adaptations
Adapt [app_snackbar.dart](file:///c:/Users/rigleyc/projects/supanotes/lib/shared/widgets/app_snackbar.dart) to redirect calls to `showExpressiveSnack` using appropriate icons:
- `showSuccess` maps to `showExpressiveSnack` with a checkmark icon.
- `showError` maps to `showExpressiveSnack` with an error icon.
- `showInfo` maps to `showExpressiveSnack` with an info/details icon.
- `showTaskCompletion` maps to `showExpressiveSnack` with a task/check icon.

## Verification Plan

### Automated Tests
Run `flutter pub get` and verify that the package dependencies resolve and build successfully.

### Manual Verification
Trigger success, info, and error notifications within the app and verify they animate using spring physics and stack on top of each other.
