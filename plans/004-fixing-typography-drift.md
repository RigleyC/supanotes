# Plan 004: Fixing Typography Drift

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat ff944a4..HEAD -- lib/shared/theme/app_typography.dart test/shared/theme/app_typography_test.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `ff944a4`, 2026-06-13

## Why this matters

The implementation of `AppTypography` was switched to use `Bricolage Grotesque` instead of `Inter` to match design changes, but the documentation comments, tests, and static declarations were not aligned. `AppTypography.fontFamily` was commented out entirely, causing compilation failures in `app_typography_test.dart` with the error: `Member not found: 'fontFamily'`.

## Current state

- `lib/shared/theme/app_typography.dart` — typography configuration of the theme
- `test/shared/theme/app_typography_test.dart` — unit tests for typography constants

Excerpts:
In `lib/shared/theme/app_typography.dart` line 20:
```dart
 // static const String fontFamily = 'Inter';
```
In `test/shared/theme/app_typography_test.dart` line 47:
```dart
    test('font family is Inter', () {
      expect(AppTypography.fontFamily, 'Inter');
    });
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Analyze | `flutter analyze` | exit 0, no issues   |
| Tests   | `flutter test test/shared/theme/app_typography_test.dart` | all pass |

## Scope

**In scope**:
- `lib/shared/theme/app_typography.dart`
- `test/shared/theme/app_typography_test.dart`

**Out of scope**:
- Changing the actual fonts used in the application screens
- Changing color theme or spacing values

## Git workflow

- Branch: `fix/typography-drift`
- Commit format: `fix(theme): align fontFamily declaration and tests`

## Steps

### Step 1: Re-enable and update fontFamily in AppTypography
In `lib/shared/theme/app_typography.dart`, uncomment `fontFamily` and update it to return Bricolage Grotesque.
```diff
   // ---------------------------------------------------------------------------
   // Font family
   // ---------------------------------------------------------------------------
 
- // static const String fontFamily = 'Inter';
+  static String get fontFamily => GoogleFonts.bricolageGrotesque().fontFamily ?? 'Bricolage Grotesque';
```
Also update the docstring of the class to reference Bricolage Grotesque instead of Inter:
```diff
 /// Typographic scale for the SupaNotes design system.
 ///
-/// Built on top of [GoogleFonts.interTextTheme] so every widget that picks up
-/// the theme renders in **Inter** — a neutral, highly-legible sans-serif
-/// designed for screens and ideal for productivity apps.
+/// Built on top of [GoogleFonts.bricolageGrotesqueTextTheme] so every widget that
+/// picks up the theme renders in **Bricolage Grotesque**.
```

**Verify**: `flutter analyze` runs, and the compiler error about `fontFamily` is resolved (but the unit test will fail on the assertion value).

### Step 2: Update typography unit test assertions
In `test/shared/theme/app_typography_test.dart`, update the font family test to expect Bricolage Grotesque.
```diff
-    test('font family is Inter', () {
-      expect(AppTypography.fontFamily, 'Inter');
-    });
+    test('font family is Bricolage Grotesque', () {
+      expect(AppTypography.fontFamily, contains('BricolageGrotesque'));
+    });
```

**Verify**: Run `flutter test test/shared/theme/app_typography_test.dart`. All tests in the file must pass.

## Test plan

- Run `flutter test test/shared/theme/app_typography_test.dart` and verify that the typography tests compile and pass successfully.

## Done criteria

- [ ] `flutter test test/shared/theme/app_typography_test.dart` passes successfully
- [ ] `flutter analyze` returns 0 issues on the modified files
- [ ] No other files modified
