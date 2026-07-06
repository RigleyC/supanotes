# Adaptive UI iOS Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the white-screen and runtime errors on iOS caused by the `adaptive_platform_ui` migration (commit `0c5b739`) so the app renders correctly on iOS with the native iOS 26 toolbar (`useNativeToolbar: true`) while keeping Android behavior unchanged.

**Architecture:** The app uses `MaterialApp.router` (kept — `Theme.of(context)` is used in 50+ callsites). The white screen on iOS 26+ comes from the `IOS26Scaffold` + `IOS26NativeToolbar` path which needs a `CupertinoTheme` ancestor and `GlobalCupertinoLocalizations` to render correctly. Content scrolling behind the semi-transparent Liquid Glass toolbar is the intended iOS 26 design and is acceptable. The fix adds `CupertinoTheme` + localization delegates to the root, adds `iosSymbol` to the two `AdaptiveAppBarAction`s that are missing it (so they appear in the native toolbar), fixes no-appBar fallback branches that render under the status bar, and replaces Material-specific overlay APIs (`ScaffoldMessenger.of(context)`, `showDialog`, `showModalBottomSheet`) with adaptive equivalents.

**Tech Stack:** Flutter, `adaptive_platform_ui` 0.1.107, `super_editor`, Riverpod 3.x, GoRouter.

---

## Context

### What broke and why

On Android, `AdaptiveScaffold` renders Material `Scaffold` + `AppBar` — the same widget family the app was built for. Tests pass, Android works.

On iOS, `AdaptiveScaffold` takes a completely different code path (`adaptive_scaffold.dart:271`):
- **iOS < 26**: `CupertinoPageScaffold` + `CupertinoNavigationBar`
- **iOS 26+ with `useNativeToolbar: true` (default)**: `IOS26Scaffold` + `IOS26NativeToolbar` (native `UiKitView` platform view)

The white screen on iOS 26+ is caused by:
1. **No `CupertinoTheme` ancestor** — `CupertinoColors` dynamic colors resolve to defaults; the `IOS26Scaffold` wraps the body in `DefaultTextStyle` with `CupertinoColors.white`/`black` which may not resolve correctly without a `CupertinoTheme`.
2. **No `GlobalCupertinoLocalizations`** — native Cupertino widgets may fail to initialize properly without localization delegates.
3. **`AdaptiveAppBarAction` without `iosSymbol`** — the `toNativeMap()` method sends `icon: iosSymbol` to the native toolbar. If `iosSymbol` is null, the native `UIBarButtonItem` gets no image and no title → blank button (not a crash, but missing UI).

### What does NOT need changing

- **`useNativeToolbar` stays `true`** — the native iOS 26 Liquid Glass toolbar is the desired design. Content scrolling behind it is the intended iOS 26 behavior and is acceptable.
- **`Theme.of(context)` works on iOS** because `MaterialApp.router` injects `Theme` at the root — no need to migrate to `AdaptiveApp.router`.
- **`AppMessenger` works on iOS** — it uses a global `GlobalKey<ScaffoldMessengerState>` (set in `main.dart:96`), no Material `Scaffold` ancestor needed.
- **`CupertinoPageScaffold` with `appBar` adds top padding** (obstructing nav bar) — content is NOT hidden for screens that pass `appBar`. The `IOS26Scaffold` does NOT add top padding (body renders behind the toolbar) — this is the intended iOS 26 design.

### The "Bad state: expected exactly one element but got 2" error

Investigation found NO `.single` calls in production code of the app, `super_editor`, `adaptive_platform_ui`, `follow_the_leader`, `overlord`, or `cue`. The error likely comes from the Flutter framework's `Hero` system — `IOS26Scaffold` creates `Hero(tag: 'adaptive_back_button')` (with `useHeroBackButton: true` default) on every screen that `canPop`. The package tries to handle this with placeholder Heroes on non-current routes, but the interaction with GoRouter's navigation stack may produce duplicate Hero tags during transitions. Adding `CupertinoTheme` (Task 1) may resolve rendering issues that expose this. If the error persists after the fix, set `useHeroBackButton: false` on the `AdaptiveScaffold`s as a follow-up.

### Files involved

**Root:**
- `lib/main.dart` — add `CupertinoTheme` wrapper + localization delegates
- `lib/shared/theme/app_theme.dart` — add `cupertinoLightTheme` / `cupertinoDarkTheme` getters

**`AdaptiveAppBarAction`s missing `iosSymbol` (2 actions):**
- `lib/features/notes/presentation/note_editor_screen.dart:205` — check button (`Icons.check`)
- `lib/features/notes/presentation/inbox_screen.dart` — check button (`Icons.check`)

**Fallback branches (add `SafeArea` — these have NO appBar so content is under status bar with nothing behind it):**
- `lib/features/notes/presentation/inbox_screen.dart` — loading/error/null branches
- `lib/features/notes/presentation/note_editor_screen.dart` — loading/error/null branches

**Material-specific API fixes:**
- `lib/features/agent/presentation/chat_screen.dart:20` — `ScaffoldMessenger.of(context)` → `AppMessenger`
- `lib/features/notes/presentation/widgets/note_editor.dart:199` — `ScaffoldMessenger.of(context)` → `AppMessenger`

**Shared helpers (make adaptive):**
- `lib/shared/widgets/confirm_dialog.dart` — `showDialog` + `AlertDialog` → `CupertinoAlertDialog` on iOS
- `lib/shared/widgets/app_bottom_sheet.dart` — `showModalBottomSheet` → style with Cupertino colors on iOS

**Inline dialog fix:**
- `lib/features/settings/presentation/settings_screen.dart:117` — inline `showDialog` + `AlertDialog` → adaptive

**Auth screens (migrate to `AdaptiveScaffold`):**
- `lib/features/auth/presentation/splash_screen.dart`
- `lib/features/auth/presentation/login_screen.dart`
- `lib/features/auth/presentation/register_screen.dart`

---

## Task 1: Add CupertinoTheme + localization delegates to MaterialApp

On iOS, `CupertinoPageScaffold`, `CupertinoNavigationBar`, and the `IOS26Scaffold`'s `DefaultTextStyle` all rely on `CupertinoColors` dynamic colors. Without a `CupertinoTheme` ancestor, these resolve to system defaults that may not work correctly with the `IOS26Scaffold`'s `DefaultTextStyle` wrapper (which uses `CupertinoColors.white`/`black`). Adding `CupertinoTheme` ensures these colors resolve properly. Adding `GlobalCupertinoLocalizations.delegate` ensures native Cupertino widgets show Portuguese text.

**Files:**
- Modify: `lib/shared/theme/app_theme.dart` — add `cupertinoLightTheme` / `cupertinoDarkTheme` getters
- Modify: `lib/main.dart:92-106` — add `CupertinoTheme` wrapper + localization delegates

- [ ] **Step 1: Add CupertinoThemeData getters to AppTheme**

In `lib/shared/theme/app_theme.dart`, add the `flutter/cupertino.dart` import at the top and two static getters after `darkTheme`:

```dart
import 'package:flutter/cupertino.dart';
```

```dart
/// Cached light Cupertino theme derived from the Material color scheme.
static final CupertinoThemeData cupertinoLightTheme = _buildCupertinoTheme(Brightness.light);

/// Cached dark Cupertino theme derived from the Material color scheme.
static final CupertinoThemeData cupertinoDarkTheme = _buildCupertinoTheme(Brightness.dark);

static CupertinoThemeData _buildCupertinoTheme(Brightness brightness) {
  final colorScheme = brightness == Brightness.light
      ? AppColors.lightColorScheme
      : AppColors.darkColorScheme;
  return CupertinoThemeData(
    brightness: brightness,
    primaryColor: colorScheme.primary,
    scaffoldBackgroundColor: colorScheme.surface,
    textTheme: CupertinoTextThemeData(
      primaryColor: colorScheme.onSurface,
      textStyle: AppTypography.textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurface,
      ) ?? const TextStyle(),
    ),
  );
}
```

- [ ] **Step 2: Update main.dart to add CupertinoTheme wrapper + localization**

In `lib/main.dart`, add these imports at the top:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
```

Then modify the `MaterialApp.router` call in `_SupaNotesAppState.build()` (lines 92-106). Add `localizationsDelegates` and `supportedLocales`, and update the `builder` to wrap the child in `CupertinoTheme` on iOS:

```dart
return MaterialApp.router(
  title: AppConstants.appName,
  debugShowCheckedModeBanner: false,
  routerConfig: router,
  scaffoldMessengerKey: AppMessenger.key,
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: const [
    Locale('pt', 'BR'),
    Locale('en', 'US'),
  ],
  builder: (context, child) {
    Widget result = child!;
    if (kDebugMode) {
      result = CueDebugTools(child: result);
    }
    if (PlatformInfo.isIOS) {
      final brightness = MediaQuery.platformBrightnessOf(context);
      result = CupertinoTheme(
        data: brightness == Brightness.dark
            ? AppTheme.cupertinoDarkTheme
            : AppTheme.cupertinoLightTheme,
        child: result,
      );
    }
    return result;
  },
  theme: AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
);
```

- [ ] **Step 3: Add flutter_localizations dependency if not present**

Check `pubspec.yaml` for `flutter_localizations`. If missing, add under `dependencies`:

```yaml
  flutter_localizations:
    sdk: flutter
```

Run: `flutter pub get`

- [ ] **Step 4: Run flutter analyze**

Run: `flutter analyze --no-pub --no-fatal-infos`
Expected: No new errors.

- [ ] **Step 5: Run tests**

Run: `flutter test --no-pub`
Expected: Same results as before (4 pre-existing failures, 0 new).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "fix(adaptive): add CupertinoTheme wrapper and localization delegates for iOS"
```

---

## Task 2: Add iosSymbol to check button actions

The `AdaptiveAppBarAction` for the check button (dismiss keyboard) in `note_editor_screen.dart` and `inbox_screen.dart` only has `icon: Icons.check` — no `iosSymbol`. On iOS 26+ with `useNativeToolbar: true`, the native toolbar uses `iosSymbol` to render an SF Symbol via `UIImage(systemName:)`. Without it, `toNativeMap()` sends no `icon` key and the button is invisible in the native toolbar.

**Files:**
- Modify: `lib/features/notes/presentation/note_editor_screen.dart:205`
- Modify: `lib/features/notes/presentation/inbox_screen.dart` (check button action)

- [ ] **Step 1: Add iosSymbol to note_editor_screen.dart check button**

In `lib/features/notes/presentation/note_editor_screen.dart`, find the check button `AdaptiveAppBarAction` (around line 205) and add `iosSymbol: 'checkmark'`:

```dart
// Before:
AdaptiveAppBarAction(
  icon: Icons.check,
  onPressed: () {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  },
),

// After:
AdaptiveAppBarAction(
  icon: Icons.check,
  iosSymbol: 'checkmark',
  onPressed: () {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  },
),
```

- [ ] **Step 2: Add iosSymbol to inbox_screen.dart check button**

In `lib/features/notes/presentation/inbox_screen.dart`, find the check button `AdaptiveAppBarAction` and add `iosSymbol: 'checkmark'`:

```dart
// Before:
AdaptiveAppBarAction(
  icon: Icons.check,
  onPressed: ...,
),

// After:
AdaptiveAppBarAction(
  icon: Icons.check,
  iosSymbol: 'checkmark',
  onPressed: ...,
),
```

- [ ] **Step 3: Run flutter analyze**

Run: `flutter analyze --no-pub --no-fatal-infos`
Expected: No new errors.

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/notes/presentation/ --no-pub`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "fix(adaptive): add iosSymbol to check button actions so they render in native iOS 26 toolbar"
```

---

## Task 3: Fix no-appBar fallback branches with SafeArea

Several screens have loading/error/null branches that create `AdaptiveScaffold(body: Center(...))` **without** an `appBar`. On iOS, without a nav bar:
- `CupertinoPageScaffold` adds NO top padding — content renders under the status bar with nothing behind it.
- `IOS26Scaffold` has no toolbar — content renders at y=0 under the status bar.

These need `SafeArea` so the content (spinner, error text, "not found" message) is not hidden under the status bar. Note: this is NOT about content behind the toolbar (which is fine) — these branches have NO toolbar at all.

**Files:**
- Modify: `lib/features/notes/presentation/inbox_screen.dart`
- Modify: `lib/features/notes/presentation/note_editor_screen.dart`

- [ ] **Step 1: Fix inbox_screen.dart fallback branches**

In `lib/features/notes/presentation/inbox_screen.dart`, find every `AdaptiveScaffold(body: ...)` that does NOT have an `appBar` and wrap the body in `SafeArea`:

```dart
// Before (loading):
const AdaptiveScaffold(body: Center(child: CircularProgressIndicator())),

// After:
const AdaptiveScaffold(body: SafeArea(child: Center(child: CircularProgressIndicator()))),
```

```dart
// Before (error):
AdaptiveScaffold(body: Center(child: Text('Error: $error'))),

// After:
AdaptiveScaffold(body: SafeArea(child: Center(child: Text('Error: $error')))),
```

Apply to ALL no-appBar `AdaptiveScaffold` instances in this file.

- [ ] **Step 2: Fix note_editor_screen.dart fallback branches**

In `lib/features/notes/presentation/note_editor_screen.dart`, same pattern — wrap all no-appBar `AdaptiveScaffold(body: ...)` bodies in `SafeArea`:

```dart
// Before (note not found):
return AdaptiveScaffold(
  body: Center(child: Text(NoteStrings.errorNotFound)),
);

// After:
return AdaptiveScaffold(
  body: SafeArea(child: Center(child: Text(NoteStrings.errorNotFound))),
);
```

```dart
// Before (loading):
const AdaptiveScaffold(body: Center(child: CircularProgressIndicator())),

// After:
const AdaptiveScaffold(body: SafeArea(child: Center(child: CircularProgressIndicator()))),
```

```dart
// Before (error):
AdaptiveScaffold(body: Center(child: Text('Error: $error'))),

// After:
AdaptiveScaffold(body: SafeArea(child: Center(child: Text('Error: $error')))),
```

- [ ] **Step 3: Run flutter analyze**

Run: `flutter analyze --no-pub --no-fatal-infos`
Expected: No new errors.

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/notes/presentation/ --no-pub`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "fix(adaptive): wrap no-appBar fallback branches in SafeArea to avoid status bar overlap on iOS"
```

---

## Task 4: Replace ScaffoldMessenger.of(context) with AppMessenger

`ScaffoldMessenger.of(context)` works (the root `ScaffoldMessenger` is installed via `scaffoldMessengerKey` in `main.dart`), but it bypasses the app's `AppMessenger` helper and shows an un-styled Material `SnackBar` on iOS. Replace with `AppMessenger` for consistent styling.

**Files:**
- Modify: `lib/features/agent/presentation/chat_screen.dart:20`
- Modify: `lib/features/notes/presentation/widgets/note_editor.dart:199`

- [ ] **Step 1: Fix chat_screen.dart**

In `lib/features/agent/presentation/chat_screen.dart`, find the method around line 20 that uses `ScaffoldMessenger.of(context)`:

```dart
// Before:
final messenger = ScaffoldMessenger.of(context);
...
messenger.showSnackBar(
  const SnackBar(content: Text('Não foi possível limpar o histórico no servidor.')),
);

// After:
AppMessenger.showError('Não foi possível limpar o histórico no servidor.');
```

Remove the `final messenger = ScaffoldMessenger.of(context);` line entirely. Replace the `messenger.showSnackBar(...)` call with `AppMessenger.showError(...)`.

Add the import if not already present:
```dart
import 'package:supanotes/shared/widgets/app_snackbar.dart';
```

- [ ] **Step 2: Fix note_editor.dart**

In `lib/features/notes/presentation/widgets/note_editor.dart`, find the `_onAttach` method error callback around line 199:

```dart
// Before:
onError: () {
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Falha ao enviar anexo')),
    );
  }
},

// After:
onError: () {
  if (mounted) {
    AppMessenger.showError('Falha ao enviar anexo');
  }
},
```

Add the import if not already present:
```dart
import 'package:supanotes/shared/widgets/app_snackbar.dart';
```

- [ ] **Step 3: Run flutter analyze**

Run: `flutter analyze --no-pub --no-fatal-infos`
Expected: No new errors.

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/notes/presentation/ --no-pub`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "fix(adaptive): replace ScaffoldMessenger.of(context) with AppMessenger for consistent snackbar styling"
```

---

## Task 5: Make showConfirmDialog adaptive

The shared `showConfirmDialog` helper in `confirm_dialog.dart` always shows a Material `AlertDialog`. On iOS it should show a `CupertinoAlertDialog` for native look and feel.

**Files:**
- Modify: `lib/shared/widgets/confirm_dialog.dart`

- [ ] **Step 1: Add CupertinoAlertDialog branch to showConfirmDialog**

In `lib/shared/widgets/confirm_dialog.dart`, add the `flutter/cupertino.dart` import and modify `showConfirmDialog` to check the platform and show `CupertinoAlertDialog` on iOS:

```dart
import 'package:flutter/cupertino.dart';
```

Replace the `showConfirmDialog` function:

```dart
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = ConfirmDialogStrings.confirm,
  String cancelLabel = ConfirmDialogStrings.cancel,
  bool destructive = false,
}) async {
  final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

  if (isIOS) {
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
    ),
  );
  return result ?? false;
}
```

The `ConfirmDialog` widget (Material `AlertDialog`) stays unchanged for the Android path.

- [ ] **Step 2: Run flutter analyze**

Run: `flutter analyze --no-pub --no-fatal-infos`
Expected: No new errors.

- [ ] **Step 3: Run tests**

Run: `flutter test --no-pub`
Expected: Same results as before. Existing tests that call `showConfirmDialog` run on Android (default test platform), so they hit the `showDialog` branch.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "fix(adaptive): showConfirmDialog uses CupertinoAlertDialog on iOS"
```

---

## Task 6: Make showAppBottomSheet adaptive

The shared `showAppBottomSheet` helper always shows a Material `showModalBottomSheet`. On iOS it should use Cupertino colors and styling for native look and feel.

**Files:**
- Modify: `lib/shared/widgets/app_bottom_sheet.dart`

- [ ] **Step 1: Add Cupertino styling branch to showAppBottomSheet**

In `lib/shared/widgets/app_bottom_sheet.dart`, add the `flutter/cupertino.dart` import and style the sheet with Cupertino background color on iOS:

```dart
import 'package:flutter/cupertino.dart';
```

Replace the `showAppBottomSheet` function:

```dart
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  double maxHeightFactor = 0.85,
}) {
  final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: isIOS ? CupertinoColors.systemBackground : null,
    shape: isIOS
        ? const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          )
        : null,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: AppSpacing.lg + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * maxHeightFactor,
          ),
          child: builder(ctx),
        ),
      );
    },
  );
}
```

Note: We keep `showModalBottomSheet` (it works on iOS) but style it with Cupertino background color and rounded corners.

- [ ] **Step 2: Run flutter analyze**

Run: `flutter analyze --no-pub --no-fatal-infos`
Expected: No new errors.

- [ ] **Step 3: Run tests**

Run: `flutter test --no-pub`
Expected: Same results as before.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "fix(adaptive): style showAppBottomSheet with Cupertino colors on iOS"
```

---

## Task 7: Fix inline showDialog in settings_screen

`settings_screen.dart:117` has an inline `showDialog` + `AlertDialog` for the sync info dialog. This should use an adaptive approach.

**Files:**
- Modify: `lib/features/settings/presentation/settings_screen.dart:110-130`

- [ ] **Step 1: Replace inline AlertDialog with adaptive dialog**

In `lib/features/settings/presentation/settings_screen.dart`, add the `flutter/cupertino.dart` import and replace the `_showSyncDialog` method:

```dart
import 'package:flutter/cupertino.dart';
```

```dart
Future<void> _showSyncDialog(BuildContext context, WidgetRef ref) async {
  final sync = ref.watch(syncStateProvider);
  final lastSynced = sync.lastSyncedAt;
  final message = lastSynced == null
      ? 'Nenhuma sincronização registrada.'
      : 'Última sync: ${timeago.format(lastSynced, locale: 'pt_BR')}';

  final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

  if (isIOS) {
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Sincronização'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Sincronização'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}
```

- [ ] **Step 2: Run flutter analyze**

Run: `flutter analyze --no-pub --no-fatal-infos`
Expected: No new errors.

- [ ] **Step 3: Run tests**

Run: `flutter test test/features/settings/ --no-pub`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "fix(adaptive): use CupertinoAlertDialog for sync info on iOS"
```

---

## Task 8: Migrate auth screens to AdaptiveScaffold

The auth screens (`splash_screen.dart`, `login_screen.dart`, `register_screen.dart`) still use Material `Scaffold`. While they work (login/register use `SafeArea`), migrating them to `AdaptiveScaffold` gives consistent nav bar styling and iOS-native appearance.

**Files:**
- Modify: `lib/features/auth/presentation/splash_screen.dart`
- Modify: `lib/features/auth/presentation/login_screen.dart`
- Modify: `lib/features/auth/presentation/register_screen.dart`

- [ ] **Step 1: Migrate splash_screen.dart**

In `lib/features/auth/presentation/splash_screen.dart`, add the `adaptive_platform_ui` import and replace `Scaffold` with `AdaptiveScaffold`:

```dart
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
```

```dart
// Before:
return Scaffold(body: Center(child: Column(...)));

// After:
return AdaptiveScaffold(
  body: SafeArea(child: Center(child: Column(...))),
);
```

No `appBar` needed for splash — it's a full-screen loading state. Wrap body in `SafeArea` to avoid status bar overlap (no nav bar = no automatic top padding).

- [ ] **Step 2: Migrate login_screen.dart**

In `lib/features/auth/presentation/login_screen.dart`, add the import and replace `Scaffold` with `AdaptiveScaffold` and add a nav bar:

```dart
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
```

```dart
// Before:
return Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(...))));

// After:
return AdaptiveScaffold(
  appBar: const AdaptiveAppBar(title: 'Entrar'),
  body: SafeArea(
    bottom: false,
    child: Center(child: SingleChildScrollView(...)),
  ),
);
```

- [ ] **Step 3: Migrate register_screen.dart**

In `lib/features/auth/presentation/register_screen.dart`, same pattern as login:

```dart
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
```

```dart
// Before:
return Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(...))));

// After:
return AdaptiveScaffold(
  appBar: const AdaptiveAppBar(title: 'Criar conta'),
  body: SafeArea(
    bottom: false,
    child: Center(child: SingleChildScrollView(...)),
  ),
);
```

- [ ] **Step 4: Run flutter analyze**

Run: `flutter analyze --no-pub --no-fatal-infos`
Expected: No new errors.

- [ ] **Step 5: Run tests**

Run: `flutter test test/features/auth/ --no-pub`
Expected: All auth tests pass. If tests reference `Scaffold` finders, update them to find `AdaptiveScaffold` or the content widgets directly.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "fix(adaptive): migrate auth screens to AdaptiveScaffold for consistent iOS appearance"
```

---

## Task 9: Final verification and deploy

- [ ] **Step 1: Run full flutter analyze**

Run: `flutter analyze --no-pub --no-fatal-infos`
Expected: 0 errors, same or fewer warnings as before.

- [ ] **Step 2: Run full flutter test**

Run: `flutter test --no-pub`
Expected: Same 4 pre-existing failures (check_db, snackbar timeout, app_theme timeout, app_typography assertion), 0 new failures.

- [ ] **Step 3: Run Go backend tests**

Run: `go test ./...` in `backend/`
Expected: All pass.

- [ ] **Step 4: Push to master**

```bash
git push origin master
```

- [ ] **Step 5: Deploy backend (if backend changed)**

The backend (`service.go` settings fix) was already deployed in the `0c5b739` commit. No backend changes in this fix, so no redeploy needed. If any backend files changed, deploy from `backend/`:

```bash
flyctl deploy
```

- [ ] **Step 6: Manual iOS verification**

On an iOS device or simulator (iOS 26+ if available):
1. Launch app — should see splash, then login screen with nav bar
2. Login — should see notes list with native Liquid Glass toolbar
3. Tap a note — should see editor with native toolbar, NOT "Bad state" error
4. The check button (dismiss keyboard) should be visible in the toolbar
5. Open settings — should see settings list with nav bar
6. Open chat — should see chat with nav bar
7. Trigger a snackbar (e.g., delete a note) — should see styled snackbar
8. Open a confirm dialog (e.g., logout) — should see `CupertinoAlertDialog` on iOS
9. Open a bottom sheet (e.g., share note) — should see styled bottom sheet

If the "Bad state: expected exactly one element but got 2" error persists, set `useHeroBackButton: false` on the `AdaptiveScaffold`s as a follow-up — the `IOS26Scaffold` creates `Hero(tag: 'adaptive_back_button')` on every poppable screen, which may conflict with GoRouter's navigation stack.
