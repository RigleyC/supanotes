# Plan 028: Remove Persisted Note Titles

> **Executor instructions**: Follow this plan step by step. Run every verification command before moving on. If a STOP condition occurs, stop and report; do not improvise.
>
> **Drift check (run first)**:
> `git diff --stat fd87433..HEAD -- lib/core/database lib/core/sync lib/features/notes test/core/sync test/features/notes backend/db backend/internal/notes backend/internal/sync backend/internal/search backend/internal/agent backend/internal/auth backend/internal/db/sqlcgen`
>
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against live code before proceeding. If the shape differs materially, stop and ask for a refreshed plan.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: none
- **Category**: migration
- **Planned at**: commit `fd87433`, 2026-06-17

## Why this matters

SupaNotes is moving to the Apple Notes title model: a note has no separately edited or persisted title. The first line of the note content is the visual and logical title, and the full note content is the source of truth. Keeping `notes.title` after this decision creates a semantic split where UI, sync, search, and agent tools can disagree about what a note is called.

This is intentionally a breaking migration. The product has one active client, so backend and Flutter can be upgraded together instead of carrying a compatibility shim for old clients.

## Current state

Domain vocabulary from `.docs/CONTEXT.md`:

- A **Note** is the primary user-owned document whose content is stored as Markdown.
- A **New Note** is a real note created immediately by the user.
- An **Empty Note** has no meaningful title/body/tasks/attachments/tags and should not appear in regular lists.
- A **save** is local persistence; sync is network push/pull and remains separate.

Current frontend title persistence:

- `lib/core/database/tables/notes.dart:8` declares `TextColumn get title => text().nullable()();`.
- `lib/features/notes/domain/note_model.dart:32` exposes `final String? title;`.
- `lib/features/notes/data/notes_repository.dart:212-228` saves a snapshot with both `title` and `content`.
- `lib/features/notes/presentation/controllers/note_editor_controller.dart:116-126` extracts the first non-empty text node as `_extractTitle`.
- `lib/core/sync/sync_mapper.dart:35-44` sends `title` in note sync JSON.
- `lib/core/sync/sync_mapper.dart:109-120` expects `title` when reading note sync JSON.
- `lib/features/notes/presentation/widgets/note_card.dart:43-45` and `lib/features/notes/presentation/widgets/note_list_row.dart:24-26` display `note.title`.

Current backend title persistence:

- `backend/db/migrations/000002_notes.up.sql:17` creates `notes.title`.
- `backend/db/migrations/000002_notes.up.sql:81-88` weights `NEW.title` into `search_vector`.
- `backend/db/queries/notes.sql:16-18` inserts `title` on note create.
- `backend/db/queries/notes.sql:27` updates `title` on note update.
- `backend/db/queries/sync.sql:30-38` upserts `title` during sync.
- `backend/internal/notes/service.go:30-44` treats title plus content as the empty-note check.
- `backend/internal/notes/handler.go:24-36` accepts `title` in create/update requests.
- `backend/internal/notes/handler.go:45-55` returns `title` in note responses.
- `backend/internal/sync/service.go:136-142` treats incoming notes with empty title and empty content as empty.
- `backend/internal/agent/tools/notes_tools.go:24-35` requires `title` for `add_note`.
- `backend/internal/agent/context.go:281` and `backend/internal/agent/context.go:299` print `n.Title.String`.
- `backend/internal/auth/service.go:288-292` creates the inbox note with title `"Rascunho"`.

Generated artifacts:

- `lib/core/database/database.g.dart` is generated from Drift tables. Do not edit it manually; regenerate it.
- `backend/internal/db/sqlcgen/*` is generated from SQL queries and migrations. Do not edit generated SQLC files manually; regenerate them.

Repo conventions:

- Flutter state uses manual Riverpod providers only. Do not introduce Riverpod codegen.
- Keep UI strings in existing constants where a constant already exists.
- Backend handlers stay thin and delegate to services.
- Go module path is `github.com/RigleyC/supanotes`.
- Commit style in recent history is conventional commits, e.g. `fix(notes): handle inbox and editor regressions`.

## Commands you will need

| Purpose | Command | Expected |
|---------|---------|----------|
| Drift generation | `dart run build_runner build --delete-conflicting-outputs` | exit 0; `database.g.dart` updated |
| Focused Flutter sync tests | `flutter test test/core/sync/sync_service_test.dart` | all pass |
| Focused Flutter notes tests | `flutter test test/features/notes` | all pass |
| Flutter analyzer | `dart analyze lib/core/database lib/core/sync lib/features/notes test/core/sync test/features/notes` | no issues in touched slice |
| SQLC generation | `sqlc generate` from `backend/` | exit 0; `internal/db/sqlcgen` updated |
| Backend notes/sync tests | `go test ./internal/notes/... ./internal/sync/...` from `backend/` | pass |
| Backend search/agent tests | `go test ./internal/search/... ./internal/agent/... ./internal/agent/tools/...` from `backend/` | pass |

If `sqlc` is unavailable locally, stop and report. Do not hand-edit generated SQLC output.

## Scope

**In scope**:

- `.docs/CONTEXT.md`
- `lib/core/database/tables/notes.dart`
- `lib/core/database/database.dart`
- `lib/core/database/database.g.dart` generated
- `lib/core/database/daos/notes_dao.dart`
- `lib/core/sync/sync_mapper.dart`
- `lib/core/sync/sync_service.dart` if needed
- `lib/features/notes/**`
- `test/core/sync/sync_service_test.dart`
- `test/features/notes/**`
- `backend/db/migrations/000017_remove_note_title.*.sql`
- `backend/db/queries/notes.sql`
- `backend/db/queries/sync.sql`
- `backend/db/queries/search.sql`
- `backend/db/queries/ai.sql`
- `backend/internal/db/sqlcgen/**` generated
- `backend/internal/notes/**`
- `backend/internal/sync/**`
- `backend/internal/search/**`
- `backend/internal/agent/context.go`
- `backend/internal/agent/tools/notes_tools.go`
- `backend/internal/agent/tools/tools_test.go`
- `backend/internal/auth/service.go`
- directly affected backend tests/mocks that no longer compile after SQLC changes

**Out of scope**:

- Task titles. `tasks.title` remains a real field.
- `destination_title` in inbox organization plans unless it is being used to persist `notes.title`; it may still be an LLM-facing proposed first line.
- Agent chat stream plans 023-027.
- Sharing permissions.
- Full redesign of list/grid cards beyond title derivation.
- Compatibility with old sync clients. This plan is a breaking migration.

## Git workflow

- Branch: `migration/remove-note-title`
- Commit message suggestion: `refactor(notes): derive title from content`
- Do not push unless the operator asks.
- Stage generated files intentionally. Do not use `git add -A`; this checkout has had Windows-invalid or unrelated local artifacts before.

## Steps

### Step 1: Document the new note-title contract

Update `.docs/CONTEXT.md` so the **Note** definition states:

- A note has no separate user-authored title.
- The first non-empty line of `content` is the display title.
- Persisted `notes.title` is removed in this breaking migration.
- The first line is still part of `content`.

Also update the **Empty Note** ambiguity if present: an empty regular note is determined from content/tasks/attachments/tags, not `title`.

**Verify**:

```powershell
Select-String -Path .docs\CONTEXT.md -Pattern "first non-empty line|display title|notes.title"
```

Expected: matching lines describe the new contract.

### Step 2: Add frontend title/excerpt derivation tests first

Create `test/features/notes/domain/note_display_text_test.dart`.

Create a small pure helper file in implementation step 3, but write tests first for the target behavior:

- `deriveNoteTitle("Trip\nBuy tickets")` returns `"Trip"`.
- `deriveNoteTitle("\n\nTrip\nBuy tickets")` returns `"Trip"`.
- `deriveNoteTitle("# Trip\nBuy tickets")` returns `"Trip"` if the serializer stores headings with markdown markers.
- `deriveNoteTitle("- item\nbody")` strips lightweight markdown markers only enough for display and returns `"item"`.
- `deriveNoteTitle("")` returns `NoteStrings.fallbackTitle` or a helper-level fallback passed by caller. Prefer returning `null` from the helper and leaving fallback selection to widgets if that matches existing style better.
- `deriveNoteExcerpt("Trip\nBuy tickets\nBook hotel")` returns body text after the title line, not the title repeated.

Use a pure Dart test, not a widget test.

**Verify**:

```powershell
flutter test test/features/notes/domain/note_display_text_test.dart
```

Expected: FAIL because helper does not exist yet.

### Step 3: Add frontend display helpers and switch note UI

Add `lib/features/notes/domain/note_display_text.dart` with pure helpers:

```dart
String? deriveNoteTitle(String content) { ... }
String? deriveNoteExcerpt(String content, {int maxLength = AppConstants.noteExcerptMaxLength}) { ... }
String prependTitleIfNeeded({required String? legacyTitle, required String content}) { ... }
```

Rules:

- First non-empty content line becomes the display title.
- Excerpt starts after the title line.
- Strip simple markdown display markers for title only: leading `#`, list bullets (`-`, `*`), ordered list markers (`1.`), checkbox markers (`- [ ]`, `- [x]`).
- Do not mutate the stored content in display helpers.
- `prependTitleIfNeeded` is for local migration only: if `legacyTitle` is non-empty and content does not already start with the same trimmed text after markdown stripping, return `"$legacyTitle\n$content"` or `legacyTitle` when content is empty.

Then update:

- `NoteModel` to remove `title` and expose `displayTitle` / `displayExcerpt` getters derived from `content` and optional existing `excerpt` only if keeping `excerpt`.
- `NoteCard` and `NoteListRow` to display `note.displayTitle`.
- `NoteCard._resolveExcerpt` to use `note.displayExcerpt`.
- `NoteEditor` to remove the unused `title` constructor field.
- `NoteEditorScreen` to stop passing `note.title`.

Do not remove database columns yet in this step.

**Verify**:

```powershell
flutter test test/features/notes/domain/note_display_text_test.dart
dart analyze lib/features/notes test/features/notes/domain/note_display_text_test.dart
```

Expected: tests pass; analyzer may still report title references in database/sync files that are handled in later steps, but no errors in changed presentation/domain files except known future database API references.

### Step 4: Remove title from frontend repository save path

Update:

- `SnapshotSave` in `note_editor_controller.dart` to remove the `title` parameter.
- `NoteEditorController._runSnapshotSave`, `_flushAndSaveFinalState`, and `defaultSnapshotSave` to save only `noteId`, `markdown`, and tasks.
- `INotesRepository.upsertNote`, `updateNote`, and `saveNoteSnapshot` to remove the `title` parameter.
- `NotesRepository._isTextEmpty` to check `note.content.trim().isEmpty` plus task state, not `note.title`.
- Any tests/fakes implementing `saveNoteSnapshot`.

Remove `_extractTitle` from `NoteEditorController`.

**Verify**:

```powershell
flutter test test/features/notes/data/notes_repository_test.dart test/features/notes/presentation/note_editor_screen_test.dart test/features/notes/presentation/notes_list_screen_test.dart
```

Expected: all pass after updating test fakes and expectations.

### Step 5: Add local Drift migration and remove `title` column locally

Update `lib/core/database/tables/notes.dart` to remove:

```dart
TextColumn get title => text().nullable()();
```

Update `lib/core/database/database.dart`:

- Bump the Drift schema version by 1.
- Add a migration step that creates a replacement notes table or otherwise follows Drift's supported SQLite column-drop pattern.
- Before dropping `title`, preserve legacy local titles by folding them into `content` using the same rule as `prependTitleIfNeeded`.

The migration must preserve:

- `id`
- `userId`
- `contextId`
- `content`
- `excerpt`
- `isInbox`
- `favorite`
- `archived`
- `embeddingStatus`
- `createdAt`
- `updatedAt`
- `deletedAt`
- `isDirty`
- `hasRemoteCopy`
- `hideCompleted`
- sharing fields

Update `notes_dao.dart`:

- Remove writes to `title`.
- Update non-empty filters from `trim(title) <> '' OR trim(content) <> ''` to content-only.

Regenerate Drift:

```powershell
dart run build_runner build --delete-conflicting-outputs
```

**Verify**:

```powershell
rg -n "\btitle\b" lib/core/database/tables/notes.dart lib/core/database/daos/notes_dao.dart lib/core/database/database.g.dart
flutter test test/features/notes/data/notes_repository_test.dart test/core/sync/sync_service_test.dart
```

Expected:

- No note-table `title` column remains. Matches for task title or UI title words outside notes table are fine.
- Focused tests pass.

### Step 6: Remove note title from Flutter sync JSON

Update `lib/core/sync/sync_mapper.dart`:

- Remove `'title': n.title` from `noteToJson`.
- Remove `title: json['title'] as String?` from `noteFromJson`.
- Keep task title mapping unchanged.

Update `test/core/sync/sync_service_test.dart`:

- Remove expectations that note JSON has `title`.
- Add an expectation that task JSON still has `title`.
- Add a pull test where note JSON without `title` maps successfully.

**Verify**:

```powershell
flutter test test/core/sync/sync_service_test.dart
dart analyze lib/core/sync test/core/sync
```

Expected: pass with no analyzer issues.

### Step 7: Add backend migration to fold title into content and drop column

Create `backend/db/migrations/000017_remove_note_title.up.sql`.

Required behavior:

1. For existing rows where `title` is non-empty:
   - If `content` is empty, set `content = title`.
   - If the first non-empty content line already equals title after trimming simple markdown heading markers, leave content unchanged.
   - Otherwise prefix title as the first line: `title || E'\n' || content`.
2. Replace `generate_note_search_vector()` so it uses only `content`.
3. Rebuild `search_vector` for all notes.
4. Drop `title` from `notes`.

Keep the SQL simple. If robust markdown-aware equality is too awkward in SQL, use a conservative condition:

```sql
WHERE title IS NOT NULL
  AND btrim(title) <> ''
  AND (
    btrim(content) = ''
    OR btrim(split_part(content, E'\n', 1)) <> btrim(title)
  )
```

Create `backend/db/migrations/000017_remove_note_title.down.sql`:

- Add `title TEXT`.
- Backfill it from the first non-empty content line using a conservative expression.
- Restore the search-vector trigger shape expected by older code.

**Verify**:

```powershell
Get-Content backend\db\migrations\000017_remove_note_title.up.sql
Get-Content backend\db\migrations\000017_remove_note_title.down.sql
```

Expected: both files exist and contain no secret values.

### Step 8: Remove note title from backend SQL queries and regenerate SQLC

Update:

- `backend/db/queries/notes.sql`
  - `CreateNote` inserts no `title`.
  - `UpdateNote` does not update `title`.
- `backend/db/queries/sync.sql`
  - `UpsertNote` inserts/updates no `title`.
  - `GetSyncNotes` still returns sharing metadata but no title column.
- `backend/db/queries/search.sql`
  - Select no `n.title`.
  - If API/service still needs display title, return content and let Go derive it.
- `backend/db/queries/ai.sql`
  - Remove selected `n.title` from semantic search rows and use content-derived display in Go.

Run:

```powershell
cd backend
sqlc generate
```

**Verify**:

```powershell
rg -n "\bTitle\b|\.title\b|title," backend/internal/db/sqlcgen
```

Expected: matches remain for tasks and notification/routine titles only. No generated note row or note params should expose `Title`.

### Step 9: Remove note title from backend services, handlers, and sync

Update:

- `backend/internal/notes/service.go`
  - `isEmptyRegularNote` accepts only `content`.
  - `CreateNote` signature removes `title *string`.
  - `UpdateNote` signature removes `title *string`.
  - `ApplyOrganization` creates new notes whose `content` starts with the proposed destination title when present, instead of saving destination title separately.
  - `batchCreateNoteSQL` inserts no `title`.
- `backend/internal/notes/handler.go`
  - Remove `Title` from create/update request structs.
  - Remove `Title` from `NoteResponse`.
  - Add `DisplayTitle string 'json:"display_title"'` if frontend/API consumers need a returned display value. Prefer this over returning `title`.
  - Derive display title from `content`.
- `backend/internal/sync/service.go`
  - `isEmptyIncomingRegularNote` checks content only.
  - `UpsertNoteParams` no longer receives title.
- `backend/internal/auth/service.go`
  - Create inbox with content `"Rascunho"` only if a visible inbox heading is desired, or empty content if inbox should not have a title line. Use the product decision: inbox is a special note, so empty content is acceptable if service allows inbox creation outside `CreateNote`.
- Backend tests/mocks that call `CreateNote` or `UpdateNote`.

Create a small backend helper, for example `backend/internal/notes/display.go`:

```go
func DisplayTitle(content string) string { ... }
func ContentWithTitle(title, content string) string { ... }
```

Use it in handlers, agent context, and tools instead of duplicating string logic.

**Verify**:

```powershell
cd backend
go test ./internal/notes/... ./internal/sync/...
```

Expected: pass.

### Step 10: Update backend search and agent note tools

Update:

- `backend/internal/search/service.go`
  - If `SearchResult.Title` remains public, fill it from `notes.DisplayTitle(r.Content)` or rename to `DisplayTitle` only if all callers are updated.
- `backend/internal/search/service_test.go`
  - Use content with first line and assert derived title.
- `backend/internal/agent/context.go`
  - Replace `n.Title.String` with derived display title.
- `backend/internal/agent/tools/notes_tools.go`
  - `add_note` schema requires only `content`.
  - If the LLM wants a title, instruct it to put that title as the first line of `content`.
  - `update_note` schema removes `title`; it updates content only.
  - Tool outputs use derived display title.
- `backend/internal/agent/tools/tools_test.go`
  - Remove note title fixture expectations and assert first-line display.

Task tools still use `title`; do not touch them.

**Verify**:

```powershell
cd backend
go test ./internal/search/... ./internal/agent/... ./internal/agent/tools/...
```

Expected: pass.

### Step 11: Make the editor first line visibly title-sized

Update `lib/features/notes/presentation/note_stylesheet.dart` and/or component styles so the first text block in a regular note renders with title styling.

Constraints:

- Do not add a separate title field.
- The first line remains editable content.
- New empty notes should start with a paragraph that renders as title-sized until the user presses Enter or adds body content.
- Existing headings should not become double-large. If the first node is already a heading, use the heading style as the title.
- Inbox can either share the same first-line title styling or be explicitly exempted. Choose the simpler consistent rule unless product code already treats inbox differently.

Add or update widget tests around `NoteEditor` if existing helpers can inspect text style. If style inspection is brittle, add a narrower unit test around the stylesheet rule or component builder predicate.

**Verify**:

```powershell
flutter test test/features/notes/presentation
```

Expected: pass.

### Step 12: Final repo-wide focused verification

Run:

```powershell
flutter test test/core/sync/sync_service_test.dart test/features/notes
dart analyze lib/core/database lib/core/sync lib/features/notes test/core/sync test/features/notes
cd backend
go test ./internal/notes/... ./internal/sync/... ./internal/search/... ./internal/agent/... ./internal/agent/tools/...
```

Then run repository-wide checks if time allows:

```powershell
flutter test
cd backend
go test ./...
```

Expected:

- Focused checks pass.
- If full checks fail due to pre-existing unrelated issues, record exact failures in the final handoff and keep focused checks clean.

## Test plan

Add or update tests for:

- `test/features/notes/domain/note_display_text_test.dart`
  - first-line title derivation
  - markdown marker stripping
  - excerpt excludes title line
  - legacy title fold-in helper
- `test/features/notes/data/notes_repository_test.dart`
  - snapshot saves content/tasks without title
  - empty-note deletion uses content/tasks
- `test/core/sync/sync_service_test.dart`
  - note sync payload omits title
  - note pull payload without title maps successfully
  - task title sync still works
- `backend/internal/notes/service_test.go`
  - create/update signatures use content-only title semantics
  - empty regular note is rejected by content only
- `backend/internal/sync/service_test.go`
  - incoming empty regular note is rejected without checking title
  - upsert note receives no title
- `backend/internal/search/service_test.go`
  - search results derive display title from content
- `backend/internal/agent/context_test.go` or `backend/internal/agent/tools/tools_test.go`
  - agent-visible note labels derive from content first line

## Done criteria

- [ ] `notes.title` no longer exists in Flutter Drift table or generated `NoteData`.
- [ ] Backend migration `000017_remove_note_title` folds old titles into content before dropping the column.
- [ ] Backend SQLC-generated note models and note params have no `Title` field.
- [ ] Sync note payloads omit `title` in both directions.
- [ ] Task `title` behavior is unchanged.
- [ ] API note responses do not expose persisted `title`; if a label is returned, it is `display_title` derived from content.
- [ ] Agent note tools no longer ask for or update a separate note title.
- [ ] Notes list/grid/editor display the first content line as the title.
- [ ] Focused Flutter and backend tests pass.
- [ ] `plans/README.md` row for 028 is updated by the executor if they own index updates.

## STOP conditions

Stop and report if:

- SQLC or Drift generation cannot run in the environment.
- The database migration would need to preserve old clients that still send `title`; this plan assumes a breaking change.
- Any required change touches task titles or changes task API contracts.
- You discover a production deployment constraint that prevents backend and app update from shipping together.
- The content migration cannot preserve existing non-empty note titles without data loss.
- Implementing first-line title styling requires replacing the editor architecture instead of a focused stylesheet/component change.

## Maintenance notes

After this lands, reviewers should reject new note APIs or UI code that introduces a separate note title. Use product language consistently: "display title" is derived from the first non-empty content line; "title" without qualification should refer only to task titles or generic UI labels.

If multi-client sync compatibility becomes necessary later, add a versioned sync contract instead of reintroducing `notes.title`.
