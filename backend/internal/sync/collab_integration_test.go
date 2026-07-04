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
	"github.com/google/uuid"
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
	noteNodes  map[pgtype.UUID]sqlcgen.NoteNode
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
	var rows []sqlcgen.GetSyncNotesRow
	for _, n := range m.db.notes {
		isOwner := n.UserID == userID
		var sharedPerm string
		if !isOwner {
			sharesList := m.db.noteShares[n.ID]
			for _, s := range sharesList {
				if s.UserID == userID {
					sharedPerm = s.Permission
					break
				}
			}
		}

		if isOwner || sharedPerm != "" {
			var sharedByEmail, sharedByName string
			if sharedPerm != "" {
				owner, ok := m.db.users[n.UserID]
				if ok {
					sharedByEmail = owner.Email
					sharedByName = owner.Name
				}
			}
			rows = append(rows, sqlcgen.GetSyncNotesRow{
				ID:               n.ID,
				UserID:           n.UserID,
				ContextID:        n.ContextID,
				Content:          n.Content,
				IsInbox:          n.IsInbox,
				CreatedAt:        n.CreatedAt,
				UpdatedAt:        n.UpdatedAt,
				DeletedAt:        n.DeletedAt,
				EmbeddingStatus:  n.EmbeddingStatus,
				CollapseImages:   n.CollapseImages,
				SharedPermission: sharedPerm,
				SharedByEmail:    sharedByEmail,
				SharedByName:     sharedByName,
			})
		}
	}
	return rows, nil
}

func (m *mockCollabRepository) UpsertNote(ctx context.Context, arg sqlcgen.UpsertNoteParams) (sqlcgen.Note, error) {
	n := sqlcgen.Note{
		ID:              arg.ID,
		UserID:          arg.UserID,
		ContextID:       arg.ContextID,
		Content:         arg.Content,
		IsInbox:         arg.IsInbox,
		EmbeddingStatus: arg.EmbeddingStatus,
		CollapseImages:  arg.CollapseImages,
		CreatedAt:       arg.CreatedAt,
		UpdatedAt:       pgtype.Timestamptz{Time: time.Now(), Valid: true},
		DeletedAt:       arg.DeletedAt,
	}
	m.db.notes[arg.ID] = n
	return n, nil
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

	var nodes []sqlcgen.NoteNode
	for _, nn := range m.db.noteNodes {
		if accessibleNotes[nn.NoteID] {
			nodes = append(nodes, nn)
		}
	}
	return nodes, nil
}

func (m *mockCollabRepository) UpsertNoteNode(ctx context.Context, arg sqlcgen.UpsertNoteNodeParams) (sqlcgen.NoteNode, error) {
	nn := sqlcgen.NoteNode{
		ID:        arg.ID,
		NoteID:    arg.NoteID,
		ParentID:  arg.ParentID,
		Position:  arg.Position,
		Type:      arg.Type,
		Data:      arg.Data,
		CreatedAt: arg.CreatedAt,
		DeletedAt: arg.DeletedAt,
	}
	m.db.noteNodes[arg.ID] = nn
	return nn, nil
}

func (m *mockCollabRepository) GetNoteByID(ctx context.Context, arg sqlcgen.GetNoteByIDParams) (sqlcgen.GetNoteByIDRow, error) {
	if n, ok := m.db.notes[arg.ID]; ok {
		isOwner := n.UserID == arg.UserID
		isShared := false
		if !isOwner {
			sharesList := m.db.noteShares[n.ID]
			for _, s := range sharesList {
				if s.UserID == arg.UserID {
					isShared = true
					break
				}
			}
		}
		if isOwner || isShared {
			return sqlcgen.GetNoteByIDRow{
				ID:              n.ID,
				UserID:          n.UserID,
				ContextID:       n.ContextID,
				Content:         n.Content,
				IsInbox:         n.IsInbox,
				CreatedAt:       n.CreatedAt,
				UpdatedAt:       n.UpdatedAt,
				DeletedAt:       n.DeletedAt,
				EmbeddingStatus: n.EmbeddingStatus,
				CollapseImages:  n.CollapseImages,
			}, nil
		}
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
		noteNodes:  make(map[pgtype.UUID]sqlcgen.NoteNode),
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
			web.SetUserID(c, uuid.UUID(currentMockUserID.Bytes).String())
			return next(c)
		}
	})

	e.POST("/api/v1/sync/push", syncH.Push)
	e.POST("/api/v1/sync/pull", syncH.Pull)
	e.POST("/api/v1/notes/:id/shares", sharesH.ShareNote)

	noteID := pgtype.UUID{Bytes: [16]byte{3}, Valid: true}
	nodeID := pgtype.UUID{Bytes: [16]byte{4}, Valid: true}

	// User A pushes note-1 and node-1
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
				Data:   []byte(`{"text":"Hello from User A"}`),
			},
		},
	}

	pushBody, _ := json.Marshal(pushPayload)
	reqPush := httptest.NewRequest(http.MethodPost, "/api/v1/sync/push", bytes.NewReader(pushBody))
	reqPush.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
	recPush := httptest.NewRecorder()
	e.ServeHTTP(recPush, reqPush)
	assert.Equal(t, http.StatusOK, recPush.Code)

	// User A shares note-1 with User B
	shareReq := shares.ShareNoteRequest{
		Email:      "userB@example.com",
		Permission: "edit",
	}
	shareBody, _ := json.Marshal(shareReq)
	reqShare := httptest.NewRequest(
		http.MethodPost,
		"/api/v1/notes/"+uuid.UUID(noteID.Bytes).String()+"/shares",
		bytes.NewReader(shareBody),
	)
	reqShare.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
	recShare := httptest.NewRecorder()
	e.ServeHTTP(recShare, reqShare)
	assert.Equal(t, http.StatusCreated, recShare.Code)

	// User B pulls note-1
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

	var pullPayloadResult sync.SyncPayload
	err := json.Unmarshal(recPull.Body.Bytes(), &pullPayloadResult)
	assert.NoError(t, err)

	// Assert note is present in pull for User B
	assert.NotEmpty(t, pullPayloadResult.Notes, "User B should have received shared note on sync pull")
	assert.Equal(t, noteID, pullPayloadResult.Notes[0].ID)
	assert.Equal(t, "edit", pullPayloadResult.Notes[0].SharedPermission)

	assert.NotEmpty(t, pullPayloadResult.NoteNodes, "User B should have received the note node on sync pull")
	assert.Equal(t, nodeID, pullPayloadResult.NoteNodes[0].ID)
	assert.Equal(t, `{"text":"Hello from User A"}`, string(pullPayloadResult.NoteNodes[0].Data))

	// User B modifies the note node
	pushPayloadB := sync.SyncPayload{
		NoteNodes: []sqlcgen.NoteNode{
			{
				ID:     nodeID,
				NoteID: noteID,
				Type:   "paragraph",
				Data:   []byte(`{"text":"Hello from User B"}`),
			},
		},
	}

	pushBodyB, _ := json.Marshal(pushPayloadB)
	reqPushB := httptest.NewRequest(http.MethodPost, "/api/v1/sync/push", bytes.NewReader(pushBodyB))
	reqPushB.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
	recPushB := httptest.NewRecorder()
	e.ServeHTTP(recPushB, reqPushB)
	assert.Equal(t, http.StatusOK, recPushB.Code)

	// User A pulls the changes
	currentMockUserID = userA.ID
	pullReqBodyA := sync.PullRequest{
		LastSyncedAt: time.Time{},
		Limit:        100,
	}
	pullBodyA, _ := json.Marshal(pullReqBodyA)
	reqPullA := httptest.NewRequest(http.MethodPost, "/api/v1/sync/pull", bytes.NewReader(pullBodyA))
	reqPullA.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
	recPullA := httptest.NewRecorder()
	e.ServeHTTP(recPullA, reqPullA)
	assert.Equal(t, http.StatusOK, recPullA.Code)

	var pullPayloadResultA sync.SyncPayload
	err = json.Unmarshal(recPullA.Body.Bytes(), &pullPayloadResultA)
	assert.NoError(t, err)

	// Assert User A has the modified note node
	assert.NotEmpty(t, pullPayloadResultA.NoteNodes, "User A should have received note nodes on sync pull")
	assert.Equal(t, nodeID, pullPayloadResultA.NoteNodes[0].ID)
	assert.Equal(t, `{"text":"Hello from User B"}`, string(pullPayloadResultA.NoteNodes[0].Data), "User A should see User B's edits")
}
