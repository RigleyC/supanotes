# Removing Notes Title Field Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the redundant `title` column from local SQLite and remote Postgres database schemas, dynamically computing the note title from its markdown content, and styling the first line as H1 in the editor.

**Architecture:** We will drop the `title` column from Drift (SQLite) and PostgreSQL schemas, remove the `title` field from all sync DTOs/handlers, dynamically calculate `title` in Dart (`NoteModel`) and in Go (using SQL `regexp_replace` for search and a Go helper for the agent prompt builder), and introduce an editor reaction to format/keep the first line as H1.

**Tech Stack:** Dart, Flutter, Riverpod, Drift, Go, pgx, SQLC, SuperEditor

---

### Task 1: Remove Title Column from Drift Schema and Sincronização

**Files:**
- Modify: `lib/core/database/tables/notes.dart:1-31`
- Modify: `lib/core/database/database.dart:39-78`
- Modify: `lib/core/sync/sync_mapper.dart:30-135`

- [ ] **Step 1: Modify Drift table definition to remove the title column**
  Open [notes.dart](file:///d:/projects/supanotes/lib/core/database/tables/notes.dart) and delete the line defining `title`:
  ```dart
  TextColumn get title => text().nullable()();
  ```

- [ ] **Step 2: Bump Drift schema version and update migration strategy**
  Open [database.dart](file:///d:/projects/supanotes/lib/core/database/database.dart), increment `schemaVersion` to `8`, and handle migration in `onUpgrade`:
  ```dart
  @override
  int get schemaVersion => 8;
  
  // Inside onUpgrade:
  if (from < 8) {
    // Note: Drift will drop column mapping automatically. Since we are using NativeDatabase,
    // SQLite itself doesn't easily support dropping columns in old versions, but Drift manages
    // it by ignoring the column from insertions/updates.
  }
  ```

- [ ] **Step 3: Regenerate Drift database code**
  Run: `dart run build_runner build --delete-conflicting-outputs`
  Expected: Command finishes successfully and regenerates `database.g.dart`.

- [ ] **Step 4: Update SyncMapper to remove note title mapping**
  Open [sync_mapper.dart](file:///d:/projects/supanotes/lib/core/sync/sync_mapper.dart). Remove `'title': n.title,` from `noteToJson` and `title: json['title'] as String?,` from `noteFromJson`.

- [ ] **Step 5: Verify Flutter code compiles**
  Run: `flutter analyze`
  Expected: Checks if there are any compiling errors in Flutter models and sync code.

- [ ] **Step 6: Commit changes**
  ```bash
  git add lib/core/database/tables/notes.dart lib/core/database/database.dart lib/core/sync/sync_mapper.dart
  git commit -m "chore(notes): remove title column from local database schema and sync mapper"
  ```

---

### Task 2: Remove Title Column from Remote PostgreSQL Database & SQLC

**Files:**
- Create [NEW]: `backend/db/migrations/000008_remove_note_title.up.sql`
- Create [NEW]: `backend/db/migrations/000008_remove_note_title.down.sql`
- Modify: `backend/db/queries/notes.sql`
- Modify: `backend/db/queries/sync.sql`
- Modify: `backend/db/queries/search.sql`
- Modify: `backend/db/queries/ai.sql`

- [ ] **Step 1: Create migration UP file**
  Create `backend/db/migrations/000008_remove_note_title.up.sql`:
  ```sql
  -- Remove the title column from notes
  ALTER TABLE notes DROP COLUMN IF EXISTS title;
  
  -- Update full-text search trigger to only index content (the first line will naturally contain the title text)
  DROP TRIGGER IF EXISTS tsvectorupdate ON notes;
  CREATE TRIGGER tsvectorupdate BEFORE INSERT OR UPDATE OF content ON notes
  FOR EACH ROW EXECUTE FUNCTION notes_search_trigger();
  ```

- [ ] **Step 2: Create migration DOWN file**
  Create `backend/db/migrations/000008_remove_note_title.down.sql`:
  ```sql
  ALTER TABLE notes ADD COLUMN title TEXT;
  -- Trigger rebuild is not strictly necessary for down migration since trigger handles title coalesce.
  ```

- [ ] **Step 3: Modify notes queries to remove title column**
  Open [notes.sql](file:///d:/projects/supanotes/backend/db/queries/notes.sql):
  - In `CreateNote` query, remove `title` column and parameter.
  - In `UpdateNote` query, remove `title` update assignment from `SET`.

- [ ] **Step 4: Modify sync queries to remove title column**
  Open [sync.sql](file:///d:/projects/supanotes/backend/db/queries/sync.sql):
  - In `UpsertNote` query, remove `title` column, value slot, and update target.

- [ ] **Step 5: Modify search and AI queries to calculate title dynamically**
  Open [search.sql](file:///d:/projects/supanotes/backend/db/queries/search.sql) and [ai.sql](file:///d:/projects/supanotes/backend/db/queries/ai.sql):
  - Replace `n.title` with `regexp_replace(split_part(n.content, E'\n', 1), '^#+\s+', '') AS title` in `SearchNotesFTS`, `SearchNotesSemantic`, `SearchNotesHybrid`, and `SearchNotesByEmbedding`.

- [ ] **Step 6: Regenerate SQLC code**
  Navigate to `backend` directory and run: `sqlc generate`
  Expected: SQLC regenerates types successfully.

- [ ] **Step 7: Commit changes**
  ```bash
  git add backend/db/migrations/ backend/db/queries/
  git commit -m "db(notes): drop title column from database and dynamically generate it in queries"
  ```

---

### Task 3: Adjust Go Backend Sync and Agent Code

**Files:**
- Modify: `backend/internal/notes/service.go`
- Modify: `backend/internal/notes/service_test.go`
- Modify: `backend/internal/notes/handler.go`
- Modify: `backend/internal/auth/service.go`
- Modify: `backend/internal/sync/service.go`
- Modify: `backend/internal/agent/context.go`
- Modify: `backend/internal/agent/tools/notes_tools.go`

- [ ] **Step 1: Update Go Notes service**
  Open [service.go](file:///d:/projects/supanotes/backend/internal/notes/service.go):
  - Remove `title *string` parameter from `CreateNote` and `UpdateNote` signatures.
  - Simplify `isEmptyRegularNote(content string) bool`.
  - In `ApplyOrganization`, for new notes creation: prepend `op.title` as a H1 header to the content if it's not empty, e.g. `fmt.Sprintf("# %s\n\n%s", *reqItem.DestinationTitle, trimmed)`. Update `batchCreateNoteSQL` query format.
  - Update `UpdateNote` logic to exclude setting `Title` parameter.

- [ ] **Step 2: Update Go Notes handler**
  Open [handler.go](file:///d:/projects/supanotes/backend/internal/notes/handler.go):
  - Update the service call invocations of `CreateNote` and `UpdateNote` to not pass a `Title` field.

- [ ] **Step 3: Update Go Auth service**
  Open [service.go](file:///d:/projects/supanotes/backend/internal/auth/service.go):
  - In `seedUserDefaults`, prepend the title header to the content (`# Rascunho\n\nBem-vindo...`) and remove `Title` from `CreateNoteParams`.

- [ ] **Step 4: Update Sync service**
  Open [service.go](file:///d:/projects/supanotes/backend/internal/sync/service.go):
  - In `isEmptyIncomingRegularNote`, check only content emptiness.
  - Remove `Title` param passing from `r.UpsertNote`.

- [ ] **Step 5: Write extractTitle helper in Agent context and fix compilation errors**
  Open [context.go](file:///d:/projects/supanotes/backend/internal/agent/context.go):
  - Implement `extractTitle(content string) string` helper function.
  - Replace `n.Title.String` references with `extractTitle(n.Content)` inside `writeNotesWithID` and `writeNotesWithContent`.

- [ ] **Step 6: Update Notes Agent Tools**
  Open [notes_tools.go](file:///d:/projects/supanotes/backend/internal/agent/tools/notes_tools.go):
  - Modify `AddNoteTool` schema and `Execute` method to remove `title` property. Prepend any title to the content if requested or simply receive content.
  - Fix any compile errors where `n.Title.String` is used.

- [ ] **Step 7: Fix Notes Go service unit tests**
  Open [service_test.go](file:///d:/projects/supanotes/backend/internal/notes/service_test.go):
  - Delete `TestService_UpdateNote_DoesNotSetEmbeddingPendingOnTitleOnly`.
  - Fix `TestCreateNoteRejectsEmptyRegularNote` parameters.

- [ ] **Step 8: Run Go tests to verify backend compilation and logic**
  Navigate to `backend` and run: `go test ./...`
  Expected: All Go unit tests pass.

- [ ] **Step 9: Commit changes**
  ```bash
  git add backend/internal/
  git commit -m "feat(notes): remove note title field references from Go backend service, sync, and agent"
  ```

---

### Task 4: Update Note Model and Repository in Flutter

**Files:**
- Modify: `lib/features/notes/domain/note_model.dart`
- Modify: `lib/features/notes/data/notes_repository.dart`
- Modify: `lib/features/notes/presentation/controllers/note_editor_controller.dart`
- Create [NEW]: `test/features/notes/domain/note_model_test.dart`

- [ ] **Step 1: Implement dynamic title extraction in NoteModel**
  Open [note_model.dart](file:///d:/projects/supanotes/lib/features/notes/domain/note_model.dart):
  - Replace `final String? title;` in the constructor or dynamically calculate it inside `fromData` factory method.
  - Implement helper `_extractTitleFromMarkdown(String content)` to parse the first non-empty line and strip any leading markdown header symbols.

- [ ] **Step 2: Write test to verify dynamic title extraction**
  Create `test/features/notes/domain/note_model_test.dart`:
  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:supanotes/features/notes/domain/note_model.dart';
  import 'package:supanotes/core/database/database.dart';
  
  void main() {
    test('extracts title correctly from H1 markdown', () {
      final noteData = NoteData(
        id: '1',
        userId: '1',
        content: '# Minha Nota\nEste é o corpo',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isInbox: false,
        favorite: false,
        archived: false,
      );
      final model = NoteModel.fromData(noteData);
      expect(model.title, 'Minha Nota');
    });
  }
  ```

- [ ] **Step 3: Run the test to verify it passes**
  Run: `flutter test test/features/notes/domain/note_model_test.dart`
  Expected: Test passes successfully.

- [ ] **Step 4: Update NotesRepository to remove title field**
  Open [notes_repository.dart](file:///d:/projects/supanotes/lib/features/notes/data/notes_repository.dart):
  - Remove `title` parameter from `saveNoteSnapshot` and update calls.
  - Simplify note insertions in local repository without passing the `title` column value.

- [ ] **Step 5: Update NoteEditorController save callback**
  Open [note_editor_controller.dart](file:///d:/projects/supanotes/lib/features/notes/presentation/controllers/note_editor_controller.dart):
  - Remove `title` parameter from `SnapshotSave` typedef and adjust saves to omit title.

- [ ] **Step 6: Commit changes**
  ```bash
  git add lib/features/notes/ test/features/notes/
  git commit -m "feat(notes): compute note title dynamically from content on frontend"
  ```

---

### Task 5: Implement H1 Formatting and Preservation in SuperEditor

**Files:**
- Modify: `lib/features/notes/domain/note_editor_commands.dart:170-248`
- Modify: `lib/features/notes/data/markdown_serializer.dart:1-36`
- Modify: `lib/features/notes/presentation/controllers/note_editor_controller.dart:70-98`

- [ ] **Step 1: Write KeepFirstLineAsTitleReaction**
  Open [note_editor_commands.dart](file:///d:/projects/supanotes/lib/features/notes/domain/note_editor_commands.dart) and add `KeepFirstLineAsTitleReaction` class at the bottom:
  ```dart
  class KeepFirstLineAsTitleReaction extends EditReaction {
    const KeepFirstLineAsTitleReaction();
  
    @override
    void react(
      EditContext editorContext,
      RequestDispatcher requestDispatcher,
      List<EditEvent> changeList,
    ) {
      final document = editorContext.document;
      if (document.isEmpty) return;
  
      final firstNode = document.first;
      if (firstNode is ParagraphNode) {
        final blockType = firstNode.getMetadataValue('blockType');
        if (blockType != header1Attribution) {
          requestDispatcher.execute([
            ChangeParagraphBlockTypeRequest(
              nodeId: firstNode.id,
              blockType: header1Attribution,
            ),
          ]);
        }
      }
    }
  }
  ```

- [ ] **Step 2: Register reaction in NoteEditorController**
  Open [note_editor_controller.dart](file:///d:/projects/supanotes/lib/features/notes/presentation/controllers/note_editor_controller.dart):
  - Add the `KeepFirstLineAsTitleReaction` to the editor's `reactionPipeline`.

- [ ] **Step 3: Force the first parsed node to be H1 in markdown deserializer**
  Open [markdown_serializer.dart](file:///d:/projects/supanotes/lib/features/notes/data/markdown_serializer.dart):
  - In `parseNoteToMarkdown`, check if the first node of the parsed document is a `ParagraphNode`. If it is, put `blockType: header1Attribution` in its metadata.

- [ ] **Step 4: Commit changes**
  ```bash
  git add lib/features/notes/
  git commit -m "feat(notes): enforce H1 style on first editor line and preserve it on deletion"
  ```
