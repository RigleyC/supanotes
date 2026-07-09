package sync

import (
	"context"
	"errors"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/reearth/ygo/crdt"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

func testNote(overrides ...func(*sqlcgen.GetSyncNotesRow)) sqlcgen.GetSyncNotesRow {
	n := sqlcgen.GetSyncNotesRow{
		ID:        pgtype.UUID{Valid: true},
		UserID:    pgtype.UUID{Valid: true},
		Content:   "",
		DeletedAt: pgtype.Timestamptz{Valid: false},
	}
	for _, o := range overrides {
		o(&n)
	}
	return n
}

func TestSyncTaskCompletionQueryMatchesCurrentSchema(t *testing.T) {
	query, err := os.ReadFile("../../db/queries/sync.sql")
	if err != nil {
		t.Fatalf("read sync query: %v", err)
	}

	if strings.Contains(string(query), "INSERT INTO task_completions (id, task_id, completed_at, status)") {
		t.Fatal("UpsertTaskCompletion must not insert task_completions.status; migration 000011 removed that column")
	}
}

func testUserID() pgtype.UUID {
	return pgtype.UUID{Valid: true}
}

func testOtherUserID() pgtype.UUID {
	return pgtype.UUID{Bytes: [16]byte{1}, Valid: true}
}

type mockRepository struct {
	upsertNoteErr       error
	lastUpsertNoteArg   sqlcgen.UpsertNoteParams
	getNoteShareForUser func(ctx context.Context, arg sqlcgen.GetNoteShareForUserParams) (sqlcgen.NoteShare, error)
	getNoteOwnerID      func(ctx context.Context, noteID pgtype.UUID) (pgtype.UUID, error)
}

func (m *mockRepository) GetSyncNotes(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.GetSyncNotesRow, error) {
	return nil, nil
}

func (m *mockRepository) UpsertNote(ctx context.Context, arg sqlcgen.UpsertNoteParams) (sqlcgen.Note, error) {
	m.lastUpsertNoteArg = arg
	return sqlcgen.Note{}, m.upsertNoteErr
}

func (m *mockRepository) GetSyncTasks(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.Task, error) {
	return nil, nil
}

func (m *mockRepository) UpsertTask(ctx context.Context, arg sqlcgen.UpsertTaskParams) (sqlcgen.Task, error) {
	return sqlcgen.Task{}, nil
}

func (m *mockRepository) GetSyncContexts(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.Context, error) {
	return nil, nil
}

func (m *mockRepository) UpsertContext(ctx context.Context, arg sqlcgen.UpsertContextParams) (sqlcgen.Context, error) {
	return sqlcgen.Context{}, nil
}

func (m *mockRepository) GetSyncTags(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.Tag, error) {
	return nil, nil
}

func (m *mockRepository) UpsertTag(ctx context.Context, arg sqlcgen.UpsertTagParams) (sqlcgen.Tag, error) {
	return sqlcgen.Tag{}, nil
}

func (m *mockRepository) GetSyncTaskCompletions(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.TaskCompletion, error) {
	return nil, nil
}

func (m *mockRepository) UpsertTaskCompletion(ctx context.Context, arg sqlcgen.UpsertTaskCompletionParams) error {
	return nil
}

func (m *mockRepository) GetSyncNoteTags(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.NoteTag, error) {
	return nil, nil
}

func (m *mockRepository) UpsertNoteTag(ctx context.Context, arg sqlcgen.UpsertNoteTagParams) error {
	return nil
}

func (m *mockRepository) GetSyncNoteLinks(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.NoteLink, error) {
	return nil, nil
}

func (m *mockRepository) UpsertNoteLink(ctx context.Context, arg sqlcgen.UpsertNoteLinkParams) error {
	return nil
}

func (m *mockRepository) GetNoteShareForUser(ctx context.Context, arg sqlcgen.GetNoteShareForUserParams) (sqlcgen.NoteShare, error) {
	if m.getNoteShareForUser != nil {
		return m.getNoteShareForUser(ctx, arg)
	}
	return sqlcgen.NoteShare{}, pgx.ErrNoRows
}

func (m *mockRepository) GetSyncUserNotePreferences(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.UserNotePreference, error) {
	return nil, nil
}

func (m *mockRepository) UpsertUserNotePreference(ctx context.Context, arg sqlcgen.UpsertUserNotePreferenceParams) (sqlcgen.UserNotePreference, error) {
	return sqlcgen.UserNotePreference{}, nil
}

func (m *mockRepository) GetNoteOwnerID(ctx context.Context, noteID pgtype.UUID) (pgtype.UUID, error) {
	if m.getNoteOwnerID != nil {
		return m.getNoteOwnerID(ctx, noteID)
	}
	return pgtype.UUID{}, nil
}

func (m *mockRepository) GetSyncNoteNodes(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.NoteNode, error) {
	return nil, nil
}

func (m *mockRepository) GetSyncNoteYjsStates(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.NoteYjsState, error) {
	return nil, nil
}

func (m *mockRepository) UpsertNoteNode(ctx context.Context, arg sqlcgen.UpsertNoteNodeParams) (sqlcgen.NoteNode, error) {
	return sqlcgen.NoteNode{}, nil
}

func (m *mockRepository) GetNoteByID(ctx context.Context, arg sqlcgen.GetNoteByIDParams) (sqlcgen.GetNoteByIDRow, error) {
	return sqlcgen.GetNoteByIDRow{ID: arg.ID, UserID: arg.UserID}, nil
}

func (m *mockRepository) WithQuerier(q sqlcgen.Querier) Repository {
	return m
}

func (m *mockRepository) UpdateNotesContentFromNodes(ctx context.Context, noteIDs []pgtype.UUID) error {
	return nil
}

func TestSyncServicePushRejectsSharedNoteWithoutEditPermission(t *testing.T) {
	repo := &mockRepository{}
	svc := NewService(repo, nil, nil, nil)

	payload := &SyncPayload{
		Notes: []sqlcgen.GetSyncNotesRow{
			testNote(func(n *sqlcgen.GetSyncNotesRow) {
				n.UserID = testOtherUserID()
				n.Content = "Hello"
			}),
		},
	}

	err := svc.Push(context.Background(), testUserID(), payload)
	if !errors.Is(err, ErrSyncConflict) {
		t.Fatalf("expected ErrSyncConflict for shared note without edit permission, got %v", err)
	}
}

func TestSyncServicePushAllowsSharedNoteWithEditPermission(t *testing.T) {
	repo := &mockRepository{
		getNoteShareForUser: func(ctx context.Context, arg sqlcgen.GetNoteShareForUserParams) (sqlcgen.NoteShare, error) {
			return sqlcgen.NoteShare{Permission: "edit"}, nil
		},
	}
	svc := NewService(repo, nil, nil, nil)

	payload := &SyncPayload{
		Notes: []sqlcgen.GetSyncNotesRow{
			testNote(func(n *sqlcgen.GetSyncNotesRow) {
				n.UserID = testOtherUserID()
				n.Content = "Hello"
			}),
		},
	}

	err := svc.Push(context.Background(), testUserID(), payload)
	if err != nil {
		t.Fatalf("expected no error for shared note with edit permission, got %v", err)
	}
}

func TestSyncServicePushAllowsTaskSyncWithoutParentNoteInPayload(t *testing.T) {
	userID := testUserID()
	noteID := pgtype.UUID{Bytes: [16]byte{2}, Valid: true}

	repo := &mockRepository{
		getNoteOwnerID: func(ctx context.Context, nId pgtype.UUID) (pgtype.UUID, error) {
			if nId == noteID {
				return userID, nil
			}
			return pgtype.UUID{}, nil
		},
	}
	svc := NewService(repo, nil, nil, nil)


	payload := &SyncPayload{
		Notes: []sqlcgen.GetSyncNotesRow{},
		Tasks: []SyncTask{
			{
				ID:     pgtype.UUID{Bytes: [16]byte{3}, Valid: true},
				UserID: userID,
				NoteID: noteID,
				Title:  "Orphaned task",
				Status: "open",
			},
		},
	}

	err := svc.Push(context.Background(), userID, payload)
	if err != nil {
		t.Fatalf("expected no error for task without parent note in payload, got %v", err)
	}
}

func TestProduceUpdateFromRows_GeneratesYjsUpdate(t *testing.T) {
	ctx := context.Background()
	nodeID := uuid.New().String()

	nodeUUID, err := uuid.Parse(nodeID)
	require.NoError(t, err)
	noteUUID := uuid.MustParse(testNoteID)

	nodes := []sqlcgen.NoteNode{
		{
			ID:        pgtype.UUID{Bytes: nodeUUID, Valid: true},
			NoteID:    pgtype.UUID{Bytes: noteUUID, Valid: true},
			Position:  "0",
			Type:      "paragraph",
			Data:      []byte(`{"text":"hello"}`),
			CreatedAt: pgtype.Timestamptz{Time: time.UnixMilli(1700000000000), Valid: true},
			DeletedAt: pgtype.Timestamptz{Valid: false},
		},
	}
	tasks := []SyncTask{}

	update, err := ProduceUpdateFromRows(ctx, nil, testNoteID, nodes, tasks)
	require.NoError(t, err)
	require.NotEmpty(t, update)

	doc := crdt.New(crdt.WithGC(false))
	doc.GetText("content/" + nodeID) // Pre-register to avoid share-map type corruption
	require.NoError(t, crdt.ApplyUpdateV1(doc, update, nil))
	keys := doc.GetMap("nodes").Keys()
	require.Len(t, keys, 1)

	raw, ok := doc.GetMap("nodes").Get(nodeID)
	require.True(t, ok)
	assert.Contains(t, raw, "hello")

	textType := doc.GetText("content/" + nodeID)
	require.NotNil(t, textType)
	assert.Equal(t, "hello", textType.ToString())
}

func TestSyncServicePushMapsNoRowsToSyncConflict(t *testing.T) {
	repo := &mockRepository{upsertNoteErr: pgx.ErrNoRows}
	svc := NewService(repo, nil, nil, nil)

	userID := testUserID()

	payload := &SyncPayload{
		Notes: []sqlcgen.GetSyncNotesRow{
			testNote(func(n *sqlcgen.GetSyncNotesRow) {
				n.Content = "Hello"
				n.CreatedAt = pgtype.Timestamptz{Time: pgtype.Timestamptz{}.Time, Valid: true}
			}),
		},
	}

	err := svc.Push(context.Background(), userID, payload)
	if !errors.Is(err, ErrSyncConflict) {
		t.Fatalf("expected ErrSyncConflict, got %v", err)
	}
}

