# Note Sharing and Collaboration Integration Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create integration tests on both backend (Go) and frontend (Flutter) that verify a note can be created, shared with another user, modified by that user, and synced back to the original owner.

**Architecture:** 
- **Backend:** Create an Echo handler integration test with `httptest` using an in-memory repository mock that simulates database state persistence (notes, shares, note nodes) across consecutive calls.
- **Frontend:** Create a widget integration test utilizing `AppDatabase.test()` in-memory SQLite database, rendering `NoteEditorScreen`, and simulating remote edits from collaborator User B to verify the UI reactively updates.

**Tech Stack:** Go (Echo, httptest), Flutter (flutter_test, Riverpod, Drift)

---

### Task 1: Backend Collaboration Integration Test

**Files:**
- Create: `backend/internal/sync/collab_integration_test.go`

- [ ] **Step 1: Write the integration test and mock repository**
  Create `backend/internal/sync/collab_integration_test.go` with the integration test setup. The mock repository will initially have hardcoded empty/error returns so that the test fails.

  ```go
  package sync_test

  import (
  	"bytes"
  	"context"
  	"encoding/json"
  	"net/http"
  	"net/http/httptest"
  	"testing"
  	"time"

  	"github.com/go-playground/validator/v10"
  	"github.com/jackc/pgx/v5"
  	"github.com/jackc/pgx/v5/pgtype"
  	"github.com/labstack/echo/v4"
  	"github.com/stretchr/testify/assert"

  	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
  	"github.com/RigleyC/supanotes/internal/shares"
  	"github.com/RigleyC/supanotes/internal/sync"
  	"github.com/RigleyC/supanotes/internal/web"
  )

  type inMemoryDB struct {
  	users      map[pgtype.UUID]sqlcgen.User
  	notes      map[pgtype.UUID]sqlcgen.Note
  	noteNodes  map[string][]sqlcgen.NoteNode // noteID string -> nodes
  	noteShares map[pgtype.UUID][]sqlcgen.NoteShare
  }

  type testValidator struct {
  	v *validator.Validate
  }

  func (tv *testValidator) Validate(i any) error {
  	return tv.v.Struct(i)
  }

  type mockCollabRepository struct {
  	db *inMemoryDB
  }

  func (m *mockCollabRepository) GetSyncNotes(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.GetSyncNotesRow, error) {
  	// Step 1: Return empty to force failure
  	return nil, nil
  }

  func (m *mockCollabRepository) UpsertNote(ctx context.Context, arg sqlcgen.UpsertNoteParams) (sqlcgen.Note, error) {
  	return sqlcgen.Note{}, nil
  }

  func (m *mockCollabRepository) GetInboxNote(ctx context.Context, userID pgtype.UUID) (sqlcgen.GetInboxNoteRow, error) {
  	return sqlcgen.GetInboxNoteRow{}, pgx.ErrNoRows
  }

  func (m *mockCollabRepository) GetSyncTasks(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.Task, error) {
  	return nil, nil
  }

  func (m *mockCollabRepository) UpsertTask(ctx context.Context, arg sqlcgen.UpsertTaskParams) (sqlcgen.Task, error) {
  	return sqlcgen.Task{}, nil
  }

  func (m *mockCollabRepository) GetSyncContexts(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.Context, error) {
  	return nil, nil
  }

  func (m *mockCollabRepository) UpsertContext(ctx context.Context, arg sqlcgen.UpsertContextParams) (sqlcgen.Context, error) {
  	return sqlcgen.Context{}, nil
  }

  func (m *mockCollabRepository) GetSyncTags(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.Tag, error) {
  	return nil, nil
  }

  func (m *mockCollabRepository) UpsertTag(ctx context.Context, arg sqlcgen.UpsertTagParams) (sqlcgen.Tag, error) {
  	return sqlcgen.Tag{}, nil
  }

  func (m *mockCollabRepository) GetSyncTaskCompletions(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.TaskCompletion, error) {
  	return nil, nil
  }

  func (m *mockCollabRepository) UpsertTaskCompletion(ctx context.Context, arg sqlcgen.UpsertTaskCompletionParams) error {
  	return nil
  }

  func (m *mockCollabRepository) GetSyncNoteTags(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.NoteTag, error) {
  	return nil, nil
  }

  func (m *mockCollabRepository) UpsertNoteTag(ctx context.Context, arg sqlcgen.UpsertNoteTagParams) error {
  	return nil
  }

  func (m *mockCollabRepository) GetSyncNoteLinks(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.NoteLink, error) {
  	return nil, nil
  }

  func (m *mockCollabRepository) UpsertNoteLink(ctx context.Context, arg sqlcgen.UpsertNoteLinkParams) error {
  	return nil
  }

  func (m *mockCollabRepository) GetSyncUserNotePreferences(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.UserNotePreference, error) {
  	return nil, nil
  }

  func (m *mockCollabRepository) UpsertUserNotePreference(ctx context.Context, arg sqlcgen.UpsertUserNotePreferenceParams) (sqlcgen.UserNotePreference, error) {
  	return sqlcgen.UserNotePreference{}, nil
  }

  func (m *mockCollabRepository) GetNoteOwnerID(ctx context.Context, noteID pgtype.UUID) (pgtype.UUID, error) {
  	if n, ok := m.db.notes[noteID]; ok {
  		return n.UserID, nil
  	}
  	return pgtype.UUID{}, pgx.ErrNoRows
  }

  func (m *mockCollabRepository) GetNoteOwner(ctx context.Context, noteID pgtype.UUID) (pgtype.UUID, error) {
  	return m.GetNoteOwnerID(ctx, noteID)
  }

  func (m *mockCollabRepository) GetSyncNoteNodes(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.NoteNode, error) {
  	return nil, nil
  }

  func (m *mockCollabRepository) UpsertNoteNode(ctx context.Context, arg sqlcgen.UpsertNoteNodeParams) (sqlcgen.NoteNode, error) {
  	return sqlcgen.NoteNode{}, nil
  }

  func (m *mockCollabRepository) GetNoteByID(ctx context.Context, arg sqlcgen.GetNoteByIDParams) (sqlcgen.GetNoteByIDRow, error) {
  	if n, ok := m.db.notes[arg.ID]; ok {
  		return sqlcgen.GetNoteByIDRow{ID: n.ID, UserID: n.UserID}, nil
  	}
  	return sqlcgen.GetNoteByIDRow{}, pgx.ErrNoRows
  }

  func (m *mockCollabRepository) GetNoteShareForUser(ctx context.Context, arg sqlcgen.GetNoteShareForUserParams) (sqlcgen.NoteShare, error) {
  	sharesList := m.db.noteShares[arg.NoteID]
  	for _, s := range sharesList {
  		if s.UserID == arg.UserID {
  			return s, nil
  		}
  	}
  	return sqlcgen.NoteShare{}, pgx.ErrNoRows
  }

  func (m *mockCollabRepository) GetUserByEmail(ctx context.Context, email string) (sqlcgen.User, error) {
  	for _, u := range m.db.users {
  		if u.Email == email {
  			return u, nil
  		}
  	}
  	return sqlcgen.User{}, pgx.ErrNoRows
  }

  func (m *mockCollabRepository) CreateNoteShare(ctx context.Context, arg sqlcgen.CreateNoteShareParams) (sqlcgen.NoteShare, error) {
  	ns := sqlcgen.NoteShare{
  		ID:         pgtype.UUID{Bytes: [16]byte{9, 9, 9}, Valid: true},
  		NoteID:     arg.NoteID,
  		UserID:     arg.UserID,
  		Permission: arg.Permission,
  	}
  	m.db.noteShares[arg.NoteID] = append(m.db.noteShares[arg.NoteID], ns)
  	return ns, nil
  }

  func (m *mockCollabRepository) GetNoteShares(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.GetNoteSharesRow, error) {
  	return nil, nil
  }

  func (m *mockCollabRepository) DeleteNoteShare(ctx context.Context, arg sqlcgen.DeleteNoteShareParams) error {
  	return nil
  }

  func (m *mockCollabRepository) UpdateNotesContentFromNodes(ctx context.Context, noteIDs []pgtype.UUID) error {
  	return nil
  }

  func (m *mockCollabRepository) WithQuerier(q sqlcgen.Querier) sync.Repository {
  	return m
  }

  func TestNoteSharingAndCollaborationIntegration(t *testing.T) {
  	userA := sqlcgen.User{
  		ID:    pgtype.UUID{Bytes: [16]byte{1}, Valid: true},
  		Email: "userA@example.com",
  		Name:  "User A",
  	}
  	userB := sqlcgen.User{
  		ID:    pgtype.UUID{Bytes: [16]byte{2}, Valid: true},
  		Email: "userB@example.com",
  		Name:  "User B",
  	}

  	db := &inMemoryDB{
  		users: map[pgtype.UUID]sqlcgen.User{
  			userA.ID: userA,
  			userB.ID: userB,
  		},
  		notes:      make(map[pgtype.UUID]sqlcgen.Note),
  		noteNodes:  make(map[string][]sqlcgen.NoteNode),
  		noteShares: make(map[pgtype.UUID][]sqlcgen.NoteShare),
  	}

  	repo := &mockCollabRepository{db: db}

  	syncSvc := sync.NewService(repo, nil)
  	syncH := sync.NewHandler(syncSvc)

  	sharesSvc := shares.NewService(repo)
  	sharesH := shares.NewHandler(sharesSvc)

  	e := echo.New()
  	e.HideBanner = true
  	e.Validator = &testValidator{v: validator.New(validator.WithRequiredStructEnabled())}

  	var currentMockUserID pgtype.UUID
  	e.Use(func(next echo.HandlerFunc) echo.HandlerFunc {
  		return func(c echo.Context) error {
  			web.SetUserID(c, currentMockUserID.Bytes)
  			return next(c)
  		}
  	})

  	e.POST("/api/v1/sync/push", syncH.Push)
  	e.POST("/api/v1/sync/pull", syncH.Pull)
  	e.POST("/api/v1/notes/:id/shares", sharesH.ShareNote)

  	noteID := pgtype.UUID{Bytes: [16]byte{3}, Valid: true}
  	nodeID := pgtype.UUID{Bytes: [16]byte{4}, Valid: true}

  	// Step 2.1: User A pushes note-1 and node-1
  	currentMockUserID = userA.ID
  	pushPayload := sync.SyncPayload{
  		Notes: []sqlcgen.GetSyncNotesRow{
  			{
  				ID:     noteID,
  				UserID: userA.ID,
  			},
  		},
  		NoteNodes: []sqlcgen.NoteNode{
  			{
  				ID:     nodeID,
  				NoteID: noteID,
  				Type:   "paragraph",
  				Data:   `{"text":"Hello from User A"}`,
  			},
  		},
  	}

  	pushBody, _ := json.Marshal(pushPayload)
  	reqPush := httptest.NewRequest(http.MethodPost, "/api/v1/sync/push", bytes.NewReader(pushBody))
  	reqPush.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
  	recPush := httptest.NewRecorder()
  	e.ServeHTTP(recPush, reqPush)
  	assert.Equal(t, http.StatusOK, recPush.Code)

  	// Step 2.2: User A shares note-1 with User B
  	shareReq := shares.ShareNoteRequest{
  		Email:      "userB@example.com",
  		Permission: "edit",
  	}
  	shareBody, _ := json.Marshal(shareReq)
  	reqShare := httptest.NewRequest(http.MethodPost, "/api/v1/notes/03000000-0000-0000-0000-000000000000/shares", bytes.NewReader(shareBody))
  	reqShare.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
  	recShare := httptest.NewRecorder()
  	e.ServeHTTP(recShare, reqShare)
  	assert.Equal(t, http.StatusCreated, recShare.Code)

  	// Step 2.3: User B pulls note-1
  	currentMockUserID = userB.ID
  	pullReqBody := sync.PullRequest{
  		LastSyncedAt: time.Time{},
  		Limit:        100,
  	}
  	pullBody, _ := json.Marshal(pullReqBody)
  	reqPull := httptest.NewRequest(http.MethodPost, "/api/v1/sync/pull", bytes.NewReader(pullBody))
  	reqPull.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
  	recPull := httptest.NewRecorder()
  	e.ServeHTTP(recPull, reqPull)
  	assert.Equal(t, http.StatusOK, recPull.Code)

  	var pullPayload sync.SyncPayload
  	err := json.Unmarshal(recPull.Body.Bytes(), &pullPayload)
  	assert.NoError(t, err)
  	
  	// Assert note is present in pull for User B
  	assert.NotEmpty(t, pullPayload.Notes, "User B should have received shared note on sync pull")
  }
  ```

- [ ] **Step 2: Run test to verify it fails**
  Run the backend test. It should fail because the mock repository returns `nil` for notes during `GetSyncNotes`.

  Run command:
  ```powershell
  cd backend; go test -v ./internal/sync -run TestNoteSharingAndCollaborationIntegration
  ```
  Expected Output: Fail on assertion `assert.NotEmpty(t, pullPayload.Notes)`

- [ ] **Step 3: Implement the correct mock repository behavior**
  Update the mock repository methods in `backend/internal/sync/collab_integration_test.go` to properly store and retrieve notes, shares, and note nodes from `inMemoryDB`:

  ```go
  func (m *mockCollabRepository) GetSyncNotes(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.GetSyncNotesRow, error) {
  	var result []sqlcgen.GetSyncNotesRow
  	for _, n := range m.db.notes {
  		// Check ownership or share
  		isOwner := n.UserID == userID
  		hasShare := false
  		sharesList := m.db.noteShares[n.ID]
  		for _, s := range sharesList {
  			if s.UserID == userID {
  				hasShare = true
  			}
  		}

  		if isOwner || hasShare {
  			result = append(result, sqlcgen.GetSyncNotesRow{
  				ID:        n.ID,
  				UserID:    n.UserID,
  				CreatedAt: n.CreatedAt,
  				UpdatedAt: n.UpdatedAt,
  			})
  		}
  	}
  	return result, nil
  }

  func (m *mockCollabRepository) UpsertNote(ctx context.Context, arg sqlcgen.UpsertNoteParams) (sqlcgen.Note, error) {
  	note := sqlcgen.Note{
  		ID:        arg.ID,
  		UserID:    arg.UserID,
  		CreatedAt: arg.CreatedAt,
  		UpdatedAt: pgtype.Timestamptz{Time: time.Now(), Valid: true},
  	}
  	m.db.notes[arg.ID] = note
  	return note, nil
  }

  func (m *mockCollabRepository) GetSyncNoteNodes(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.NoteNode, error) {
  	var result []sqlcgen.NoteNode
  	for noteIDStr, nodes := range m.db.noteNodes {
  		noteID, _ := uid.UUIDFromString(noteIDStr)
  		// Check ownership or share
  		n, exists := m.db.notes[noteID]
  		if !exists {
  			continue
  		}
  		isOwner := n.UserID == userID
  		hasShare := false
  		sharesList := m.db.noteShares[noteID]
  		for _, s := range sharesList {
  			if s.UserID == userID {
  				hasShare = true
  			}
  		}

  		if isOwner || hasShare {
  			result = append(result, nodes...)
  		}
  	}
  	return result, nil
  }

  func (m *mockCollabRepository) UpsertNoteNode(ctx context.Context, arg sqlcgen.UpsertNoteNodeParams) (sqlcgen.NoteNode, error) {
  	node := sqlcgen.NoteNode{
  		ID:        arg.ID,
  		NoteID:    arg.NoteID,
  		Type:      arg.Type,
  		Data:      arg.Data,
  		CreatedAt: arg.CreatedAt,
  		UpdatedAt: pgtype.Timestamptz{Time: time.Now(), Valid: true},
  	}
  	noteIDStr := uid.UUIDToString(arg.NoteID)
  	nodes := m.db.noteNodes[noteIDStr]
  	found := false
  	for i, n := range nodes {
  		if n.ID == arg.ID {
  			nodes[i] = node
  			found = true
  			break
  		}
  	}
  	if !found {
  		nodes = append(nodes, node)
  	}
  	m.db.noteNodes[noteIDStr] = nodes
  	return node, nil
  }
  ```

  Also, extend the test function `TestNoteSharingAndCollaborationIntegration` to complete steps 4, 5, and 6:
  ```go
  	// Step 2.4: User B modifies note-1
  	currentMockUserID = userB.ID
  	pushPayloadB := sync.SyncPayload{
  		Notes: []sqlcgen.GetSyncNotesRow{},
  		NoteNodes: []sqlcgen.NoteNode{
  			{
  				ID:     nodeID,
  				NoteID: noteID,
  				Type:   "paragraph",
  				Data:   `{"text":"Hello from User B (collaborator)"}`,
  			},
  		},
  	}
  	pushBodyB, _ := json.Marshal(pushPayloadB)
  	reqPushB := httptest.NewRequest(http.MethodPost, "/api/v1/sync/push", bytes.NewReader(pushBodyB))
  	reqPushB.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
  	recPushB := httptest.NewRecorder()
  	e.ServeHTTP(recPushB, reqPushB)
  	assert.Equal(t, http.StatusOK, recPushB.Code)

  	// Step 2.5: User A pulls and verifies content
  	currentMockUserID = userA.ID
  	reqPullA := httptest.NewRequest(http.MethodPost, "/api/v1/sync/pull", bytes.NewReader(pullBody))
  	reqPullA.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
  	recPullA := httptest.NewRecorder()
  	e.ServeHTTP(recPullA, reqPullA)
  	assert.Equal(t, http.StatusOK, recPullA.Code)

  	var pullPayloadA sync.SyncPayload
  	err = json.Unmarshal(recPullA.Body.Bytes(), &pullPayloadA)
  	assert.NoError(t, err)

  	assert.NotEmpty(t, pullPayloadA.NoteNodes)
  	assert.Equal(t, `{"text":"Hello from User B (collaborator)"}`, pullPayloadA.NoteNodes[0].Data)
  ```

- [ ] **Step 4: Run the test to verify it passes**
  Run the test again.

  Run command:
  ```powershell
  cd backend; go test -v ./internal/sync -run TestNoteSharingAndCollaborationIntegration
  ```
  Expected Output: `PASS`

- [ ] **Step 5: Commit**
  ```bash
  git add backend/internal/sync/collab_integration_test.go
  git commit -m "test(sync): add backend collaboration sync and sharing integration test"
  ```

---

### Task 2: Frontend Collaboration Widget Integration Test

**Files:**
- Create: `test/features/notes/presentation/note_editor_collab_test.dart`

- [ ] **Step 1: Write the widget test using AppDatabase.test()**
  Create `test/features/notes/presentation/note_editor_collab_test.dart`. It will set up the DB, load the note editor screen with "Original content from User A".

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:shared_preferences/shared_preferences.dart';
  import 'package:drift/drift.dart' hide isNull, isNotNull;
  import 'package:mocktail/mocktail.dart';

  import 'package:supanotes/core/auth/current_user.dart';
  import 'package:supanotes/core/database/database.dart';
  import 'package:supanotes/features/notes/presentation/note_editor_screen.dart';
  import 'package:supanotes/features/tasks/data/tasks_repository.dart';

  class _MockTasksRepository extends Mock implements ITasksRepository {}

  void main() {
    late AppDatabase db;
    late _MockTasksRepository mockTasksRepo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.test();
      mockTasksRepo = _MockTasksRepository();
      when(() => mockTasksRepo.watchByNote(any())).thenAnswer((_) => Stream.value([]));
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('dynamic content update when other user edits note', (WidgetTester tester) async {
      final now = DateTime.now().toUtc();
      
      // Seed initial note and node
      await db.into(db.notes).insert(
        NotesCompanion.insert(
          id: 'note-1',
          userId: 'user-A',
          content: '',
          createdAt: now,
          updatedAt: now,
          isDirty: const Value(false),
          hasRemoteCopy: const Value(true),
        ),
      );

      await db.into(db.noteNodes).insert(
        NoteNodesCompanion.insert(
          id: 'node-1',
          noteId: 'note-1',
          position: 0.0,
          type: 'paragraph',
          data: '{"text":"Original content from User A"}',
          createdAt: now,
          updatedAt: now,
          isDirty: const Value(false),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            currentUserIdProvider.overrideWithValue('user-A'),
            tasksRepositoryProvider.overrideWithValue(mockTasksRepo),
          ],
          child: const MaterialApp(
            home: NoteEditorScreen(noteId: 'note-1'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check initial text is rendered
      expect(find.text('Original content from User A'), findsWidgets);

      // Verify that "Updated content from User B" does NOT exist yet
      expect(find.text('Updated content from User B'), findsNothing);
    });
  }
  ```

- [ ] **Step 2: Run the test to verify it fails**
  Run the test. It should pass the check that original content is found, but we want to assert that updating updates it. Let's make the test fail by asserting `"Updated content from User B"` should be found (before we actually update the db).

  Add to test function:
  ```dart
      expect(find.text('Updated content from User B'), findsOneWidget);
  ```

  Run command:
  ```powershell
  flutter test test/features/notes/presentation/note_editor_collab_test.dart
  ```
  Expected Output: Fail because `"Updated content from User B"` is not found.

- [ ] **Step 3: Simulate the database node update**
  Replace the failing assertion with the DB update statement and the correct assertion:

  ```dart
      // Seed update from collaborator User B
      await db.into(db.noteNodes).insertOnConflictUpdate(
        NoteNodesCompanion.insert(
          id: 'node-1',
          noteId: 'note-1',
          position: 0.0,
          type: 'paragraph',
          data: '{"text":"Updated content from User B"}',
          createdAt: now,
          updatedAt: now.add(const Duration(seconds: 1)),
          isDirty: const Value(false),
        ),
      );

      await tester.pumpAndSettle();

      // Verify that the UI updated reactively to show User B's content
      expect(find.text('Updated content from User B'), findsWidgets);
      expect(find.text('Original content from User A'), findsNothing);
  ```

- [ ] **Step 4: Run the test to verify it passes**
  Run the test again.

  Run command:
  ```powershell
  flutter test test/features/notes/presentation/note_editor_collab_test.dart
  ```
  Expected Output: `All tests passed!`

- [ ] **Step 5: Commit**
  ```bash
  git add test/features/notes/presentation/note_editor_collab_test.dart
  git commit -m "test(notes): add frontend widget integration test for collaboration content updates"
  ```
