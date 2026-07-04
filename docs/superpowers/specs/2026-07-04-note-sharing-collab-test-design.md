# Design Spec: Note Sharing and Collaboration Integration Tests

This specification outlines the integration test design for testing note creation, sharing, real-time sync simulation, and concurrent modifications across both backend (Go) and frontend (Flutter) environments in SupaNotes.

## Goal

To verify the complete note collaboration pipeline. When User A creates a note and shares it with User B (with edit permission), User B should be able to write to the note via sync push. User A should receive these edits on their subsequent sync pull, and the Flutter UI should dynamically update to display the modified content.

---

## 1. Backend Integration Test Design

### Location
[collab_integration_test.go](file:///c:/Users/rigleyc/projects/supanotes/backend/internal/sync/collab_integration_test.go)

### Setup
We will set up an in-memory database simulation (`inMemoryDB`) within the test file to avoid requiring a live PostgreSQL instance.

```go
type inMemoryDB struct {
    users      map[pgtype.UUID]sqlcgen.User
    notes      map[pgtype.UUID]sqlcgen.Note
    noteNodes  map[pgtype.UUID][]sqlcgen.NoteNode
    noteShares map[pgtype.UUID][]sqlcgen.NoteShare
}
```

A mock repository implementing both `sync.Repository` and `shares.Repository` will read and write to this `inMemoryDB`.

### HTTP Routing & Handlers
An Echo HTTP server will be instantiated mounting:
- `POST /api/v1/sync/push` -> `sync.Handler.Push`
- `POST /api/v1/sync/pull` -> `sync.Handler.Pull`
- `POST /api/v1/notes/:id/shares` -> `shares.Handler.ShareNote`

### Test Flow
1. **User Setup**: Create User A (`user_a_id`) and User B (`user_b_id`) in `inMemoryDB`.
2. **Note Creation (User A)**:
   - Call `POST /api/v1/sync/push` with User A's credentials.
   - Payload contains a new note `note-1` and a node `node-1` with text `"Hello from User A"`.
   - Verify the note and node are saved in `inMemoryDB` under User A.
3. **Sharing**:
   - Call `POST /api/v1/notes/note-1/shares` with User A's credentials.
   - Body: `{"email": "userB@example.com", "permission": "edit"}`.
   - Verify a share entry is created in `inMemoryDB` allowing User B to edit `note-1`.
4. **Pull (User B)**:
   - Call `POST /api/v1/sync/pull` with User B's credentials.
   - Verify that `note-1` and `node-1` are returned in the sync response payload.
5. **Modification (User B)**:
   - Call `POST /api/v1/sync/push` with User B's credentials.
   - Payload contains updated `node-1` with text `"Hello from User B (collaborator)"`.
   - Verify backend accepts the write because User B has edit permission, updating `inMemoryDB`.
6. **Verification (User A)**:
   - Call `POST /api/v1/sync/pull` with User A's credentials.
   - Verify that the returned `node-1` content is indeed `"Hello from User B (collaborator)"`.

---

## 2. Frontend Integration Test Design

### Location
[note_editor_collab_test.dart](file:///c:/Users/rigleyc/projects/supanotes/test/features/notes/presentation/note_editor_collab_test.dart)

### Setup
We will test using the actual `NotesRepository` and widgets but backed by a real, local SQLite database running in memory via `AppDatabase.test()`.

```dart
final db = AppDatabase.test();
```

We will override:
- `appDatabaseProvider` with the in-memory database instance.
- `currentUserIdProvider` with `"user-A"`.

### Test Flow
1. **Local Database Seed**:
   - Seed `db.notes` with `note-1` belonging to `user-A`.
   - Seed `db.noteNodes` with `node-1` containing text `"Original content from User A"`.
2. **Render UI**:
   - Pump `NoteEditorScreen(noteId: 'note-1')`.
   - Verify the UI is displaying `"Original content from User A"` inside the editor view.
3. **Simulate User B Write**:
   - Directly insert/update `node-1` in `db.noteNodes` with text `"Updated content from User B"`.
   - This simulates what `SyncService` does when it receives new/updated nodes from the remote backend.
4. **Reactive UI Verification**:
   - Call `tester.pumpAndSettle()`.
   - Verify that the editor screen automatically reacts to the database change and renders `"Updated content from User B"` without page refresh.
