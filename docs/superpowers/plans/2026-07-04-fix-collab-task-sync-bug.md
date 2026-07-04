# Fix Collaboration Task Sync Bug Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the 409 conflict when a collaborator adds or edits a task inside a shared note.

**Root Cause:**
1. The database query `UpsertTask` has a `WHERE tasks.user_id = EXCLUDED.user_id` constraint.
2. When collaborator User B pushes edits to a task created by User A, the client sends User B's ID as the task's `user_id`.
3. The conflict update fails on the query constraint, returning `ErrNoRows` (no rows in result set), which the server maps to a `409 Conflict`.
4. The backend service lacks proper check on parent note edit permission for tasks during sync push.

**Solution:**
1. Remove `WHERE tasks.user_id = EXCLUDED.user_id` from `UpsertTask` in `backend/db/queries/sync.sql`.
2. Regenerate sqlc code with `make sqlc`.
3. Add a Go-level parent note edit authorization check to `service.go` when processing `payload.Tasks`.

---

### Task 1: Add Reproducing Test Case (TDD RED)

**Files:**
- Modify: `backend/internal/sync/collab_integration_test.go`

- [ ] **Step 1: Update inMemoryDB and Mock Repository**
  Modify `backend/internal/sync/collab_integration_test.go` to add `tasks` map to `inMemoryDB`, implement `GetSyncTasks` and `UpsertTask` (reproducing the db security constraint in the mock).

  ```go
  // Update inMemoryDB in collab_integration_test.go:
  type inMemoryDB struct {
  	users      map[pgtype.UUID]sqlcgen.User
  	notes      map[pgtype.UUID]sqlcgen.Note
  	noteNodes  map[pgtype.UUID]sqlcgen.NoteNode
  	noteShares map[pgtype.UUID][]sqlcgen.NoteShare
  	tasks      map[pgtype.UUID]sqlcgen.Task // Add tasks map
  }
  ```

  And mock methods:
  ```go
  func (m *mockCollabRepository) GetSyncTasks(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.Task, error) {
  	accessibleNotes := make(map[pgtype.UUID]bool)
  	for _, n := range m.db.notes {
  		isOwner := n.UserID == userID
  		isShared := false
  		if !isOwner {
  			sharesList := m.db.noteShares[n.ID]
  			for _, s := range sharesList {
  				if s.UserID == userID {
  					isShared = true
  					break
  				}
  			}
  		}
  		if isOwner || isShared {
  			accessibleNotes[n.ID] = true
  		}
  	}

  	var tasks []sqlcgen.Task
  	for _, t := range m.db.tasks {
  		if accessibleNotes[t.NoteID] {
  			tasks = append(tasks, t)
  		}
  	}
  	return tasks, nil
  }

  func (m *mockCollabRepository) UpsertTask(ctx context.Context, arg sqlcgen.UpsertTaskParams) (sqlcgen.Task, error) {
  	// Simulate the security check "WHERE tasks.user_id = EXCLUDED.user_id"
  	existing, exists := m.db.tasks[arg.ID]
  	if exists && existing.UserID != arg.UserID {
  		return sqlcgen.Task{}, pgx.ErrNoRows
  	}

  	t := sqlcgen.Task{
  		ID:         arg.ID,
  		UserID:     arg.UserID,
  		NoteID:     arg.NoteID,
  		Title:      arg.Title,
  		Status:     arg.Status,
  		Position:   arg.Position,
  		Recurrence: arg.Recurrence,
  		DueDate:    arg.DueDate,
  		CreatedAt:  arg.CreatedAt,
  		UpdatedAt:  pgtype.Timestamptz{Time: time.Now(), Valid: true},
  		DeletedAt:  arg.DeletedAt,
  	}
  	m.db.tasks[arg.ID] = t
  	return t, nil
  }
  ```

- [ ] **Step 2: Add Collaborator Task Update Test Scenario**
  Append a collaborator task editing step to `TestNoteSharingAndCollaborationIntegration` in `backend/internal/sync/collab_integration_test.go`:

  ```go
  	// User A creates a task on note-1
  	taskID := pgtype.UUID{Bytes: [16]byte{5}, Valid: true}
  	pushPayloadTask := sync.SyncPayload{
  		Tasks: []sync.SyncTask{
  			{
  				ID:     taskID,
  				UserID: userA.ID,
  				NoteID: noteID,
  				Title:  "Buy milk",
  				Status: "open",
  			},
  		},
  	}
  	pushBodyTask, _ := json.Marshal(pushPayloadTask)
  	reqPushTask := httptest.NewRequest(http.MethodPost, "/api/v1/sync/push", bytes.NewReader(pushBodyTask))
  	reqPushTask.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
  	recPushTask := httptest.NewRecorder()
  	e.ServeHTTP(recPushTask, reqPushTask)
  	assert.Equal(t, http.StatusOK, recPushTask.Code)

  	// User B pulls and receives the task
  	currentMockUserID = userB.ID
  	reqPullBTask := httptest.NewRequest(http.MethodPost, "/api/v1/sync/pull", bytes.NewReader(pullBody))
  	reqPullBTask.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
  	recPullBTask := httptest.NewRecorder()
  	e.ServeHTTP(recPullBTask, reqPullBTask)
  	assert.Equal(t, http.StatusOK, recPullBTask.Code)

  	var pullPayloadResultBTask sync.SyncPayload
  	json.Unmarshal(recPullBTask.Body.Bytes(), &pullPayloadResultBTask)
  	assert.NotEmpty(t, pullPayloadResultBTask.Tasks)

  	// User B (collaborator) edits User A's task (marks as done)
  	// The client sends the task with User B's user ID.
  	pushPayloadBTask := sync.SyncPayload{
  		Tasks: []sync.SyncTask{
  			{
  				ID:     taskID,
  				UserID: userB.ID, // Collaborator's ID
  				NoteID: noteID,
  				Title:  "Buy milk",
  				Status: "done",
  			},
  		},
  	}
  	pushBodyBTask, _ := json.Marshal(pushPayloadBTask)
  	reqPushBTask := httptest.NewRequest(http.MethodPost, "/api/v1/sync/push", bytes.NewReader(pushBodyBTask))
  	reqPushBTask.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
  	recPushBTask := httptest.NewRecorder()
  	e.ServeHTTP(recPushBTask, reqPushBTask)
  	
  	// We assert that the status code is 200 OK. Under the bug, this returns 409 Conflict.
  	assert.Equal(t, http.StatusOK, recPushBTask.Code)
  ```

- [ ] **Step 3: Run the test to verify it fails**
  Run the test. It should fail on `assert.Equal(t, http.StatusOK, recPushBTask.Code)` returning `409` instead of `200`.

  Run command:
  ```powershell
  cd backend; go test -v ./internal/sync -run TestNoteSharingAndCollaborationIntegration
  ```
  Expected Output: FAIL (returns 409 conflict).

---

### Task 2: Implement Backend Fixes (TDD GREEN)

**Files:**
- Modify: `backend/db/queries/sync.sql:56-70`
- Modify: `backend/internal/sync/service.go:273-305`
- Modify: `backend/internal/sync/collab_integration_test.go`

- [ ] **Step 1: Remove DB Constraint from UpsertTask**
  Modify `backend/db/queries/sync.sql` to remove `WHERE tasks.user_id = EXCLUDED.user_id` from the `UpsertTask` query.

  ```sql
  -- name: UpsertTask :one
  INSERT INTO tasks (id, user_id, note_id, title, status, position, recurrence, due_date, created_at, updated_at, deleted_at)
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW(), $10)
  ON CONFLICT (id) DO UPDATE
  SET note_id = EXCLUDED.note_id,
      title = EXCLUDED.title,
      status = EXCLUDED.status,
      position = EXCLUDED.position,
      recurrence = EXCLUDED.recurrence,
      due_date = EXCLUDED.due_date,
      updated_at = NOW(),
      deleted_at = EXCLUDED.deleted_at
  RETURNING *;
  ```

- [ ] **Step 2: Regenerate sqlc code**
  Run:
  ```powershell
  cd backend; make sqlc
  ```

- [ ] **Step 3: Add Authorization Check in service.go**
  Modify `backend/internal/sync/service.go` to add Go-level parent note authorization check in `Push` for each task:

  ```go
  	for _, st := range payload.Tasks {
  		t, err := fromSyncTask(st)
  		if err != nil {
  			return err
  		}

  		status := sanitizeTaskStatus(t.Status)

  		// Authorize task push by checking parent note edit permission
  		noteID := t.NoteID
  		canEdit, exists := editableNotes[noteID]
  		if !exists {
  			ownerID, err := r.GetNoteOwnerID(ctx, noteID)
  			if err != nil {
  				if errors.Is(err, pgx.ErrNoRows) {
  					share, shareErr := r.GetNoteShareForUser(ctx, sqlcgen.GetNoteShareForUserParams{
  						NoteID: noteID,
  						UserID: userID,
  					})
  					canEdit = shareErr == nil && share.Permission == "edit"
  				} else {
  					return err
  				}
  			} else {
  				canEdit = ownerID == userID
  				if !canEdit {
  					share, shareErr := r.GetNoteShareForUser(ctx, sqlcgen.GetNoteShareForUserParams{
  						NoteID: noteID,
  						UserID: userID,
  					})
  					canEdit = shareErr == nil && share.Permission == "edit"
  				}
  			}
  			editableNotes[noteID] = canEdit
  		}

  		if !canEdit {
  			log.Error().Interface("task_id", t.ID).Interface("note_id", noteID).Interface("user_id", userID).Msg("sync push conflict: user unauthorized to write task")
  			return ErrSyncConflict
  		}

  		upsertUserID := userID
  		if t.UserID != userID {
  			upsertUserID = t.UserID
  		}
  		_, err = r.UpsertTask(ctx, sqlcgen.UpsertTaskParams{
  			ID:         t.ID,
  			UserID:     upsertUserID,
  			NoteID:     t.NoteID,
  			Title:      t.Title,
  			Status:     status,
  			Position:   t.Position,
  			Recurrence: t.Recurrence,
  			DueDate:    t.DueDate,
  			CreatedAt:  t.CreatedAt,
  			DeletedAt:  t.DeletedAt,
  		})
  		if err != nil {
  			if errors.Is(err, pgx.ErrNoRows) {
  				log.Error().Interface("task_id", t.ID).Interface("note_id", t.NoteID).Interface("user_id", upsertUserID).Err(err).Msg("sync push conflict: UpsertTask returned ErrNoRows")
  				return ErrSyncConflict
  			}
  			return err
  		}
  	}
  ```

- [ ] **Step 4: Remove Mock DB Constraint from Test File**
  Remove the simulated constraint check `if exists && existing.UserID != arg.UserID` from `mockCollabRepository.UpsertTask` in `backend/internal/sync/collab_integration_test.go`.

- [ ] **Step 5: Run the test to verify it passes**
  Run the test. It should compile and pass successfully.

  Run command:
  ```powershell
  cd backend; go test -v ./internal/sync -run TestNoteSharingAndCollaborationIntegration
  ```
  Expected Output: `PASS`

- [ ] **Step 6: Commit all changes**
  ```bash
  git add backend/db/queries/sync.sql backend/internal/db/sqlcgen/ backend/internal/sync/
  git commit -m "fix(sync): allow collaborators to sync tasks within shared notes"
  ```
