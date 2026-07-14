package sync

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

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

func (m *mockRepository) GetNoteByID(ctx context.Context, arg sqlcgen.GetNoteByIDParams) (sqlcgen.GetNoteByIDRow, error) {
	return sqlcgen.GetNoteByIDRow{ID: arg.ID, UserID: arg.UserID}, nil
}

func (m *mockRepository) UpsertNoteYjsState(ctx context.Context, arg sqlcgen.UpsertNoteYjsStateParams) error {
	return nil
}

func (m *mockRepository) WithQuerier(q sqlcgen.Querier) Repository {
	return m
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

