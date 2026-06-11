package notes

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type mockRepo struct {
	Repository
	getNoteByIDFn func(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.Note, error)
	updateNoteFn  func(ctx context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error)
}

func (m *mockRepo) GetNoteByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.Note, error) {
	return m.getNoteByIDFn(ctx, id, userID)
}

func (m *mockRepo) UpdateNote(ctx context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
	return m.updateNoteFn(ctx, arg)
}

func TestService_UpdateNote_SetsEmbeddingPendingOnContentChange(t *testing.T) {
	var capturedArg sqlcgen.UpdateNoteParams
	svc := NewService(&mockRepo{
		getNoteByIDFn: func(_ context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.Note, error) {
			return sqlcgen.Note{ID: id, UserID: userID}, nil
		},
		updateNoteFn: func(_ context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
			capturedArg = arg
			return sqlcgen.Note{ID: arg.ID}, nil
		},
	})

	newContent := "updated content"
	note, err := svc.UpdateNote(context.Background(), pgtype.UUID{}, pgtype.UUID{}, nil, &newContent, nil, nil, nil)
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

func TestService_UpdateNote_DoesNotSetEmbeddingPendingOnTitleOnly(t *testing.T) {
	var capturedArg sqlcgen.UpdateNoteParams
	svc := NewService(&mockRepo{
		getNoteByIDFn: func(_ context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.Note, error) {
			return sqlcgen.Note{ID: id, UserID: userID}, nil
		},
		updateNoteFn: func(_ context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
			capturedArg = arg
			return sqlcgen.Note{ID: arg.ID}, nil
		},
	})

	newTitle := "new title"
	note, err := svc.UpdateNote(context.Background(), pgtype.UUID{}, pgtype.UUID{}, &newTitle, nil, nil, nil, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	_ = note
	if capturedArg.EmbeddingStatus.Valid {
		t.Fatal("expected embedding_status to NOT be set when only title changes")
	}
}

func TestService_UpdateNote_DoesNotSetEmbeddingPendingOnFavoriteOnly(t *testing.T) {
	var capturedArg sqlcgen.UpdateNoteParams
	fav := true
	svc := NewService(&mockRepo{
		getNoteByIDFn: func(_ context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.Note, error) {
			return sqlcgen.Note{ID: id, UserID: userID}, nil
		},
		updateNoteFn: func(_ context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
			capturedArg = arg
			return sqlcgen.Note{ID: arg.ID}, nil
		},
	})

	note, err := svc.UpdateNote(context.Background(), pgtype.UUID{}, pgtype.UUID{}, nil, nil, nil, &fav, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	_ = note
	if capturedArg.EmbeddingStatus.Valid {
		t.Fatal("expected embedding_status to NOT be set when only favorite changes")
	}
}

func TestCreateNoteRejectsEmptyRegularNote(t *testing.T) {
	svc := NewService(&mockRepo{})
	userID := pgtype.UUID{Valid: true}

	_, err := svc.CreateNote(context.Background(), userID, nil, "   ", nil, false, false)

	if !errors.Is(err, ErrEmptyNote) {
		t.Fatalf("expected ErrEmptyNote, got %v", err)
	}
}
