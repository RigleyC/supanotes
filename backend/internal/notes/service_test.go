package notes

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type mockRepo struct {
	getNoteByIDFn func(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.GetNoteByIDRow, error)
	updateNoteFn  func(ctx context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error)
}

func (m *mockRepo) CreateNote(ctx context.Context, arg sqlcgen.CreateNoteParams) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}
func (m *mockRepo) GetNoteByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.GetNoteByIDRow, error) {
	if m.getNoteByIDFn != nil {
		return m.getNoteByIDFn(ctx, id, userID)
	}
	return sqlcgen.GetNoteByIDRow{}, nil
}
func (m *mockRepo) UpdateNote(ctx context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
	if m.updateNoteFn != nil {
		return m.updateNoteFn(ctx, arg)
	}
	return sqlcgen.Note{}, nil
}
func (m *mockRepo) DeleteNote(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) error {
	return nil
}
func (m *mockRepo) GetNotes(ctx context.Context, arg sqlcgen.GetNotesParams) ([]sqlcgen.GetNotesRow, error) {
	return nil, nil
}
func (m *mockRepo) WithQuerier(q sqlcgen.Querier) Repository {
	return m
}

func TestService_UpdateNote_SetsEmbeddingPendingOnContentChange(t *testing.T) {
	var capturedArg sqlcgen.UpdateNoteParams
	svc := NewService(&mockRepo{
		getNoteByIDFn: func(_ context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.GetNoteByIDRow, error) {
			return sqlcgen.GetNoteByIDRow{ID: id, UserID: userID}, nil
		},
		updateNoteFn: func(_ context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
			capturedArg = arg
			return sqlcgen.Note{ID: arg.ID}, nil
		},
	}, nil)

	newContent := "updated content"
	note, err := svc.UpdateNote(context.Background(), pgtype.UUID{}, pgtype.UUID{}, &newContent, nil, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	_ = note
	if !capturedArg.EmbeddingStatus.Valid {
		t.Fatal("expected embedding_status to be set when content changes")
	}
	if capturedArg.EmbeddingStatus.String != "pending" {
		t.Fatalf("expected 'pending', got %q", capturedArg.EmbeddingStatus.String)
	}
}

func TestCreateNoteRejectsEmptyRegularNote(t *testing.T) {
	svc := NewService(&mockRepo{}, nil)
	userID := pgtype.UUID{Valid: true}

	_, err := svc.CreateNote(context.Background(), userID, "   ", nil, false)

	if !errors.Is(err, ErrEmptyNote) {
		t.Fatalf("expected ErrEmptyNote, got %v", err)
	}
}

