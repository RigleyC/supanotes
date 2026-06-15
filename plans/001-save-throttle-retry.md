# Plan 001: Fix save throttle silent failure

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result. Update the status row in `plans/README.md` when done.
> **Drift check**: `git diff --stat HEAD -- lib/core/utils/save_throttle.dart`

## Status
- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug

## Why this matters
Currently, if the local SQLite database is locked or an autosave fails 3 times, `SaveThrottle` silently drops the edit and logs to the console. The user has no idea their work wasn't saved, leading to permanent data loss when they close the app. We need to throw the error or surface it.

## Current state
`lib/core/utils/save_throttle.dart:84`
```dart
      } catch (e) {
        if (attempt == maxAttempts - 1) {
          debugPrint('saveThrottle: all retries failed: $e');
          return;
        }
```

## Scope
**In scope**: `lib/core/utils/save_throttle.dart`

## Steps

### Step 1: Rethrow error on final attempt
Change `SaveThrottle._runIfCurrent` to rethrow the error instead of silently returning on the final attempt.

```dart
      } catch (e) {
        if (attempt == maxAttempts - 1) {
          debugPrint('saveThrottle: all retries failed: $e');
          throw e; // RETHROW here
        }
```
**Verify**: Run `flutter analyze` -> no errors.

## Done criteria
- [ ] Error is rethrown on exhaustion.
- [ ] `flutter test` passes.
- [ ] `plans/README.md` updated.
