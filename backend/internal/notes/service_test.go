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
