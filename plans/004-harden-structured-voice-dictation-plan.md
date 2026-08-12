# Plan 004: Make the structured voice dictation plan safe to execute

> **Executor instructions**: This plan changes documentation only. Follow each
> step in order. Run every verification command. Stop on a STOP condition. Do
> not resolve a mismatch by inventing a new interface, fallback, compatibility
> path, or direct task-table write.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: docs and architecture
- **Planned at**: commit `870dc960`, 2026-08-11
- **Input plan SHA-256**:
  `57bfa26c8be6267c22da78ffe72bc8f0a4b00cd6b15f944aa6062c87947f00f2`

## Drift check

The input plan is untracked at the planned commit. A Git diff cannot detect a
change to it. Run both commands before editing:

```powershell
rtk certutil -hashfile docs/superpowers/plans/2026-08-11-dictation-stt-model-evaluation.md SHA256
rtk git status --short -- docs/superpowers/plans/2026-08-11-dictation-stt-model-evaluation.md plans/README.md
```

Expected: the first command prints the SHA-256 above. The second command can
show the input plan as untracked and `plans/README.md` as modified. If the hash
differs, STOP. Read the new plan and reconcile this review with it before work.

The repository has unrelated user changes. Do not clean, restore, stage, or
commit them.

## Why this matters

The input plan describes the whole feature, but it still lets the executor
choose several load-bearing details. Different valid-looking choices would
produce incompatible Go and Dart contracts, unsafe cursor placement, broken
multipart replay, inconsistent audio cleanup, or non-reproducible model scores.
This plan fixes those choices before implementation starts.

The output remains one implementation plan with 26 tasks. Do not split the
feature into more implementation-plan files.

## Current state

- `notes.document` is the canonical note and task source. Dictation must enter
  the note only through one Super Editor command transaction.
- `lib/features/notes/editor/document/document_projection_applier.dart:262-275`
  restores a selection by node ID and uses
  `textPosition.offset.clamp(0, node.text.length)`. It does not transform a saved
  offset through remote text edits.
- `lib/shared/widgets/app_bottom_sheet.dart:6-18` calls
  `showModalBottomSheet` with `showDragHandle: true` and exposes no dismissal or
  drag controls.
- `lib/core/api/auth_interceptor.dart:112-117` changes the authorization header,
  marks `retry`, and replays the same `RequestOptions`. It does not rebuild
  `RequestOptions.data`.
- `lib/shared/widgets/app_snackbar.dart:10-22` and
  `lib/shared/widgets/expressive_snack/src/show_expressive_snack.dart:5-23`
  return `void`, although `SnackOverlay.add` returns the actual snack instance.
- `lib/features/tasks/presentation/widgets/task_metadata_sheet.dart:151-152`
  permits a reminder option only when `option.isRelative == state.hasTime`.
- The app already depends on `flutter_timezone`, `path_provider`, and `uuid`.
  Reuse them.
- The current Flutter SDK is 3.44.1 with Dart 3.12.1. The backend uses Go 1.25.

## Commands

| Purpose | Command | Expected result |
|---|---|---|
| Find obsolete plan text | `rtk rg -n "latest\|disposeAsync\|rebases\|after each request\|25 MiB" docs/superpowers/plans/2026-08-11-dictation-stt-model-evaluation.md` | no active instruction uses an obsolete design |
| Confirm required decisions | `rtk rg -n "4 MiB\|180 seconds\|ReplayBodyFactory\|FailureKind\|650 to 850\|reviewer-a" docs/superpowers/plans/2026-08-11-dictation-stt-model-evaluation.md` | every term has at least one match |
| Markdown whitespace | `rtk git diff --check -- docs/superpowers/plans/2026-08-11-dictation-stt-model-evaluation.md plans/README.md` | exit 0, no output |
| Scope check | `rtk git status --short -- docs/superpowers/plans/2026-08-11-dictation-stt-model-evaluation.md plans/README.md` | only these documentation paths show this work |

Primary references to recheck at execution time:

- [Cloudflare Whisper Large V3 Turbo model](https://developers.cloudflare.com/workers-ai/models/whisper-large-v3-turbo/)
- [Cloudflare Workers limits](https://developers.cloudflare.com/workers/platform/limits/)
- [Cloudflare Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/)
- [Cloudflare Whisper base64 example](https://developers.cloudflare.com/workers-ai/guides/tutorials/build-a-workers-ai-whisper-with-chunking/)

## Scope

**In scope**:

- `docs/superpowers/plans/2026-08-11-dictation-stt-model-evaluation.md`
- `plans/README.md`, only to set Plan 004 status

**Out of scope**:

- all Flutter, Go, Worker, test, generated, lock, platform, and deployment files;
- model evaluation execution;
- provider or Worker deployment;
- secrets and environment values;
- changes to the approved product behavior.

## Architecture that the main plan must state

Use three deep modules with small interfaces:

1. **STT Worker module**: authenticate, bound the M4A body, call the fixed
   Whisper model, and return a transcript. It knows nothing about notes, tasks,
   dates, users, or editor blocks.
2. **Go dictation module**: validate audio, transcribe, structure, validate the
   block plan, and map typed failures to HTTP. The handler is an adapter. The
   `Transcriber` and `Structurer` ports are internal seams for the two true
   external dependencies. Production must not import `internal/dictationeval`.
3. **Flutter dictation module**: own microphone permission, recording, temporary
   file, request cancellation, retry, and state transitions. The note screen
   sends user and lifecycle events. Only `NoteEditorController` can apply the
   final plan to the document.

Do not add a generic AI module, provider registry, runtime provider selector,
fallback router, persistent dictation queue, direct Drift task write, or backend
note mutation.

## Required revisions

### Step 1: Add plan control and phase gates

Remove the agent-control directive at the top of the input plan. Add:

- planned commit and the source-file inventory below;
- a checklist for all 26 tasks;
- gates after Tasks 4, 9, 14, 18, 22, and 25;
- the STOP conditions from this plan;
- a rule to run Flutter commands sequentially.

The source drift inventory must include:

```text
agents.md
pubspec.yaml
backend/go.mod
backend/cmd/server/main.go
backend/pkg/config/config.go
backend/internal/auth/rate_limit.go
backend/internal/noteoperations/
lib/core/api/api_client.dart
lib/core/api/auth_interceptor.dart
lib/core/di/providers.dart
lib/features/notes/editor/application/note_editor_controller.dart
lib/features/notes/editor/document/document_projection_applier.dart
lib/features/notes/editor/document/note_document_codec.dart
lib/features/notes/editor/document/note_editor_commands.dart
lib/features/notes/editor/presentation/note_editor_screen.dart
lib/features/notes/editor/presentation/widgets/note_editor.dart
lib/features/notes/editor/presentation/widgets/note_toolbar.dart
lib/features/tasks/domain/
lib/features/tasks/presentation/widgets/task_metadata_sheet.dart
lib/shared/widgets/app_bottom_sheet.dart
lib/shared/widgets/app_snackbar.dart
lib/shared/widgets/expressive_snack/
```

**Verify**: the input plan has one phase-gate table and all 26 task checkboxes.

### Step 2: Close the structured-content contract

Keep the approved public fields, but add these rules to Task 1, the JSON Schema,
the semantic prompt, Go validation, Dart validation, and corpus tests.

#### Text and language

- Normalize the STT transcript only by converting CRLF to LF and trimming
  leading and trailing Unicode whitespace.
- Reject NUL and control characters other than LF and TAB.
- The model must return that normalized transcript exactly in `transcript`.
  The Go service compares it with the STT result. Blocks can remove hesitation
  and clear accidental repetition, but the `transcript` field cannot.
- `language` must match `^[a-z]{2,3}(-[A-Z]{2})?$`.
- `warnings` is a non-null array of unique codes. Its only valid values are
  `ambiguous_date`, `ambiguous_time`, `unsupported_recurrence`,
  `ambiguous_reminder`, and `uncertain_structure`. It cannot contain user text.

#### Blocks

- One block maps to one Super Editor node.
- Each bullet, numbered item, or task is a separate block. A list is represented
  by adjacent blocks of the same list type. There is no list wrapper.
- `indent` is an integer from 0 through 8. It must be 0 for paragraph, heading,
  quote, and divider blocks. Only list and task blocks can use a larger value.
- Divider text is exactly empty. All other text is non-empty after trim.
- Only task blocks have `taskMetadata`. Every other block has null metadata.
- `isCompleted` is always false. Completed actions remain prose.

#### Task temporal invariants

Use this closed table:

| Shape | `dueDate` | `hasTime` | `recurrence` | `reminder` |
|---|---|---:|---|---|
| No date | null | false | null | null |
| All-day | local midnight as RFC 3339 with the supplied zone offset | false | optional supported value | null or `9am`, `12pm`, `6pm`, `1d_before_9am` |
| Timed | exact local time as RFC 3339 with the supplied zone offset | true | optional supported value | null or `at_time`, `5m_before`, `1h_before`, `1d_before` |

Additional rules:

- Recurrence requires a due date because the date is its anchor.
- A reminder requires a due date.
- Resolve dates in the supplied IANA zone. Reject a returned offset that does
  not match that zone at the returned instant, including a DST transition.
- Preserve ambiguous or unsupported expressions in task text. Leave the related
  metadata null and add the matching warning code.
- Do not add `recurrenceRule`. The main plan must first confirm that the current
  branch has completed its move to canonical `recurrence`; otherwise STOP.

Show one exact valid JSON example and one invalid example for each table row.

**Verify**: Task 1, Task 2, Task 5, Task 11, Task 19, and Task 22 all refer to the
same table instead of restating different rules.

### Step 3: Make evaluation attempts and cost reproducible

Pin these exact Worker development versions and require `package-lock.json`:

```json
{
  "@cloudflare/workers-types": "5.20260811.1",
  "typescript": "7.0.2",
  "vitest": "4.1.10",
  "wrangler": "4.120.1"
}
```

Before Round 1, require one capability probe per candidate. It checks endpoint,
model availability, authentication, JSON-object mode, token accounting, and one
contract-valid response. A production candidate that cannot complete the probe
is not silently skipped. STOP and revise the candidate decision.

Define exactly one `RunRecord` per logical candidate/case/repetition. Replace the
integer-only attempt representation with:

```go
type AttemptRecord struct {
    Number       int      `json:"number"`
    Outcome      string   `json:"outcome"`
    Retryable    bool     `json:"retryable"`
    LatencyMS    int64    `json:"latency_ms"`
    InputTokens  int      `json:"input_tokens"`
    OutputTokens int      `json:"output_tokens"`
    EstimatedUSD *float64 `json:"estimated_usd,omitempty"`
    ErrorCode    string   `json:"error_code,omitempty"`
}
```

`RunRecord` contains `Attempts []AttemptRecord`, final validity, final plan, and
total latency and cost. Write the record only after the logical run finishes.
Never write one scored line per attempt. Round 2 remains exactly 360 semantic
records. A failed logical run remains in the denominator.

Use a seeded shuffle of candidate order for each case and repetition. Store the
seed in the run manifest. Do not always run providers in the same order.

Create `backend/internal/dictationeval/testdata/cost5m.json` with exactly ten
synthetic Portuguese transcripts of 650 to 850 words. Run all ten cases three
times for each of the three finalists: 90 cost-only logical records. Store them
in a separate cost JSONL. Exclude them from semantic scores and manual review.
For each finalist:

```text
five-minute cost = p95(text cost across its 30 cost runs) + US$0.0025 STT
```

Refresh all provider prices from primary provider documentation immediately
before each round. Record URL and retrieval time. Do not change a historical run
after a price changes.

**Verify**: corpus tests require 10 cost cases and 650..850 words; runner tests
require 360 semantic and 90 cost records with retry cardinality unchanged.

### Step 4: Define independent blind reviews and adjudication

Add `ReviewerID` to `ManualScore`. Use separate immutable input files:

```text
round2-review/reviewer-a.json
round2-review/reviewer-b.json
round2-review/adjudicator.json
round2-review/resolved.json
```

Reviewer A and B score every run independently. If any numeric dimension differs
by 2 or more, or `critical_invention` differs, the adjudicator scores that whole
run without seeing provider identity or prior scores. Resolve each numeric field
as the median of three when adjudicated, otherwise the arithmetic mean of A and
B. Resolve `critical_invention` from the adjudicator when used; otherwise use
the matching A/B value. Keep all original files. The scorer reads only
`resolved.json`.

Round 1 uses `reviewer-a.json` only. The CLI must reject duplicate reviewer IDs,
missing runs, extra runs, zero scores, and an adjudication file that contains a
run without a qualifying disagreement.

**Verify**: focused tests cover no disagreement, numeric disagreement,
invention disagreement, missing review, duplicate review, and deterministic
resolved output.

### Step 5: Fix the Worker contract and memory bound

Replace the 25 MiB decision with one 4 MiB limit across Worker, Go, Flutter UI,
and tests. The fixed recorder profile is 64 kbit/s for at most 300 seconds, which
produces about 2.4 MB of AAC payload before small container overhead. Four MiB
keeps a valid recording inside the product limit and leaves Worker memory
headroom.

The Worker accepts only `audio/mp4` and `audio/x-m4a`. It must:

1. authenticate before reading the body;
2. reject `Content-Length > 4 MiB` before reading;
3. use a bounded reader for missing or false `Content-Length` and cancel after
   the 4 MiB plus one-byte probe;
4. convert the bounded bytes once to base64 with `Buffer`;
5. call `env.AI.run('@cf/openai/whisper-large-v3-turbo', {audio: base64,
   task: 'transcribe'})` without forcing a language;
6. trim only outer whitespace from the returned text;
7. return the fixed model ID and text, or a stable error code;
8. never log the token, body, transcript, or response content.

Do not split compressed M4A bytes into arbitrary chunks. Such chunks are not
independent M4A files. The Cloudflare binding path uses base64 audio. Keep at
most four active transcriptions per isolate and return 429 before body buffering
when that local limit is full. Release the slot in `finally`.

Compare bearer tokens without an early-exit plaintext comparison: hash both
values with SHA-256, compare the fixed-length digests with an accumulated XOR,
and reject a missing token before any AI work.

Add a remote smoke test with a generated five-minute, non-speech M4A below
4 MiB. Record peak local heap during the unit load test and check Cloudflare
metrics for `exceededMemory` after the remote test. STOP if the binding types do
not accept the documented base64 form or if a valid recorder output exceeds
4 MiB.

**Verify**: tests cover 4 MiB exact, 4 MiB plus one byte, chunked transfer,
four active calls, fifth call rejected, slot release, safe auth, and blank STT.

### Step 6: Define one typed Go failure model and HTTP matrix

Create one closed `FailureKind` in `backend/internal/dictation`. STT and model
adapters return it. The service preserves it. Only the handler maps it to HTTP.
Do not map errors by text.

Use this response shape:

```json
{"error":"safe human message","code":"stable_machine_code"}
```

Use this exact matrix:

| Code | HTTP | Retry in app | Keep phone audio |
|---|---:|---:|---:|
| `invalid_request` | 400 | no | no |
| `audio_too_large` | 413 | no | no |
| `unsupported_audio` | 415 | no | no |
| `invalid_audio` | 422 | no | no |
| `empty_transcript` | 422 | yes | yes |
| `structure_invalid` | 422 | yes | yes |
| `rate_limited` | 429 | yes, explicit tap | yes |
| `stt_unavailable` | 502 | yes | yes |
| `model_unavailable` | 502 | yes | yes |
| `deadline_exceeded` | 504 | yes | yes |
| `internal_error` | 500 | yes | yes |

429 responses include `Retry-After` in whole seconds. Flutter uses only `code`
for cleanup and retry policy. It uses `error` only as safe display text. Unknown
codes become `internal_error`; do not guess from status text.

**Verify**: table-driven Go and Dart tests contain one case for every row and
assert the same retry and retention decision.

### Step 7: Define one end-to-end deadline

Use these fixed budgets:

- Flutter upload send timeout: 30 seconds;
- Flutter receive timeout: 180 seconds;
- Go handler deadline: 170 seconds from authenticated handler entry;
- STT phase budget: 100 seconds total, first attempt at most 60 seconds;
- structuring phase budget: 55 seconds total, first attempt at most 35 seconds;
- validation, backoff, and serialization reserve: 15 seconds.

A retry uses only the remaining phase and request time. Do not start a retry
when fewer than five seconds remain in its phase. Backoff is bounded by the same
deadline. When Flutter cancels, Echo request context cancellation must reach the
STT and structurer calls. The backend must stop paid work after cancellation.

**Verify**: fake-clock tests cover first-attempt success, each permitted retry,
insufficient time for retry, cancellation in each phase, and the 170-second
handler deadline. No theoretical backend path exceeds the Flutter timeout.

### Step 8: Make multipart replay a shared transport feature

Add this file to Task 19:

```text
lib/core/api/replayable_request_body.dart
```

Define:

```dart
typedef ReplayBodyFactory = Future<Object?> Function();

final class ReplayableRequestBody {
  const ReplayableRequestBody(this.create);
  final ReplayBodyFactory create;
}
```

Add `ApiClient.postReplayable`, not another Dio instance:

```dart
Future<Response<T>> postReplayable<T>(
  String path, {
  required ReplayBodyFactory createData,
  Options? options,
  CancelToken? cancelToken,
  Duration? sendTimeout,
  Duration? receiveTimeout,
})
```

It creates the initial body and stores one `ReplayableRequestBody` in a private
`RequestOptions.extra` key. On 401 after successful token refresh,
`AuthInterceptor` calls the factory again and replaces `RequestOptions.data`
before `_replay`. It then marks the request retried. Normal `post` requests do
not use this path and keep current behavior.

`ApiDictationRepository` owns the multipart factory. Every call creates new
`FormData` and a new `MultipartFile.fromFile` from the same temporary path. It
must fail safely if the file was removed. It sends
`recorded_at=recordedAt.toUtc().toIso8601String()` and the separate IANA zone.
The factory must not capture an open file handle.

**Verify**: integration tests prove first request success, 401 then refresh then
successful multipart replay, refreshed request cancellation, removed file before
replay, and unchanged JSON replay.

### Step 9: Define the backend limiter in the current deployment model

After multipart and M4A validation, but before external work:

- increment a 30-attempt rolling-hour bucket for the authenticated user;
- acquire one active-request slot for that user;
- release the active slot in `defer` on every return and panic unwind;
- count STT and model failures as attempts;
- do not count malformed or invalid audio;
- prune idle keys on each access.

The limiter is process-local. The current Fly deployment must stay at one app
machine for this contract. Task 26 must verify one machine before release. STOP
if the backend runs more than one machine. Do not describe the limit as global.
Before any future horizontal scale, replace this limiter with one shared atomic
implementation and keep the same external interface.

**Verify**: tests cover concurrency, hour boundary, `Retry-After`, independent
users, failed paid attempts, invalid-audio exclusion, release after panic, and
idle-key cleanup.

### Step 10: Make the Flutter state machine race-safe

Keep `DictationFlowController` screen-owned. Do not create a Riverpod state
controller. The repository provider remains `Provider.autoDispose`.

The controller owns the recorder, temporary path, `CancelToken`, monotonic
`Stopwatch`, UI tick timer, recorded instant, insertion anchor, validated plan,
undo handle, and an integer operation generation. Every asynchronous completion
captures the generation and does nothing if cancel or a newer operation changed
it. `start`, `stopAndProcess`, `retry`, `applyAtNewAnchor`, and `cancel` must be
idempotent for duplicate taps. Only one stop and one HTTP request can be active.

The five-minute limit uses the monotonic stopwatch. A periodic timer updates the
visible elapsed value only; it is not the authority for the stop deadline.

Add an audio ownership table to the main plan:

| State | Audio exists | Exit that deletes it |
|---|---:|---|
| idle | no | none |
| recording | yes | cancel or failed recording |
| paused with stopped audio | yes | cancel or resumed processing completion |
| processing | yes | successful apply, permanent failure, or cancel |
| recoverable error | yes | successful retry or cancel |
| awaiting anchor | yes | successful apply or cancel |
| applying | yes | success, permanent apply failure, or cancel |
| completed/cancelled | no | already deleted exactly once |

Use one private `deleteOwnedAudio()` that clears ownership before awaiting file
deletion, so two cleanup paths cannot delete the same owned file. A failed delete
is logged without the path and retried by the stale-file purge. Purge only files
with the exact `supanotes-dictation-` prefix older than one hour in the temporary
directory.

**Verify**: fake tests complete old futures after cancel and after a new start;
state and files must not change. Tests cover duplicate stop, duplicate retry,
timer/manual-stop race, and deletion failure.

### Step 11: Put navigation guards on both routes

Extend `showAppBottomSheet` with:

```dart
bool isDismissible = true,
bool enableDrag = true,
bool? showDragHandle,
```

Existing callers keep their behavior. Dictation passes false, false, and true.
`DictationSheet` has `VoidCallback onReady` and calls it once in a post-frame
callback after its first mount. Recording starts only through this callback.

Put a `PopScope(canPop: false)` inside the dictation sheet route. Its back event
awaits the same controller `cancel()` used by the Cancel button and then closes
the sheet once. A `PopScope` only on the underlying screen is insufficient.

Put a second guard around the editor screen for the state where the sheet is
closed but the controller still owns a cached plan or audio while waiting for a
new anchor. Back, note replacement, sign-out navigation, and note deletion await
`cancel()` before leaving. Synchronous widget `dispose()` starts last-resort
unawaited cleanup only; correctness cannot depend on it.

**Verify**: widget tests cover Android back in the sheet, iOS close action,
explicit Cancel, back while awaiting anchor, note replacement, and duplicate
back. Each path pops once and only after cleanup.

### Step 12: Validate anchors conservatively

`DictationInsertionAnchor` stores the selection, affinity, every selected node
ID, and every selected node's type and plain-text value. Store values directly;
do not log them. Before apply, compare every captured node with the live node.

- If a captured node changed text, changed type, or disappeared, throw
  `DictationAnchorMissingException` and enter `DictationAwaitingAnchor`.
- A remote change outside the selected nodes does not invalidate the anchor.
- Do not claim that `DocumentProjectionApplier` rebases the old offset.
- Do not silently move the plan to the document end or nearest node.

When the user chooses a new anchor, delete the old anchor, close the sheet, allow
editor interaction, and apply the cached plan at the next explicit toolbar tap.
Do not call STT or the model again.

**Verify**: tests cover insert/delete before the caret in the same node, text
replacement, type change, interior node change in a multi-node selection, node
removal, unrelated remote edit, and explicit new-anchor apply.

### Step 13: Keep editor insertion atomic and local

Map each plan block to one new node with a new UUID. Build all edit requests
before mutation and call `editor.execute(requests)` once. Never mutate
`MutableDocument` directly. Never call a task repository or Drift.

Preserve the approved insertion rules, and add these details:

- split text nodes with Super Editor text positions and preserve inline
  attributions on both remaining fragments;
- insert after the full list/task node when the caret is inside a list or task;
- replace all nodes touched by an expanded selection;
- create one empty paragraph after a final divider for the final caret;
- set task metadata from the validated contract without a second date parser or
  independent enum mapping;
- subscribe to document changes only after `editor.execute` returns, so the
  insertion does not invalidate its own undo handle.

`DictationUndoHandle` can call the editor history undo only while no later local
or remote document change has happened. If the public Super Editor history
interface cannot prove one transaction and exact selection restoration, STOP.
Do not implement snapshot replacement as a second mutation path.

**Verify**: one undo restores node values, metadata, order, attributions, and
selection. REST/OT capture contains canonical task metadata and replay converges.

### Step 14: Make the undo notification removable

Add these paths and tests to Task 23:

```text
lib/shared/widgets/app_snackbar.dart
lib/shared/widgets/expressive_snack/src/show_expressive_snack.dart
lib/shared/widgets/expressive_snack/src/snack_overlay.dart
```

`showExpressiveSnack` returns the actual `Snack` returned by `SnackOverlay.add`.
`AppMessenger.showSuccess` returns that snack. Existing callers can ignore it.
Dictation retains it and calls `SnackOverlay.remove(snack)` when the undo handle
is used or invalidated. The action checks `canUndo` again before calling undo.

If `warnings` is not empty after insertion, use the fixed subtitle
`Alguns detalhes ambíguos foram mantidos no texto.` Do not display or log warning
content as arbitrary text because warning values are codes.

**Verify**: tests cover success, undo tap, later local change, later remote
change, duplicate snack coalescing, and an action invoked after invalidation.

### Step 15: Reconcile files, tests, and delivery gates

Update the target-file map and every task's file list. At minimum add:

```text
workers/dictation-stt/package-lock.json
backend/internal/dictation/failure.go
backend/internal/dictation/limiter.go
backend/internal/dictationeval/testdata/cost5m.json
lib/core/api/replayable_request_body.dart
lib/shared/widgets/app_bottom_sheet.dart
lib/shared/widgets/app_snackbar.dart
lib/shared/widgets/expressive_snack/src/show_expressive_snack.dart
lib/shared/widgets/expressive_snack/src/snack_overlay.dart
```

Every task must end with focused verification and an expected result. Each phase
gate runs its full affected suite before the next phase. Do not use `git add`
commands that stage whole directories with unrelated user changes. List exact
files created or changed by that task.

Task 26 must verify:

- one iPhone and one Android device;
- automatic five-minute stop and a near-4-MiB file;
- 401 multipart replay;
- cancel in STT and model phases;
- back from the sheet and awaiting-anchor mode;
- remote edit in the same anchor node and outside it;
- one-action undo and invalidation;
- 429 and every stable error-code policy;
- one Fly app machine;
- Worker metrics with no `exceededMemory` event;
- logs without audio, transcript, block text, note text, file path, or token.

Run the repository checks sequentially:

```powershell
cd backend
rtk go test -count=1 -short ./...
cd ..
rtk flutter analyze --no-fatal-infos
rtk flutter test
cd workers/dictation-stt
rtk npm test
rtk npm run typecheck
```

Expected: every command exits 0. A timeout is a timeout, not a pass.

## Test plan for this documentation revision

- Confirm every cross-tier field has one owner and one validation rule.
- Confirm every asynchronous resource has an owner and terminal cleanup path.
- Confirm every retry has a maximum count, error class, and deadline.
- Confirm every external seam has a production adapter and test adapter.
- Confirm the UI cannot mutate the canonical document outside the editor command.
- Confirm model selection is reproducible from committed corpora plus temporary
  sanitized run artifacts.
- Confirm every file named in a step appears in the target map and task scope.

## Done criteria

- [ ] The main implementation plan remains one file with 26 tasks.
- [ ] The input plan hash was checked before editing.
- [ ] The architecture names the three modules and their interfaces.
- [ ] The block and task contract includes all invariants from Step 2.
- [ ] Round 2 produces exactly 360 semantic and 90 cost-only logical records.
- [ ] Retry attempts stay nested in one logical record.
- [ ] Blind review files and adjudication are deterministic.
- [ ] Worker upload is fixed at 4 MiB and uses one bounded base64 conversion.
- [ ] Go and Dart share the exact failure-code matrix.
- [ ] The 180/170/100/55-second deadline hierarchy is present.
- [ ] Multipart replay rebuilds `FormData` through `postReplayable`.
- [ ] Audio ownership, stale completion guards, and double-delete prevention are
  specified and tested.
- [ ] Both the modal route and editor route have navigation cleanup tests.
- [ ] Anchor validation never relies on offset rebasing.
- [ ] Editor insertion uses one transaction and one canonical REST/OT path.
- [ ] Undo feedback is removed after use or invalidation.
- [ ] Every task has exact files, tests, commands, expected results, and a gate.
- [ ] `rtk git diff --check` exits 0.
- [ ] No source file was changed by Plan 004.
- [ ] `plans/README.md` marks Plan 004 DONE only after all checks pass.

## STOP conditions

Stop and report instead of improvising if:

- the input plan hash differs;
- a source path in the target map no longer exists or has changed role;
- the current branch still writes new task recurrence only to `recurrenceRule`;
- a candidate, model ID, endpoint, JSON mode, or price cannot be confirmed from
  a primary provider source before its round;
- fewer than three production candidates pass Round 1;
- no finalist passes every production gate;
- the Cloudflare binding does not accept the documented base64 audio input;
- a valid 300-second recorder output exceeds 4 MiB;
- the backend runs more than one app machine with the process-local limiter;
- Super Editor cannot express the full insertion and selection change as one
  public-interface history transaction;
- a baseline focused test fails before its phase starts;
- live test credentials or physical iOS and Android devices are unavailable.

Do not add compatibility layers, fallback models, alternate write paths, hidden
persistence, or silent relocation to bypass a STOP condition.

## Maintenance notes

The contract is shared by prompt, evaluator, Go validation, HTTP response, Dart
validation, editor conversion, and tests. A future contract change must update
all of them in one change. Before horizontal backend scaling, replace the
process-local limiter with a shared atomic implementation without changing its
external interface. Before changing recorder bitrate or maximum duration,
recalculate and retest the 4 MiB limit and Worker peak memory.
