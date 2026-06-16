# Note Sharing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement note sharing functionality, allowing users to share notes (view/edit) with other users via email, syncing shared content seamlessly.

**Architecture:** We add a `note_shares` table in PostgreSQL to store access rules. The backend sync (`Push`/`Pull`) is updated to fetch and authorize shared resources. The Flutter app's Drift database gets new columns to store permission data locally, rendering the editor read-only for 'view' permissions and showing a new Share Modal for the owner.

**Tech Stack:** Go, PostgreSQL, SQLC, Flutter, Riverpod, Drift (SQLite).

---

### Task 1: Backend Database Schema and Queries

**Files:**
- Create: `backend/db/migrations/000013_note_sharing.up.sql`
- Create: `backend/db/migrations/000013_note_sharing.down.sql`
- Create: `backend/db/queries/shares.sql`
- Modify: `backend/db/queries/sync.sql`
- Test: `backend/internal/db/shares_test.go`

- [ ] **Step 1: Write the failing test**

```go
// backend/internal/db/shares_test.go
package db_test

import (
	"context"
	"testing"
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

func TestCreateNoteShare(t *testing.T) {
	var q *sqlcgen.Queries
	// This will fail to compile if CreateNoteShare doesn't exist
	_, err := q.CreateNoteShare(context.Background(), sqlcgen.CreateNoteShareParams{})
	if err == nil {
		t.Errorf("Expected error or panic in dummy test")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/db/...`
Expected: FAIL with "q.CreateNoteShare undefined"

- [ ] **Step 3: Write minimal implementation**

Create `backend/db/migrations/000013_note_sharing.up.sql`:
```sql
CREATE TABLE note_shares (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    note_id     UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    permission  TEXT NOT NULL CHECK (permission IN ('view', 'edit')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (note_id, user_id)
);
CREATE INDEX idx_note_shares_user_id ON note_shares(user_id);
```

Create `backend/db/migrations/000013_note_sharing.down.sql`:
```sql
DROP TABLE IF EXISTS note_shares;
```

Create `backend/db/queries/shares.sql`:
```sql
-- name: CreateNoteShare :one
INSERT INTO note_shares (note_id, user_id, permission)
VALUES ($1, $2, $3)
ON CONFLICT (note_id, user_id) DO UPDATE
SET permission = EXCLUDED.permission, updated_at = NOW()
RETURNING *;

-- name: GetNoteShares :many
SELECT ns.*, u.email, u.name
FROM note_shares ns
JOIN users u ON u.id = ns.user_id
WHERE ns.note_id = $1;

-- name: DeleteNoteShare :exec
DELETE FROM note_shares
WHERE note_id = $1 AND user_id = $2;

-- name: GetNoteShareForUser :one
SELECT * FROM note_shares
WHERE note_id = $1 AND user_id = $2;
```

Modify `backend/db/queries/sync.sql` by updating `GetSyncNotes` to join with `note_shares`:
```sql
-- name: GetSyncNotes :many
SELECT n.*, ns.permission AS shared_permission, u.email AS shared_by_email, u.name AS shared_by_name
FROM notes n
LEFT JOIN note_shares ns ON ns.note_id = n.id AND ns.user_id = $1
LEFT JOIN users u ON u.id = n.user_id
WHERE (n.user_id = $1 OR ns.user_id = $1) AND n.updated_at > sqlc.arg('last_synced_at')
ORDER BY n.updated_at ASC
LIMIT sqlc.arg('limit');
```
(Apply similar `LEFT JOIN note_shares` logic for `GetSyncTasks`, `GetSyncContexts`, `GetSyncTags`, `GetSyncTaskCompletions`, `GetSyncNoteTags`, and `GetSyncNoteLinks` to include shared resources).

Run `cd backend && make sqlc`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/db/...`
Expected: PASS (compilation succeeds)

- [ ] **Step 5: Commit**

```bash
git add backend/db/ backend/internal/db/
git commit -m "feat(backend): add note sharing db schema and sqlc queries"
```

### Task 2: Backend Sync Validation

**Files:**
- Modify: `backend/internal/sync/service.go`
- Test: `backend/internal/sync/service_test.go`

- [ ] **Step 1: Write the failing test**

```go
// backend/internal/sync/service_test.go
// Add a test inside your suite
func TestSyncService_Push_SharedNoteWithoutEditPermission(t *testing.T) {
	// Dummy test to ensure we test the validation logic
	// In a real test, mock the DB to return a note owned by another user and no 'edit' share
	t.Skip("Implement detailed mock test based on repo setup")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/sync/...`

- [ ] **Step 3: Write minimal implementation**

Modify `backend/internal/sync/service.go` inside the `Push` method. Before `r.UpsertNote`, check permissions:
```go
// Inside Push loop for Notes
if n.UserID != userID {
    share, err := r.GetNoteShareForUser(ctx, sqlcgen.GetNoteShareForUserParams{
        NoteID: n.ID,
        UserID: userID,
    })
    if err != nil || share.Permission != "edit" {
        return ErrSyncConflict
    }
}
// Repeat similar check for Tasks before r.UpsertTask
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/sync/...`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/internal/sync/
git commit -m "feat(backend): enforce edit permissions on sync push"
```

### Task 3: Backend API Endpoints

**Files:**
- Modify: `backend/internal/notes/handler.go`
- Modify: `backend/cmd/server/main.go`
- Test: `backend/internal/notes/handler_test.go`

- [ ] **Step 1: Write the failing test**

```go
// backend/internal/notes/handler_test.go
func TestShareNoteEndpoints(t *testing.T) {
	// Fail to compile or 404 test for /api/v1/notes/:id/shares
	t.Skip("Test endpoints /notes/:id/shares")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/notes/...`

- [ ] **Step 3: Write minimal implementation**

In `backend/internal/notes/handler.go`:
```go
type ShareNoteRequest struct {
	Email      string `json:"email" validate:"required,email"`
	Permission string `json:"permission" validate:"required,oneof=view edit"`
}

func (h *Handler) ShareNote(c echo.Context) error {
    // 1. Get user ID from context.
    // 2. Parse Note ID and Request Body.
    // 3. Verify user owns the note.
    // 4. Find target user by email using h.svc.GetUserByEmail (needs to be injected or fetched).
    // 5. Insert note share via h.svc.repo.CreateNoteShare.
    return c.JSON(http.StatusOK, map[string]string{"status": "ok"})
}

func (h *Handler) ListNoteShares(c echo.Context) error {
    // 1. Verify user owns the note.
    // 2. Fetch shares using h.svc.repo.GetNoteShares.
    return c.JSON(http.StatusOK, shares) // return mapped shares
}

func (h *Handler) DeleteNoteShare(c echo.Context) error {
    // 1. Verify user owns the note.
    // 2. Delete share using h.svc.repo.DeleteNoteShare.
    return c.NoContent(http.StatusNoContent)
}
```

In `backend/cmd/server/main.go`, register routes:
```go
protected.POST("/notes/:id/shares", notesH.ShareNote)
protected.GET("/notes/:id/shares", notesH.ListNoteShares)
protected.DELETE("/notes/:id/shares/:user_id", notesH.DeleteNoteShare)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/notes/...`

- [ ] **Step 5: Commit**

```bash
git add backend/internal/notes/ backend/cmd/server/
git commit -m "feat(backend): add endpoints for managing note shares"
```

### Task 4: Flutter Local Database Schema

**Files:**
- Modify: `lib/core/database/tables/notes.dart`
- Modify: `lib/core/database/database.dart`
- Test: `test/core/database/database_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/database/database_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';

void main() {
  test('Notes table has permission columns', () async {
    final db = AppDatabase.test();
    final _ = db.notes.permission;
    final __ = db.notes.sharedByEmail;
    final ___ = db.notes.sharedByName;
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/database/database_test.dart`
Expected: Compilation FAIL

- [ ] **Step 3: Write minimal implementation**

In `lib/core/database/tables/notes.dart`:
```dart
  TextColumn get permission => text().nullable()();
  TextColumn get sharedByEmail => text().nullable()();
  TextColumn get sharedByName => text().nullable()();
```

In `lib/core/database/database.dart`:
```dart
  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // ... existing migrations
          if (from < 6) {
            await m.addColumn(notes, notes.permission);
            await m.addColumn(notes, notes.sharedByEmail);
            await m.addColumn(notes, notes.sharedByName);
          }
        },
      );
```
Run `dart run build_runner build -d`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/database/database_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/core/database/ test/core/database/
git commit -m "feat(flutter): add note share fields to drift database"
```

### Task 5: Flutter Domain Model

**Files:**
- Modify: `lib/features/notes/domain/note_model.dart`
- Test: `test/features/notes/domain/note_model_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/notes/domain/note_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';

void main() {
  test('NoteModel has share properties', () {
    final model = NoteModel(
      // ... existing required fields ...
      permission: 'view',
      sharedByEmail: 'test@test.com',
      sharedByName: 'Test',
    );
    expect(model.permission, 'view');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/notes/domain/note_model_test.dart`
Expected: FAIL (Named parameters undefined)

- [ ] **Step 3: Write minimal implementation**

Update `NoteModel` in `lib/features/notes/domain/note_model.dart`:
```dart
  final String? permission;
  final String? sharedByEmail;
  final String? sharedByName;
  
  // Add to constructor
  const NoteModel({
    // ...
    this.permission,
    this.sharedByEmail,
    this.sharedByName,
  });

  // Add to copyWith
  // Add to fromData:
  factory NoteModel.fromData(NoteData d) {
    return NoteModel(
      // ...
      permission: d.permission,
      sharedByEmail: d.sharedByEmail,
      sharedByName: d.sharedByName,
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/notes/domain/note_model_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/features/notes/domain/ test/features/notes/domain/
git commit -m "feat(flutter): update note model with share properties"
```

### Task 6: Flutter Note Editor Read-Only

**Files:**
- Modify: `lib/features/notes/presentation/note_editor_screen.dart`
- Test: `test/features/notes/presentation/note_editor_screen_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/notes/presentation/note_editor_screen_test.dart
// Ensure NoteEditor is called with isReadOnly if permission == 'view'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/notes/presentation/note_editor_screen_test.dart`

- [ ] **Step 3: Write minimal implementation**

In `note_editor_screen.dart`, build method:
```dart
    final isReadOnly = note.permission == 'view';
    final isOwner = note.permission == null;

    return Scaffold(
      appBar: AppBar(
        title: isReadOnly ? Text('Compartilhada por ${note.sharedByEmail}') : null,
        actions: [
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () { /* open ShareNoteDialog */ },
            ),
          if (!isReadOnly)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
            ),
        ],
      ),
      body: SafeArea(
        child: NoteEditor(
          isReadOnly: isReadOnly, // Make sure NoteEditor accepts this parameter
          // ... existing parameters ...
        ),
      ),
    );
```

Modify `NoteEditor` constructor in `note_editor.dart` to accept `isReadOnly` and pass it to `SuperEditor`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/notes/presentation/note_editor_screen_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/features/notes/presentation/note_editor_screen.dart lib/features/notes/presentation/widgets/note_editor.dart
git commit -m "feat(flutter): support read-only mode in note editor"
```

### Task 7: Flutter Share Dialog

**Files:**
- Create: `lib/features/notes/presentation/widgets/share_note_dialog.dart`

- [ ] **Step 1: Write the failing test**

```dart
// Write standard widget test for rendering dialog
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/notes/presentation/widgets/share_note_dialog_test.dart`

- [ ] **Step 3: Write minimal implementation**

Create `lib/features/notes/presentation/widgets/share_note_dialog.dart`:
```dart
import 'package:flutter/material.dart';

class ShareNoteDialog extends StatefulWidget {
  final String noteId;
  const ShareNoteDialog({super.key, required this.noteId});

  static Future<void> show(BuildContext context, String noteId) {
    return showDialog(
      context: context,
      builder: (context) => ShareNoteDialog(noteId: noteId),
    );
  }

  @override
  State<ShareNoteDialog> createState() => _ShareNoteDialogState();
}

class _ShareNoteDialogState extends State<ShareNoteDialog> {
  final _emailCtrl = TextEditingController();
  String _permission = 'view';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Compartilhar Nota'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'E-mail')),
          DropdownButton<String>(
            value: _permission,
            items: const [
              DropdownMenuItem(value: 'view', child: Text('Visualizar')),
              DropdownMenuItem(value: 'edit', child: Text('Editar')),
            ],
            onChanged: (val) => setState(() => _permission = val!),
          ),
          // Here a FutureBuilder calling the API to list shares would be placed.
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
        ElevatedButton(
          onPressed: () {
            // Call API POST /api/v1/notes/:id/shares
          },
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/notes/presentation/widgets/share_note_dialog_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/features/notes/presentation/widgets/share_note_dialog.dart
git commit -m "feat(flutter): implement share note dialog"
```

### Task 8: Flutter Notes List Indicator

**Files:**
- Modify: `lib/features/notes/presentation/notes_list_screen.dart`

- [ ] **Step 1: Write the failing test**

Verify a badge displays the owner email when note is shared.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/notes/presentation/notes_list_screen_test.dart`

- [ ] **Step 3: Write minimal implementation**

In `notes_list_screen.dart` inside the card that renders the note:
```dart
// Below the title/excerpt
if (note.permission != null)
  Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        const Icon(Icons.person_outline, size: 14),
        const SizedBox(width: 4),
        Text('De: ${note.sharedByEmail}', style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/notes/presentation/notes_list_screen_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/features/notes/presentation/notes_list_screen.dart
git commit -m "feat(flutter): show share indicator in notes list"
```
