package notes

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

var (
	ErrNoteNotFound = errors.New("note not found")
	ErrInboxRule    = errors.New("operation not allowed on inbox note")
)

type Service struct {
	repo Repository
}

func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) CreateNote(ctx context.Context, userID pgtype.UUID, title *string, content string, contextID *pgtype.UUID, favorite, archived bool) (sqlcgen.Note, error) {
	arg := sqlcgen.CreateNoteParams{
		UserID:          userID,
		Content:         content,
		IsInbox:         false,
		Favorite:        favorite,
		Archived:        archived,
		EmbeddingStatus: "pending",
	}
	if title != nil {
		arg.Title = pgtype.Text{String: *title, Valid: true}
	}
	if contextID != nil {
		arg.ContextID = *contextID
	}
	return s.repo.CreateNote(ctx, arg)
}

func (s *Service) GetNoteByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.Note, error) {
	note, err := s.repo.GetNoteByID(ctx, id, userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return sqlcgen.Note{}, ErrNoteNotFound
		}
		return sqlcgen.Note{}, err
	}
	return note, nil
}

func (s *Service) UpdateNote(ctx context.Context, userID pgtype.UUID, id pgtype.UUID, title *string, content *string, contextID *pgtype.UUID, favorite *bool, archived *bool) (sqlcgen.Note, error) {
	note, err := s.GetNoteByID(ctx, id, userID)
	if err != nil {
		return sqlcgen.Note{}, err
	}
	if note.IsInbox {
		// Inbox note properties should not be easily manipulated (except content).
		if archived != nil && *archived {
			return sqlcgen.Note{}, ErrInboxRule
		}
	}

	arg := sqlcgen.UpdateNoteParams{
		ID:              id,
		UserID:          userID,
		EmbeddingStatus: pgtype.Text{String: "pending", Valid: true},
	}
	if title != nil {
		arg.Title = pgtype.Text{String: *title, Valid: true}
	}
	if content != nil {
		arg.Content = pgtype.Text{String: *content, Valid: true}
	}
	if contextID != nil {
		arg.ContextID = *contextID
	}
	if favorite != nil {
		arg.Favorite = pgtype.Bool{Bool: *favorite, Valid: true}
	}
	if archived != nil {
		arg.Archived = pgtype.Bool{Bool: *archived, Valid: true}
	}

	return s.repo.UpdateNote(ctx, arg)
}

func (s *Service) DeleteNote(ctx context.Context, userID pgtype.UUID, id pgtype.UUID) error {
	note, err := s.GetNoteByID(ctx, id, userID)
	if err != nil {
		return err
	}
	if note.IsInbox {
		return ErrInboxRule
	}
	return s.repo.DeleteNote(ctx, id, userID)
}

func (s *Service) GetNotes(ctx context.Context, userID pgtype.UUID, contextID *pgtype.UUID, favorite *bool, limit int32, cursorUpdatedAt *time.Time, cursorID *pgtype.UUID) ([]sqlcgen.Note, error) {
	arg := sqlcgen.GetNotesParams{
		UserID: userID,
		Limit:  limit,
	}
	if contextID != nil {
		arg.ContextID = *contextID
	}
	if favorite != nil {
		arg.Favorite = pgtype.Bool{Bool: *favorite, Valid: true}
	}
	if cursorUpdatedAt != nil && cursorID != nil {
		arg.CursorUpdatedAt = pgtype.Timestamptz{Time: *cursorUpdatedAt, Valid: true}
		arg.CursorID = *cursorID
	}

	return s.repo.GetNotes(ctx, arg)
}

func (s *Service) GetInboxNote(ctx context.Context, userID pgtype.UUID) (sqlcgen.Note, error) {
	note, err := s.repo.GetInboxNote(ctx, userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return sqlcgen.Note{}, ErrNoteNotFound
		}
		return sqlcgen.Note{}, err
	}
	return note, nil
}

func (s *Service) AppendToInbox(ctx context.Context, userID pgtype.UUID, content string) (sqlcgen.Note, error) {
	note, err := s.GetInboxNote(ctx, userID)
	if err != nil {
		return sqlcgen.Note{}, err
	}
	return s.repo.AppendToInbox(ctx, sqlcgen.AppendToInboxParams{
		ID:      note.ID,
		UserID:  userID,
		Content: content,
	})
}
