# Plan 050: Replace `print` in NodeSyncManager Write Errors with Structured Logging

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat bfebe7e..HEAD -- lib/features/notes/domain/node_sync_manager.dart`
> If any in-scope file changed since this plan was written (plans 048 may
> land first), compare the "Current state" excerpts against the live code
> before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (orthogonal to 046-049; can run before them)
- **Category**: bug | dx
- **Planned at**: commit `bfebe7e`, 2026-07-06

## Why this matters

`NodeSyncManager._enqueueDbWrite` wraps every Drift write in a `try/catch`
that logs via `print(...)` and swallows the exception. Per AGENTS.md ("Erros
não podem ser engolidos", "Use structured logging (e.g., `log/slog`)") this
violates project conventions, hides production sync failures from any
centralized log pipeline, and trains developers to ignore the console output.
The fix is mechanical: swap `print` for `dev.log` (already imported on
`NoteEditorController.dart:3` and used in `initFromNodes`), accept that this
catch is intentional (DB writes shouldn't tear down the editor process), but
classify the log at error level and include the stack trace.

## Current state

### File in scope

`lib/features/notes/domain/node_sync_manager.dart` — only the
`_enqueueDbWrite` method (lines 67-75) and the import header.

### Current code

Lines 67-75:

```dart
Future<double> _writeLock = Future.value();

void _enqueueDbWrite(FutureOr<void> Function() action) {
  _writeLock = _writeLock.then((_) async {
    try {
      await action();
    } catch (e, stackTrace) {
      print('[NodeSyncManager] SQLite Write Error: $e\n$stackTrace');
    }
  });
}
```

Imports (lines 1-10):

```dart
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:super_editor/super_editor.dart';

import '../../../core/database/database.dart';
import 'attachment_nodes.dart';
import 'note_display_text.dart';
import 'task_entry.dart';
```

### Repository conventions

- `dev.log` is the project's logging function. Pattern in
  `note_editor_controller.dart:40-43`:
  ```dart
  dev.log('[NoteEditorController.initFromNodes] nodeCount=${nodes.length}',
      name: 'NoteEditor');
  ```
- Include stack trace when relevant (second param).
- Catching errors here IS intentional (a failed write should not crash the
  editor), but the error message should identify itself as ERROR.
- Do not add code comments unless asked by the plan.

## Commands you will need

| Purpose          | Command                                                              | Expected on success |
|------------------|----------------------------------------------------------------------|---------------------|
| Static analysis  | `dart analyze lib/features/notes/domain/node_sync_manager.dart`      | no errors           |
| Run notes tests  | `flutter test test/features/notes/`                                 | all pass            |
| Grep             | `Select-String -Path lib/features/notes/domain/node_sync_manager.dart -Pattern "print("` | no matches |

## Scope

**In scope** (the only files you should modify):
- `lib/features/notes/domain/node_sync_manager.dart`

**Out of scope** (do NOT touch):
- Any other file that uses `print` — if broader cleanup is wanted, that's a
  separate finding.
- The behavior of swallowing the error (still caught).
- Test files.

## Git workflow

- Branch: `chore/050-node-sync-manager-structured-logging`
- Commit: `chore(editor): use structured logging for NodeSyncManager write errors`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add `dart:developer` import

Open `lib/features/notes/domain/node_sync_manager.dart`. At the top, between
line 2 (`import 'dart:convert';`) and `import 'package:drift/drift.dart';`,
add:

```dart
import 'dart:developer' as dev;
```

### Step 2: Replace `print` with `dev.log`

Replace the catch block (lines 71-73):

```dart
} catch (e, stackTrace) {
  print('[NodeSyncManager] SQLite Write Error: $e\n$stackTrace');
}
```

with:

```dart
} catch (e, stackTrace) {
  dev.log(
    'SQLite write error: $e',
    name: 'NodeSyncManager',
    error: e,
    stackTrace: stackTrace,
    level: 1000,
  );
```

`level: 1000` is dart:developer's convention for SEVERE / error-level. If
unsure, leave it out — `dev.log` defaults to INFO; the `error` and
`stackTrace` fields are what distinguish it. Including `level: 1000` is
preferable for filtering.

`dev.log` signature: `log(String message, {int level, String name, Object? error, StackTrace? stackTrace})`.

### Step 3: Verify

**Verify**: `dart analyze lib/features/notes/domain/node_sync_manager.dart`
→ no errors.

**Verify**: rg/grep for `print(` returns no matches in the file:
```bash
Select-String -Path lib/features/notes/domain/node_sync_manager.dart -Pattern "print\("
```
Expected: empty.

**Verify**: `flutter test test/features/notes/`
→ all pass.

## Test plan

No new tests. The change is a logging-only refactor; existing tests exercise
the catch path indirectly if any failure cases are configured, but the
assertion shape doesn't change.

## Done criteria

- [ ] `dart analyze lib/features/notes/domain/node_sync_manager.dart` exits 0
- [ ] `Select-String` for `print(` in `node_sync_manager.dart` returns no matches
- [ ] `flutter test test/features/notes/` exits 0
- [ ] `git diff --name-only` shows only `node_sync_manager.dart`
- [ ] New import `dart:developer` as `dev`; `dev.log` call with `name: 'NodeSyncManager'`, `error:`, `stackTrace:`, `level: 1000` parameters
- [ ] `plans/README.md` status row for 050 updated to DONE

## STOP conditions

Stop and report back (do not improvise) if:

- `dev.log` signature differs (e.g., no `level` param in this Flutter SDK
  version) — drop `level` and keep the rest; update Done Criteria accordingly.
- Some other file (like `notes_repository.dart`) uses `print` and converts
  errors here — stay strictly in scope; report for a future plan.
- Plan 048 has already modified `_enqueueDbWrite` — re-read live code, update
  the excerpts accordingly, and proceed with the same surgical change.

## Maintenance notes

- The catch is still swallowing — by design. The fix is logging, not
  rethrowing. If a future plan decides DB write failures should surface to the
  UI (snackbar "Sync failed, retry?"), the catch must be revisited.
- A reviewer should confirm: did the executor `dev.log` once per failed
  write (not once per catch), with both `error` and `stackTrace`? Did they
  include the write-type context in the message? If not, advocate for adding
  `"${action.runtimeType}"` or similar in the message — but the plan above is
  minimum sufficient; do not require it for DONE.
- Future code in `NodeSyncManager` that swallows errors must follow this
  pattern, not `print`. Grep for `print(` in `lib/features/notes/` should
  return zero matches after this plan lands.