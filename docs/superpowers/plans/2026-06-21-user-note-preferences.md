# User Note Preferences Implementation Plan (Revised)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Drift check (run first)**: `git diff --stat 77d1a1e..HEAD -- backend/internal/sync/ backend/db/ lib/core/database/ lib/core/sync/ lib/features/notes/`
> If any in-scope file changed since this plan was written, compare the excerpts below against live code before proceeding; on a mismatch, treat it as a STOP condition.

**Goal:** Implement a user-specific and synchronized notes preferences system (specifically hide/show completed tasks) so that collaborators can control their own view without interfering with other users.

**Architecture:** Introduce `user_note_preferences` table in both backend (PostgreSQL) and frontend (Drift SQLite). Synchronize this entity over the existing `/sync` endpoints. In the Flutter UI, watch the user preference alongside the note and merge them in `NoteEditorScreen`.

**Tech Stack:** Go, PostgreSQL, sqlc, Flutter, Drift SQLite, Riverpod.

**Planned at:** commit `77d1a1e`, 2026-06-21

---

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| SQLC codegen | `cd backend && sqlc generate` | exit 0, no errors |
| Go tests (sync) | `cd backend && go test ./internal/sync/...` | PASS |
| Go build | `cd backend && go build ./...` | exit 0 |
| Drift codegen | `dart run build_runner build --delete-conflicting-outputs` | exit 0 |
| Flutter analyze | `dart analyze` | No issues found |

---

## STOP conditions

Stop and report back (do not improvise) if:

- The code at any location cited below doesn't match the excerpts (codebase has drifted).
- A step's verification fails twice after a reasonable fix attempt.
- The fix appears to require touching an out-of-scope file not listed below.
- SQLC generates a type name different from `UserNotePreference` — all downstream code references that name.

---

### Task 1: Backend Database Migration

**Files:**
- Create: `backend/db/migrations/000019_user_note_preferences.up.sql`
- Create: `backend/db/migrations/000019_user_note_preferences.down.sql`

- [ ] **Step 1: Create the up migration file**

  Create `backend/db/migrations/000019_user_note_preferences.up.sql`:
  ```sql
  BEGIN;

  CREATE TABLE IF NOT EXISTS user_note_preferences (
      user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      note_id          UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
      hide_completed   BOOLEAN NOT NULL DEFAULT FALSE,
      filters          JSONB NOT NULL DEFAULT '{}'::jsonb,
      created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (user_id, note_id)
  );

  CREATE INDEX IF NOT EXISTS idx_user_note_prefs_user_id ON user_note_preferences(user_id);

  -- Seed existing hide_completed values into per-user preferences
  INSERT INTO user_note_preferences (user_id, note_id, hide_completed, created_at, updated_at)
  SELECT user_id, id, hide_completed, created_at, updated_at FROM notes
  WHERE deleted_at IS NULL
  ON CONFLICT (user_id, note_id) DO NOTHING;

  COMMIT;
  ```

- [ ] **Step 2: Create the down migration file**

  Create `backend/db/migrations/000019_user_note_preferences.down.sql`:
  ```sql
  BEGIN;
  DROP TABLE IF EXISTS user_note_preferences;
  COMMIT;
  ```

- [ ] **Step 3: Commit**
  ```bash
  git add backend/db/migrations/000019_user_note_preferences.up.sql backend/db/migrations/000019_user_note_preferences.down.sql
  git commit -m "migration(backend): add user_note_preferences table"
  ```

---

### Task 2: SQLC Query Definitions and Code Generation

**Files:**
- Modify: `backend/db/queries/sync.sql` (append at end)
- Regenerate: `backend/internal/db/sqlcgen/` (all generated files)

**Current state:** `backend/db/queries/sync.sql` ends at line 173 with the `UpsertNoteLink` query. The last line is `SET relation = EXCLUDED.relation, updated_at = NOW();`.

- [ ] **Step 1: Append SQLC queries**

  Add the following to the **end** of `backend/db/queries/sync.sql`:
  ```sql

  -- name: GetSyncUserNotePreferences :many
  SELECT * FROM user_note_preferences
  WHERE user_id = $1 AND updated_at > sqlc.arg('last_synced_at')
  ORDER BY updated_at ASC
  LIMIT sqlc.arg('limit');

  -- name: UpsertUserNotePreference :one
  INSERT INTO user_note_preferences (user_id, note_id, hide_completed, filters, created_at, updated_at)
  VALUES ($1, $2, $3, $4, $5, NOW())
  ON CONFLICT (user_id, note_id) DO UPDATE
  SET hide_completed = EXCLUDED.hide_completed,
      filters = EXCLUDED.filters,
      updated_at = NOW()
  RETURNING *;
  ```

- [ ] **Step 2: Run SQLC generation**

  Run: `cd backend && sqlc generate`
  Expected: exit 0, no errors. This will create/update `backend/internal/db/sqlcgen/sync.sql.go` with new `GetSyncUserNotePreferences` and `UpsertUserNotePreference` methods and a `UserNotePreference` struct.

- [ ] **Step 3: Update all test stub files that implement `sqlcgen.Querier`**

  SQLC added two new methods to the `Querier` interface. **Six test files** have structs that implement `Querier` and will fail to compile without stubs. Add the following two methods to each stub struct listed below:

  ```go
  func (s *stubQuerier) GetSyncUserNotePreferences(ctx context.Context, arg sqlcgen.GetSyncUserNotePreferencesParams) ([]sqlcgen.UserNotePreference, error) {
  	return nil, nil
  }
  func (s *stubQuerier) UpsertUserNotePreference(ctx context.Context, arg sqlcgen.UpsertUserNotePreferenceParams) (sqlcgen.UserNotePreference, error) {
  	return sqlcgen.UserNotePreference{}, nil
  }
  ```

  Files to update (adjust `s *stubQuerier` to match the receiver name in each file):
  1. `backend/internal/agent/context_test.go` — receiver: `s *stubQuerier`
  2. `backend/internal/agent/loop_test.go` — receiver: `s *stubLoopQuerier`
  3. `backend/internal/agent/tools/tools_test.go` — receiver: `s *stubQuerier`
  4. `backend/internal/auth/service_test.go` — receiver: `m *mockQuerier`
  5. `backend/internal/contexts/service_test.go` — receiver: `m *mockQuerier`
  6. `backend/internal/tags/mock_test.go` — check receiver name in file

- [ ] **Step 4: Verify compilation**

  Run: `cd backend && go build ./...`
  Expected: exit 0

- [ ] **Step 5: Commit**
  ```bash
  git add backend/db/queries/sync.sql backend/internal/db/sqlcgen/ backend/internal/agent/ backend/internal/auth/ backend/internal/contexts/ backend/internal/tags/
  git commit -m "backend(sqlc): add user_note_preferences queries and update test stubs"
  ```

---

### Task 3: Backend Sync Service Integration

**Files:**
- Modify: `backend/internal/sync/repository.go`
- Modify: `backend/internal/sync/service.go`
- Modify: `backend/internal/sync/service_test.go`

**Current state of `repository.go`:** The `Repository` interface (L11-29) has methods like `GetSyncNotes`, `UpsertNote`, etc. The `repo` struct (L31-33) wraps `sqlcgen.Querier`.

**Current state of `service.go`:** `SyncPayload` struct (L25-33) has fields: Notes, Tasks, Contexts, Tags, TaskCompletions, NoteTags, NoteLinks. `Pull` method (L54-124) fetches each entity in sequence. `Push` method (L143-337) processes each entity in sequence, ending with NoteLinks at L319-331, then commits the transaction at L333-336.

- [ ] **Step 1: Add repository interface methods and implementation**

  In `backend/internal/sync/repository.go`, add to the `Repository` interface (before `WithQuerier`):
  ```go
  GetSyncUserNotePreferences(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.UserNotePreference, error)
  UpsertUserNotePreference(ctx context.Context, arg sqlcgen.UpsertUserNotePreferenceParams) (sqlcgen.UserNotePreference, error)
  ```

  Add implementations on `repo` struct (before `WithQuerier`):
  ```go
  func (r *repo) GetSyncUserNotePreferences(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.UserNotePreference, error) {
  	return r.q.GetSyncUserNotePreferences(ctx, sqlcgen.GetSyncUserNotePreferencesParams{
  		UserID:       userID,
  		LastSyncedAt: lastSyncedAt,
  		Limit:        limit,
  	})
  }

  func (r *repo) UpsertUserNotePreference(ctx context.Context, arg sqlcgen.UpsertUserNotePreferenceParams) (sqlcgen.UserNotePreference, error) {
  	return r.q.UpsertUserNotePreference(ctx, arg)
  }
  ```

- [ ] **Step 2: Update SyncPayload and Pull method**

  In `backend/internal/sync/service.go`:

  Add to `SyncPayload` struct (after `NoteLinks`):
  ```go
  UserNotePreferences []sqlcgen.UserNotePreference `json:"user_note_preferences"`
  ```

  In the `Pull` method, add **before** the final `return` statement (before L115):
  ```go
  prefs, err := s.repo.GetSyncUserNotePreferences(ctx, userID, lastSyncedAt, limit)
  if err != nil {
  	return nil, err
  }
  if prefs == nil {
  	prefs = make([]sqlcgen.UserNotePreference, 0)
  }
  ```

  Add `UserNotePreferences: prefs,` to the returned `SyncPayload` literal.

- [ ] **Step 3: Update Push method**

  In the `Push` method of `backend/internal/sync/service.go`, add the following block **after** the NoteLinks loop (after L331) and **before** the transaction commit (before L333):

  ```go
  for _, p := range payload.UserNotePreferences {
  	_, err := r.UpsertUserNotePreference(ctx, sqlcgen.UpsertUserNotePreferenceParams{
  		UserID:        userID, // Always use authenticated user, never trust payload
  		NoteID:        p.NoteID,
  		HideCompleted: p.HideCompleted,
  		Filters:       p.Filters,
  		CreatedAt:     p.CreatedAt,
  	})
  	if err != nil {
  		if errors.Is(err, pgx.ErrNoRows) {
  			return ErrSyncConflict
  		}
  		return err
  	}
  }
  ```

  **Note:** Access validation is handled by the SQL itself — `UpsertUserNotePreference` will insert/update only for the authenticated `userID`. No separate `GetNoteByID` call is needed. If the `note_id` foreign key doesn't exist, PostgreSQL will return a constraint violation error, which is propagated as-is.

- [ ] **Step 4: Update test mocks**

  In `backend/internal/sync/service_test.go`, add to `mockRepository`:
  ```go
  func (m *mockRepository) GetSyncUserNotePreferences(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.UserNotePreference, error) {
  	return nil, nil
  }

  func (m *mockRepository) UpsertUserNotePreference(ctx context.Context, arg sqlcgen.UpsertUserNotePreferenceParams) (sqlcgen.UserNotePreference, error) {
  	return sqlcgen.UserNotePreference{}, nil
  }
  ```

- [ ] **Step 5: Run tests**

  Run: `cd backend && go test ./internal/sync/...`
  Expected: PASS

- [ ] **Step 6: Commit**
  ```bash
  git add backend/internal/sync/
  git commit -m "backend(sync): integrate user_note_preferences into pull/push"
  ```

---

### Task 4: Flutter Drift Table & Database Upgrade

**Files:**
- Create: `lib/core/database/tables/user_note_preferences.dart`
- Modify: `lib/core/database/database.dart`
- Regenerate: `lib/core/database/database.g.dart`

**Current state of `database.dart`:**
- `schemaVersion` is `10` (L43-44, comment: "v10 adds collapseImages")
- `@DriftDatabase` tables list (L32): `[Notes, Tasks, Contexts, Tags, LocalNoteTags, LocalTaskCompletions, NoteLinks, Attachments]`
- `@DriftDatabase` daos list (L33): `[NotesDao, ContextsDao, TasksDao, TagsDao, TaskCompletionsDao, NoteLinksDao, NoteTagsDao, AttachmentsDao]`
- Latest migration guard: `if (from < 10)` at ~L87

- [ ] **Step 1: Create table definition**

  Create `lib/core/database/tables/user_note_preferences.dart`:
  ```dart
  import 'package:drift/drift.dart';

  @DataClassName('UserNotePreferenceData')
  class UserNotePreferences extends Table {
    TextColumn get userId => text()();
    TextColumn get noteId => text()();
    BoolColumn get hideCompleted => boolean().withDefault(const Constant(false))();
    TextColumn get filters => text().withDefault(const Constant('{}'))();

    DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
    DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
    BoolColumn get isDirty => boolean().withDefault(const Constant(true))();

    @override
    Set<Column> get primaryKey => {userId, noteId};
  }
  ```

- [ ] **Step 2: Update `database.dart`**

  In `lib/core/database/database.dart`:

  1. Add import: `import 'tables/user_note_preferences.dart';`
  2. Add import: `import 'daos/user_note_preferences_dao.dart';` (will be created in Task 6 — import now so codegen sees it)
  3. Update `@DriftDatabase` tables: add `UserNotePreferences` to the list
  4. Update `@DriftDatabase` daos: add `UserNotePreferencesDao` to the list
  5. Change `schemaVersion` from `10` to `11`
  6. Update comment to: `/// Latest schema version. Bumped to 11 — v11 adds user_note_preferences.`
  7. Add migration guard inside `onUpgrade`, after the `from < 10` block:
     ```dart
     if (from < 11) {
       await m.createTable(userNotePreferences);
     }
     ```

  **IMPORTANT:** Do NOT remove or alter any existing tables or daos in the lists (Notes, Tasks, Contexts, Tags, LocalNoteTags, LocalTaskCompletions, NoteLinks, Attachments, and their respective DAOs are all present and must remain).

- [ ] **Step 3: Create DAO file (needed for codegen to succeed)**

  Create `lib/core/database/daos/user_note_preferences_dao.dart`:
  ```dart
  import 'package:drift/drift.dart';
  import '../database.dart';
  import '../tables/user_note_preferences.dart';

  part 'user_note_preferences_dao.g.dart';

  @DriftAccessor(tables: [UserNotePreferences])
  class UserNotePreferencesDao extends DatabaseAccessor<AppDatabase>
      with _$UserNotePreferencesDaoMixin {
    UserNotePreferencesDao(super.db);

    Stream<UserNotePreferenceData?> watchPreference(
        String userId, String noteId) {
      return (select(userNotePreferences)
            ..where(
                (t) => t.userId.equals(userId) & t.noteId.equals(noteId)))
          .watchSingleOrNull();
    }

    Future<UserNotePreferenceData?> getPreference(
        String userId, String noteId) {
      return (select(userNotePreferences)
            ..where(
                (t) => t.userId.equals(userId) & t.noteId.equals(noteId)))
          .getSingleOrNull();
    }

    Future<List<UserNotePreferenceData>> getDirtyPreferences() {
      return (select(userNotePreferences)
            ..where((t) => t.isDirty.equals(true)))
          .get();
    }

    Future<void> clearDirtyFlag(String userId, String noteId) async {
      await (update(userNotePreferences)
            ..where(
                (t) => t.userId.equals(userId) & t.noteId.equals(noteId)))
          .write(
        const UserNotePreferencesCompanion(isDirty: Value(false)),
      );
    }

    Future<void> setHideCompleted(
        String userId, String noteId, bool hideCompleted) async {
      final now = DateTime.now();
      await into(userNotePreferences).insert(
        UserNotePreferencesCompanion.insert(
          userId: userId,
          noteId: noteId,
          hideCompleted: Value(hideCompleted),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
        onConflict: DoUpdate(
          (old) => UserNotePreferencesCompanion(
            hideCompleted: Value(hideCompleted),
            updatedAt: Value(now),
            isDirty: const Value(true),
          ),
        ),
      );
    }
  }
  ```

- [ ] **Step 4: Run Drift codegen**

  Run: `dart run build_runner build --delete-conflicting-outputs`
  Expected: exit 0, successful generation.

- [ ] **Step 5: Commit**
  ```bash
  git add lib/core/database/
  git commit -m "feat(database): add user_note_preferences table and DAO"
  ```

---

### Task 5: Flutter Sync Client Integration

**Files:**
- Modify: `lib/core/sync/sync_mapper.dart`
- Modify: `lib/core/sync/sync_service.dart`

**Current state of `sync_mapper.dart`:** Contains paired methods like `noteToJson`/`noteFromJson`, `taskToJson`/`taskFromJson`, etc. Each maps between Drift `Data` objects and JSON maps.

**Current state of `sync_service.dart`:**
- `push()` (L130-186): Queries dirty rows from each DAO, builds a JSON payload map, calls `_repo.push(payload)`, then clears dirty flags in a transaction.
- `pull()` (L188-276): Calls `_repo.pull(lastSyncedAt: ...)`, gets back a `Map<String, dynamic>`, then processes each entity list inside a `_db.batch(...)`.

- [ ] **Step 1: Add JSON mapping methods**

  In `lib/core/sync/sync_mapper.dart`, add the import for the database (if not already present) and add these two methods:

  ```dart
  Map<String, dynamic> userNotePreferenceToJson(UserNotePreferenceData p) {
    return {
      'user_id': p.userId,
      'note_id': p.noteId,
      'hide_completed': p.hideCompleted,
      'filters': p.filters,
      'created_at': p.createdAt.toUtc().toIso8601String(),
      'updated_at': p.updatedAt.toUtc().toIso8601String(),
    };
  }

  UserNotePreferencesCompanion userNotePreferenceFromJson(
      Map<String, dynamic> json) {
    return UserNotePreferencesCompanion(
      userId: Value(json['user_id'] as String),
      noteId: Value(json['note_id'] as String),
      hideCompleted: Value(json['hide_completed'] as bool? ?? false),
      filters: Value(json['filters'] as String? ?? '{}'),
      createdAt:
          Value(DateTime.parse(json['created_at'] as String).toLocal()),
      updatedAt:
          Value(DateTime.parse(json['updated_at'] as String).toLocal()),
      isDirty: const Value(false),
    );
  }
  ```

  **Note:** We return `UserNotePreferencesCompanion` (not `UserNotePreferenceData`) from `fromJson` so we can use it directly in `batch.insert` with `DoUpdate`. Follow the pattern used by `noteFromJson` which returns a Companion for batch operations.

- [ ] **Step 2: Update push() method**

  In `lib/core/sync/sync_service.dart`, in the `push()` method:

  1. After the existing dirty-row queries (after L137), add:
     ```dart
     final prefs = await _db.userNotePreferencesDao.getDirtyPreferences();
     ```

  2. Add `prefs` to the emptiness check (L139-147):
     ```dart
     if (notes.isEmpty &&
         tasks.isEmpty &&
         contexts.isEmpty &&
         tags.isEmpty &&
         completions.isEmpty &&
         noteLinks.isEmpty &&
         noteTags.isEmpty &&
         prefs.isEmpty) {
       return;
     }
     ```

  3. Add to the payload map (after L157):
     ```dart
     'user_note_preferences':
         prefs.map(_mapper.userNotePreferenceToJson).toList(),
     ```

  4. In the post-push transaction (L162-185), add after the noteTags loop:
     ```dart
     for (final p in prefs) {
       await _db.userNotePreferencesDao.clearDirtyFlag(p.userId, p.noteId);
     }
     ```

- [ ] **Step 3: Update pull() method**

  In the `pull()` method, inside the `_db.batch((batch) { ... })` block (L205-270), add after the note_tags loop:

  ```dart
  for (final raw in (data['user_note_preferences'] as List? ?? [])) {
    final pref = _mapper.userNotePreferenceFromJson(
        raw as Map<String, dynamic>);
    batch.insert(
      _db.userNotePreferences,
      pref,
      onConflict: DoUpdate((_) => pref),
    );
  }
  ```

- [ ] **Step 4: Verify**

  Run: `dart analyze`
  Expected: No issues found.

- [ ] **Step 5: Commit**
  ```bash
  git add lib/core/sync/
  git commit -m "feat(sync): synchronize user_note_preferences"
  ```

---

### Task 6: Flutter Repository & Riverpod Provider

**Files:**
- Create: `lib/features/notes/data/user_note_preferences_repository.dart`

**Note:** The DAO was already created in Task 4 Step 3 (needed for codegen). This task creates the repository layer and providers.

- [ ] **Step 1: Create repository and provider**

  Create `lib/features/notes/data/user_note_preferences_repository.dart`:
  ```dart
  import 'package:flutter_riverpod/flutter_riverpod.dart';

  import '../../../core/auth/current_user.dart';
  import '../../../core/database/database.dart';
  import '../../../core/di/providers.dart';

  class UserNotePreferencesRepository {
    UserNotePreferencesRepository(this._db);
    final AppDatabase _db;

    Stream<UserNotePreferenceData?> watchPreference(
        String userId, String noteId) {
      return _db.userNotePreferencesDao.watchPreference(userId, noteId);
    }

    Future<void> setHideCompleted(
        String userId, String noteId, bool hideCompleted) {
      return _db.userNotePreferencesDao
          .setHideCompleted(userId, noteId, hideCompleted);
    }
  }

  final userNotePreferencesRepositoryProvider =
      Provider.autoDispose<UserNotePreferencesRepository>((ref) {
    final db = ref.watch(appDatabaseProvider);
    return UserNotePreferencesRepository(db);
  });

  final userNotePreferenceStreamProvider = StreamProvider.autoDispose
      .family<UserNotePreferenceData?, String>((ref, noteId) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return Stream.value(null);
    return ref
        .watch(userNotePreferencesRepositoryProvider)
        .watchPreference(userId, noteId);
  });
  ```

- [ ] **Step 2: Verify**

  Run: `dart analyze`
  Expected: No issues found.

- [ ] **Step 3: Commit**
  ```bash
  git add lib/features/notes/data/user_note_preferences_repository.dart
  git commit -m "feat(repo): add user note preferences repository and providers"
  ```

---

### Task 7: Update NoteEditorScreen UI

**Files:**
- Modify: `lib/features/notes/presentation/note_editor_screen.dart`

**Current state (L86-182):**
```dart
final isOwner = note.isOwner;
final isReadOnly = note.isReadOnly;

return Scaffold(
  resizeToAvoidBottomInset: false,
  appBar: AppBar(
    title: isReadOnly ? Text('${NoteStrings.sharedByPrefix} ${note.sharedByEmail}') : null,
    actions: [
      if (isOwner)                           // ← GUARD: entire menu only for owner
        AdaptivePopupMenuButton.icon<String>(
          ...
          items: [
            // 'share'
            // 'hide_completed'
            // 'collapse_images'
          ],
        ),
      if (!isReadOnly)
        IconButton(icon: const Icon(Icons.check), ...),
    ],
  ),
  body: SafeArea(
    top: false,
    child: NoteEditor(
      ...
      hideCompleted: note.hideCompleted,    // ← from NoteModel (note table)
      collapseImages: note.collapseImages,
      ...
    ),
  ),
);
```

The goal is:
1. Watch the user-specific preference for `hideCompleted`.
2. Always show the popup menu (remove `if (isOwner)` guard on the entire menu).
3. Keep `share` item only for `isOwner`.
4. Keep `hide_completed` and `collapse_images` items available for everyone.
5. When `hide_completed` is toggled, write to the new preferences table instead of the notes table.
6. `collapse_images` stays on the notes table (owner-only feature per current behavior).

- [ ] **Step 1: Add import and watch the preference provider**

  In `lib/features/notes/presentation/note_editor_screen.dart`:

  Add import:
  ```dart
  import 'package:supanotes/features/notes/data/user_note_preferences_repository.dart';
  ```

  Inside `build()`, after the `note` null check (after L82), add:
  ```dart
  final prefAsync = ref.watch(userNotePreferenceStreamProvider(widget.noteId));
  final hideCompleted = prefAsync.asData?.value?.hideCompleted ?? note.hideCompleted;
  ```

- [ ] **Step 2: Restructure the AppBar actions**

  Replace the entire `actions: [...]` block (L93-152) with:
  ```dart
  actions: [
    AdaptivePopupMenuButton.icon<String>(
      icon: PlatformInfo.isIOS26OrHigher()
          ? 'ellipsis'
          : Icons.more_vert,
      onSelected: (index, entry) async {
        switch (entry.value) {
          case 'share':
            await ShareNoteDialog.show(context, widget.noteId);
          case 'hide_completed':
            final userId = ref.read(currentUserIdProvider);
            if (userId != null) {
              await ref
                  .read(userNotePreferencesRepositoryProvider)
                  .setHideCompleted(
                    userId,
                    widget.noteId,
                    !hideCompleted,
                  );
            }
          case 'collapse_images':
            await repo.updateNote(
              widget.noteId,
              collapseImages: !note.collapseImages,
            );
        }
      },
      items: [
        if (isOwner)
          AdaptivePopupMenuItem<String>(
            label: NoteStrings.shareLabel,
            icon: PlatformInfo.isIOS26OrHigher()
                ? 'square.and.arrow.up'
                : Icons.share_outlined,
            value: 'share',
          ),
        AdaptivePopupMenuItem<String>(
          label: hideCompleted
              ? NoteStrings.showCompleted
              : NoteStrings.hideCompleted,
          icon: PlatformInfo.isIOS26OrHigher()
              ? (hideCompleted ? 'eye' : 'eye.slash')
              : (hideCompleted
                  ? Icons.visibility
                  : Icons.visibility_off),
          value: 'hide_completed',
        ),
        if (isOwner)
          AdaptivePopupMenuItem<String>(
            label: note.collapseImages
                ? 'Expandir imagens'
                : 'Colapsar imagens',
            icon: PlatformInfo.isIOS26OrHigher()
                ? (note.collapseImages ? 'photo.fill' : 'photo')
                : (note.collapseImages
                    ? Icons.image
                    : Icons.image_outlined),
            value: 'collapse_images',
          ),
      ],
    ),
    if (!isReadOnly)
      IconButton(
        icon: const Icon(Icons.check),
        onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
      ),
  ],
  ```

  Add import for `currentUserIdProvider` if not present:
  ```dart
  import 'package:supanotes/core/auth/current_user.dart';
  ```

- [ ] **Step 3: Update NoteEditor widget call to use local variable**

  Change `hideCompleted: note.hideCompleted,` (L160) to:
  ```dart
  hideCompleted: hideCompleted,
  ```
  (Use the local `hideCompleted` variable from Step 1, not `note.hideCompleted`.)

- [ ] **Step 4: Verify**

  Run: `dart analyze`
  Expected: No issues found.

- [ ] **Step 5: Commit**
  ```bash
  git add lib/features/notes/presentation/note_editor_screen.dart
  git commit -m "feat(ui): per-user hide completed toggle for all note viewers"
  ```
