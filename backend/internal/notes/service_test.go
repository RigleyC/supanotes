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
	addTagFn      func(ctx context.Context, noteID pgtype.UUID, tagID pgtype.UUID) error
	removeTagFn   func(ctx context.Context, noteID pgtype.UUID, tagID pgtype.UUID) error
	updateNoteFn  func(ctx context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error)
}

func (m *mockRepo) GetNoteByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.Note, error) {
	return m.getNoteByIDFn(ctx, id, userID)
}

func (m *mockRepo) AddTagToNote(ctx context.Context, noteID pgtype.UUID, tagID pgtype.UUID) error {
	return m.addTagFn(ctx, noteID, tagID)
}

func (m *mockRepo) RemoveTagFromNote(ctx context.Context, noteID pgtype.UUID, tagID pgtype.UUID) error {
	return m.removeTagFn(ctx, noteID, tagID)
}

func (m *mockRepo) UpdateNote(ctx context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
	return m.updateNoteFn(ctx, arg)
}

func TestService_AddTagToNote_Success(t *testing.T) {
	var (
		addedNoteID pgtype.UUID
		addedTagID  pgtype.UUID
	)
	svc := NewService(&mockRepo{
		getNoteByIDFn: func(_ context.Context, id pgtype.UUID, _ pgtype.UUID) (sqlcgen.Note, error) {
			return sqlcgen.Note{ID: id}, nil
		},
		addTagFn: func(_ context.Context, noteID pgtype.UUID, tagID pgtype.UUID) error {
			addedNoteID = noteID
			addedTagID = tagID
			return nil
		},
	})

	noteID := pgtype.UUID{Bytes: [16]byte{1}, Valid: true}
	tagID := pgtype.UUID{Bytes: [16]byte{2}, Valid: true}
	userID := pgtype.UUID{Bytes: [16]byte{3}, Valid: true}

	err := svc.AddTagToNote(context.Background(), noteID, tagID, userID)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if addedNoteID != noteID {
		t.Errorf("noteID: want %v, got %v", noteID, addedNoteID)
	}
	if addedTagID != tagID {
		t.Errorf("tagID: want %v, got %v", tagID, addedTagID)
	}
}

func TestService_AddTagToNote_NoteNotFound(t *testing.T) {
	svc := NewService(&mockRepo{
		getNoteByIDFn: func(_ context.Context, _ pgtype.UUID, _ pgtype.UUID) (sqlcgen.Note, error) {
			return sqlcgen.Note{}, ErrNoteNotFound
		},
	})

	err := svc.AddTagToNote(context.Background(), pgtype.UUID{}, pgtype.UUID{}, pgtype.UUID{})
	if !errors.Is(err, ErrNoteNotFound) {
		t.Fatalf("want ErrNoteNotFound, got %v", err)
	}
}

func TestService_RemoveTagFromNote_Success(t *testing.T) {
	var (
		removedNoteID pgtype.UUID
		removedTagID  pgtype.UUID
	)
	svc := NewService(&mockRepo{
		getNoteByIDFn: func(_ context.Context, id pgtype.UUID, _ pgtype.UUID) (sqlcgen.Note, error) {
			return sqlcgen.Note{ID: id}, nil
		},
		removeTagFn: func(_ context.Context, noteID pgtype.UUID, tagID pgtype.UUID) error {
			removedNoteID = noteID
			removedTagID = tagID
			return nil
		},
	})

	noteID := pgtype.UUID{Bytes: [16]byte{1}, Valid: true}
	tagID := pgtype.UUID{Bytes: [16]byte{2}, Valid: true}
	userID := pgtype.UUID{Bytes: [16]byte{3}, Valid: true}

	err := svc.RemoveTagFromNote(context.Background(), noteID, tagID, userID)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if removedNoteID != noteID {
		t.Errorf("noteID: want %v, got %v", noteID, removedNoteID)
	}
	if removedTagID != tagID {
		t.Errorf("tagID: want %v, got %v", tagID, removedTagID)
	}
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

func TestService_RemoveTagFromNote_NoteNotFound(t *testing.T) {
	svc := NewService(&mockRepo{
		getNoteByIDFn: func(_ context.Context, _ pgtype.UUID, _ pgtype.UUID) (sqlcgen.Note, error) {
			return sqlcgen.Note{}, ErrNoteNotFound
		},
	})

	err := svc.RemoveTagFromNote(context.Background(), pgtype.UUID{}, pgtype.UUID{}, pgtype.UUID{})
	if !errors.Is(err, ErrNoteNotFound) {
		t.Fatalf("want ErrNoteNotFound, got %v", err)
	}
}
