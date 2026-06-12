package sync

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type mockRepository struct {
	upsertNoteErr error
}

func (m *mockRepository) GetSyncNotes(ctx context.Context, userID pgtype.UUID, lastSyncedAt pgtype.Timestamptz, limit int32) ([]sqlcgen.Note, error) {
	return nil, nil
}

func (m *mockRepository) UpsertNote(ctx context.Context, arg sqlcgen.UpsertNoteParams) (sqlcgen.Note, error) {
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

func (m *mockRepository) WithQuerier(q sqlcgen.Querier) Repository {
	return m
}

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

func TestSyncServicePushMapsNoRowsToSyncConflict(t *testing.T) {
	repo := &mockRepository{upsertNoteErr: pgx.ErrNoRows}
	svc := NewService(repo, nil)

	userID := pgtype.UUID{Valid: true}

	payload := &SyncPayload{
		Notes: []sqlcgen.Note{{
			ID:              pgtype.UUID{Valid: true},
			ContextID:       pgtype.UUID{Valid: false},
			Title:           pgtype.Text{String: "Test", Valid: true},
			Content:         "Hello",
			IsInbox:         false,
			Favorite:        false,
			Archived:        false,
			EmbeddingStatus: "",
			CreatedAt:       pgtype.Timestamptz{Time: pgtype.Timestamptz{}.Time, Valid: true},
			DeletedAt:       pgtype.Timestamptz{Valid: false},
		}},
	}

	err := svc.Push(context.Background(), userID, payload)
	if !errors.Is(err, ErrSyncConflict) {
		t.Fatalf("expected ErrSyncConflict, got %v", err)
	}
}
