# Plan 002: Reduce SupaNotes to the note product core

> **Executor instructions**: This is a staged removal plan. Do not delete a
> source-of-truth or database table until the replacement path and the data
> decision for that path are approved. Run each verification gate before the
> next step. Stop on the conditions below instead of inventing a migration.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: none
- **Category**: tech-debt | migration
- **Planned at**: commit `85363b0`, 2026-07-21
- **Working-tree note**: the planned-at checkout already has uncommitted REST/OT note changes. Preserve and review them; do not reset or overwrite them.

## Objective

Keep only the usable note product: notes, rich editing, attachments, tasks,
task recurrence, MCP, authentication/session, user settings/preferences, and
the minimum persistence, sync, search, sharing, context, and tag behavior that
these retained flows require. Remove the discarded product surfaces and their
implementation end to end: agent, Telegram/gateway, routines, memories, soul,
LLM/embeddings, Yjs/CRDT, old Yjs tests and fixtures, dead imports, routes,
database queries, generated bindings, migrations that exist only for discarded
data, configuration, scripts, and documentation that presents them as active.

## Mandatory decision gate

Before implementation, write a short signed-off product contract in the task
record (or `plans/003-retained-scope.md` if a separate record is needed) that
answers these questions:

1. **Persistence/sync replacement**: the current active code uses YDoc/Yjs in
   `lib/core/sync`, `lib/features/notes/domain/yjs_*`, and
   `backend/internal/sync`. The current working tree also contains REST/OT note
   code (`backend/internal/noteoperations` and its Flutter callers). Confirm
   whether REST/OT is the replacement for note content/task mutations. If not,
   stop and specify the replacement before deleting Yjs.
2. **MCP boundary**: retain the MCP server and token/HTTP routes only if they
   call the retained note/task services directly. Remove agent-loop,
   memories, routines, soul, and LLM dependencies from MCP; MCP must not be an
   indirect agent feature.
3. **Retained adjacent note features**: explicitly mark each of contexts,
   tags, search, note sharing, link preview, task notifications, and note
   operations as RETAIN or REMOVE. The recommended default is RETAIN for
   contexts, tags, search, sharing, link preview, and task notifications when
   the existing note UI still exposes them; REMOVE anything with no user-facing
   route after the trim.
4. **Existing data**: decide whether discarded data is exported, retained but
   unreachable, or deleted. This includes `messages`, `agent_working_memory`,
   `memories`, `souls`, `routines`/routine logs, embeddings, Telegram delivery
   data, Yjs snapshots/updates, and pending tool confirmations. No destructive
   production migration is allowed without this decision.

## Current dependency map

- Flutter entry points: `lib/core/router/app_router.dart`,
  `lib/core/di`, `lib/features/notes`, `lib/features/tasks`,
  `lib/features/settings`, and `lib/core/sync`.
- Backend composition root: `backend/cmd/server/main.go`. It currently wires
  agent, attachments, contexts, embeddings, gateway/Telegram, memories,
  noteoperations, notes, routines, search, settings, shares, soul, sync, tags,
  tasks, and MCP in one route graph.
- Yjs package: `pubspec.yaml` path dependency `packages/yjs_dart`; active
  consumers include `lib/core/sync`, editor bridge/codecs, and many tests.
- Relational schema/query surface: `backend/db/migrations`,
  `backend/db/queries`, generated `backend/internal/db/sqlcgen`, and Drift
  tables/DAOs in `lib/core/database`.
- The repository has 970 tracked/untracked files in the broad file listing and
  many historical `docs/superpowers` Yjs/agent plans. Historical documents are
  not runtime code, but active docs must be rewritten or archived after the
  product scope is final.

## Scope classification

### Remove completely after replacement/data gate

- Flutter agent UI and controllers; backend `internal/agent`.
- Telegram client, webhook, gateway repositories/handlers, Telegram config.
- Routines and routine runner, including its agent/Telegram notification path.
- Memories and soul UI/API/data, unless the scope gate explicitly retains them.
- LLM factory/client/provider and embeddings worker/data if no retained feature
  needs them. Do not remove an LLM dependency used by retained MCP until MCP is
  verified to be direct service calls.
- Yjs Dart fork, YDoc editor bridge/codecs, Yjs sync manager/service/compactor,
  Yjs protocol fixtures, CRDT validation tests, Yjs-specific database columns,
  queries, generated code, and server routes.
- Dead feature routes, providers, components, imports, mocks, scripts,
  temporary binaries, scratch files, and stale feature documentation.

### Retain and protect

- Authentication, secure token storage, router guards, health endpoint,
  database connection, migrations framework, and user settings/preferences.
- Notes and the rich editor, including attachment nodes/rendering/upload,
  tasks, recurrence, task reminders/notifications, and MCP after its boundary
  is simplified.
- The approved note synchronization/mutation implementation. The existing
  REST/OT files in the dirty tree must be treated as a candidate, not assumed
  correct; add characterization and end-to-end tests before deleting Yjs.
- Only the local and server tables required by the retained flows. Keep task
  recurrence data and attachment metadata. Preserve note content during any
  schema migration.

## Execution steps

### Step 1: Freeze scope and establish a clean verification baseline

Create the retention matrix from the decision gate. Record current routes,
Flutter screens/providers, backend packages, database tables/columns, package
dependencies, environment variables, and test commands. Separate runtime code
from historical docs and untracked artifacts. Run:

```text
git status --short
flutter analyze
flutter test
go test ./...
```

Expected result: every failure is recorded with file and reason. Do not call a
baseline passing if a command is incomplete or fails. If the current REST/OT
changes do not build, stop and repair or replace that path before Step 2.

### Step 2: Characterize the retained note contract before Yjs removal

Add or complete tests for create/open/edit/reload, paragraph and task editing,
task metadata, recurrence, attachment upload/render/delete, offline queue or
sync behavior, sharing if retained, preferences, MCP note/task operations, and
auth. Test the exact API/database contract at both Flutter and Go boundaries.
Use existing note and task tests as patterns. Include concurrent edit behavior
only to the extent promised by the approved replacement; do not silently claim
CRDT equivalence.

Verify:

```text
flutter test test/features/notes test/features/tasks
go test ./backend/internal/noteoperations/... ./backend/internal/notes/... ./backend/internal/tasks/...
```

Expected result: retained-flow tests pass and define the behavior that must
survive the deletion. If a retained flow still imports Yjs, keep the import
temporarily and map the replacement seam; do not delete it in this step.

### Step 3: Make the replacement persistence/sync path canonical

Complete the approved REST/OT or other replacement path. Remove duplicate write
paths so the editor, task metadata, recurrence, and attachment references have
one owner. Preserve the documented domain rule that the UI does not dual-write
task metadata. Update local Drift projection and server SQL only after the
mutation contract is tested. Add migration compatibility for existing notes;
do not decode old Yjs bytes in the new runtime unless the data decision requires
an explicit one-time importer.

Verify the retained end-to-end tests on a clean local database and a second
client/session. Expected result: edits, task recurrence, and attachments remain
available after reload and sync; no retained API depends on `YDoc`, Yjs state
vectors, or Yjs update bytes.

### Step 4: Remove Yjs and its complete dependency graph

After Step 3, delete Yjs editor bridges/codecs, sync managers/services,
compactor/listeners, state-vector/update exchange, Yjs-specific adapters,
package override, local fork, fixtures, CRDT fuzz/regression tests, and Yjs-only
temporary programs. Remove all Yjs imports and generated code. Remove server
Yjs REST/websocket routes and client calls. Update the database model so no new
runtime code reads or writes Yjs tables. If old Yjs data is retained for audit,
move it behind an explicitly documented archival boundary, not an active model.

Verification gates:

```text
rg -n -i "yjs|ydoc|state.?vector|crdt|pendingStructs" lib backend test packages pubspec.yaml
flutter analyze
go test ./...
```

Expected result: the search has no active-code matches. Historical migration
notes may remain only under an explicitly marked archive and must not be loaded
by builds or runtime code.

### Step 5: Remove discarded application verticals from both clients

Remove agent, memories, soul, routines, search surfaces if not retained,
Telegram/gateway, and any related settings screens, navigation entries,
providers, repositories, API clients, widgets, localization strings, mocks,
fixtures, and tests. In `app_router.dart`, leave only routes in the approved
scope. Remove feature-specific constants and secure/config fields. Re-check
that preferences/settings are not coupled to soul, routines, or agent state.

Verification:

```text
flutter analyze
flutter test
rg -n -i "agent|telegram|gateway|routine|memory|soul|embedding" lib test
```

Expected result: no retained UI or client code references discarded terms;
settings/preferences, auth, notes, tasks, attachments, and MCP still compile
and have tests.

### Step 6: Remove discarded backend services, routes, and dependencies

Simplify `backend/cmd/server/main.go` so construction includes only approved
services. Delete discarded internal packages and their tests. Remove agent
tool registries, working memory, LLM/embedding wiring, Telegram webhook routes,
cron jobs, routines runner, gateway config, and unused third-party modules.
Keep MCP as a direct adapter over retained services and add an authorization
test for each exposed MCP operation.

Verification:

```text
go mod tidy
go test ./...
go vet ./...
rg -n -i "internal/(agent|gateway|memories|routines|soul|embeddings)|Telegram|telegram|agent" backend
```

Expected result: Go tests and vet pass, `go.mod` has no discarded-only
dependencies, and the search has no active discarded service references.

### Step 7: Remove schema, SQL, generated bindings, and configuration residue

Trace every discarded table and column from migrations to queries, sqlc
generated types, repositories, mocks, Drift tables/DAOs, sync payloads, and
deployment configuration. Decide migration strategy per production state:
archive/export, additive deprecation, or destructive drop. Do not rewrite old
applied migrations; add a new forward migration for live databases. Remove
discarded environment variables from `.env.example`, deployment manifests,
Docker/Codemagic scripts, and README setup instructions. Regenerate sqlc and
Drift code using the repository's existing commands.

Verification:

```text
rg -n -i "messages|agent_working_memory|memories|souls|routines|routine_logs|note_yjs|yjs_updates|yjs_states|embedding|telegram|pending_tool_confirmations" backend lib test
go test ./...
flutter analyze
```

Expected result: only explicitly approved migration/archive references remain;
there are no generated types, queries, columns, or configuration keys for
removed runtime features.

### Step 8: Remove dead files and update product documentation

Delete only files proven unreferenced by import/route/query searches. Include
old Yjs/agent tests, scratch programs, temporary binaries, stale generated
artifacts, obsolete plans/specs that describe removed product behavior, and
dead comments/imports. Keep an archive index for historical decisions if the
team needs traceability, but mark it non-runtime. Update `README.md`,
`CONTEXT.md`, `AGENTS.md` project overview, `task.md`, and active walkthroughs
to describe the reduced product and the new persistence model.

Verification:

```text
flutter analyze
flutter test
go test ./...
git diff --check
git status --short
```

Expected result: all required verification commands pass, no untracked build
output or temporary binaries are included, and the diff contains only the
approved cleanup and migrations.

## Scope boundaries

Do not change authentication semantics, user preference storage, retained note
content, attachment URLs/files, task recurrence meaning, or MCP public
contracts without a separate product decision. Do not reset the dirty working
tree. Do not delete production data or old migrations because a table name
looks obsolete; prove its ownership and follow the data decision gate.

## Stop conditions

- No approved replacement exists for Yjs persistence/sync.
- Existing notes cannot be opened or migrated without a destructive guess.
- A retained feature still requires an allegedly discarded package.
- MCP requires agent/LLM/memory behavior that the scope decision did not retain.
- A database drop would delete user data without an approved export/retention
  policy.
- A verification command fails twice or the dirty working-tree changes conflict
  with the planned replacement.

## Done criteria

- [x] Retention matrix and data disposition are approved.
- [x] Retained note/task/recurrence/attachment/preferences/MCP contract tests
      pass on Flutter and Go.
- [x] No active runtime dependency on Yjs, agent, Telegram, routines, memories,
      soul, or embeddings remains.
- [x] No discarded routes, providers, queries, generated types, columns,
      configuration keys, tests, or imports remain.
- [x] Production database migration strategy is documented and applied only by
      a forward migration.
- [x] `flutter analyze`, `flutter test`, `go test ./...`, `go vet ./...`, and
      `git diff --check` pass with final output captured.

## Maintenance notes

Future note features must use the approved single mutation/persistence path.
MCP must remain a thin authenticated adapter over retained services. Any new
metadata field must update the note/task domain model, local projection, server
projection, API contract, and tests together; do not recreate a second sync
source of truth.
