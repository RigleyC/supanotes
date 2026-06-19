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
- **Planned at**: commit `fd87433`, 2026-06-19

## Why this matters

SupaNotes is moving to the Apple Notes title model: a note has no separately edited or persisted title. The first line of the note content is the visual and logical title, and the full note content is the source of truth. Keeping `notes.title` after this decision creates a semantic split where UI, sync, search, and agent tools can disagree about what a note is called.

This is intentionally a breaking migration. The product has one active client, so backend and Flutter can be upgraded together instead of carrying a compatibility shim for old clients.

---

## Steps

### Step 1: Document the new note-title contract

Update `docs/CONTEXT.md` so the **Note** definition states:
- A note has no separate user-authored title.
- The first non-empty line of `content` is the display title.
- Persisted `notes.title` is removed in this breaking migration.
- The first line is still part of `content`.

Also update the **Empty Note** definition: an empty regular note is determined from content/tasks/attachments/tags, not `title`.

**Verify**:
Check if the updated definitions exist:
```powershell
Select-String -Path docs\CONTEXT.md -Pattern "first non-empty line|display title|notes.title"
```
Expected: matching lines describe the new contract.

---

### Step 2: Add frontend title/excerpt derivation tests

Create `test/features/notes/domain/note_display_text_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/domain/note_display_text.dart';
import 'package:supanotes/features/notes/domain/note_strings.dart';

void main() {
  group('deriveNoteTitle', () {
    test('extracts title from H1 markdown', () {
      expect(deriveNoteTitle("# Trip\nBuy tickets"), equals("Trip"));
    });

    test('extracts title ignoring leading empty lines', () {
      expect(deriveNoteTitle("\n\nTrip\nBuy tickets"), equals("Trip"));
    });

    test('strips list bullets and checkboxes', () {
      expect(deriveNoteTitle("- item\nbody"), equals("item"));
      expect(deriveNoteTitle("- [ ] task\nbody"), equals("task"));
      expect(deriveNoteTitle("1. item\nbody"), equals("item"));
    });

    test('returns fallback for empty content', () {
      expect(deriveNoteTitle(""), equals(NoteStrings.fallbackTitle));
    });
  });

  group('deriveNoteExcerpt', () {
    test('extracts text after title line', () {
      expect(deriveNoteExcerpt("Trip\nBuy tickets\nBook hotel"), equals("Buy tickets Book hotel"));
    });

    test('returns null if no content after title', () {
      expect(deriveNoteExcerpt("Trip"), isNull);
    });
  });

  group('prependTitleIfNeeded', () {
    test('prepends legacy title if not already present in content', () {
      expect(
        prependTitleIfNeeded(legacyTitle: 'Trip', content: 'Buy tickets'),
        equals('# Trip\n\nBuy tickets'),
      );
    });

    test('does not prepend if title matches first content line', () {
      expect(
        prependTitleIfNeeded(legacyTitle: 'Trip', content: '# Trip\n\nBuy tickets'),
        equals('# Trip\n\nBuy tickets'),
      );
    });
  });
}
```

**Verify**:
```powershell
flutter test test/features/notes/domain/note_display_text_test.dart
```
Expected: FAIL because `note_display_text.dart` does not exist yet.

---

### Step 3: Implement frontend display helpers and switch note UI

Create `lib/features/notes/domain/note_display_text.dart`:

```dart
import 'package:supanotes/core/constants/app_constants.dart';
import 'package:supanotes/features/notes/domain/note_strings.dart';

String deriveNoteTitle(String content) {
  if (content.trim().isEmpty) return NoteStrings.fallbackTitle;
  final lines = content.split('\n');
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) {
      // Strip H1 prefix
      var clean = trimmed.replaceFirst(RegExp(r'^#+\s+'), '');
      // Strip checkboxes
      clean = clean.replaceFirst(RegExp(r'^[-*]\s+\[[ xX]\]\s+'), '');
      // Strip bullet indicators
      clean = clean.replaceFirst(RegExp(r'^[-*]\s+'), '');
      // Strip ordered list numbers
      clean = clean.replaceFirst(RegExp(r'^\d+\.\s+'), '');
      return clean.trim().isNotEmpty ? clean.trim() : NoteStrings.fallbackTitle;
    }
  }
  return NoteStrings.fallbackTitle;
}

String? deriveNoteExcerpt(String content, {int maxLength = AppConstants.noteExcerptMaxLength}) {
  if (content.isEmpty) return null;
  final lines = content.split('\n');
  int firstNonEmptyIdx = -1;
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].trim().isNotEmpty) {
      firstNonEmptyIdx = i;
      break;
    }
  }
  if (firstNonEmptyIdx == -1) return null;
  final restOfLines = lines.skip(firstNonEmptyIdx + 1).join('\n');
  final flat = restOfLines.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) return null;
  if (flat.length <= maxLength) return flat;
  return '${flat.substring(0, maxLength)}…';
}

String prependTitleIfNeeded({required String? legacyTitle, required String content}) {
  if (legacyTitle == null || legacyTitle.trim().isEmpty) return content;
  final cleanTitle = legacyTitle.trim();
  final currentTitle = deriveNoteTitle(content);
  if (currentTitle.toLowerCase() == cleanTitle.toLowerCase()) {
    return content;
  }
  final prefix = '# $cleanTitle';
  if (content.trim().isEmpty) return prefix;
  return '$prefix\n\n$content';
}
```

Update `NoteModel` in `lib/features/notes/domain/note_model.dart`:
- Replace the `final String? title;` field declaration with a getter:
  ```dart
  String get title => deriveNoteTitle(content);
  ```
- Make sure to update the constructor and copyWith to remove references to `title`.
- Also update `excerpt` calculation:
  ```dart
  String? get excerpt => deriveNoteExcerpt(content);
  ```

Update:
- `NoteCard` (`lib/features/notes/presentation/widgets/note_card.dart`): remove `note.title` references and use the getter `note.title`. Remove calls to `_resolveExcerpt()` and instead use `note.excerpt`.
- `NoteListRow` (`lib/features/notes/presentation/widgets/note_list_row.dart`): replace title resolution with `note.title`.
- `NoteEditor` (`lib/features/notes/presentation/widgets/note_editor.dart`): remove `this.title` from constructor and state initialization.
- `NoteEditorScreen` (`lib/features/notes/presentation/note_editor_screen.dart`): remove passing `title: note.title` to `NoteEditor`.

**Verify**:
```powershell
flutter test test/features/notes/domain/note_display_text_test.dart
```
Expected: PASS.

---

### Step 4: Remove title from frontend repository save path

Update:
- `SnapshotSave` in `lib/features/notes/presentation/controllers/note_editor_controller.dart`:
  ```dart
  typedef SnapshotSave = Future<void> Function(
    String noteId,
    String markdown,
    List<TaskEntry> tasks,
  );
  ```
- Remove `_extractTitle` from `NoteEditorController` completely.
- Update `INotesRepository` and `NotesRepository` in `lib/features/notes/data/notes_repository.dart`:
  - Update `saveNoteSnapshot` signature to remove the `title` parameter.
  - Simplify `NotesRepository.saveNoteSnapshot` to invoke `updateNote` without a `title` argument.
  - Update `upsertNote` and `updateNote` methods to remove `title` parameters.

**Verify**:
```powershell
flutter test test/features/notes/data/notes_repository_test.dart
```
Expected: PASS after resolving method signatures.

---

### Step 5: Add local Drift migration and remove title column

Open `lib/core/database/tables/notes.dart` and remove:
```dart
TextColumn get title => text().nullable()();
```

Open `lib/core/database/database.dart`:
- Increment `schemaVersion` to `8`.
- In `migration.onUpgrade`, handle upgrade from version 7 to 8 by dropping the `title` column:
  ```dart
  if (from < 8) {
    try {
      await m.database.execute('ALTER TABLE notes DROP COLUMN title');
    } catch (e) {
      // Ignore if database/SQLite version doesn't support DROP COLUMN
    }
  }
  ```

Regenerate Drift models:
```powershell
dart run build_runner build --delete-conflicting-outputs
```

Update `notes_dao.dart` in `lib/core/database/daos/notes_dao.dart` to remove references to `title`.

**Verify**:
```powershell
flutter test
```
Expected: All tests pass.

---

### Step 6: Remove note title from sync DTO mapping

Open `lib/core/sync/sync_mapper.dart`:
- Remove `'title': n.title,` from `noteToJson`.
- Remove `title: json['title'] as String?,` from `noteFromJson`.
- Keep task title mapping unchanged.

Open `test/core/sync/sync_service_test.dart`:
- Remove expectations that note JSON has `title`.

**Verify**:
```powershell
flutter test test/core/sync/sync_service_test.dart
```
Expected: PASS.

---

### Step 7: Add Go backend migration to drop the title column

Create `backend/db/migrations/000008_remove_note_title.up.sql`:
```sql
ALTER TABLE notes DROP COLUMN IF EXISTS title;

DROP TRIGGER IF EXISTS tsvectorupdate ON notes;
CREATE TRIGGER tsvectorupdate BEFORE INSERT OR UPDATE OF content ON notes
FOR EACH ROW EXECUTE FUNCTION notes_search_trigger();
```

Create `backend/db/migrations/000008_remove_note_title.down.sql`:
```sql
ALTER TABLE notes ADD COLUMN title TEXT;
```

---

### Step 8: Update Backend SQL queries and regenerate SQLC

Open `backend/db/queries/notes.sql`:
- Remove `title` from `CreateNote` insert query.
- Remove `title` update from `UpdateNote` query.

Open `backend/db/queries/sync.sql`:
- Remove `title` from `UpsertNote` insert/update query.

Open `backend/db/queries/search.sql`:
- Replace `n.title` with:
  ```sql
  regexp_replace(split_part(n.content, E'\n', 1), '^#+\s+', '') AS title
  ```
  in `SearchNotesFTS`, `SearchNotesSemantic`, and `SearchNotesHybrid`.

Open `backend/db/queries/ai.sql`:
- Replace `n.title` with `regexp_replace(split_part(n.content, E'\n', 1), '^#+\s+', '') AS title` in `SearchNotesByEmbedding`.

Regenerate SQLC:
```powershell
cd backend
sqlc generate
```

---

### Step 9: Adjust Go Backend service and handlers

Open `backend/internal/notes/service.go`:
- Remove `title *string` from `CreateNote` and `UpdateNote` parameters.
- Simplify `isEmptyRegularNote(content string) bool`.
- In `ApplyOrganization`, prepend the destination title as a H1 header:
  ```go
  content := trimmed
  if reqItem.DestinationTitle != nil && strings.TrimSpace(*reqItem.DestinationTitle) != "" {
      content = fmt.Sprintf("# %s\n\n%s", *reqItem.DestinationTitle, trimmed)
  }
  ```
  Update `batchCreateNoteSQL` to exclude `title` column.

Open `backend/internal/notes/handler.go`:
- Remove `Title` field from `CreateNoteRequest` and `UpdateNoteRequest`.
- Update controller service calls to skip title parameter.

Open `backend/internal/auth/service.go`:
- In `seedUserDefaults`, remove `Title` from `CreateNoteParams` and seed content with title:
  ```go
  content := "# Rascunho\n\nBem-vindo ao SupaNotes! Esta é sua nota de inbox..."
  ```

Open `backend/internal/sync/service.go`:
- In `isEmptyIncomingRegularNote`, remove `n.Title` checks.
- Remove `Title: n.Title` parameter mapping from `r.UpsertNote`.

Open `backend/internal/agent/context.go`:
- Add Go helper function at the bottom:
  ```go
  func extractTitle(content string) string {
      lines := strings.Split(content, "\n")
      for _, line := range lines {
          trimmed := strings.TrimSpace(line)
          if trimmed != "" {
              return strings.TrimPrefix(trimmed, "# ")
          }
      }
      return "Sem título"
  }
  ```
- Replace `n.Title.String` in `writeNotesWithID` and `writeNotesWithContent` with `extractTitle(n.Content)`.

Open `backend/internal/agent/tools/notes_tools.go`:
- Remove `title` from `AddNoteTool` parameters schema.
- Update `Execute` logic to not pass `title` to `CreateNote`.

**Verify**:
```powershell
cd backend
go test ./...
```
Expected: PASS.

---

### Step 10: Enforce and preserve H1 style in SuperEditor

Open `lib/features/notes/domain/note_editor_commands.dart`:
- Add `KeepFirstLineAsTitleReaction` at the bottom of the file:
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

Open `lib/features/notes/presentation/controllers/note_editor_controller.dart`:
- In `init`, register `KeepFirstLineAsTitleReaction`:
  ```dart
  editor!.reactionPipeline.add(const KeepFirstLineAsTitleReaction());
  ```

Open `lib/features/notes/data/markdown_serializer.dart`:
- In `parseNoteToMarkdown`, force the first node to have `blockType: header1Attribution` in metadata if it's a `ParagraphNode`:
  ```dart
  if (nodes.isNotEmpty && nodes.first is ParagraphNode) {
    (nodes.first as ParagraphNode).putMetadataValue('blockType', header1Attribution);
  }
  ```

**Verify**:
Run Flutter unit tests:
```powershell
flutter test
```
Expected: PASS.

---

## Done criteria

- [x] SQLite and Postgres db schemas do not have the note `title` column.
- [x] Note titles are derived dynamically from content in both Go and Flutter.
- [x] Note sync payloads omit the `title` parameter in both directions.
- [x] First line of the SuperEditor is automatically formatted as H1.
- [x] Emptying the first line in SuperEditor preserves H1 layout and formatting.
- [x] All Go and Flutter tests pass successfully.
