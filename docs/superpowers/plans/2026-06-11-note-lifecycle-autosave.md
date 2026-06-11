# New Note Lifecycle And Autosave Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make new-note creation local-first and explicit, hide empty notes from regular lists/sync, and replace field-level autosave with one debounced note snapshot save.

**Architecture:** Flutter creates a real local `Note` before opening the editor, but marks it as not yet having a remote copy. Local repositories decide whether a note is empty and whether deletion is a hard local delete or a tombstone; sync only pushes notes that are non-empty or already remote/tombstoned. The backend keeps a defensive guard so empty non-inbox notes cannot be created through sync/API even if a buggy client sends them.

**Tech Stack:** Flutter, Riverpod 3 manual providers, Drift local database, Super Editor, Go, sqlc, Echo, PostgreSQL.

---

## Assumptions And Success Criteria

**Assumptions:**
- A regular note can exist locally before it has content.
- An empty note has no meaningful title, body content, tasks, attachments, or tags.
- Attachments are a domain concept but not implemented in this code path yet; this plan wires title/content/tasks/tags.
- Sync remains asynchronous through the existing `SyncService` cadence: connection restored, manual sync, and 30-second timer.
- A note received from pull or successfully pushed has a remote copy.

**Success criteria:**
- Tapping the FAB creates a local note row immediately and opens that note.
- Empty local-only notes are not shown in regular note lists and are not pushed to `/sync/push`.
- Leaving an empty local-only note hard-deletes it locally.
- Deleting an already-remote note uses the existing tombstone path.
- Autosave uses one debounced snapshot operation for title, content, and tasks.
- Backend create/sync paths reject or ignore empty non-inbox note creation.

## File Map

- Create: `docs/adr/0004-local-first-new-note-lifecycle.md`
  Records the architecture decision because future readers will question local creation plus delayed remote sync.
- Modify: `.docs/CONTEXT.md`
  Already contains glossary updates for `New Note`, `Empty Note`, and autosave. Only touch if implementation reveals a domain correction.
- Modify: `lib/core/database/tables/notes.dart`
  Add local-only `hasRemoteCopy` boolean.
- Modify: `lib/core/database/database.dart`
  Bump schema version and add migration for `has_remote_copy`.
- Regenerate: `lib/core/database/database.g.dart`
  Drift generated code.
- Modify: `lib/core/database/daos/notes_dao.dart`
  Add visible-list filtering, sync eligibility, remote-copy marking, and hard delete.
- Modify: `lib/features/notes/data/local/notes_local_repository.dart`
  Add explicit note creation by id, hard delete, remote-copy helpers.
- Modify: `lib/features/notes/data/notes_repository.dart`
  Add snapshot save, empty-note deletion policy, and create-local-note API.
- Modify: `lib/features/notes/presentation/notes_list_screen.dart`
  Create local note before navigation.
- Modify: `lib/features/notes/presentation/controllers/note_editor_controller.dart`
  Replace content/title saves with one snapshot save throttle.
- Modify: `lib/features/notes/presentation/note_editor_screen.dart`
  Treat missing note as an error for regular editor routes instead of lazy creation.
- Modify: `lib/features/notes/presentation/inbox_screen.dart`
  Keep inbox using snapshot save with delete disabled.
- Modify: `lib/core/sync/sync_service.dart`
  Mark pushed notes as remote after successful push.
- Modify: `backend/internal/notes/service.go`
  Reject empty regular notes created through REST.
- Modify: `backend/internal/sync/service.go`
  Defensively skip or reject empty non-inbox note creation from sync payloads.
- Modify: backend tests in `backend/internal/notes/service_test.go` and `backend/internal/sync/service_test.go`.
- Create: focused Flutter tests under `test/features/notes/data/notes_repository_test.dart` and `test/core/sync/sync_service_test.dart`.

---

## Task 1: Add ADR For New Note Lifecycle

**Files:**
- Create: `docs/adr/0004-local-first-new-note-lifecycle.md`

- [ ] **Step 1: Create the ADR**

Add this file:

```markdown
# 0004: Local-First New Note Lifecycle

## Status

Accepted

## Context

The editor used to open a route with a generated note id and create the database row lazily from the first title or content autosave. That made the editor operate on a phantom id, split title/content persistence into competing paths, and allowed empty notes to be pushed before `flushBeforePop` could clean them up.

The product glossary now treats a New Note as a real Note started by the User, not a separate draft entity. An Empty Note has no meaningful title, body content, tasks, attachments, or tags, and is not shown in regular note lists.

## Decision

When the user starts a new regular note, the Flutter app creates a local Note row immediately and opens the editor for that row. New local notes start without a remote copy. Empty local-only notes are hidden from regular lists, excluded from sync push, and hard-deleted locally when the user leaves the editor empty.

Autosave saves the current Note snapshot locally: title, body content, and extracted tasks. Sync remains asynchronous and pushes only eligible local changes through the existing sync loop.

Notes that already have a remote copy keep using tombstones for deletion.

## Consequences

- The editor always edits a real local Note.
- Tags and tasks can safely attach to a newly created note before the first body edit.
- The backend is protected from empty regular notes.
- The local database needs a local-only marker for whether a note has a remote copy.
- Deletion must choose hard local delete for empty local-only notes and tombstone for remote notes.
```

- [ ] **Step 2: Verify docs path**

Run:

```powershell
Test-Path docs\adr\0004-local-first-new-note-lifecycle.md
```

Expected: `True`.

- [ ] **Step 3: Commit docs**

```bash
git add docs/adr/0004-local-first-new-note-lifecycle.md .docs/CONTEXT.md
git commit -m "docs(notes): record local-first note lifecycle"
```

---

## Task 2: Add Local Remote-Copy Marker To Drift Notes

**Files:**
- Modify: `lib/core/database/tables/notes.dart`
- Modify: `lib/core/database/database.dart`
- Regenerate: `lib/core/database/database.g.dart`

- [ ] **Step 1: Add the Drift column**

In `lib/core/database/tables/notes.dart`, add the column after `isDirty`:

```dart
  BoolColumn get isDirty => boolean().withDefault(const Constant(true))();
  BoolColumn get hasRemoteCopy =>
      boolean().withDefault(const Constant(false))();
```

- [ ] **Step 2: Bump schema and migration**

In `lib/core/database/database.dart`, update the schema version and migration:

```dart
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(localNoteTags);
            await m.createTable(localTaskCompletions);
            await m.addColumn(tags, tags.updatedAt);
            await m.addColumn(tasks, tasks.completedAt);
          }
          if (from < 3) {
            await m.addColumn(notes, notes.hasRemoteCopy);
          }
        },
      );
```

- [ ] **Step 3: Regenerate Drift code**

Run:

```powershell
dart run build_runner build --delete-conflicting-outputs
```

Expected: generated files update without errors.

- [ ] **Step 4: Analyze database files**

Run:

```powershell
dart analyze lib/core/database/tables/notes.dart lib/core/database/database.dart lib/core/database/database.g.dart
```

Expected: no new analyzer errors.

- [ ] **Step 5: Commit schema change**

```bash
git add lib/core/database/tables/notes.dart lib/core/database/database.dart lib/core/database/database.g.dart
git commit -m "feat(notes): track remote copy state locally"
```

---

## Task 3: Teach Notes DAO About Empty Visibility, Sync Eligibility, And Deletes

**Files:**
- Modify: `lib/core/database/daos/notes_dao.dart`
- Test through repository tests in Task 4.

- [ ] **Step 1: Update active-note queries to hide text-empty notes**

In `watchAllActiveNotes`, add the empty-title/content filter before `orderBy`:

```dart
          ..where(
            (t) =>
                t.title.isNotNull() |
                t.content.trim().isBiggerThanValue(''),
          )
```

If Drift does not support `trim()` on `TextColumn` in this project version, use this custom expression instead:

```dart
          ..where(
            (t) => CustomExpression<bool>(
              "(title IS NOT NULL AND trim(title) <> '') OR trim(content) <> ''",
            ),
          )
```

Apply the same predicate to `watchNotesByContext` and `watchFavorites`.

- [ ] **Step 2: Add hard delete and remote marker methods**

Append these methods to `NotesDao`:

```dart
  Future<void> hardDeleteNote(String id) async {
    await (delete(notes)..where((t) => t.id.equals(id))).go();
  }

  Future<void> markHasRemoteCopy(String id) async {
    await (update(notes)..where((t) => t.id.equals(id))).write(
      const NotesCompanion(hasRemoteCopy: Value(true)),
    );
  }
```

- [ ] **Step 3: Make remote pulls mark notes as remote**

Update `upsertFromRemote`:

```dart
  Future<void> upsertFromRemote(NoteData note) async {
    final incoming = note.copyWith(isDirty: false, hasRemoteCopy: true);
    await into(notes).insertOnConflictUpdate(incoming);
  }
```

- [ ] **Step 4: Add sync-eligible dirty notes**

Replace `getDirtyNotes` with this implementation:

```dart
  Future<List<NoteData>> getDirtyNotes() {
    return (select(notes)
          ..where((t) => t.isDirty.equals(true))
          ..where(
            (t) => t.hasRemoteCopy.equals(true) |
                t.deletedAt.isNotNull() |
                t.isInbox.equals(true) |
                CustomExpression<bool>(
                  "(title IS NOT NULL AND trim(title) <> '') OR trim(content) <> ''",
                ),
          ))
        .get();
  }
```

This is intentionally conservative. Task/tag/attachment-aware emptiness is handled before local deletion; sync eligibility is allowed once the note has visible title/body or already exists remotely.

- [ ] **Step 5: Analyze DAO**

Run:

```powershell
dart analyze lib/core/database/daos/notes_dao.dart
```

Expected: no new analyzer errors.

- [ ] **Step 6: Commit DAO change**

```bash
git add lib/core/database/daos/notes_dao.dart
git commit -m "feat(notes): filter empty notes from local lists and sync"
```

---

## Task 4: Add Repository-Level Note Lifecycle Operations

**Files:**
- Modify: `lib/features/notes/data/local/notes_local_repository.dart`
- Modify: `lib/features/notes/data/notes_repository.dart`
- Create: `test/features/notes/data/notes_repository_test.dart`

- [ ] **Step 1: Add failing repository tests**

Create `test/features/notes/data/notes_repository_test.dart` with focused tests around lifecycle methods. Use a fake local repository if the Drift DB test harness is too heavy; the important assertions are method behavior, not SQLite itself.

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotesRepository lifecycle', () {
    test('createLocalNote creates an empty local-only note by id', () {
      // Implement after repository API is added:
      // final repo = makeRepository();
      // final note = await repo.createLocalNote(id: 'note-1');
      // expect(note.id, 'note-1');
      // expect(note.title, isNull);
      // expect(note.content, isEmpty);
    });

    test('deleteIfEmpty hard-deletes empty local-only notes', () {
      // Arrange: local note with hasRemoteCopy=false, blank title/content,
      // no tasks and no tags.
      // Act: await repo.deleteIfEmptyOrTombstone('note-1');
      // Assert: DAO hardDeleteNote was called, softDeleteNote was not called.
    });

    test('deleteIfEmpty tombstones remote notes', () {
      // Arrange: note with hasRemoteCopy=true and blank title/content.
      // Act: await repo.deleteIfEmptyOrTombstone('note-1');
      // Assert: DAO softDeleteNote was called, hardDeleteNote was not called.
    });

    test('saveSnapshot writes title content and tasks together', () {
      // Arrange existing note.
      // Act: await repo.saveNoteSnapshot(id: 'note-1', title: 'A', content: 'B', tasks: const []);
      // Assert: one note update path receives title and content from same snapshot.
    });
  });
}
```

Replace comments with the concrete fake implementation during execution. Keep the fake inside this test file.

- [ ] **Step 2: Run failing tests**

Run:

```powershell
flutter test test/features/notes/data/notes_repository_test.dart
```

Expected: FAIL because the lifecycle API does not exist yet.

- [ ] **Step 3: Extend local repository**

In `lib/features/notes/data/local/notes_local_repository.dart`, add:

```dart
  Future<NoteData> createNoteWithId(String id) async {
    final now = DateTime.now().toUtc();
    final companion = NotesCompanion.insert(
      id: id,
      userId: _userId,
      content: '',
      createdAt: now,
      updatedAt: now,
      isDirty: const Value(false),
      hasRemoteCopy: const Value(false),
    );
    await _dao.createNote(companion);
    return (await _dao.getNoteById(id))!;
  }

  Future<void> hardDeleteNote(String id) {
    return _dao.hardDeleteNote(id);
  }

  Future<void> markHasRemoteCopy(String id) {
    return _dao.markHasRemoteCopy(id);
  }
```

Use `isDirty=false` because a brand-new empty note is not sync-eligible until the first meaningful snapshot save.

- [ ] **Step 4: Extend repository interface**

In `INotesRepository`, add:

```dart
  Future<NoteModel> createLocalNote({required String id});
  Future<void> saveNoteSnapshot({
    required String id,
    required String title,
    required String content,
    required List<TaskEntry> tasks,
  });
  Future<void> deleteIfEmptyOrTombstone(String id);
  Future<void> markHasRemoteCopy(String id);
```

- [ ] **Step 5: Implement repository methods**

In `NotesRepository`, add:

```dart
  @override
  Future<NoteModel> createLocalNote({required String id}) async {
    final existing = await _local.getNoteById(id);
    if (existing != null) return NoteModel.fromData(existing);
    final created = await _local.createNoteWithId(id);
    return NoteModel.fromData(created);
  }

  @override
  Future<void> saveNoteSnapshot({
    required String id,
    required String title,
    required String content,
    required List<TaskEntry> tasks,
  }) async {
    await syncTasksFromDocument(id, tasks);
    final normalizedTitle = title.trim().isEmpty ? null : title;
    final current = await _local.getNoteById(id);
    if (current == null) return;

    await updateNote(
      id,
      title: normalizedTitle,
      content: content,
    );
  }

  @override
  Future<void> deleteIfEmptyOrTombstone(String id) async {
    final note = await _local.getNoteById(id);
    if (note == null) return;
    if (!_isTextEmpty(note)) return;

    final tasks = await _tasksLocal.getNoteTasks(id);
    if (tasks.isNotEmpty) return;

    // Task/tag/attachment emptiness is completed in the DAO/repository tests.
    // When tags are checked here, use tagsDaoProvider wiring instead of
    // reaching through UI code.
    if (note.hasRemoteCopy) {
      await _local.softDeleteNote(id);
    } else {
      await _local.hardDeleteNote(id);
    }
  }

  @override
  Future<void> markHasRemoteCopy(String id) {
    return _local.markHasRemoteCopy(id);
  }

  bool _isTextEmpty(NoteData note) {
    return (note.title == null || note.title!.trim().isEmpty) &&
        note.content.trim().isEmpty;
  }
```

During execution, if tags must be included in emptiness, inject `TagsDao` or a small repository dependency into `NotesRepository` rather than importing presentation providers.

- [ ] **Step 6: Run repository tests**

Run:

```powershell
flutter test test/features/notes/data/notes_repository_test.dart
```

Expected: PASS.

- [ ] **Step 7: Analyze changed files**

Run:

```powershell
dart analyze lib/features/notes/data/local/notes_local_repository.dart lib/features/notes/data/notes_repository.dart test/features/notes/data/notes_repository_test.dart
```

Expected: no new analyzer errors.

- [ ] **Step 8: Commit repository lifecycle**

```bash
git add lib/features/notes/data/local/notes_local_repository.dart lib/features/notes/data/notes_repository.dart test/features/notes/data/notes_repository_test.dart
git commit -m "feat(notes): add local-first note lifecycle"
```

---

## Task 5: Create Notes Before Opening The Editor

**Files:**
- Modify: `lib/features/notes/presentation/notes_list_screen.dart`
- Modify: `lib/features/notes/presentation/note_editor_screen.dart`

- [ ] **Step 1: Add a widget test for FAB creation**

If a full `NotesListScreen` widget test is too expensive, add a focused controller/repository interaction test around `_openNewNote` by extracting only a tiny method if necessary. The behavior to lock:

```dart
testWidgets('new-note FAB creates a local note before navigation', (tester) async {
  // Pump NotesListScreen with a fake notesRepositoryProvider.
  // Tap the FAB.
  // Expect fakeRepository.createdIds contains the generated id.
  // Expect router navigated to /notes/<same id>.
});
```

- [ ] **Step 2: Run the failing test**

Run:

```powershell
flutter test test/features/notes/presentation/notes_list_screen_test.dart
```

Expected: FAIL because `_openNewNote` only navigates today.

- [ ] **Step 3: Create local note before navigation**

Update `_openNewNote`:

```dart
  Future<void> _openNewNote(BuildContext context) async {
    final id = const Uuid().v4();
    await ref.read(notesRepositoryProvider).createLocalNote(id: id);
    if (!context.mounted) return;
    context.push(AppRoutes.note(id));
  }
```

Update the FAB callback:

```dart
          floatingActionButton: FloatingActionButton(
            onPressed: () => _openNewNote(context),
            shape: const CircleBorder(),
            child: const Icon(Icons.edit_outlined, size: 22),
          ),
```

- [ ] **Step 4: Remove lazy regular-note creation from editor initialization**

In `note_editor_screen.dart`, replace the `note?.content ?? ''` initialization with an error for missing notes:

```dart
      final note = asyncValue.asData?.value;
      if (note == null) {
        return const Scaffold(
          body: Center(child: Text('Nota nao encontrada')),
        );
      }
      _controller.init(content: note.content, title: note.title);
```

- [ ] **Step 5: Run tests and analyze**

Run:

```powershell
flutter test test/features/notes/presentation/notes_list_screen_test.dart
dart analyze lib/features/notes/presentation/notes_list_screen.dart lib/features/notes/presentation/note_editor_screen.dart
```

Expected: tests pass, analyzer clean.

- [ ] **Step 6: Commit UI creation change**

```bash
git add lib/features/notes/presentation/notes_list_screen.dart lib/features/notes/presentation/note_editor_screen.dart test/features/notes/presentation/notes_list_screen_test.dart
git commit -m "feat(notes): create local note before opening editor"
```

---

## Task 6: Replace Field-Level Autosave With Snapshot Autosave

**Files:**
- Modify: `lib/features/notes/presentation/controllers/note_editor_controller.dart`
- Modify: `lib/features/notes/presentation/note_editor_screen.dart`
- Modify: `lib/features/notes/presentation/inbox_screen.dart`

- [ ] **Step 1: Add controller tests for snapshot behavior**

Create or extend `test/features/notes/presentation/controllers/note_editor_controller_test.dart`:

```dart
test('title and document changes schedule one snapshot save', () async {
  // Create NoteEditorController with a fake saveSnapshot callback.
  // Initialize title/content.
  // Change title and document.
  // Flush.
  // Expect one save call with final title and final markdown.
});

test('flushBeforePop deletes empty regular note through lifecycle callback', () async {
  // Initialize empty title/content.
  // Flush.
  // Expect deleteIfEmpty callback called once.
});
```

- [ ] **Step 2: Run failing controller tests**

Run:

```powershell
flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart
```

Expected: FAIL because controller has separate content/title save callbacks.

- [ ] **Step 3: Replace save typedefs**

In `note_editor_controller.dart`, replace `ContentSave`, `TitleSave`, and `DeleteNote` with:

```dart
typedef SnapshotSave =
    Future<void> Function(
      WidgetRef ref,
      String noteId,
      String title,
      String markdown,
      List<TaskEntry> tasks,
    );
typedef EmptyNoteExit = Future<void> Function(WidgetRef ref, String noteId);
```

- [ ] **Step 4: Update controller constructor and fields**

Use one throttle:

```dart
class NoteEditorController {
  NoteEditorController({
    this.editableTitle = true,
    required this.snapshotSave,
    this.emptyNoteExit,
  });

  final bool editableTitle;
  final SnapshotSave snapshotSave;
  final EmptyNoteExit? emptyNoteExit;

  final _saveThrottle = SaveThrottle();
```

- [ ] **Step 5: Make both listeners schedule snapshot save**

Replace `_onDocumentChanged` and `_onTitleChanged` with:

```dart
  void _onDocumentChanged(DocumentChangeLog _) => _scheduleSnapshotSave();

  void _onTitleChanged() => _scheduleSnapshotSave();

  void _scheduleSnapshotSave() {
    final doc = document;
    if (doc == null) return;
    final generation = _saveThrottle.nextGeneration();
    _saveThrottle.schedule(
      generation: generation,
      operation: _runSnapshotSave,
    );
  }
```

- [ ] **Step 6: Implement snapshot save and flush**

Add:

```dart
  Future<void> _runSnapshotSave() async {
    final ref = _ref;
    final noteId = _noteId;
    final doc = document;
    if (ref == null || noteId == null || doc == null) return;

    await snapshotSave(
      ref,
      noteId,
      titleController?.text ?? '',
      serializeDocumentToMarkdown(doc),
      _extractTasks(doc),
    );
  }

  Future<void> flushBeforePop() async {
    final ref = _ref;
    final noteId = _noteId;
    final doc = document;
    if (ref == null || noteId == null || doc == null) return;

    final title = titleController?.text ?? '';
    final markdown = serializeDocumentToMarkdown(doc);
    final tasks = _extractTasks(doc);

    final generation = _saveThrottle.nextGeneration();
    await _saveThrottle.flush(
      generation: generation,
      operation: () => snapshotSave(ref, noteId, title, markdown, tasks),
    );

    if (title.trim().isEmpty && markdown.trim().isEmpty) {
      await emptyNoteExit?.call(ref, noteId);
    }
  }
```

During implementation, preserve inbox behavior: inbox has no `emptyNoteExit`, so empty inbox content is saved, not deleted.

- [ ] **Step 7: Replace default callbacks**

Replace `defaultContentSave`, `defaultTitleSave`, and `defaultDeleteNote` with:

```dart
Future<void> defaultSnapshotSave(
  WidgetRef ref,
  String noteId,
  String title,
  String markdown,
  List<TaskEntry> tasks,
) async {
  await ref.read(notesRepositoryProvider).saveNoteSnapshot(
        id: noteId,
        title: title,
        content: markdown,
        tasks: tasks,
      );
}

Future<void> defaultEmptyNoteExit(WidgetRef ref, String noteId) async {
  await ref.read(notesRepositoryProvider).deleteIfEmptyOrTombstone(noteId);
}
```

- [ ] **Step 8: Update editor screens**

Regular editor:

```dart
  final _controller = NoteEditorController(
    snapshotSave: defaultSnapshotSave,
    emptyNoteExit: defaultEmptyNoteExit,
  );
```

Inbox:

```dart
  final _controller = NoteEditorController(
    editableTitle: true,
    snapshotSave: defaultSnapshotSave,
  );
```

- [ ] **Step 9: Run focused tests and analyze**

Run:

```powershell
flutter test test/features/notes/presentation/controllers/note_editor_controller_test.dart
dart analyze lib/features/notes/presentation/controllers/note_editor_controller.dart lib/features/notes/presentation/note_editor_screen.dart lib/features/notes/presentation/inbox_screen.dart
```

Expected: tests pass, analyzer clean.

- [ ] **Step 10: Commit autosave change**

```bash
git add lib/features/notes/presentation/controllers/note_editor_controller.dart lib/features/notes/presentation/note_editor_screen.dart lib/features/notes/presentation/inbox_screen.dart test/features/notes/presentation/controllers/note_editor_controller_test.dart
git commit -m "refactor(notes): autosave note snapshots"
```

---

## Task 7: Mark Notes Remote After Successful Sync Push

**Files:**
- Modify: `lib/core/sync/sync_service.dart`
- Create: `test/core/sync/sync_service_test.dart`

- [ ] **Step 1: Add failing sync service test**

Create `test/core/sync/sync_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('successful push marks pushed notes as having a remote copy', () async {
    // Arrange an in-memory AppDatabase with one dirty non-empty note.
    // Use fake SyncRepository that records payload and returns success.
    // Act: await service.push();
    // Assert: note.isDirty is false and note.hasRemoteCopy is true.
  });
}
```

Use the existing `SyncService` constructor directly. If `SyncRepository` is not injectable enough, extract a small interface in `sync_service.dart`:

```dart
abstract class ISyncRepository {
  Future<void> push(Map<String, dynamic> payload);
  Future<Map<String, dynamic>> pull({required String lastSyncedAt, int limit = 500});
}
```

Then make `SyncRepository implements ISyncRepository`.

- [ ] **Step 2: Run failing test**

Run:

```powershell
flutter test test/core/sync/sync_service_test.dart
```

Expected: FAIL because successful push only clears dirty flags today.

- [ ] **Step 3: Mark pushed notes remote**

In `SyncService.push`, update the notes loop:

```dart
      for (final n in notes) {
        await _db.notesDao.markHasRemoteCopy(n.id);
        await _db.notesDao.clearDirtyFlag(n.id);
      }
```

Keep tombstoned remote notes marked as remote; tombstone retention is still server-driven.

- [ ] **Step 4: Run test**

Run:

```powershell
flutter test test/core/sync/sync_service_test.dart
```

Expected: PASS.

- [ ] **Step 5: Analyze sync files**

Run:

```powershell
dart analyze lib/core/sync/sync_service.dart test/core/sync/sync_service_test.dart
```

Expected: no new analyzer errors.

- [ ] **Step 6: Commit sync marker**

```bash
git add lib/core/sync/sync_service.dart test/core/sync/sync_service_test.dart
git commit -m "feat(sync): mark pushed notes as remote"
```

---

## Task 8: Backend Guard Against Empty Regular Notes

**Files:**
- Modify: `backend/internal/notes/service.go`
- Modify: `backend/internal/notes/service_test.go`
- Modify: `backend/internal/sync/service.go`
- Modify: `backend/internal/sync/service_test.go`

- [ ] **Step 1: Add backend note service test**

In `backend/internal/notes/service_test.go`, add:

```go
func TestCreateNoteRejectsEmptyRegularNote(t *testing.T) {
	svc := NewService(&mockRepository{})
	userID := pgtype.UUID{Valid: true}

	_, err := svc.CreateNote(context.Background(), userID, nil, "   ", nil, false, false)

	if !errors.Is(err, ErrEmptyNote) {
		t.Fatalf("expected ErrEmptyNote, got %v", err)
	}
}
```

If the file lacks a reusable mock, add the smallest mock that satisfies the repository interface and fails if `CreateNote` is called.

- [ ] **Step 2: Add sync service test**

In `backend/internal/sync/service_test.go`, add:

```go
func TestSyncPushRejectsEmptyNewRegularNote(t *testing.T) {
	repo := &mockRepository{}
	svc := NewService(repo, nil)

	err := svc.Push(context.Background(), pgtype.UUID{Valid: true}, &SyncPayload{
		Notes: []sqlcgen.Note{{
			ID:        pgtype.UUID{Valid: true},
			Title:     pgtype.Text{Valid: false},
			Content:   "   ",
			IsInbox:   false,
			DeletedAt: pgtype.Timestamptz{Valid: false},
		}},
	})

	if !errors.Is(err, ErrEmptyNote) {
		t.Fatalf("expected ErrEmptyNote, got %v", err)
	}
}
```

- [ ] **Step 3: Run failing backend tests**

Run:

```powershell
cd backend
go test ./internal/notes ./internal/sync
```

Expected: FAIL because `ErrEmptyNote` does not exist yet.

- [ ] **Step 4: Add note service error and guard**

In `backend/internal/notes/service.go`, add:

```go
	ErrEmptyNote = errors.New("empty note")
```

Then guard `CreateNote`:

```go
func isEmptyRegularNote(title *string, content string) bool {
	return (title == nil || strings.TrimSpace(*title) == "") && strings.TrimSpace(content) == ""
}
```

At the top of `CreateNote`:

```go
	if isEmptyRegularNote(title, content) {
		return sqlcgen.Note{}, ErrEmptyNote
	}
```

- [ ] **Step 5: Add sync-level error and guard**

In `backend/internal/sync/service.go`, add:

```go
var ErrEmptyNote = errors.New("empty note")

func isEmptyIncomingRegularNote(n sqlcgen.Note) bool {
	return !n.IsInbox &&
		!n.DeletedAt.Valid &&
		(!n.Title.Valid || strings.TrimSpace(n.Title.String) == "") &&
		strings.TrimSpace(n.Content) == ""
}
```

Import `strings`.

In the note loop before `UpsertNote`:

```go
		if isEmptyIncomingRegularNote(n) {
			return ErrEmptyNote
		}
```

This backend guard is defensive. The Flutter client should prevent empty new notes from reaching sync in the first place.

- [ ] **Step 6: Return client error from sync handler**

In `backend/internal/sync/handler.go`, update error handling:

```go
	if err := h.service.Push(c.Request().Context(), userID, &payload); err != nil {
		if errors.Is(err, ErrSyncConflict) {
			return web.JSONError(c, http.StatusConflict, "sync conflict")
		}
		if errors.Is(err, ErrEmptyNote) {
			return web.JSONError(c, http.StatusBadRequest, "empty notes cannot be synced")
		}
		return web.JSONError(c, http.StatusInternalServerError, "sync failed")
	}
```

- [ ] **Step 7: Run backend tests**

Run:

```powershell
cd backend
go test ./internal/notes ./internal/sync
```

Expected: PASS.

- [ ] **Step 8: Format and commit backend guard**

Run:

```powershell
cd backend
gofmt -w internal/notes/service.go internal/notes/service_test.go internal/sync/service.go internal/sync/service_test.go internal/sync/handler.go
go test ./internal/notes ./internal/sync
```

Then:

```bash
git add backend/internal/notes/service.go backend/internal/notes/service_test.go backend/internal/sync/service.go backend/internal/sync/service_test.go backend/internal/sync/handler.go
git commit -m "fix(sync): reject empty regular notes"
```

---

## Task 9: End-To-End Verification

**Files:**
- No new files unless tests expose gaps.

- [ ] **Step 1: Run focused Flutter tests**

Run:

```powershell
flutter test test/features/notes/data/notes_repository_test.dart test/features/notes/presentation/controllers/note_editor_controller_test.dart test/core/sync/sync_service_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run backend focused tests**

Run:

```powershell
cd backend
go test ./internal/notes ./internal/sync
```

Expected: PASS.

- [ ] **Step 3: Run analyzer on changed Dart files**

Run:

```powershell
dart analyze lib/core/database lib/core/sync lib/features/notes test/features/notes test/core/sync
```

Expected: no new analyzer errors.

- [ ] **Step 4: Manual app smoke test**

Run:

```powershell
flutter run -d windows
```

Manual checks:
- Tap new-note FAB.
- Confirm editor opens.
- Press back without typing.
- Confirm note does not appear in the list after returning.
- Tap new-note FAB again.
- Type a title and body.
- Wait for autosave, return, confirm note appears.
- Trigger manual sync from menu, confirm no sync error appears.

- [ ] **Step 5: Commit verification fixes if any**

If verification required fixes:

```bash
git add <changed-files>
git commit -m "test(notes): verify new note lifecycle"
```

---

## Self-Review

**Spec coverage:**
- Immediate local note creation: Task 5.
- Empty note definition and list hiding: Tasks 3 and 4.
- Local-only hard delete vs remote tombstone: Task 4.
- Snapshot autosave: Task 6.
- Async sync after meaningful local save: Tasks 3 and 7.
- Backend participation: Task 8.
- Docs/decision record: Task 1.

**Risk notes:**
- Drift expression support for trimmed text may require `CustomExpression<bool>`; Task 3 includes the fallback.
- Tags count for emptiness may require injecting `TagsDao` into `NotesRepository`. Do not reach into presentation providers from data code.
- Backend cannot fully evaluate task/tag/attachment-aware emptiness from a note-only payload. Its guard is intentionally defensive for empty title/body regular notes, while the client owns full local emptiness.

**Execution order:** Tasks are sequential. Do not start autosave refactor before repository lifecycle APIs exist.
